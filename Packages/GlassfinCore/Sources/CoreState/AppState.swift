import CoreModels
import CoreNetworking
import Foundation
import GlassfinServices
import Observation

#if canImport(Network)
    import Network
#endif

public enum Connectivity: Sendable, Equatable {
    case online
    case offline
    case serverUnreachable
    case degraded
}

public enum PingOutcome: Sendable, Equatable {
    case ok
    case failed(AppError)
}

public protocol ReachabilityPinging: Sendable {
    func ping() async -> PingOutcome
}

public struct SystemServicePinger: ReachabilityPinging {
    public var service: any SystemService
    public var deviceOffline: @Sendable () -> Bool

    public init(service: any SystemService, deviceOffline: @escaping @Sendable () -> Bool = { false }) {
        self.service = service
        self.deviceOffline = deviceOffline
    }

    public func ping() async -> PingOutcome {
        do {
            _ = try await service.ping()
            return .ok
        } catch let error as APIError {
            return .failed(AppErrorMapping.map(error, context: .anonymous, deviceOffline: deviceOffline()))
        } catch {
            return .failed(.serverUnreachable)
        }
    }
}

public protocol ConnectivityPath: Sendable {
    var isOnline: Bool { get }
    func changes() -> AsyncStream<Bool>
}

public struct StaticConnectivityPath: ConnectivityPath {
    public var isOnline: Bool

    public init(online: Bool) {
        self.isOnline = online
    }

    public func changes() -> AsyncStream<Bool> {
        let online = isOnline
        return AsyncStream { continuation in
            continuation.yield(online)
            continuation.finish()
        }
    }
}

#if canImport(Network)
    public final class SystemPathMonitor: ConnectivityPath, @unchecked Sendable {
        private let monitor = NWPathMonitor()
        private let lock = NSLock()
        private var online = true
        private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

        public init() {
            monitor.pathUpdateHandler = { [weak self] path in
                self?.publish(path.status == .satisfied)
            }
            monitor.start(queue: DispatchQueue(label: "org.glassfin.path"))
        }

        deinit { monitor.cancel() }

        public var isOnline: Bool {
            lock.lock()
            defer { lock.unlock() }
            return online
        }

        public func changes() -> AsyncStream<Bool> {
            AsyncStream { continuation in
                let id = UUID()
                self.lock.lock()
                self.continuations[id] = continuation
                let current = self.online
                self.lock.unlock()
                continuation.yield(current)
                continuation.onTermination = { [weak self] _ in
                    self?.remove(id)
                }
            }
        }

        private func publish(_ online: Bool) {
            lock.lock()
            self.online = online
            let current = Array(continuations.values)
            lock.unlock()
            for continuation in current {
                continuation.yield(online)
            }
        }

        private func remove(_ id: UUID) {
            lock.lock()
            continuations[id] = nil
            lock.unlock()
        }
    }
#endif

@MainActor
@Observable
public final class AppState {
    public enum Phase: Sendable, Equatable {
        case launching
        case needsServer
        case needsLogin(ServerInfo)
        case signedIn(UserSession)
    }

    public private(set) var phase: Phase = .launching
    public private(set) var connectivity: Connectivity = .online
    public private(set) var activeServer: ServerInfo?
    public private(set) var bannerKey: String?
    public private(set) var sessionNoticeKey: String?

    public var banner: String? {
        bannerKey.map(AppErrorMessage.localized)
    }

    public var sessionNotice: String? {
        sessionNoticeKey.map(AppErrorMessage.localized)
    }
    /// Set when the saved server is below the minimum. The phase enum has no blocked case.
    public private(set) var blockingError: AppError?
    public private(set) var securityNotice: AppError?
    public private(set) var requestGeneration = 0
    public private(set) var userDataGeneration = 0
    public private(set) var libraryGeneration = 0

    public let userData: UserDataStore
    public let responses: ResponseCache
    public let snapshots: HomeSnapshotStore
    public let images: ImageStore
    public let scope: RequestScope
    public let signposter: any Signposting

    @ObservationIgnored private let secureStore: any SecureStore
    @ObservationIgnored private let preferences: PreferencesRepository
    @ObservationIgnored private let path: any ConnectivityPath
    @ObservationIgnored private let pinger: any ReachabilityPinging
    @ObservationIgnored private let clock: any GlassfinClock
    @ObservationIgnored private let automaticPing: Bool
    @ObservationIgnored private let log: any GlassfinLog
    @ObservationIgnored private var pathOnline: Bool
    @ObservationIgnored private var logoutStarted = false
    @ObservationIgnored private var pingArmed = false
    @ObservationIgnored private var pingTask: Task<Void, Never>?
    @ObservationIgnored private var pingGeneration = UUID()
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var pathTask: Task<Void, Never>?
    @ObservationIgnored private var probeTask: Task<Void, Never>?
    @ObservationIgnored public var onReconnect: (@MainActor () -> Void)?

    public var showsServerDown: Bool { connectivity == .serverUnreachable }
    public var serverDownTitleKey: String { AppErrorMessage.serverDownKey }
    public var serverDownTitle: String { AppErrorMessage.serverDown }
    public var retryTitleKey: String { AppErrorMessage.retryKey }
    public var retryTitle: String { AppErrorMessage.retry }
    public var changeServerTitleKey: String { AppErrorMessage.changeServerKey }
    public var changeServerTitle: String { AppErrorMessage.changeServer }
    public var scheduledPingDelay: Duration { NetworkThresholds.serverPingInterval }
    public var playbackBlocked: Bool { connectivity == .offline || connectivity == .serverUnreachable }

    public var playbackBlockedMessageKey: String? {
        switch connectivity {
        case .offline:
            AppErrorMessage.playbackOfflineKey
        case .serverUnreachable:
            AppErrorMessage.playbackUnreachableKey
        case .online, .degraded:
            nil
        }
    }

    public var playbackBlockedMessage: String? {
        switch connectivity {
        case .offline:
            AppErrorMessage.playbackOffline
        case .serverUnreachable:
            AppErrorMessage.playbackUnreachable
        case .online, .degraded:
            nil
        }
    }

    public init(
        secureStore: any SecureStore,
        settings: any SettingsStore,
        path: any ConnectivityPath,
        pinger: any ReachabilityPinging,
        cacheRoot: URL,
        clock: any GlassfinClock = SystemGlassfinClock(),
        automaticPing: Bool = true,
        signposter: any Signposting = Signposters.production(),
        log: any GlassfinLog = SilentLog()
    ) {
        self.secureStore = secureStore
        self.preferences = PreferencesRepository(store: settings)
        self.path = path
        self.pathOnline = path.isOnline
        self.pinger = pinger
        self.clock = clock
        self.automaticPing = automaticPing
        self.signposter = signposter
        self.log = log
        self.userData = UserDataStore()
        self.responses = ResponseCache()
        self.snapshots = HomeSnapshotStore(file: cacheRoot.appendingPathComponent("home.json"))
        let disk = DiskImageCache(
            directory: cacheRoot.appendingPathComponent("images", isDirectory: true),
            byteLimit: CacheBudget.imageDiskBytes
        )
        let memory = MemoryImageCache(byteLimit: CacheBudget.imageMemoryBytes)
        self.images = ImageStore(memory: memory, disk: disk)
        self.scope = RequestScope()
        if !path.isOnline {
            self.connectivity = .offline
            self.bannerKey = AppErrorMessage.offlineKey
        }
    }

    public func bootstrap() {
        let prefs = preferences.load()
        guard let stored = prefs.activeServer() else {
            phase = .needsServer
            activeServer = nil
            return
        }
        guard let version = SemVer(parsing: stored.version) else {
            let info = ServerInfo(
                id: stored.id, name: stored.name, url: stored.url, version: SemVer(major: 0, minor: 0, patch: 0))
            activeServer = info
            blockingError = .unsupportedServer(version: stored.version)
            phase = .needsLogin(info)
            return
        }
        let info = ServerInfo(id: stored.id, name: stored.name, url: stored.url, version: version)
        activeServer = info
        if let failure = ServerVersionGate.failure(for: version) {
            blockingError = failure
            phase = .needsLogin(info)
            return
        }
        guard let user = prefs.activeUser(),
            let data = try? secureStore.data(
                for: SessionCredential.account(serverID: info.id, userID: user.userID)),
            !data.isEmpty
        else {
            phase = .needsLogin(info)
            return
        }
        phase = .signedIn(
            UserSession(
                server: info, userID: user.userID, userName: user.userName, isAdministrator: user.isAdministrator))
    }

    public func didSignIn(_ session: UserSession, token: String) throws(PreferencesError) {
        var prefs = preferences.load()
        let stored = StoredServer(
            id: session.server.id,
            name: session.server.name,
            url: session.server.url,
            version: ServerVersionGate.dotted(session.server.version),
            certificatePinSHA256: prefs.servers.first { $0.id == session.server.id }?.certificatePinSHA256
        )
        prefs = try prefs.upserting(server: stored)
        let existing = prefs.users.first { $0.serverID == session.server.id && $0.userID == session.userID }
        let user = StoredUser(
            serverID: session.server.id,
            userID: session.userID,
            userName: session.userName,
            isAdministrator: session.isAdministrator,
            audioLanguage: existing?.audioLanguage,
            subtitleLanguage: existing?.subtitleLanguage
        )
        prefs = prefs.upserting(user: user)
        prefs.activeServerID = session.server.id
        prefs.activeUserID = session.userID
        try preferences.save(prefs)
        do {
            try secureStore.set(
                Data(token.utf8),
                account: SessionCredential.account(serverID: session.server.id, userID: session.userID),
                attributes: .production
            )
        } catch {
            log.warning("Non-fatal invariant failure")
            throw .keychainFailed
        }
        log.debug("Signed in.")
        logoutStarted = false
        sessionNoticeKey = nil
        blockingError = nil
        phase = .signedIn(session)
        activeServer = session.server
    }

    public func removeServer(id: String) {
        let loaded = preferences.load()
        let (updated, accounts) = loaded.removing(serverID: id)
        try? preferences.save(updated)
        for account in accounts {
            try? secureStore.remove(account: account)
        }
        if case .signedIn(let session) = phase, session.server.id == id {
            logoutStarted = true
            phase = .needsServer
            activeServer = nil
            sessionNoticeKey = nil
        } else if activeServer?.id == id {
            phase = .needsServer
            activeServer = nil
        }
    }

    public func beginServerSwitch() {
        var prefs = preferences.load()
        prefs.activeServerID = nil
        prefs.activeUserID = nil
        try? preferences.save(prefs)
        pingTask?.cancel()
        pingArmed = false
        phase = .needsServer
        activeServer = nil
        if pathOnline, connectivity == .serverUnreachable {
            connectivity = .online
        }
    }

    public func preferencesSnapshot() -> AppPreferences {
        preferences.load()
    }

    public func handle(_ error: AppError) {
        switch error {
        case .unauthorized:
            endSession()
        case .offline:
            enterOffline()
        case .serverUnreachable:
            enterUnreachable()
        case .tlsUntrusted, .insecureRedirect:
            securityNotice = error
        case .internalInvariant:
            log.warning("Non-fatal invariant failure")
        default:
            break
        }
    }

    public func noteRequestFinished(elapsed: Duration) {
        guard pathOnline, connectivity != .serverUnreachable, connectivity != .offline else { return }
        if elapsed > NetworkThresholds.degradedAfter {
            connectivity = .degraded
        } else if connectivity == .degraded {
            connectivity = .online
        }
    }

    public func startPathUpdates() {
        pathTask?.cancel()
        let updates = path.changes()
        pathTask = Task { @MainActor [weak self] in
            for await online in updates {
                self?.applyPath(online)
            }
        }
    }

    public func watch(_ stream: any ServerEventStream) {
        eventTask?.cancel()
        let events = stream.events
        eventTask = Task { @MainActor [weak self] in
            for await event in events {
                await self?.handle(event)
            }
        }
    }

    public func retryNow() async {
        await probeServer()
    }

    public func probeServer() async {
        if Task.isCancelled { return }
        guard pathOnline else {
            enterOffline()
            return
        }
        switch await pinger.ping() {
        case .ok:
            recoverFromServerDown()
        case .failed(let error):
            if SessionTermination.shouldEndSession(error) || AppErrorMapping.isConnectivity(error) {
                handle(error)
            } else if case .tlsUntrusted = error {
                handle(error)
            } else if case .insecureRedirect = error {
                handle(error)
            } else {
                recoverFromServerDown()
            }
        }
    }

    private func endSession() {
        guard case .signedIn(let session) = phase else { return }
        guard !logoutStarted else { return }
        logoutStarted = true
        scope.cancelAll()
        pingTask?.cancel()
        pingArmed = false
        try? secureStore.remove(
            account: SessionCredential.account(serverID: session.server.id, userID: session.userID))
        log.warning("Ended the session after HTTP 401.")
        sessionNoticeKey = AppErrorMessage.sessionExpiredKey
        phase = .needsLogin(session.server)
        activeServer = session.server
        requestGeneration += 1
    }

    private func enterOffline() {
        connectivity = .offline
        bannerKey = AppErrorMessage.offlineKey
        pingArmed = false
        pingTask?.cancel()
    }

    private func enterUnreachable() {
        guard pathOnline else {
            enterOffline()
            return
        }
        connectivity = .serverUnreachable
        bannerKey = nil
        pingArmed = true
        armPingLoop()
    }

    private func recoverFromServerDown() {
        pingArmed = false
        bannerKey = nil
        if connectivity == .serverUnreachable || connectivity == .offline {
            connectivity = .online
        }
    }

    private func applyPath(_ online: Bool) {
        pathOnline = online
        if !online {
            enterOffline()
            return
        }
        guard connectivity == .offline else { return }
        bannerKey = nil
        connectivity = .online
        onReconnect?()
        scheduleProbe()
    }

    private func scheduleProbe() {
        probeTask?.cancel()
        probeTask = Task { @MainActor [weak self] in
            await self?.probeServer()
        }
    }

    private func armPingLoop() {
        guard automaticPing, pingTask == nil else { return }
        let generation = UUID()
        pingGeneration = generation
        pingTask = Task { @MainActor [weak self] in
            await self?.runPingLoop()
            if self?.pingGeneration == generation {
                self?.pingTask = nil
            }
        }
    }

    private func runPingLoop() async {
        while !Task.isCancelled {
            guard connectivity == .serverUnreachable, pingArmed else { return }
            do {
                try await clock.sleep(for: scheduledPingDelay)
            } catch {
                return
            }
            if Task.isCancelled { return }
            await probeServer()
        }
    }

    private func handle(_ event: ServerEvent) async {
        switch event {
        case .userDataChanged(let items):
            let interval = signposter.begin(.remoteUserData)
            for item in items {
                await userData.applyRemote(item, log: log)
            }
            await responses.invalidateAll()
            userDataGeneration += 1
            signposter.end(interval)
        case .libraryChanged:
            await responses.invalidateAll()
            libraryGeneration += 1
        case .serverShuttingDown, .serverRestarting:
            enterUnreachable()
        case .play, .playstate, .generalCommand:
            break
        }
    }
}
