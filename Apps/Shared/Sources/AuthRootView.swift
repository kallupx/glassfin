import GlassfinCore
import SwiftUI

struct AuthRootView: View {
    @Bindable var flow: AuthFlow
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var focused: AuthFocus?
    @State private var password = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            panel
                .padding(48)
        }
        .onAppear { focused = flow.focus }
        .onChange(of: flow.focus) { _, focus in
            focused = focus
        }
        .onChange(of: flow.inlineError) { _, error in
            if error == .invalidCredentials {
                password = ""
                focused = .password
            }
        }
        .task { await flow.restoreSession() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { flow.sceneBecameBackground() }
            if phase == .active { Task { await flow.sceneBecameActive() } }
        }
        .onChange(of: flow.appPhase) { _, _ in
            Task { await flow.synchronizeSession() }
        }
    }

    @ViewBuilder
    private var panel: some View {
        switch flow.screen {
        case .welcome:
            welcome
        case .home:
            home
        default:
            Group {
                if reduceTransparency {
                    content.background(.background, in: ConcentricRectangle())
                } else {
                    GlassEffectContainer {
                        content.glassEffect(.regular, in: ConcentricRectangle())
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 24) {
            if flow.screen != .welcome && flow.screen != .home {
                backButton
            }
            switch flow.screen {
            case .welcome:
                EmptyView()
            case .address:
                address
            case .cleartext:
                cleartext
            case .certificate, .certificateMismatch:
                certificate
            case .unsupported:
                message(AuthCopy.localized(.unsupportedServer), detail: flow.unsupportedVersion)
            case .setupIncomplete:
                setup
            case .loginMethod:
                loginMethod
            case .quickConnect:
                quickConnect
            case .userPicker:
                userPicker
            case .credentials:
                credentials
            case .home:
                home
            case .signedOut:
                message(AuthCopy.localized(.signOut), detail: flow.displayedName)
            case .logoutConfirm:
                logoutConfirm
            }
            if let notice = flow.noticeKey {
                Text(verbatim: AuthCopy.localized(notice))
                    .accessibilityIdentifier("auth.notice")
                    .accessibilityValue(notice.rawValue)
            }
            if let error = flow.inlineError {
                Text(verbatim: AuthCopy.localized(error))
                    .accessibilityIdentifier("address.error")
                    .accessibilityValue(error.rawValue)
            }
            if flow.httpSkippedByPolicy {
                Text(verbatim: AuthCopy.localized(.httpOnlyOnLocalNetwork))
                    .accessibilityIdentifier("address.httpSkipped")
            }
        }
        .padding(32)
        .defaultFocus($focused, flow.focus)
        #if os(tvOS)
            .onExitCommand {
                guard flow.screen != .welcome else { return }
                flow.goBack()
            }
        #endif
    }

    private var welcome: some View {
        VStack(spacing: 24) {
            Text(verbatim: AuthCopy.localized(.glassfin))
                .font(.largeTitle)
                .accessibilityIdentifier("welcome.root")
            Button(AuthCopy.localized(.connectToServer)) { flow.connect() }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier(WelcomeCopy.Key.connect.rawValue)
                .focused($focused, equals: .connect)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .defaultFocus($focused, .connect)
    }

    private var address: some View {
        VStack(spacing: 16) {
            TextField(AuthCopy.localized(.serverAddress), text: $flow.addressText)
                .accessibilityIdentifier("address.field")
                .focused($focused, equals: .addressField)
            if flow.isProbing {
                ProgressView()
                    .accessibilityIdentifier("address.loading")
            }
            Button(AuthCopy.localized(.continue)) { flow.submitAddress() }
                .accessibilityIdentifier("address.continue")
                .focused($focused, equals: .continueButton)
            if !flow.displayedName.isEmpty {
                Text(verbatim: flow.displayedName)
                    .accessibilityIdentifier("address.serverName")
                Text(verbatim: flow.displayedVersion)
                    .accessibilityIdentifier("address.serverVersion")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("address.root")
    }

    private var cleartext: some View {
        VStack(spacing: 16) {
            Text(verbatim: AuthCopy.localized(.connectionNotEncrypted))
                .accessibilityIdentifier("cleartext.root")
            Button(AuthCopy.localized(.continueUnencrypted)) { Task { await flow.acceptCleartext() } }
                .accessibilityIdentifier("cleartext.accept")
            Button(AuthCopy.localized(.cancel)) { flow.rejectCleartext() }
                .accessibilityIdentifier("cleartext.cancel")
                .focused($focused, equals: .cancel)
        }
    }

    private var certificate: some View {
        VStack(spacing: 12) {
            Text(verbatim: flow.displayedName)
                .accessibilityIdentifier("certificate.serverName")
            Text(verbatim: flow.certificate?.sha256 ?? flow.mismatchPresented?.sha256 ?? "")
                .accessibilityIdentifier("certificate.fingerprint")
            Text(verbatim: flow.certificate?.subject ?? flow.mismatchPresented?.subject ?? "")
                .accessibilityIdentifier("certificate.subject")
            if let previous = flow.mismatchPrevious {
                Text(verbatim: previous)
                    .accessibilityIdentifier("certificate.previous")
            }
            Text(verbatim: AuthCopy.localized(.certificateChanged))
            if flow.canAcceptCertificate {
                Button(AuthCopy.localized(.accept)) {
                    guard let leaf = flow.certificate else { return }
                    try? flow.acceptCertificate(userAcceptedFingerprint: leaf.sha256)
                }
                .accessibilityIdentifier("certificate.accept")
            }
            Button(AuthCopy.localized(.cancel)) { flow.rejectCertificate() }
                .accessibilityIdentifier("certificate.cancel")
                .focused($focused, equals: .cancel)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("certificate.root")
    }

    private var setup: some View {
        VStack(spacing: 16) {
            Text(verbatim: flow.displayedName)
            Text(verbatim: AuthCopy.setupIncomplete(address: flow.setupAddress?.absoluteString ?? ""))
                .accessibilityIdentifier("setup.root")
            Button(AuthCopy.localized(.tryAgain)) { flow.retrySetup() }
                .accessibilityIdentifier("setup.retry")
                .focused($focused, equals: .tryAgain)
        }
    }

    private var loginMethod: some View {
        VStack(spacing: 16) {
            Text(verbatim: flow.displayedName).accessibilityIdentifier("login.serverName")
            Text(verbatim: flow.displayedVersion).accessibilityIdentifier("login.serverVersion")
            if flow.quickConnectEnabled {
                Button(AuthCopy.localized(.quickConnect)) { Task { await flow.chooseQuickConnect() } }
                    .accessibilityIdentifier("login.quickConnect")
                    .focused($focused, equals: .quickConnect)
            }
            Button(AuthCopy.localized(.usePassword)) { flow.choosePassword() }
                .accessibilityIdentifier("login.password")
                .focused($focused, equals: .usePassword)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("login.root")
    }

    private var quickConnect: some View {
        VStack(spacing: 16) {
            Text(verbatim: flow.quickConnectCode ?? "")
                .font(.largeTitle)
                .accessibilityIdentifier("quickconnect.code")
            Text(verbatim: AuthCopy.localized(.quickConnectInstruction))
                .accessibilityIdentifier("quickconnect.instruction")
            if flow.quickConnectExpired || flow.inlineError != nil {
                Button(AuthCopy.localized(.getNewCode)) { Task { await flow.getNewQuickConnectCode() } }
                    .accessibilityIdentifier("quickconnect.newCode")
                    .focused($focused, equals: .newCode)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quickconnect.root")
        .focused($focused, equals: .quickConnectCode)
    }

    private var userPicker: some View {
        VStack(spacing: 12) {
            Text(verbatim: flow.displayedName)
            ForEach(Array(flow.publicUsers.enumerated()), id: \.element.id) { index, user in
                Button {
                    flow.selectUser(user)
                } label: {
                    Text(verbatim: user.name)
                }
                .accessibilityIdentifier("users.\(user.id)")
                .focused($focused, equals: index == 0 ? .continueButton : nil)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("users.root")
    }

    private var credentials: some View {
        VStack(spacing: 16) {
            TextField(AuthCopy.localized(.username), text: $flow.username)
                .textContentType(.username)
                .accessibilityIdentifier("credentials.username")
                .focused($focused, equals: .username)
            SecureField(AuthCopy.localized(.password), text: $password)
                .textContentType(.password)
                .accessibilityIdentifier("credentials.password")
                .focused($focused, equals: .password)
            Button(AuthCopy.localized(.signIn)) {
                let value = password
                password = ""
                Task { await flow.signIn(password: value) }
            }
            .accessibilityIdentifier("credentials.signIn")
            .focused($focused, equals: .signIn)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("credentials.root")
    }

    private var home: some View {
        TabView {
            Tab(AuthCopy.localized(.home), systemImage: "house") {
                VStack(spacing: 16) {
                    Text(verbatim: AuthCopy.localized(.home)).accessibilityIdentifier("home.root")
                    if let key = flow.bannerKey {
                        Text(verbatim: AuthCopy.localized(key)).accessibilityIdentifier("home.banner")
                    }
                    if let key = flow.homeErrorKey {
                        Text(verbatim: AuthCopy.localized(key)).accessibilityIdentifier("home.error")
                        Button(AuthCopy.localized(.tryAgain)) { Task { await flow.retryHome() } }
                            .accessibilityIdentifier("home.retry")
                            .focused($focused, equals: .tryAgain)
                    } else if let snapshot = flow.cachedHome {
                        ForEach(snapshot.resume + snapshot.nextUp + snapshot.latest, id: \.id) { item in
                            Text(verbatim: item.name)
                        }
                    }
                }
                .defaultFocus($focused, flow.focus)
            }
            Tab(AuthCopy.localized(.settings), systemImage: "gear") {
                VStack(spacing: 16) {
                    Text(verbatim: flow.displayedName)
                        .accessibilityIdentifier("settings.serverName")
                    Button(AuthCopy.localized(.signOut)) { flow.requestLogout() }
                        .accessibilityIdentifier("settings.signOut")
                    Text(
                        verbatim: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                            ?? ""
                    )
                    .accessibilityIdentifier("settings.version")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("settings.root")
            }
        }
    }

    private var logoutConfirm: some View {
        VStack(spacing: 16) {
            Text(verbatim: AuthCopy.localized(.signOutConfirm))
                .accessibilityIdentifier("logout.root")
            Button(AuthCopy.localized(.signOut)) { Task { await flow.confirmLogout() } }
                .accessibilityIdentifier("logout.confirm")
            Button(AuthCopy.localized(.cancel)) { flow.cancelLogout() }
                .accessibilityIdentifier("logout.cancel")
                .focused($focused, equals: .cancel)
        }
    }

    private var backButton: some View {
        Button(AuthCopy.localized(.back)) { flow.goBack() }
            .accessibilityIdentifier("navigation.back")
            .focused($focused, equals: .back)
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Text(verbatim: title)
            Text(verbatim: detail)
        }
    }
}

enum AuthAssembly {
    @MainActor
    static func make(arguments: [String]) -> AuthFlow {
        #if DEBUG
            let configuration = LaunchConfiguration(arguments: arguments)
            if configuration.useMockServer || configuration.resetState {
                return assemble(
                    backend: UITestAuthBackend(), secure: InMemorySecureStore(), settings: InMemorySettingsStore(),
                    clock: arguments.contains("-uitest-qc-expired") ? UITestExpiryClock() : SystemGlassfinClock())
            }
        #else
            _ = arguments
        #endif
        let secure = KeychainSecureStore()
        let settings = UserDefaultsSettingsStore(defaults: .standard)
        return assemble(
            backend: LiveAuthBackend(secureStore: secure, pins: SettingsCertificatePinStore(settings: settings)),
            secure: secure, settings: settings)
    }

    @MainActor
    private static func assemble(
        backend: any AuthBackend, secure: any SecureStore, settings: any SettingsStore,
        clock: any GlassfinClock = SystemGlassfinClock()
    ) -> AuthFlow {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Glassfin", isDirectory: true)
        let app = AppState(
            secureStore: secure,
            settings: settings,
            path: SystemPathMonitor(),
            pinger: AuthAssemblyPinger(backend: backend, settings: settings, secure: secure),
            cacheRoot: root
        )
        let vault = CredentialVault(
            secureStore: secure, settings: settings, accessGroup: KeychainAttributes.production.accessGroup)
        return AuthFlow(
            app: app,
            backend: backend,
            pins: SettingsCertificatePinStore(settings: settings),
            vault: vault,
            clock: clock
        )
    }
}

private struct AuthAssemblyPinger: ReachabilityPinging {
    var backend: any AuthBackend
    var settings: any SettingsStore
    var secure: any SecureStore

    func ping() async -> PingOutcome {
        let prefs = PreferencesRepository(store: settings).load()
        guard let stored = prefs.activeServer(), let user = prefs.activeUser(),
            let version = SemVer(parsing: stored.version)
        else { return .failed(.serverUnreachable) }
        let vault = CredentialVault(
            secureStore: secure, settings: settings, accessGroup: KeychainAttributes.production.accessGroup)
        guard let token = try? vault.loadToken(serverID: stored.id, userID: user.userID) else {
            return .failed(.serverUnreachable)
        }
        let server = ServerInfo(id: stored.id, name: stored.name, url: stored.url, version: version)
        do {
            _ = try await backend.currentUser(on: server, token: token)
            return .ok
        } catch {
            return .failed(error == .unauthorized ? .unauthorized : .serverUnreachable)
        }
    }
}

#if DEBUG
    private struct UITestExpiryClock: GlassfinClock {
        private let origin = ContinuousClock.now
        func now() -> Duration { origin.duration(to: .now) * 3_000 }
        func sleep(for duration: Duration) async throws {
            try await Task.sleep(for: duration / 3_000)
        }
    }

    struct UITestAuthBackend: AuthBackend {
        func probe(_ address: String, certificatePin: OriginCertificatePin?) async -> ServerProbeOutcome {
            let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("http://"), !trimmed.contains("192.168."), !trimmed.contains("10."),
                !trimmed.contains(".local")
            {
                return .publicHTTPRejected
            }
            if trimmed.contains("192.168.") {
                return .needsCleartext(server(url: "http://192.168.1.10:8096"))
            }
            if trimmed.isEmpty { return .invalidAddress }
            return .ready(server(url: "https://media.example"))
        }

        func quickConnectEnabled(on server: ServerInfo) async throws(APIError) -> Bool {
            _ = server
            return !ProcessInfo.processInfo.arguments.contains("-uitest-qc-disabled")
        }

        func beginQuickConnect(on server: ServerInfo) async throws(APIError) -> QuickConnectChallenge {
            _ = server
            return QuickConnectChallenge(code: "482913", secret: "uitest-secret", authenticated: false)
        }

        func pollQuickConnect(on server: ServerInfo, secret: QuickConnectSecret) async throws(APIError) -> Bool {
            _ = server
            _ = secret
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-uitest-qc-expired") || arguments.contains("-uitest-qc-pending") { return false }
            do { try await Task.sleep(for: .seconds(2)) } catch { throw APIError.cancelled }
            return true
        }

        func signIn(on server: ServerInfo, username: String, password: String) async throws(APIError)
            -> AuthenticatedSession
        {
            if password == "wrong" { throw APIError.unauthorized }
            let session = UserSession(server: server, userID: Self.user, userName: username, isAdministrator: false)
            return AuthenticatedSession(session: session, accessToken: "uitest-token")
        }

        func finishQuickConnect(on server: ServerInfo, secret: QuickConnectSecret) async throws(APIError)
            -> AuthenticatedSession
        {
            _ = secret
            let session = UserSession(server: server, userID: Self.user, userName: "Ada", isAdministrator: false)
            return AuthenticatedSession(session: session, accessToken: "uitest-token")
        }

        func currentUser(on server: ServerInfo, token: String) async throws(APIError) -> UserSession {
            _ = token
            return UserSession(server: server, userID: Self.user, userName: "Ada", isAdministrator: false)
        }

        func publicUsers(on server: ServerInfo) async throws(APIError) -> [PublicUser] {
            _ = server
            return []
        }

        func postCapabilities(on server: ServerInfo, token: String) async throws(APIError) {
            _ = server
            _ = token
        }

        func logout(on server: ServerInfo, token: String) async throws(APIError) {
            _ = server
            _ = token
        }

        private func server(url raw: String) -> ServerInfo {
            ServerInfo(
                id: Self.server,
                name: "Home",
                url: URL(string: raw) ?? URL(string: "https://media.example")!,
                version: SemVer(major: 10, minor: 11, patch: 0)
            )
        }

        private static let server = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        private static let user = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    }
#endif
