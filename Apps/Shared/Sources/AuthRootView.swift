import GlassfinCore
import SwiftUI

struct AuthRootView: View {
    @Bindable var flow: AuthFlow
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
            }
        }
        .task { await flow.restoreSession() }
    }

    @ViewBuilder
    private var panel: some View {
        switch flow.screen {
        case .welcome:
            welcome
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
            if flow.screen != .welcome {
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
            if let error = flow.inlineError {
                Text(AuthCopy.localized(error))
                    .accessibilityIdentifier("address.error")
                    .accessibilityValue(error.rawValue)
            }
            if flow.httpSkippedByPolicy {
                Text(AuthCopy.localized(.httpOnlyOnLocalNetwork))
                    .accessibilityIdentifier("address.httpSkipped")
            }
        }
        .padding(32)
        .onExitCommand {
            guard flow.screen != .welcome else { return }
            flow.goBack()
        }
    }

    private var welcome: some View {
        VStack(spacing: 24) {
            Text(AuthCopy.localized(.glassfin))
                .font(.largeTitle)
                .accessibilityIdentifier("welcome.root")
            Button(AuthCopy.localized(.connectToServer)) { flow.connect() }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("welcome.connect")
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
                Text(flow.displayedName)
                    .accessibilityIdentifier("address.serverName")
                Text(flow.displayedVersion)
                    .accessibilityIdentifier("address.serverVersion")
            }
        }
        .accessibilityIdentifier("address.root")
    }

    private var cleartext: some View {
        VStack(spacing: 16) {
            Text(AuthCopy.localized(.connectionNotEncrypted))
                .accessibilityIdentifier("cleartext.root")
            Button(AuthCopy.localized(.accept)) { Task { await flow.acceptCleartext() } }
                .accessibilityIdentifier("cleartext.accept")
            Button(AuthCopy.localized(.cancel)) { flow.rejectCleartext() }
                .accessibilityIdentifier("cleartext.cancel")
                .focused($focused, equals: .cancel)
        }
    }

    private var certificate: some View {
        VStack(spacing: 12) {
            Text(flow.certificate?.sha256 ?? flow.mismatchPresented?.sha256 ?? "")
                .accessibilityIdentifier("certificate.fingerprint")
            Text(flow.certificate?.subject ?? flow.mismatchPresented?.subject ?? "")
                .accessibilityIdentifier("certificate.subject")
            if let previous = flow.mismatchPrevious {
                Text(previous)
                    .accessibilityIdentifier("certificate.previous")
            }
            Text(AuthCopy.localized(.certificateChanged))
            Button(AuthCopy.localized(.accept)) {
                guard let leaf = flow.certificate else { return }
                try? flow.acceptCertificate(userAcceptedFingerprint: leaf.sha256)
            }
            .accessibilityIdentifier("certificate.accept")
            Button(AuthCopy.localized(.cancel)) { flow.rejectCertificate() }
                .accessibilityIdentifier("certificate.cancel")
                .focused($focused, equals: .cancel)
        }
        .accessibilityIdentifier("certificate.root")
    }

    private var setup: some View {
        VStack(spacing: 16) {
            Text(AuthCopy.setupIncomplete(address: flow.setupAddress?.absoluteString ?? ""))
                .accessibilityIdentifier("setup.root")
            Button(AuthCopy.localized(.tryAgain)) { flow.retrySetup() }
                .accessibilityIdentifier("setup.retry")
                .focused($focused, equals: .tryAgain)
        }
    }

    private var loginMethod: some View {
        VStack(spacing: 16) {
            Text(flow.displayedName).accessibilityIdentifier("login.serverName")
            Text(flow.displayedVersion).accessibilityIdentifier("login.serverVersion")
            if flow.quickConnectEnabled {
                Button(AuthCopy.localized(.quickConnect)) { Task { await flow.chooseQuickConnect() } }
                    .accessibilityIdentifier("login.quickConnect")
                    .focused($focused, equals: .quickConnect)
            }
            Button(AuthCopy.localized(.usePassword)) { flow.choosePassword() }
                .accessibilityIdentifier("login.password")
                .focused($focused, equals: .usePassword)
        }
        .accessibilityIdentifier("login.root")
    }

    private var quickConnect: some View {
        VStack(spacing: 16) {
            Text(flow.quickConnectCode ?? "")
                .font(.largeTitle)
                .accessibilityIdentifier("quickconnect.code")
            Text(AuthCopy.localized(.quickConnectInstruction))
                .accessibilityIdentifier("quickconnect.instruction")
        }
        .accessibilityIdentifier("quickconnect.root")
        .focused($focused, equals: .quickConnectCode)
    }

    private var userPicker: some View {
        VStack(spacing: 12) {
            ForEach(flow.publicUsers, id: \.id) { user in
                Button(user.name) { flow.selectUser(user) }
                    .accessibilityIdentifier("users.\(user.id)")
            }
        }
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
        .accessibilityIdentifier("credentials.root")
    }

    private var home: some View {
        VStack(spacing: 16) {
            Text(AuthCopy.localized(.home))
                .accessibilityIdentifier("home.root")
            Button(AuthCopy.localized(.signOut)) { flow.requestLogout() }
                .accessibilityIdentifier("home.signOut")
        }
    }

    private var logoutConfirm: some View {
        VStack(spacing: 16) {
            Text(AuthCopy.localized(.signOutConfirm))
                .accessibilityIdentifier("logout.root")
            Button(AuthCopy.localized(.signOut)) { Task { await flow.confirmLogout() } }
                .accessibilityIdentifier("logout.confirm")
            Button(AuthCopy.localized(.cancel)) { flow.cancelLogout() }
                .accessibilityIdentifier("logout.cancel")
        }
    }

    private var backButton: some View {
        Button(AuthCopy.localized(.back)) { flow.goBack() }
            .accessibilityIdentifier("navigation.back")
            .focused($focused, equals: .back)
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Text(title)
            Text(detail)
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
                    backend: UITestAuthBackend(), secure: InMemorySecureStore(), settings: InMemorySettingsStore())
            }
        #else
            _ = arguments
        #endif
        let secure = KeychainSecureStore()
        let settings = UserDefaultsSettingsStore(defaults: .standard)
        return assemble(backend: LiveAuthBackend(secureStore: secure), secure: secure, settings: settings)
    }

    @MainActor
    private static func assemble(
        backend: any AuthBackend, secure: any SecureStore, settings: any SettingsStore
    ) -> AuthFlow {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "glassfin-ui-\(UUID().uuidString)", isDirectory: true)
        let app = AppState(
            secureStore: secure,
            settings: settings,
            path: StaticConnectivityPath(online: true),
            pinger: AuthAssemblyPinger(),
            cacheRoot: root,
            automaticPing: false
        )
        let vault = CredentialVault(secureStore: secure, settings: settings, accessGroup: "")
        return AuthFlow(
            app: app,
            backend: backend,
            pins: SettingsCertificatePinStore(settings: settings),
            vault: vault,
            clock: SystemGlassfinClock()
        )
    }
}

private struct AuthAssemblyPinger: ReachabilityPinging {
    func ping() async -> PingOutcome { .ok }
}

#if DEBUG
    struct UITestAuthBackend: AuthBackend {
        func probe(_ address: String) async -> ServerProbeOutcome {
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
            return true
        }

        func beginQuickConnect(on server: ServerInfo) async throws(APIError) -> QuickConnectChallenge {
            _ = server
            return QuickConnectChallenge(code: "482913", secret: "uitest-secret", authenticated: false)
        }

        func pollQuickConnect(on server: ServerInfo, secret: QuickConnectSecret) async throws(APIError) -> Bool {
            _ = server
            _ = secret
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
