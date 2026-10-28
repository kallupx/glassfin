import CoreModels
import CoreNetworking
import Foundation
import Observation

/// Authentication screens and the rules that move between them.
/// Tokens and Quick Connect secrets are not published and are not logged.
@MainActor
@Observable
public final class AuthFlow: ViewContentProviding {
    public private(set) var screen: AuthScreen = .welcome
    public private(set) var focus: AuthFocus = .connect
    public private(set) var inlineError: AuthCopy.Key?
    public private(set) var httpSkippedByPolicy = false
    public private(set) var noticeKey: AuthCopy.Key?
    public private(set) var isProbing = false
    public private(set) var isPolling = false
    public private(set) var isSigningOut = false
    public private(set) var quickConnectCode: String?
    public private(set) var quickConnectExpired = false
    public private(set) var quickConnectRenewals = 0
    public private(set) var cachedHome: HomeSnapshot?
    /// Minimal M09 hook: credentials remain inside the core assembly.
    public func makeSearchFeature(client override: (any JellyfinAPIClient)? = nil) throws(APIError) -> SearchFeature? {
        guard case .signedIn(let session) = app.phase,
            let token = loadToken(serverID: session.server.id, userID: session.userID),
            let deviceID = try? DeviceIdentityStore.loadOrCreate(secureStore: vault.secureStore, reset: false)
        else { return nil }
        let certificatePin = try pins.certificatePin(for: session.server.id, url: session.server.url)
        let identity = ClientIdentity(deviceName: "Apple TV", deviceID: deviceID, version: "0.1.0", token: token)
        let client =
            override
            ?? HTTPJellyfinClient(
                server: session.server.url, identity: identity,
                certificatePin: certificatePin)
        return SearchFeature(app: app, session: session, client: client)
    }

    /// Minimal M06 composition hook; authentication remains owned by this flow.
    public var homeApp: AppState { app }

    public func makeHomeClient() throws(APIError) -> any JellyfinAPIClient {
        guard case .signedIn(let session) = app.phase,
            let token = loadToken(serverID: session.server.id, userID: session.userID),
            let live = backend as? LiveAuthBackend
        else { throw .network }
        return HomeSessionClient(
            inner: try live.makeClient(for: session.server, token: token), app: app, scope: app.scope)
    }

    public func makeHomeEvents() throws -> any ServerEventStream {
        guard case .signedIn(let session) = app.phase,
            let token = loadToken(serverID: session.server.id, userID: session.userID),
            let live = backend as? LiveAuthBackend,
            let http = try live.makeClient(for: session.server, token: token) as? HTTPJellyfinClient
        else { throw APIError.network }
        let app = app
        let sockets = try URLSessionEventSocketFactory(
            server: http.server, identity: http.identity, pin: http.certificatePin,
            onUnauthorized: { await app.handle(.unauthorized) })
        return ReconnectingServerEventStream(
            request: try SocketRequestBuilder.make(server: http.server, identity: http.identity),
            sockets: sockets, clock: SystemGlassfinClock(), jitter: SystemJitter())
    }

    public var appPhase: AppState.Phase { app.phase }
    /// Shared signed-in state for feature composition; authentication still owns the session.
    public var featureApp: AppState { app }

    /// Loads credentials only inside the core; the UI never receives the token.
    public func makeFeatureClient() throws(APIError) -> any JellyfinAPIClient {
        guard case .signedIn(let session) = app.phase,
            let token = loadToken(serverID: session.server.id, userID: session.userID)
        else { throw .unauthorized }
        let pin = try pins.certificatePin(for: session.server.id, url: session.server.url)
        let deviceID: String
        do { deviceID = try DeviceIdentityStore.loadOrCreate(secureStore: vault.secureStore, reset: false) } catch {
            throw .headerRejected
        }
        let identity = ClientIdentity(
            deviceName: "Apple TV", deviceID: deviceID,
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0",
            token: token)
        return SessionFeatureClient(
            inner: RetryingAPIClient(
                inner: HTTPJellyfinClient(server: session.server.url, identity: identity, certificatePin: pin),
                clock: clock), app: app)
    }
    public var settingsApp: AppState { app }
    public var connectivity: Connectivity { app.connectivity }
    /// The M04 Home tab renders cached sections until the Home feature screen is installed.
    public var hasContent: Bool {
        guard let cachedHome else { return false }
        return [cachedHome.resume, cachedHome.nextUp, cachedHome.latest].contains { !$0.isEmpty }
    }

    public func onAppear() {
        app.currentView = self
    }

    public var homeErrorKey: AuthCopy.Key? {
        guard !hasContent else { return nil }
        switch app.connectivity {
        case .offline, .serverUnreachable: return app.isServerStarting ? .serverStarting : .serverUnreachable
        case .online, .degraded: return nil
        }
    }
    public var bannerKey: AuthCopy.Key? {
        switch app.bannerKey {
        case AppErrorMessage.offlineKey: .noNetworkConnection
        case AppErrorMessage.serverDownKey: .serverUnreachable
        case AppErrorMessage.serverStartingKey: .serverStarting
        default: nil
        }
    }
    public private(set) var displayedName = ""
    public private(set) var displayedVersion = ""
    public private(set) var certificate: CertificatePresentation?
    public var canAcceptCertificate: Bool {
        guard let certificate, certificateURL != nil else { return false }
        return CertificateFingerprint.isValid(CertificateFingerprint.normalize(certificate.sha256))
    }
    public private(set) var mismatchPrevious: String?
    public private(set) var mismatchPresented: CertificatePresentation?
    public private(set) var setupAddress: URL?
    public private(set) var unsupportedVersion = ""
    public private(set) var publicUsers: [PublicUser] = []
    public private(set) var passwordCleared = true
    public private(set) var quickConnectEnabled = false
    public private(set) var confirmFocus: AuthFocus?
    public var addressText = ""
    public var username = ""

    @ObservationIgnored private let app: AppState
    @ObservationIgnored private let backend: any AuthBackend
    @ObservationIgnored private let pins: any CertificatePinStore
    @ObservationIgnored private let vault: CredentialVault
    @ObservationIgnored private let clock: any GlassfinClock
    @ObservationIgnored private let log: any GlassfinLog
    @ObservationIgnored private var server: ServerInfo?
    @ObservationIgnored private var certificateURL: URL?
    @ObservationIgnored private var acceptedCertificatePin: OriginCertificatePin?
    @ObservationIgnored private var acceptedPinToStore: String?
    @ObservationIgnored private var quickConnectSecret: QuickConnectSecret?
    @ObservationIgnored private var probeTask: Task<Void, Never>?
    // Tests can retain and await a cancelled poll after pausePolling clears this reference.
    @ObservationIgnored private(set) var pollTask: Task<Void, Never>?
    @ObservationIgnored private var quickConnectIssuedAt: Duration?
    @ObservationIgnored private var pollGeneration = UUID()
    @ObservationIgnored private var isBackground = false
    @ObservationIgnored private var capabilitiesRetryInFlight = false

    public init(
        app: AppState,
        backend: any AuthBackend,
        pins: any CertificatePinStore,
        vault: CredentialVault,
        clock: any GlassfinClock,
        log: any GlassfinLog = SilentLog()
    ) {
        self.app = app
        self.backend = backend
        self.pins = pins
        self.vault = vault
        self.clock = clock
        self.log = log
        app.startPathUpdates()
    }

    public func connect() {
        screen = .address
        inlineError = nil
        httpSkippedByPolicy = false
        focus = AuthFocusPolicy.address(fieldIsEmpty: addressText.isEmpty)
    }

    public func submitAddress() {
        probeTask?.cancel()
        let address = addressText
        let backend = backend
        let candidates = ServerAddressCandidates.expand(address).candidates.map(\.url)
        if !candidates.contains(where: { acceptedCertificatePin?.fingerprint(for: $0) != nil }) {
            acceptedCertificatePin = nil
            acceptedPinToStore = nil
        }
        server = nil
        displayedName = ""
        displayedVersion = ""
        certificate = nil
        certificateURL = nil
        mismatchPrevious = nil
        mismatchPresented = nil
        isProbing = true
        inlineError = nil
        httpSkippedByPolicy = false
        let certificatePin: OriginCertificatePin?
        do {
            let storedPin = try candidates.compactMap { url in
                try pinnedMatch(for: url).map { OriginCertificatePin(url: url, sha256: $0.fingerprint) }
            }.first
            certificatePin = acceptedCertificatePin ?? storedPin
        } catch {
            failPinLookup()
            return
        }
        probeTask = Task {
            let outcome = await backend.probe(address, certificatePin: certificatePin)
            guard !Task.isCancelled else { return }
            isProbing = false
            await apply(outcome)
        }
    }

    public func cancelProbe() {
        probeTask?.cancel()
        isProbing = false
    }

    public func acceptCleartext() async {
        guard let server else { return }
        await showLogin(for: server)
    }

    public func rejectCleartext() {
        server = nil
        screen = .address
        focus = AuthFocusPolicy.address(fieldIsEmpty: addressText.isEmpty)
    }

    public func acceptCertificate(userAcceptedFingerprint: String) throws {
        guard canAcceptCertificate, let leaf = certificate, let url = certificateURL,
            ServerAddressCandidates.expand(addressText).candidates.contains(where: {
                RedirectPolicy.originsMatch($0.url, url)
            })
        else { return }
        let storedFingerprint: String?
        do {
            storedFingerprint = try pinnedMatch(for: url)?.fingerprint
        } catch {
            failPinLookup()
            throw error
        }
        let outcome = SelfSignedTrustFlow.handle(
            isSystemTrusted: false, leaf: leaf,
            pinnedSHA256: storedFingerprint,
            userAcceptedFingerprint: userAcceptedFingerprint
        )
        switch outcome.decision {
        case .usePinnedCredential:
            // Only the trust outcome supplies new pin bytes. No ID is invented before the probe succeeds.
            let fingerprint = outcome.pinToStore ?? storedFingerprint
            guard let fingerprint else { return }
            acceptedCertificatePin = OriginCertificatePin(url: url, sha256: fingerprint)
            acceptedPinToStore = outcome.pinToStore
            screen = .address
            submitAddress()
        case .cancelPinMismatch(let previous, let presented):
            mismatchPrevious = previous
            mismatchPresented = presented
            screen = .certificateMismatch
            focus = AuthFocusPolicy.cleartextAndCertificate
        case .cancelUntrusted, .performDefaultHandling:
            screen = .address
            focus = AuthFocusPolicy.address(fieldIsEmpty: addressText.isEmpty)
        }
    }

    public func rejectCertificate() {
        screen = .address
        certificate = nil
        certificateURL = nil
        acceptedCertificatePin = nil
        acceptedPinToStore = nil
        focus = AuthFocusPolicy.address(fieldIsEmpty: addressText.isEmpty)
    }

    public func retrySetup() {
        screen = .address
        setupAddress = nil
        focus = AuthFocusPolicy.address(fieldIsEmpty: addressText.isEmpty)
        submitAddress()
    }

    public func selectUser(_ user: PublicUser) {
        username = user.name
        enterMethod()
    }

    public func chooseQuickConnect() async {
        guard quickConnectEnabled else { return }
        screen = .quickConnect
        focus = .quickConnectCode
        inlineError = nil
        if await beginQuickConnectIfNeeded() { startPolling() }
    }

    public func getNewQuickConnectCode() async {
        stopPolling()
        quickConnectRenewals = 0
        await chooseQuickConnect()
    }

    public func choosePassword() {
        screen = .credentials
        focus = username.isEmpty ? .username : .password
    }

    public func signIn(password: String) async {
        guard let server else { return }
        var field = PasswordField(password)
        let backend = backend
        let name = username
        do {
            let session = try await field.authenticate { @Sendable value in
                try await backend.signIn(on: server, username: name, password: value)
            }
            passwordCleared = field.isEmpty
            try await complete(session)
        } catch let error as APIError {
            passwordCleared = field.isEmpty
            handleLogin(error)
        } catch {
            passwordCleared = field.isEmpty
            inlineError = .loginTransportFailure
        }
    }

    public func restoreSession() async {
        let stillAtWelcome = screen == .welcome
        app.bootstrap()
        guard case .signedIn(let session) = app.phase else {
            if stillAtWelcome {
                if case .needsLogin(let saved) = app.phase {
                    addressText = saved.url.absoluteString
                    if app.blockingError != nil {
                        server = saved
                        unsupportedVersion = ServerVersionGate.dotted(saved.version)
                        screen = .unsupported
                        focus = .back
                    } else {
                        await showLogin(for: saved)
                    }
                } else {
                    screen = .welcome
                }
            }
            return
        }
        server = session.server
        addressText = session.server.url.absoluteString
        cachedHome = app.snapshots.load()
        displayedName = AuthServerName.display(session.server.name, host: session.server.url.host ?? "")
        displayedVersion = ServerVersionGate.dotted(session.server.version)
        guard let token = loadToken(serverID: session.server.id, userID: session.userID) else {
            screen = .home
            return
        }
        let backend = backend
        let clock = clock
        let result = await TimedCall.value(timeout: AuthSessionTiming.currentUserTimeout, clock: clock) {
            () async throws(APIError) -> UserSession in
            try await backend.currentUser(on: session.server, token: token)
        }
        switch result {
        case .success:
            app.sessionRestored()
            screen = .home
            noticeKey = nil
            inlineError = nil
            await retryCapabilitiesIfNeeded()
        case .failure(let error):
            let mapped = AppErrorMapping.map(error, context: .authenticated, deviceOffline: false)
            if CoreModels.SessionTermination.shouldEndSession(mapped) {
                screen = .signedOut
                app.handle(mapped)
                noticeKey = .sessionExpired
                await showLogin(for: session.server, includePublicUsers: false)
                return
            }
            if mapped == .cancelled { return }
            app.handle(mapped)
            if mapped != .serverStarting { app.handle(.serverUnreachable) }
            inlineError = nil
            screen = .home
            focus = .tryAgain
            await retryCapabilitiesIfNeeded()
        }
    }

    public func requestLogout() {
        guard case .signedIn = app.phase else { return }
        screen = .logoutConfirm
        confirmFocus = .cancel
        focus = .cancel
    }

    public func confirmLogout() async {
        guard !isSigningOut, case .signedIn(let session) = app.phase else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        var serverFailed = true
        if let token = loadToken(serverID: session.server.id, userID: session.userID) {
            do {
                try await backend.logout(on: session.server, token: token)
                serverFailed = false
            } catch {
                serverFailed = true
            }
        }
        screen = .signedOut
        app.signOutLocally(notice: nil)
        stopPolling()
        noticeKey = serverFailed ? .serverSessionMayRemain : nil
        server = session.server
        addressText = session.server.url.absoluteString
        quickConnectEnabled = (try? await backend.quickConnectEnabled(on: session.server)) ?? false
        let others = app.preferencesSnapshot().users.filter {
            $0.serverID == session.server.id && $0.userID != session.userID
        }
        publicUsers = others.map { PublicUser(id: $0.userID, name: $0.userName, host: session.server.url.host ?? "") }
        username = ""
        inlineError = nil
        if !publicUsers.isEmpty {
            screen = .userPicker
            focus = .continueButton
        } else {
            enterMethod()
        }
    }

    public func cancelLogout() {
        guard !isSigningOut else { return }
        screen = .home
        confirmFocus = nil
        focus = homeErrorKey == nil ? .connect : .tryAgain
    }

    public func removeCurrentServer() {
        cancelProbe()
        acceptedCertificatePin = nil
        acceptedPinToStore = nil
        certificate = nil
        certificateURL = nil
        guard let id = server?.id ?? app.activeServer?.id else {
            screen = .welcome
            return
        }
        try? pins.remove(serverID: id)
        app.removeServer(id: id)
        server = nil
        quickConnectSecret = nil
        screen = .welcome
        focus = .connect
    }

    public func sceneBecameBackground() {
        isBackground = true
        pausePolling()
    }

    public func sceneBecameActive() async {
        isBackground = false
        if screen == .quickConnect, let issued = quickConnectIssuedAt, !quickConnectExpired {
            if clock.now() - issued >= QuickConnectSecurity.timeout {
                await renewExpiredCode()
            } else {
                // The monitor checks once immediately before sleeping for its next poll.
                startPolling()
            }
        }
        await retryCapabilitiesIfNeeded()
    }

    public func retryHome() async {
        await restoreSession()
    }

    public func retryServerStarting() async {
        inlineError = nil
        switch screen {
        case .address:
            submitAddress()
        case .quickConnect:
            // Keep the current code and secret when polling was interrupted by startup.
            await chooseQuickConnect()
        default:
            if let server { await showLogin(for: server) }
        }
    }

    public func synchronizeSession() async {
        if case .needsServer = app.phase, screen == .home {
            screen = .welcome
            focus = .connect
            return
        }
        if case .needsLogin(let saved) = app.phase, screen == .home || screen == .logoutConfirm {
            screen = .signedOut
            noticeKey = .sessionExpired
            await showLogin(for: saved, includePublicUsers: false)
        }
    }

    public func goBack() {
        switch screen {
        case .welcome:
            return
        case .address, .signedOut:
            stopPolling()
            screen = .welcome
            focus = .connect
        case .cleartext, .certificate, .certificateMismatch, .unsupported, .setupIncomplete, .userPicker:
            screen = .address
            focus = AuthFocusPolicy.address(fieldIsEmpty: addressText.isEmpty)
        case .loginMethod:
            screen = .address
            focus = AuthFocusPolicy.address(fieldIsEmpty: addressText.isEmpty)
        case .quickConnect:
            stopPolling()
            screen = .loginMethod
            focus = quickConnectEnabled ? .quickConnect : .usePassword
        case .credentials:
            screen = quickConnectEnabled ? .loginMethod : .address
            focus = quickConnectEnabled ? .quickConnect : AuthFocusPolicy.address(fieldIsEmpty: addressText.isEmpty)
        case .home:
            return
        case .logoutConfirm:
            cancelLogout()
        }
    }

    private func apply(_ outcome: ServerProbeOutcome) async {
        if case .cancelled = outcome { return }
        switch outcome {
        case .serverStarting:
            // Accepted trust remains provisional until a normal, identified server response arrives.
            inlineError = .serverStarting
            screen = .address
            focus = .tryAgain
        case .ready(let info):
            if let pin = acceptedPinToStore, acceptedCertificatePin?.fingerprint(for: info.url) == pin {
                do {
                    try pins.save(fingerprint: pin, serverID: info.id)
                    acceptedPinToStore = nil
                } catch {
                    inlineError = .loginTransportFailure
                    screen = .address
                    return
                }
            }
            await showLogin(for: info)
        case .needsCleartext(let info):
            server = info
            displayedName = AuthServerName.display(info.name, host: info.url.host ?? "")
            displayedVersion = ServerVersionGate.dotted(info.version)
            screen = .cleartext
            focus = AuthFocusPolicy.cleartextAndCertificate
        case .needsCertificate(let leaf, let url):
            presentCertificate(leaf, url: url)
        case .publicHTTPRejected:
            inlineError = .publicAddressRequiresHTTPS
            httpSkippedByPolicy = false
            screen = .address
        case .notFound(let detail):
            inlineError = .serverNotFound
            httpSkippedByPolicy = detail.httpSkippedByPolicy
            screen = .address
        case .notJellyfin(let detail):
            inlineError = .notJellyfin
            httpSkippedByPolicy = detail.httpSkippedByPolicy
            screen = .address
        case .unsupported(let version, let info):
            server = info
            unsupportedVersion = version
            displayedName = AuthServerName.display(info.name, host: info.url.host ?? "")
            screen = .unsupported
            focus = .back
        case .setupIncomplete(let address):
            displayedName = AuthServerName.display("", host: address.host ?? "")
            setupAddress = address
            screen = .setupIncomplete
            focus = .tryAgain
        case .userinfoRejected:
            inlineError = .userinfoRejected
            screen = .address
        case .invalidAddress:
            inlineError = .invalidAddress
            screen = .address
        case .cancelled:
            return
        }
    }

    private func presentCertificate(_ leaf: CertificatePresentation, url: URL) {
        certificate = leaf
        certificateURL = url
        displayedName =
            app.preferencesSnapshot().servers.first {
                RedirectPolicy.originsMatch($0.url, url)
            }.map { AuthServerName.display($0.name, host: url.host ?? "") }
            ?? AuthServerName.display("", host: url.host ?? "")
        let match: (serverID: String, fingerprint: String)?
        do {
            match = try pinnedMatch(for: url)
        } catch {
            failPinLookup()
            return
        }
        if let match {
            let decision = SelfSignedTrustFlow.handle(
                isSystemTrusted: false,
                leaf: leaf,
                pinnedSHA256: match.fingerprint,
                userAcceptedFingerprint: nil
            )
            if case .cancelPinMismatch(let previous, let presented) = decision.decision {
                mismatchPrevious = previous
                mismatchPresented = presented
                screen = .certificateMismatch
                focus = AuthFocusPolicy.cleartextAndCertificate
                return
            }
        }
        screen = .certificate
        focus = AuthFocusPolicy.cleartextAndCertificate
    }

    private func showLogin(for info: ServerInfo, includePublicUsers: Bool = true) async {
        server = info
        displayedName = AuthServerName.display(info.name, host: info.url.host ?? "")
        displayedVersion = ServerVersionGate.dotted(info.version)
        do {
            quickConnectEnabled = try await backend.quickConnectEnabled(on: info)
        } catch {
            quickConnectEnabled = false
            if error == .server(status: 503) {
                screen = .address
                inlineError = .serverStarting
                focus = .tryAgain
                return
            }
        }
        let savedUsers = app.preferencesSnapshot().users.filter { $0.serverID == info.id }
        publicUsers =
            includePublicUsers
            ? savedUsers.map { PublicUser(id: $0.userID, name: $0.userName, host: info.url.host ?? "") } : []
        if publicUsers.count > 1 {
            screen = .userPicker
            focus = .continueButton
            return
        }
        if publicUsers.count == 1 {
            username = publicUsers[0].name
        }
        enterMethod()
    }

    private func enterMethod() {
        inlineError = nil
        if quickConnectEnabled {
            screen = .loginMethod
            focus = .quickConnect
        } else {
            choosePassword()
        }
    }

    private func beginQuickConnectIfNeeded() async -> Bool {
        if quickConnectSecret != nil { return true }
        guard let server, screen == .quickConnect, !isBackground else { return false }
        let generation = pollGeneration
        do {
            let challenge = try await backend.beginQuickConnect(on: server)
            guard generation == pollGeneration, screen == .quickConnect, !isBackground else { return false }
            quickConnectCode = challenge.code
            quickConnectSecret = QuickConnectSecret(challenge.secret)
            quickConnectIssuedAt = clock.now()
            quickConnectExpired = false
            return true
        } catch {
            guard generation == pollGeneration else { return false }
            inlineError = loginErrorKey(error, quickConnect: true)
            focus = .newCode
            return false
        }
    }

    private func startPolling() {
        guard let secret = quickConnectSecret, let code = quickConnectCode, let server,
            let issued = quickConnectIssuedAt, screen == .quickConnect, !isBackground
        else { return }
        pausePolling()
        let generation = pollGeneration
        isPolling = true
        let backend = backend
        let clock = clock
        let log = log
        let remaining = QuickConnectSecurity.timeout - (clock.now() - issued)
        pollTask = Task {
            let monitor = QuickConnectMonitor(clock: clock, timeout: max(.zero, remaining))
            let outcome = await monitor.run(secret: secret, code: code, log: log) { revealed in
                if Task.isCancelled { return .pending }
                do {
                    let accepted = try await backend.pollQuickConnect(on: server, secret: QuickConnectSecret(revealed))
                    return accepted ? .authenticated : .pending
                } catch {
                    if (error as? APIError) == .server(status: 503) {
                        return .serverStarting
                    }
                    return .pending
                }
            }
            guard !Task.isCancelled, generation == self.pollGeneration else { return }
            await self.finishPoll(outcome, server: server, secret: secret, generation: generation)
        }
    }

    private func finishPoll(
        _ outcome: QuickConnectOutcome, server: ServerInfo, secret: QuickConnectSecret, generation: UUID
    ) async {
        isPolling = false
        switch outcome {
        case .serverStarting:
            pollTask = nil
            inlineError = .serverStarting
            focus = .tryAgain
        case .authenticated:
            do {
                let session = try await backend.finishQuickConnect(on: server, secret: secret)
                guard generation == pollGeneration, screen == .quickConnect, !isBackground else { return }
                quickConnectSecret = nil
                pollTask = nil
                try await complete(session)
            } catch {
                guard generation == pollGeneration else { return }
                inlineError = loginErrorKey(error as? APIError ?? .network, quickConnect: true)
                focus = .newCode
            }
        case .expired:
            pollTask = nil
            await renewExpiredCode()
        case .cancelled:
            break
        }
    }

    private func renewExpiredCode() async {
        pausePolling()
        quickConnectSecret = nil
        quickConnectCode = nil
        guard quickConnectRenewals < 3 else {
            quickConnectExpired = true
            inlineError = .quickConnectExpired
            focus = .newCode
            return
        }
        quickConnectRenewals += 1
        if await beginQuickConnectIfNeeded() { startPolling() }
    }

    private func pausePolling() {
        pollGeneration = UUID()
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
    }

    private func stopPolling() {
        pausePolling()
        quickConnectSecret = nil
        quickConnectCode = nil
        quickConnectIssuedAt = nil
        quickConnectRenewals = 0
        quickConnectExpired = false
    }

    private func complete(_ session: AuthenticatedSession) async throws {
        try persist(session)
        app.setCapabilitiesRetryPending(true, serverID: session.session.server.id, userID: session.session.userID)
        stopPolling()
        screen = .home
        inlineError = nil
        noticeKey = nil
        focus = .connect
        capabilitiesRetryInFlight = true
        defer { capabilitiesRetryInFlight = false }
        do {
            try await backend.postCapabilities(on: session.session.server, token: session.accessToken)
            app.setCapabilitiesRetryPending(false, serverID: session.session.server.id, userID: session.session.userID)
        } catch {
            log.warning("Capabilities registration failed; one retry is pending.")
            if error == .server(status: 503) { app.handle(.serverStarting) }
        }
    }

    private func retryCapabilitiesIfNeeded() async {
        guard !capabilitiesRetryInFlight, case .signedIn(let session) = app.phase,
            app.preferencesSnapshot().activeUser()?.capabilitiesRetryPending == true,
            let token = loadToken(serverID: session.server.id, userID: session.userID)
        else { return }
        capabilitiesRetryInFlight = true
        defer { capabilitiesRetryInFlight = false }
        // Consume before the request so a failed retry is not repeated on every foreground.
        app.setCapabilitiesRetryPending(false, serverID: session.server.id, userID: session.userID)
        do {
            try await backend.postCapabilities(on: session.server, token: token)
        } catch {
            log.warning("Capabilities registration retry failed.")
            if error == .server(status: 503) { app.handle(.serverStarting) }
        }
    }

    private func loginErrorKey(_ error: APIError, quickConnect: Bool = false) -> AuthCopy.Key? {
        switch error {
        case .cancelled: nil
        case .unauthorized: quickConnect ? .quickConnectUnauthorized : .invalidCredentials
        case .server(status: 503): .serverStarting
        case .server: .loginServerFailure
        default: .loginTransportFailure
        }
    }

    private func persist(_ session: AuthenticatedSession) throws(PreferencesError) {
        let user = session.session
        let profile = StoredSessionProfile(
            serverID: user.server.id, serverName: user.server.name,
            serverURL: user.server.url.absoluteString, userID: user.userID,
            userName: user.userName, isAdministrator: user.isAdministrator
        )
        do {
            try vault.save(token: session.accessToken, serverID: user.server.id, userID: user.userID, profile: profile)
        } catch {
            throw .keychainFailed
        }
        try app.publishSignedIn(user)
    }

    private func handleLogin(_ error: APIError) {
        inlineError = loginErrorKey(error)
        if error == .unauthorized { focus = .password }
    }

    private func loadToken(serverID: String, userID: String) -> String? {
        try? vault.loadToken(serverID: serverID, userID: userID)
    }

    private func failPinLookup() {
        isProbing = false
        acceptedCertificatePin = nil
        acceptedPinToStore = nil
        certificate = nil
        certificateURL = nil
        inlineError = .loginTransportFailure
        screen = .address
        focus = AuthFocusPolicy.address(fieldIsEmpty: addressText.isEmpty)
    }

    private func pinnedMatch(for url: URL) throws(APIError) -> (serverID: String, fingerprint: String)? {
        for stored in app.preferencesSnapshot().servers where RedirectPolicy.originsMatch(stored.url, url) {
            if let pin = try pins.certificatePin(for: stored.id, url: url) {
                return (stored.id, pin.sha256)
            }
        }
        return nil
    }

}

enum TimedCall {
    static func value<T: Sendable>(
        timeout: Duration,
        clock: any GlassfinClock,
        operation: @escaping @Sendable () async throws(APIError) -> T
    ) async -> Result<T, APIError> {
        await withTaskGroup(of: Result<T, APIError>?.self) { group in
            group.addTask {
                do {
                    return .success(try await operation())
                } catch let error as APIError {
                    return .failure(error)
                } catch is CancellationError {
                    return .failure(.cancelled)
                } catch {
                    return .failure(.network)
                }
            }
            group.addTask {
                do {
                    try await clock.sleep(for: timeout)
                } catch {
                    return nil
                }
                return .failure(.timeout)
            }
            for await next in group {
                if let next {
                    group.cancelAll()
                    return next
                }
            }
            return .failure(.timeout)
        }
    }
}
