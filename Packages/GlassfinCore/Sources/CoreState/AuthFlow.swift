import CoreModels
import CoreNetworking
import Foundation
import Observation

/// Authentication screens and the rules that move between them.
/// Tokens and Quick Connect secrets are not published and are not logged.
@MainActor
@Observable
public final class AuthFlow {
    public private(set) var screen: AuthScreen = .welcome
    public private(set) var focus: AuthFocus = .connect
    public private(set) var inlineError: AuthCopy.Key?
    public private(set) var httpSkippedByPolicy = false
    public private(set) var noticeKey: AuthCopy.Key?
    public private(set) var isProbing = false
    public private(set) var isPolling = false
    public private(set) var quickConnectCode: String?
    public private(set) var displayedName = ""
    public private(set) var displayedVersion = ""
    public private(set) var certificate: CertificatePresentation?
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
    @ObservationIgnored private var quickConnectSecret: QuickConnectSecret?
    @ObservationIgnored private var probeTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var acceptedFingerprint: String?

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
        isProbing = true
        inlineError = nil
        httpSkippedByPolicy = false
        probeTask = Task {
            let outcome = await backend.probe(address)
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
        guard let leaf = certificate else { return }
        let serverID = pinnedMatch(for: leaf)?.serverID ?? server?.id ?? "pending"
        let coordinator = CertificateAcceptanceCoordinator(pins: pins)
        let outcome = try coordinator.apply(
            isSystemTrusted: false,
            leaf: leaf,
            pinnedSHA256: try? pins.fingerprint(for: serverID),
            userAcceptedFingerprint: userAcceptedFingerprint,
            serverID: serverID
        )
        switch outcome.decision {
        case .usePinnedCredential:
            acceptedFingerprint = outcome.pinToStore ?? userAcceptedFingerprint
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
        focus = AuthFocusPolicy.address(fieldIsEmpty: addressText.isEmpty)
    }

    public func retrySetup() {
        screen = .address
        setupAddress = nil
        focus = AuthFocusPolicy.address(fieldIsEmpty: addressText.isEmpty)
    }

    public func selectUser(_ user: PublicUser) {
        username = user.name
        enterMethod()
    }

    public func chooseQuickConnect() async {
        await beginQuickConnectIfNeeded()
        guard quickConnectCode != nil else { return }
        screen = .quickConnect
        focus = .quickConnectCode
        startPolling()
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
            inlineError = AuthOpenQuestions.loginTransportFailureKey
        }
    }

    public func restoreSession() async {
        let stillAtWelcome = screen == .welcome
        app.bootstrap()
        guard case .signedIn(let session) = app.phase else {
            if stillAtWelcome {
                screen = app.phase == .needsServer ? .welcome : .address
                if screen == .address {
                    focus = AuthFocusPolicy.address(fieldIsEmpty: addressText.isEmpty)
                }
            }
            return
        }
        server = session.server
        displayedName = AuthServerName.display(session.server.name)
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
            screen = .home
            noticeKey = nil
        case .failure(let error):
            let mapped = AppErrorMapping.map(error, context: .authenticated, deviceOffline: false)
            if CoreModels.SessionTermination.shouldEndSession(mapped) {
                app.handle(mapped)
                noticeKey = AuthOpenQuestions.sessionEndedNoticeKey
                screen = .loginMethod
                focus = .usePassword
                return
            }
            app.handle(mapped)
            inlineError = AuthOpenQuestions.sessionRestoreFailureKey
            screen = .home
        }
    }

    public func requestLogout() {
        guard case .signedIn = app.phase else { return }
        screen = .logoutConfirm
        confirmFocus = AuthOpenQuestions.logoutConfirmDefaultFocus
    }

    public func confirmLogout() async {
        guard case .signedIn(let session) = app.phase else { return }
        var serverFailed = true
        if let token = loadToken(serverID: session.server.id, userID: session.userID) {
            do {
                try await backend.logout(on: session.server, token: token)
                serverFailed = false
            } catch {
                serverFailed = true
            }
        }
        app.signOutLocally(notice: nil)
        noticeKey = serverFailed ? .serverSessionMayRemain : nil
        applyPostLogout()
    }

    public func cancelLogout() {
        screen = .home
        confirmFocus = nil
    }

    public func removeCurrentServer() {
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
        guard isPolling else { return }
        if !AuthOpenQuestions.continueQuickConnectInBackground {
            stopPolling()
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
        case .ready(let info):
            await showLogin(for: info)
        case .needsCleartext(let info):
            server = info
            displayedName = AuthServerName.display(info.name)
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
            displayedName = AuthServerName.display(info.name)
            screen = .unsupported
            focus = .back
        case .setupIncomplete(let address):
            setupAddress = address
            screen = .setupIncomplete
            focus = .tryAgain
        case .invalidAddress:
            inlineError = .invalidAddress
            screen = .address
        case .cancelled:
            return
        }
    }

    private func presentCertificate(_ leaf: CertificatePresentation, url: URL) {
        certificate = leaf
        if let match = pinnedMatch(for: url) {
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

    private func showLogin(for info: ServerInfo) async {
        server = info
        displayedName = AuthServerName.display(info.name)
        displayedVersion = ServerVersionGate.dotted(info.version)
        quickConnectEnabled = (try? await backend.quickConnectEnabled(on: info)) ?? false
        publicUsers = (try? await backend.publicUsers(on: info)) ?? []
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
        if quickConnectEnabled {
            screen = .loginMethod
            focus = .quickConnect
            if AuthOpenQuestions.initiateQuickConnectOnMethodEntry {
                Task { await beginQuickConnectIfNeeded() }
            }
            return
        }
        switch AuthOpenQuestions.quickConnectDisabledPresentation {
        case .passwordOnly:
            screen = .credentials
            focus = .password
        case .methodScreen:
            screen = .loginMethod
            focus = .usePassword
        }
    }

    private func beginQuickConnectIfNeeded() async {
        guard quickConnectSecret == nil, let server else { return }
        do {
            let challenge = try await backend.beginQuickConnect(on: server)
            quickConnectCode = challenge.code
            quickConnectSecret = QuickConnectSecret(challenge.secret)
        } catch {
            inlineError = AuthOpenQuestions.loginTransportFailureKey
        }
    }

    private func startPolling() {
        guard let secret = quickConnectSecret, let code = quickConnectCode, let server else { return }
        pollTask?.cancel()
        isPolling = true
        let backend = backend
        let clock = clock
        let log = log
        pollTask = Task {
            let monitor = QuickConnectMonitor(clock: clock)
            let outcome = await monitor.run(secret: secret, code: code, log: log) { revealed in
                if Task.isCancelled { return .pending }
                do {
                    let accepted = try await backend.pollQuickConnect(
                        on: server, secret: QuickConnectSecret(revealed))
                    return accepted ? .authenticated : .pending
                } catch {
                    return .pending
                }
            }
            if Task.isCancelled {
                self.isPolling = false
                return
            }
            await self.finishPoll(outcome, server: server, secret: secret)
        }
    }

    private func finishPoll(_ outcome: QuickConnectOutcome, server: ServerInfo, secret: QuickConnectSecret) async {
        isPolling = false
        switch outcome {
        case .authenticated:
            do {
                let session = try await backend.finishQuickConnect(on: server, secret: secret)
                quickConnectSecret = nil
                try await complete(session)
            } catch let error as APIError {
                if SessionFailurePolicy.effect(of: error, kind: .login) == .invalidCredentials {
                    inlineError = AuthOpenQuestions.quickConnectUnauthorizedKey
                } else {
                    inlineError = AuthOpenQuestions.loginTransportFailureKey
                }
            } catch {
                inlineError = AuthOpenQuestions.loginTransportFailureKey
            }
        case .expired:
            if AuthOpenQuestions.renewQuickConnectCodeAtTimeout {
                quickConnectSecret = nil
                quickConnectCode = nil
                await beginQuickConnectIfNeeded()
                startPolling()
            }
        case .cancelled:
            break
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        isPolling = false
        quickConnectSecret = nil
    }

    private func complete(_ session: AuthenticatedSession) async throws {
        let blocks = AuthOpenQuestions.capabilitiesFailureBlocksSignIn
        do {
            try await backend.postCapabilities(on: session.session.server, token: session.accessToken)
        } catch {
            if blocks {
                inlineError = AuthOpenQuestions.loginTransportFailureKey
                return
            }
        }
        try persist(session)
        quickConnectSecret = nil
        quickConnectCode = nil
        screen = .home
        focus = .connect
    }

    private func persist(_ session: AuthenticatedSession) throws(PreferencesError) {
        let user = session.session
        if (try? CredentialVault.tokenAccount(serverID: user.server.id, userID: user.userID)) != nil {
            let profile = StoredSessionProfile(
                serverID: user.server.id,
                serverName: user.server.name,
                serverURL: user.server.url.absoluteString,
                userID: user.userID,
                userName: user.userName,
                isAdministrator: user.isAdministrator
            )
            do {
                try vault.save(
                    token: session.accessToken, serverID: user.server.id, userID: user.userID, profile: profile)
            } catch {
                throw .keychainFailed
            }
            try app.publishSignedIn(user)
        } else {
            try app.didSignIn(user, token: session.accessToken)
        }
    }

    private func handleLogin(_ error: APIError) {
        switch SessionFailurePolicy.effect(of: error, kind: .login) {
        case .invalidCredentials:
            inlineError = .invalidCredentials
            focus = .password
        case .endSession, .keepToken:
            inlineError = AuthOpenQuestions.loginTransportFailureKey
        }
    }

    private func loadToken(serverID: String, userID: String) -> String? {
        if let token = try? vault.loadToken(serverID: serverID, userID: userID), !token.isEmpty {
            return token
        }
        let account = SessionCredential.account(serverID: serverID, userID: userID)
        guard let data = try? vault.secureStore.data(for: account), !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private func pinnedMatch(for url: URL) -> (serverID: String, fingerprint: String)? {
        for stored in app.preferencesSnapshot().servers where stored.url.host?.lowercased() == url.host?.lowercased() {
            if let fingerprint = try? pins.fingerprint(for: stored.id) {
                return (stored.id, fingerprint)
            }
        }
        return nil
    }

    private func pinnedMatch(for leaf: CertificatePresentation) -> (serverID: String, fingerprint: String)? {
        _ = leaf
        if let server, let fingerprint = try? pins.fingerprint(for: server.id) {
            return (server.id, fingerprint)
        }
        return nil
    }

    private func applyPostLogout() {
        switch AuthOpenQuestions.postLogoutScreen {
        case .welcome:
            screen = .welcome
            focus = .connect
        case .address:
            screen = .address
            focus = AuthFocusPolicy.address(fieldIsEmpty: addressText.isEmpty)
        case .login:
            screen = .loginMethod
            focus = .usePassword
        case nil:
            screen = .signedOut
            focus = .signIn
        }
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
