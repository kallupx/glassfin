import CoreModels
import CoreNetworking
import CoreState
import Foundation
import XCTest

@MainActor
final class T04AuthFlowTests: XCTestCase {
    func testT04_05_addressFocusFollowsTheField() {
        XCTAssertEqual(AuthFocusPolicy.address(fieldIsEmpty: true), .addressField)
        XCTAssertEqual(AuthFocusPolicy.address(fieldIsEmpty: false), .continueButton)
        XCTAssertEqual(AuthFocusPolicy.cleartextAndCertificate, .cancel)
    }

    func testT04_16_serverNameDropsMarkupAndConsultsTheCap() {
        let raw = "<b>Home</b>\u{0007}" + String(repeating: "n", count: 500)
        let shown = AuthServerName.display(raw)
        XCTAssertFalse(shown.contains("<"))
        XCTAssertFalse(shown.contains("\u{0007}"))
        if let limit = AuthOpenQuestions.addressServerNameLimit {
            XCTAssertLessThanOrEqual(shown.count, limit)
        } else {
            XCTAssertGreaterThan(shown.count, DiscoveryPolicy.maximumNameLength)
        }
    }

    func testT04_26_rejectingCleartextDoesNotSaveTheServer() async {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .needsCleartext(rig.server())
        rig.flow.addressText = "http://192.168.1.10:8096"
        rig.flow.submitAddress()
        await rig.wait()
        XCTAssertEqual(rig.flow.screen, .cleartext)
        XCTAssertEqual(rig.flow.focus, .cancel)
        rig.flow.rejectCleartext()
        XCTAssertEqual(rig.flow.screen, .address)
        XCTAssertTrue(rig.harness.app.preferencesSnapshot().servers.isEmpty)
    }

    func testT04_27_warningScreensFocusCancel() async {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .needsCleartext(rig.server())
        rig.flow.submitAddress()
        await rig.wait()
        XCTAssertEqual(rig.flow.focus, AuthFocusPolicy.cleartextAndCertificate)
    }

    func testT04_31_pinMismatchKeepsTheToken() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        let leaf = sampleLeaf()
        try rig.pins.save(fingerprint: String(repeating: "cd", count: 32), serverID: Sample.serverID)
        try seed(rig.harness, version: "10.11.0", token: Sample.token)
        rig.harness.app.bootstrap()
        rig.backend.probeOutcome = .needsCertificate(leaf, url: Sample.url("https://media.example:8096"))
        rig.flow.addressText = "https://media.example:8096"
        rig.flow.submitAddress()
        await rig.wait()
        XCTAssertEqual(rig.flow.screen, .certificateMismatch)
        XCTAssertNotNil(rig.flow.mismatchPrevious)
        XCTAssertEqual(rig.flow.mismatchPresented?.sha256, leaf.sha256)
        XCTAssertNotNil(try rig.harness.secure.data(for: Sample.account()))
        guard case .signedIn = rig.harness.app.phase else {
            return XCTFail("mismatch must not sign the user out")
        }
    }

    func testT04_34_disabledQuickConnectConsultsTheConstant() async {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.quickConnect = false
        rig.backend.probeOutcome = .ready(rig.server())
        rig.flow.submitAddress()
        await rig.wait()
        switch AuthOpenQuestions.quickConnectDisabledPresentation {
        case .passwordOnly:
            XCTAssertEqual(rig.flow.screen, .credentials)
        case .methodScreen:
            XCTAssertEqual(rig.flow.screen, .loginMethod)
            XCTAssertEqual(rig.flow.focus, .usePassword)
        }
    }

    func testT04_35_initiateIsPostAndFollowsTheConstant() async {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server())
        rig.flow.submitAddress()
        await rig.wait()
        if AuthOpenQuestions.initiateQuickConnectOnMethodEntry {
            XCTAssertEqual(rig.backend.initiates, 1)
        } else {
            XCTAssertEqual(rig.backend.initiates, 0)
        }
        await rig.flow.chooseQuickConnect()
        XCTAssertEqual(rig.backend.initiates, 1)
        XCTAssertEqual(rig.backend.initiateMethods, ["POST"])
        XCTAssertEqual(rig.flow.quickConnectCode, "482913")
        XCTAssertEqual(rig.flow.screen, .quickConnect)
    }

    func testT04_37_secretIsNotStoredOrLogged() async {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server())
        rig.backend.secret = "super-secret-value"
        rig.flow.submitAddress()
        await rig.wait()
        await rig.flow.chooseQuickConnect()
        let settings = rig.harness.settings.allValues().values.joined()
        XCTAssertFalse(settings.contains("super-secret-value"))
        XCTAssertFalse(rig.harness.log.contains("super-secret-value"))
        XCTAssertEqual(rig.flow.quickConnectCode, "482913")
        let described = QuickConnectChallenge(code: "482913", secret: "super-secret-value", authenticated: false)
        XCTAssertFalse(String(describing: described).contains("super-secret-value"))
        XCTAssertFalse(String(reflecting: QuickConnectSecret("super-secret-value")).contains("super-secret-value"))
    }

    func testT04_40_expiryConsultsTheRenewConstant() async {
        let clock = AdvancingClock()
        let rig = Rig(clock: clock)
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server())
        rig.backend.pollAuthenticated = false
        rig.flow.submitAddress()
        await rig.wait()
        await rig.flow.chooseQuickConnect()
        await rig.wait()
        if AuthOpenQuestions.renewQuickConnectCodeAtTimeout {
            XCTAssertGreaterThan(rig.backend.initiates, 1)
        } else {
            XCTAssertEqual(rig.backend.initiates, 1)
            XCTAssertFalse(rig.flow.isPolling)
        }
    }

    func testT04_41_transientPollFailureDoesNotSignOut() async {
        let rig = Rig(clock: AdvancingClock())
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server())
        rig.backend.pollError = .server(status: 503)
        rig.backend.pollThenAuthenticate = true
        rig.flow.submitAddress()
        await rig.wait()
        await rig.flow.chooseQuickConnect()
        await rig.wait()
        guard case .signedIn = rig.harness.app.phase else { return XCTFail("expected home") }
        XCTAssertNotEqual(rig.harness.app.phase, .needsLogin(rig.server()))
    }

    func testT04_42_backgroundConsultsTheConstant() async {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server())
        rig.backend.blockPoll = true
        rig.flow.submitAddress()
        await rig.wait()
        await rig.flow.chooseQuickConnect()
        XCTAssertTrue(rig.flow.isPolling)
        rig.flow.sceneBecameBackground()
        if AuthOpenQuestions.continueQuickConnectInBackground {
            XCTAssertTrue(rig.flow.isPolling)
        } else {
            XCTAssertFalse(rig.flow.isPolling)
        }
        rig.backend.resumePoll(true)
    }

    func testT04_43_quickConnectUnauthorizedKeepsTheSession() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        try rig.harness.secure.set(Data(Sample.token.utf8), account: Sample.account(), attributes: .production)
        rig.backend.probeOutcome = .ready(rig.server())
        rig.backend.finishError = .unauthorized
        rig.flow.submitAddress()
        await rig.wait()
        await rig.flow.chooseQuickConnect()
        await rig.wait()
        XCTAssertEqual(rig.flow.inlineError, AuthOpenQuestions.quickConnectUnauthorizedKey)
        XCTAssertNotEqual(rig.flow.inlineError, .invalidCredentials)
        XCTAssertNotNil(try rig.harness.secure.data(for: Sample.account()))
        guard case .launching = rig.harness.app.phase else {
            return XCTFail("Quick Connect 401 must not end a session")
        }
    }

    func testT04_46_passwordSignInReachesHome() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server(id: AuthIDs.server))
        rig.backend.quickConnect = false
        rig.flow.submitAddress()
        await rig.wait()
        rig.flow.choosePassword()
        rig.flow.username = "Ada"
        await rig.flow.signIn(password: "correct")
        guard case .signedIn(let session) = rig.harness.app.phase else { return XCTFail("expected signed in") }
        XCTAssertEqual(session.userID, AuthIDs.user)
        XCTAssertEqual(rig.flow.screen, .home)
        let account = try CredentialVault.tokenAccount(serverID: AuthIDs.server, userID: AuthIDs.user)
        let stored = try XCTUnwrap(try rig.harness.secure.data(for: account))
        XCTAssertEqual(String(decoding: stored, as: UTF8.self), "access-token")
        XCTAssertEqual(rig.backend.capabilityBodies.count, 1)
        let body = String(decoding: rig.backend.capabilityBodies[0], as: UTF8.self)
        XCTAssertTrue(body.contains("Video"))
        XCTAssertTrue(body.contains("Audio"))
        XCTAssertTrue(body.contains("SupportsMediaControl"))
        XCTAssertFalse(AuthOpenQuestions.includeDeviceProfile)
        XCTAssertFalse(body.contains("DeviceProfile"))
    }

    func testT04_47_wrongPasswordClearsTheFieldAndKeepsTheToken() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        try rig.harness.secure.set(Data(Sample.token.utf8), account: Sample.account(), attributes: .production)
        rig.backend.probeOutcome = .ready(rig.server())
        rig.backend.quickConnect = false
        rig.backend.signInError = .unauthorized
        rig.flow.submitAddress()
        await rig.wait()
        rig.flow.choosePassword()
        await rig.flow.signIn(password: "wrong")
        XCTAssertEqual(rig.flow.inlineError, .invalidCredentials)
        XCTAssertEqual(rig.flow.focus, .password)
        XCTAssertTrue(rig.flow.passwordCleared)
        XCTAssertNotNil(try rig.harness.secure.data(for: Sample.account()))
        guard case .signedIn = rig.harness.app.phase else { return }
        XCTFail("login 401 must not end a session")
    }

    func testT04_48_passwordIsAbsentAfterTheCall() async {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server(id: AuthIDs.server))
        rig.backend.quickConnect = false
        rig.flow.submitAddress()
        await rig.wait()
        rig.flow.choosePassword()
        await rig.flow.signIn(password: "pässi🔑")
        XCTAssertTrue(rig.flow.passwordCleared)
        let settings = rig.harness.settings.allValues().values.joined()
        XCTAssertFalse(settings.contains("pässi"))
        XCTAssertFalse(rig.harness.log.contains("pässi"))
        XCTAssertFalse(rig.backend.seenPasswords.isEmpty)
    }

    func testT04_50_transportFailureIsNotInvalidCredentials() async {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server())
        rig.backend.quickConnect = false
        rig.backend.signInError = .server(status: 500)
        rig.flow.submitAddress()
        await rig.wait()
        rig.flow.choosePassword()
        await rig.flow.signIn(password: "secret")
        XCTAssertEqual(rig.flow.inlineError, AuthOpenQuestions.loginTransportFailureKey)
        XCTAssertNotEqual(rig.flow.inlineError, .invalidCredentials)
    }

    func testT04_52_capabilitiesFailureConsultsTheConstant() async {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server(id: AuthIDs.server))
        rig.backend.quickConnect = false
        rig.backend.capabilitiesError = .server(status: 500)
        rig.flow.submitAddress()
        await rig.wait()
        rig.flow.choosePassword()
        await rig.flow.signIn(password: "correct")
        if AuthOpenQuestions.capabilitiesFailureBlocksSignIn {
            guard case .signedIn = rig.harness.app.phase else { return }
            XCTFail("constant says capabilities failure blocks sign-in")
        } else {
            guard case .signedIn = rig.harness.app.phase else { return XCTFail("sign-in should proceed") }
        }
    }

    func testT04_54_tokenIsNotInTheSessionOrSettings() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server(id: AuthIDs.server))
        rig.backend.quickConnect = false
        rig.flow.submitAddress()
        await rig.wait()
        rig.flow.choosePassword()
        await rig.flow.signIn(password: "correct")
        guard case .signedIn(let session) = rig.harness.app.phase else { return XCTFail("expected session") }
        XCTAssertFalse(String(describing: session).contains("access-token"))
        let snapshot = String(decoding: try JSONEncoder().encode(rig.harness.app.preferencesSnapshot()), as: UTF8.self)
        XCTAssertFalse(snapshot.contains("access-token"))
    }

    func testT04_55_tenServersAndUsersStayUnderTheBudget() throws {
        var preferences = AppPreferences.empty
        for index in 0..<10 {
            let id = String(format: "server-%02d", index)
            preferences = try preferences.upserting(
                server: StoredServer(
                    id: id, name: "Home \(index)", url: Sample.url("https://media-\(index).example"),
                    version: "10.11.0")
            )
            preferences = preferences.upserting(
                user: StoredUser(
                    serverID: id, userID: "user-\(index)", userName: "Ada \(index)", isAdministrator: false))
        }
        let bytes = try XCTUnwrap(PreferencesRepository.encodedByteCount(preferences))
        XCTAssertLessThan(bytes, AppPreferences.maximumBytes)
        let store = InMemorySettingsStore()
        try PreferencesRepository(store: store).save(preferences)
    }

    func testT04_58_usersMeUnauthorizedLogsOutOnce() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        try seed(rig.harness, version: "10.11.0", token: Sample.token)
        rig.backend.currentUserError = .unauthorized
        await rig.flow.restoreSession()
        XCTAssertEqual(rig.backend.currentUserCalls, 1)
        XCTAssertEqual(rig.flow.noticeKey, AuthOpenQuestions.sessionEndedNoticeKey)
        XCTAssertNil(try rig.harness.secure.data(for: Sample.account()))
        guard case .needsLogin = rig.harness.app.phase else { return XCTFail("expected login") }
        await rig.flow.restoreSession()
        XCTAssertEqual(rig.backend.currentUserCalls, 1)
    }

    func testT04_60_usersMeUsesFiveSecondsAndOneAttempt() async throws {
        XCTAssertEqual(AuthSessionTiming.currentUserTimeout, .seconds(5))
        let rig = Rig()
        defer { rig.cleanup() }
        try seed(rig.harness, version: "10.11.0", token: Sample.token)
        rig.backend.currentUserError = .timeout
        await rig.flow.restoreSession()
        XCTAssertEqual(rig.backend.currentUserCalls, 1)
        XCTAssertEqual(rig.flow.screen, .home)
        XCTAssertNotNil(try rig.harness.secure.data(for: Sample.account()))
        guard case .signedIn = rig.harness.app.phase else { return XCTFail("timeout stays signed in") }
    }

    func testT04_61_usersMeFailuresKeepTheToken() async throws {
        for error in [APIError.forbidden, .server(status: 500), .server(status: 502), .tls, .timeout] {
            let rig = Rig()
            try seed(rig.harness, version: "10.11.0", token: Sample.token)
            rig.backend.currentUserError = error
            await rig.flow.restoreSession()
            XCTAssertNotNil(try rig.harness.secure.data(for: Sample.account()), "\(error)")
            guard case .signedIn = rig.harness.app.phase else {
                XCTFail("\(error) logged the user out")
                rig.cleanup()
                continue
            }
            XCTAssertEqual(rig.flow.inlineError, AuthOpenQuestions.sessionRestoreFailureKey, "\(error)")
            rig.cleanup()
        }
    }

    func testT04_65_oldStoredVersionBlocksAndKeepsTheToken() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        try seed(rig.harness, version: "10.9.11", token: Sample.token)
        await rig.flow.restoreSession()
        XCTAssertEqual(rig.harness.app.blockingError, .unsupportedServer(version: "10.9.11"))
        guard case .needsLogin = rig.harness.app.phase else { return XCTFail("expected login") }
        XCTAssertNotNil(try rig.harness.secure.data(for: Sample.account()))
        XCTAssertEqual(rig.backend.currentUserCalls, 0)
    }

    func testT04_66_logoutPostsThenClearsTheKeychain() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        try seed(rig.harness, version: "10.11.0", token: Sample.token)
        rig.harness.app.bootstrap()
        await rig.flow.confirmLogout()
        XCTAssertEqual(rig.backend.logoutCalls, 1)
        XCTAssertNil(try rig.harness.secure.data(for: Sample.account()))
        guard case .needsLogin = rig.harness.app.phase else { return XCTFail("expected signed out") }
    }

    func testT04_67_failedLogoutStillClearsAndReportsTheKey() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        try seed(rig.harness, version: "10.11.0", token: Sample.token)
        rig.harness.app.bootstrap()
        rig.backend.logoutError = .server(status: 500)
        rig.flow.requestLogout()
        XCTAssertEqual(rig.flow.confirmFocus, AuthOpenQuestions.logoutConfirmDefaultFocus)
        await rig.flow.confirmLogout()
        XCTAssertNil(try rig.harness.secure.data(for: Sample.account()))
        XCTAssertEqual(rig.flow.noticeKey, .serverSessionMayRemain)
        switch AuthOpenQuestions.postLogoutScreen {
        case .welcome:
            XCTAssertEqual(rig.flow.screen, .welcome)
        case .address:
            XCTAssertEqual(rig.flow.screen, .address)
        case .login:
            XCTAssertEqual(rig.flow.screen, .loginMethod)
        case nil:
            XCTAssertEqual(rig.flow.screen, .signedOut)
        }
    }

    func testT04_70_removingAServerKeepsTheOtherAccount() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        var preferences = AppPreferences.empty
        preferences = try preferences.upserting(
            server: StoredServer(
                id: Sample.serverID, name: "Home", url: Sample.url("https://media.example"), version: "10.11.0"))
        preferences = try preferences.upserting(
            server: StoredServer(
                id: Sample.otherServerID, name: "Other", url: Sample.url("https://other.example"), version: "10.11.0"))
        preferences = preferences.upserting(
            user: StoredUser(serverID: Sample.serverID, userID: Sample.userID, userName: "Ada", isAdministrator: false)
        )
        preferences = preferences.upserting(
            user: StoredUser(
                serverID: Sample.otherServerID, userID: Sample.otherUserID, userName: "Bea", isAdministrator: false)
        )
        preferences.activeServerID = Sample.serverID
        preferences.activeUserID = Sample.userID
        try PreferencesRepository(store: rig.harness.settings).save(preferences)
        try rig.harness.secure.set(Data("one".utf8), account: Sample.account(), attributes: .production)
        try rig.harness.secure.set(
            Data("two".utf8),
            account: Sample.account(serverID: Sample.otherServerID, userID: Sample.otherUserID),
            attributes: .production
        )
        try rig.pins.save(fingerprint: String(repeating: "ab", count: 32), serverID: Sample.serverID)
        rig.harness.app.bootstrap()
        rig.flow.removeCurrentServer()
        XCTAssertEqual(rig.harness.app.phase, .needsServer)
        XCTAssertNil(try rig.harness.secure.data(for: Sample.account()))
        XCTAssertNotNil(
            try rig.harness.secure.data(for: Sample.account(serverID: Sample.otherServerID, userID: Sample.otherUserID))
        )
        XCTAssertNil(try rig.pins.fingerprint(for: Sample.serverID))
    }

    func testProbeFailureShowsTheSkippedHTTPFlag() async {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .notFound(ProbeFailureDetail(httpSkippedByPolicy: true))
        rig.flow.addressText = "203.0.113.5"
        rig.flow.submitAddress()
        await rig.wait()
        XCTAssertEqual(rig.flow.inlineError, .serverNotFound)
        XCTAssertTrue(rig.flow.httpSkippedByPolicy)
        rig.backend.probeOutcome = .publicHTTPRejected
        rig.flow.addressText = "http://203.0.113.5:8096"
        rig.flow.submitAddress()
        await rig.wait()
        XCTAssertEqual(rig.flow.inlineError, .publicAddressRequiresHTTPS)
        XCTAssertFalse(rig.flow.httpSkippedByPolicy)
    }

    func testSetupIncompleteDoesNotSave() async {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .setupIncomplete(address: Sample.url("https://media.example"))
        rig.flow.submitAddress()
        await rig.wait()
        XCTAssertEqual(rig.flow.screen, .setupIncomplete)
        XCTAssertEqual(rig.flow.focus, .tryAgain)
        XCTAssertTrue(rig.harness.app.preferencesSnapshot().servers.isEmpty)
        rig.flow.retrySetup()
        XCTAssertEqual(rig.flow.screen, .address)
    }
}

private enum AuthIDs {
    static let server = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    static let user = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
}

@MainActor
private struct Rig {

    var harness: Harness
    var backend: ScriptAuth
    var pins: MemoryPins
    var flow: AuthFlow

    init(clock: (any GlassfinClock)? = nil) {
        harness = Harness.make(suspendingClock: true)
        backend = ScriptAuth()
        pins = MemoryPins()
        let vault = CredentialVault(secureStore: harness.secure, settings: harness.settings, accessGroup: "")
        flow = AuthFlow(
            app: harness.app,
            backend: backend,
            pins: pins,
            vault: vault,
            clock: clock ?? harness.clock,
            log: harness.log
        )
    }

    func cleanup() { harness.cleanup() }

    func server(id: String = Sample.serverID, user: String = Sample.userID) -> ServerInfo {
        _ = user
        return ServerInfo(
            id: id, name: "Home", url: Sample.url("https://media.example"),
            version: SemVer(major: 10, minor: 11, patch: 0))
    }

    func wait() async {
        for _ in 0..<100 {
            if !flow.isProbing && !flow.isPolling { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

private func seed(_ harness: Harness, version: String, token: String) throws {
    var preferences = AppPreferences.empty
    preferences = try preferences.upserting(
        server: StoredServer(
            id: Sample.serverID, name: "Home", url: Sample.url("https://media.example:8096"), version: version))
    preferences = preferences.upserting(
        user: StoredUser(serverID: Sample.serverID, userID: Sample.userID, userName: "Ada", isAdministrator: false))
    preferences.activeServerID = Sample.serverID
    preferences.activeUserID = Sample.userID
    try PreferencesRepository(store: harness.settings).save(preferences)
    try harness.secure.set(Data(token.utf8), account: Sample.account(), attributes: .production)
}

private func sampleLeaf() -> CertificatePresentation {
    CertificatePresentation(
        sha256: String(repeating: "ab", count: 32), subject: "CN=media",
        notBefore: Date(timeIntervalSince1970: 1), notAfter: Date(timeIntervalSince1970: 2))
}

private final class ScriptAuth: AuthBackend, @unchecked Sendable {
    var probeOutcome: ServerProbeOutcome = .invalidAddress
    var quickConnect = true
    var initiates = 0
    var initiateMethods: [String] = []
    var secret = "super-secret-value"
    var pollAuthenticated = true
    var pollError: APIError?
    var pollThenAuthenticate = false
    var polls = 0
    var blockPoll = false
    var signInError: APIError?
    var finishError: APIError?
    var capabilitiesError: APIError?
    var capabilityBodies: [Data] = []
    var currentUserError: APIError?
    var currentUserCalls = 0
    var logoutCalls = 0
    var logoutError: APIError?
    var seenPasswords: [String] = []
    private var pollWaiter: CheckedContinuation<Bool, Error>?
    private let lock = NSLock()

    func probe(_ address: String) async -> ServerProbeOutcome {
        _ = address
        return probeOutcome
    }

    func quickConnectEnabled(on server: ServerInfo) async throws(APIError) -> Bool {
        _ = server
        return quickConnect
    }

    func beginQuickConnect(on server: ServerInfo) async throws(APIError) -> QuickConnectChallenge {
        _ = server
        let secret = recordInitiate()
        return QuickConnectChallenge(code: "482913", secret: secret, authenticated: false)
    }

    func pollQuickConnect(on server: ServerInfo, secret: QuickConnectSecret) async throws(APIError) -> Bool {
        _ = server
        _ = secret
        let snapshot = recordPoll()
        if let error = snapshot.error, !(snapshot.thenAuthenticate && snapshot.polls > 1) { throw error }
        if snapshot.block {
            do {
                return try await withCheckedThrowingContinuation { continuation in
                    storePollWaiter(continuation)
                }
            } catch {
                throw APIError.cancelled
            }
        }
        return snapshot.accepted
    }

    func resumePoll(_ value: Bool) {
        takePollWaiter()?.resume(returning: value)
    }

    func signIn(on server: ServerInfo, username: String, password: String) async throws(APIError)
        -> AuthenticatedSession
    {
        recordPassword(password)
        if let signInError { throw signInError }
        let session = UserSession(server: server, userID: AuthIDs.user, userName: username, isAdministrator: false)
        return AuthenticatedSession(session: session, accessToken: "access-token")
    }

    func finishQuickConnect(on server: ServerInfo, secret: QuickConnectSecret) async throws(APIError)
        -> AuthenticatedSession
    {
        _ = secret
        if let finishError { throw finishError }
        let session = UserSession(server: server, userID: Sample.userID, userName: "Ada", isAdministrator: false)
        return AuthenticatedSession(session: session, accessToken: "access-token")
    }

    func currentUser(on server: ServerInfo, token: String) async throws(APIError) -> UserSession {
        _ = token
        recordCurrentUser()
        if let currentUserError { throw currentUserError }
        return UserSession(server: server, userID: Sample.userID, userName: "Ada", isAdministrator: false)
    }

    func publicUsers(on server: ServerInfo) async throws(APIError) -> [PublicUser] {
        _ = server
        return []
    }

    func postCapabilities(on server: ServerInfo, token: String) async throws(APIError) {
        _ = server
        _ = token
        let body = Data(
            #"{"PlayableMediaTypes":["Video","Audio"],"SupportsMediaControl":true,"SupportedCommands":[]}"#.utf8)
        recordCapabilities(body)
        if let capabilitiesError { throw capabilitiesError }
    }

    func logout(on server: ServerInfo, token: String) async throws(APIError) {
        _ = server
        _ = token
        recordLogout()
        if let logoutError { throw logoutError }
    }

    private func recordInitiate() -> String {
        lock.lock()
        initiates += 1
        initiateMethods.append("POST")
        let secret = secret
        lock.unlock()
        return secret
    }

    private struct PollSnapshot {
        var polls: Int
        var error: APIError?
        var block: Bool
        var thenAuthenticate: Bool
        var accepted: Bool
    }

    private func recordPoll() -> PollSnapshot {
        lock.lock()
        polls += 1
        let snapshot = PollSnapshot(
            polls: polls, error: pollError, block: blockPoll, thenAuthenticate: pollThenAuthenticate,
            accepted: pollAuthenticated)
        lock.unlock()
        return snapshot
    }

    private func storePollWaiter(_ continuation: CheckedContinuation<Bool, Error>) {
        lock.lock()
        pollWaiter = continuation
        lock.unlock()
    }

    private func takePollWaiter() -> CheckedContinuation<Bool, Error>? {
        lock.lock()
        let waiter = pollWaiter
        pollWaiter = nil
        lock.unlock()
        return waiter
    }

    private func recordPassword(_ password: String) {
        lock.lock()
        seenPasswords.append(password)
        lock.unlock()
    }

    private func recordCurrentUser() {
        lock.lock()
        currentUserCalls += 1
        lock.unlock()
    }

    private func recordCapabilities(_ body: Data) {
        lock.lock()
        capabilityBodies.append(body)
        lock.unlock()
    }

    private func recordLogout() {
        lock.lock()
        logoutCalls += 1
        lock.unlock()
    }
}

private final class MemoryPins: CertificatePinStore, @unchecked Sendable {
    private var values: [String: String] = [:]
    func fingerprint(for serverID: String) throws -> String? { values[serverID] }
    func save(fingerprint: String, serverID: String) throws { values[serverID] = fingerprint }
    func remove(serverID: String) throws { values[serverID] = nil }
}

private final class AdvancingClock: GlassfinClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Duration = .zero
    func now() -> Duration {
        lock.lock()
        defer { lock.unlock() }
        return current
    }
    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        advance(by: duration)
    }

    func advance(by delta: Duration) {
        lock.lock()
        current += delta
        lock.unlock()
    }
}
