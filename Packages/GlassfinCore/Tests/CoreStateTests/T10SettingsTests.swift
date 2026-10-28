import CoreModels
import CoreNetworking
import CoreState
import Foundation
import XCTest

final class T10SettingsTests: XCTestCase {
    @MainActor
    func testTPOC_42_settingsReclaimsVisibleContentOfflineWithoutRequests() async throws {
        let rig = SettingsRig()
        defer { rig.cleanup() }
        try rig.harness.signIn()
        let model = SettingsViewModel(auth: rig.flow, appVersion: " 1.2.3\n")
        model.onAppear()
        rig.harness.app.handle(.serverUnreachable)
        XCTAssertTrue(rig.harness.app.currentView === model)
        XCTAssertTrue(model.hasContent)
        XCTAssertFalse(rig.harness.app.showsServerDown)
        XCTAssertEqual(model.appVersion, "1.2.3")
        XCTAssertTrue(rig.client.calls.isEmpty)
        XCTAssertNotNil(try rig.harness.secure.data(for: Sample.account()))

        model.onDisappear()
        XCTAssertNil(rig.harness.app.currentView)
        model.onAppear()
        XCTAssertTrue(rig.harness.app.currentView === model)
        let next = SettingsViewModel(auth: rig.flow, appVersion: nil)
        next.onAppear()
        model.onDisappear()
        XCTAssertTrue(rig.harness.app.currentView === next)
        XCTAssertNil(next.appVersion)
        XCTAssertNil(SettingsViewModel(auth: rig.flow, appVersion: " \n").appVersion)
    }

    @MainActor
    func testTPOC_43_cancelAndMenuKeepCredentialsWithoutLogoutRequest() async throws {
        let rig = SettingsRig()
        defer { rig.cleanup() }
        try rig.harness.signIn()
        let model = SettingsViewModel(auth: rig.flow)
        model.requestSignOut()
        XCTAssertEqual(rig.flow.screen, .logoutConfirm)
        XCTAssertEqual(rig.flow.focus, .cancel)
        XCTAssertEqual(rig.flow.confirmFocus, .cancel)
        rig.flow.cancelLogout()
        XCTAssertEqual(rig.flow.screen, .home)
        model.requestSignOut()
        rig.flow.goBack()
        XCTAssertEqual(rig.flow.screen, .home)
        XCTAssertEqual(rig.harness.app.phase, .signedIn(Sample.session()))
        XCTAssertNotNil(try rig.harness.secure.data(for: Sample.account()))
        XCTAssertTrue(rig.client.calls.isEmpty)
    }

    @MainActor
    func testTPOC_44_confirmUsesM04LogoutAndClearsOnlyTheActiveCredential() async throws {
        let rig = SettingsRig()
        defer { rig.cleanup() }
        try rig.harness.signIn()
        let other = Sample.account(serverID: Sample.otherServerID, userID: Sample.otherUserID)
        try rig.harness.secure.set(Data(UUID().uuidString.utf8), account: other, attributes: .production)
        SettingsViewModel(auth: rig.flow).requestSignOut()
        await rig.flow.confirmLogout()
        XCTAssertEqual(rig.client.calls, ["POST /Sessions/Logout", "GET /QuickConnect/Enabled"])
        XCTAssertNil(try rig.harness.secure.data(for: Sample.account()))
        XCTAssertNotNil(try rig.harness.secure.data(for: other))
        XCTAssertEqual(rig.harness.app.phase, .needsLogin(Sample.server()))
        XCTAssertEqual(rig.harness.app.preferencesSnapshot().activeServer()?.id, Sample.serverID)
        XCTAssertEqual(rig.flow.screen, .loginMethod)
        XCTAssertNil(rig.flow.noticeKey)
        XCTAssertFalse(rig.flow.isSigningOut)
        XCTAssertFalse(rig.harness.log.contains(Sample.token))
        XCTAssertFalse(rig.harness.settings.allValues().values.contains { $0.contains(Sample.token) })
    }

    @MainActor
    func testTPOC_44_failedLogoutStillClearsCredentialsAndShowsSafeNotice() async throws {
        for failure in [APIError.network, .timeout, .server(status: 500)] {
            let rig = SettingsRig()
            defer { rig.cleanup() }
            try rig.harness.signIn()
            rig.client.failLogout(with: failure)
            SettingsViewModel(auth: rig.flow).requestSignOut()
            await rig.flow.confirmLogout()
            XCTAssertNil(try rig.harness.secure.data(for: Sample.account()))
            XCTAssertEqual(rig.flow.noticeKey, .serverSessionMayRemain)
            XCTAssertEqual(rig.flow.screen, .loginMethod)
            XCTAssertEqual(rig.harness.app.phase, .needsLogin(Sample.server()))
            XCTAssertEqual(rig.client.calls.filter { $0 == "POST /Sessions/Logout" }.count, 1)
            XCTAssertFalse(rig.harness.log.contains(Sample.token))
        }
    }

    @MainActor
    func testTPOC_44_repeatedSelectSendsOneLogoutAndCannotCancelAfterConfirmation() async throws {
        let rig = SettingsRig()
        defer { rig.cleanup() }
        try rig.harness.signIn()
        let gate = ResumeGate()
        rig.client.holdLogout(at: gate)
        defer { gate.releaseAll() }
        let model = SettingsViewModel(auth: rig.flow)
        model.requestSignOut()
        let first = Task { await rig.flow.confirmLogout() }
        await waitUntil { gate.waiting() == 1 }
        XCTAssertTrue(rig.flow.isSigningOut)
        await rig.flow.confirmLogout()
        rig.flow.cancelLogout()
        rig.flow.goBack()
        XCTAssertEqual(rig.flow.screen, .logoutConfirm)
        XCTAssertNotNil(try rig.harness.secure.data(for: Sample.account()))
        XCTAssertEqual(rig.client.calls, ["POST /Sessions/Logout"])
        gate.releaseAll()
        await first.value
        XCTAssertFalse(rig.flow.isSigningOut)
        XCTAssertNil(try rig.harness.secure.data(for: Sample.account()))
    }

    @MainActor
    func testTPOC_46_passwordSignInAfterLogoutReturnsHome() async throws {
        let rig = SettingsRig()
        defer { rig.cleanup() }
        try rig.harness.signIn()
        SettingsViewModel(auth: rig.flow).requestSignOut()
        await rig.flow.confirmLogout()
        rig.flow.choosePassword()
        rig.flow.username = "Ada"
        await rig.flow.signIn(password: UUID().uuidString)
        XCTAssertEqual(rig.flow.screen, .home)
        XCTAssertEqual(rig.harness.app.phase, .signedIn(Sample.session()))
        XCTAssertNotNil(try rig.harness.secure.data(for: Sample.account()))
        XCTAssertTrue(rig.client.calls.contains("POST /Users/AuthenticateByName"))
        XCTAssertNil(rig.flow.noticeKey)
    }

    @MainActor
    func testTPOC_47_freshLaunchAfterLogoutKeepsServerWithoutRestoringSession() async throws {
        let rig = SettingsRig()
        defer { rig.cleanup() }
        try rig.harness.signIn()
        SettingsViewModel(auth: rig.flow).requestSignOut()
        await rig.flow.confirmLogout()
        var restored = rig.harness
        restored.app = AppState(
            secureStore: restored.secure, settings: restored.settings,
            path: restored.path, pinger: restored.pinger, cacheRoot: restored.root,
            clock: restored.clock, automaticPing: false, log: restored.log)
        let fresh = SettingsRig(harness: restored)
        await fresh.flow.restoreSession()
        XCTAssertEqual(fresh.harness.app.phase, .needsLogin(Sample.server()))
        XCTAssertEqual(fresh.flow.screen, .loginMethod)
        XCTAssertEqual(fresh.harness.app.preferencesSnapshot().servers.count, 1)
        XCTAssertFalse(fresh.client.calls.contains("GET /Users/Me"))
        SettingsViewModel(auth: fresh.flow).requestSignOut()
        XCTAssertEqual(fresh.flow.screen, .loginMethod)
    }
}

@MainActor
private struct SettingsRig {
    let harness: Harness
    let client: SettingsWireClient
    let flow: AuthFlow

    init(harness: Harness? = nil) {
        let harness = harness ?? Harness.make(suspendingClock: true)
        self.harness = harness
        client = SettingsWireClient()
        flow = AuthFlow(
            app: harness.app,
            backend: LiveAuthBackend(secureStore: harness.secure, log: harness.log, client: client),
            pins: SettingsCertificatePinStore(settings: harness.settings),
            vault: CredentialVault(secureStore: harness.secure, settings: harness.settings),
            clock: harness.clock, log: harness.log)
    }

    func cleanup() {
        flow.sceneBecameBackground()
        harness.app.signOutLocally(notice: nil)
        harness.cleanup()
    }
}

private final class SettingsWireClient: JellyfinAPIClient, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    private var logoutError: APIError?
    private var logoutGate: ResumeGate?
    var calls: [String] { lock.withLock { recorded } }

    func failLogout(with error: APIError) { lock.withLock { logoutError = error } }
    func holdLogout(at gate: ResumeGate) { lock.withLock { logoutGate = gate } }

    func send(_ request: APIRequest) async throws(APIError) -> Data {
        let (failure, gate) = lock.withLock {
            recorded.append("\(request.method) \(request.path)")
            return (logoutError, logoutGate)
        }
        switch request.path {
        case "/Sessions/Logout":
            if let gate { await gate.wait() }
            if let failure { throw failure }
            return Data()
        case "/QuickConnect/Enabled":
            return Data("true".utf8)
        case "/Users/Public":
            return Data("[]".utf8)
        case "/Users/AuthenticateByName":
            return Data(
                """
                {"AccessToken":"\(UUID().uuidString)","ServerId":"\(Sample.serverID)",
                "User":{"Id":"\(Sample.userID)","Name":"Ada","Policy":{"IsAdministrator":false}}}
                """.utf8)
        case "/Sessions/Capabilities/Full":
            return Data()
        default:
            throw .notFound
        }
    }
}
