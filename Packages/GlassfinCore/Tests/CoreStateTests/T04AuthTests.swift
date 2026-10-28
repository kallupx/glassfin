import CoreModels
import CoreNetworking
import Foundation
import Observation
import XCTest

@testable import CoreState

final class T04AuthFlowTests: XCTestCase {
    @MainActor
    func testPinReadFailureStopsProbeAndShowsExistingError() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        try seed(rig.harness, version: "10.11.0", token: Sample.token)
        rig.pins.failOnRead = 1
        rig.flow.addressText = "https://media.example:8096"
        rig.flow.submitAddress()
        await rig.wait(for: .address)
        XCTAssertEqual(rig.flow.inlineError, .loginTransportFailure)
        XCTAssertEqual(rig.backend.probes, 0)
        XCTAssertFalse(rig.flow.isProbing)
        XCTAssertTrue(rig.pins.writes.isEmpty)
    }

    @MainActor
    func testPinReadFailureWhilePresentingCertificateStopsAcceptance() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        try seed(rig.harness, version: "10.11.0", token: Sample.token)
        rig.pins.failOnRead = 2
        rig.flow.addressText = "https://media.example:8096"
        rig.backend.probeOutcome = .needsCertificate(sampleLeaf(), url: Sample.url(rig.flow.addressText))
        rig.flow.submitAddress()
        await rig.wait(until: { rig.flow.inlineError != nil })
        XCTAssertEqual(rig.flow.screen, .address)
        XCTAssertEqual(rig.flow.inlineError, .loginTransportFailure)
        XCTAssertFalse(rig.flow.canAcceptCertificate)
        XCTAssertEqual(rig.backend.probes, 1)
        XCTAssertTrue(rig.pins.writes.isEmpty)
    }

    @MainActor
    func testPinReadFailureDuringAcceptanceThrowsAndDoesNotRetry() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        try seed(rig.harness, version: "10.11.0", token: Sample.token)
        rig.flow.addressText = "https://media.example:8096"
        rig.backend.probeOutcome = .needsCertificate(sampleLeaf(), url: Sample.url(rig.flow.addressText))
        rig.flow.submitAddress()
        await rig.wait(for: .certificate)
        rig.pins.failOnRead = rig.pins.reads + 1
        XCTAssertThrowsError(try rig.flow.acceptCertificate(userAcceptedFingerprint: sampleLeaf().sha256)) { error in
            XCTAssertEqual(error as? APIError, .tls)
        }
        XCTAssertEqual(rig.flow.screen, .address)
        XCTAssertEqual(rig.flow.inlineError, .loginTransportFailure)
        XCTAssertFalse(rig.flow.canAcceptCertificate)
        XCTAssertEqual(rig.backend.probes, 1)
        XCTAssertTrue(rig.pins.writes.isEmpty)
    }

    @MainActor
    func testSavedPinAndMissingPinKeepProbeConfiguration() async throws {
        for fingerprint in [String(repeating: "ab", count: 32), nil] {
            let rig = Rig()
            defer { rig.cleanup() }
            try seed(rig.harness, version: "10.11.0", token: Sample.token)
            if let fingerprint { try rig.pins.save(fingerprint: fingerprint, serverID: Sample.serverID) }
            rig.flow.addressText = "https://media.example:8096"
            rig.backend.probeOutcome = .ready(rig.server())
            rig.flow.submitAddress()
            await rig.wait(for: .loginMethod)
            XCTAssertEqual(rig.backend.probes, 1)
            XCTAssertEqual(rig.backend.probePins.first.flatMap { $0 }?.sha256, fingerprint)
            XCTAssertNil(rig.flow.inlineError)
        }
    }

    @MainActor
    func testT04_05_addressFocusFollowsTheField() async {
        XCTAssertEqual(AuthFocusPolicy.address(fieldIsEmpty: true), .addressField)
        XCTAssertEqual(AuthFocusPolicy.address(fieldIsEmpty: false), .continueButton)
        XCTAssertEqual(AuthFocusPolicy.cleartextAndCertificate, .cancel)
    }

    @MainActor
    func testT04_16_serverNameDropsMarkupAndCapsAt64() async {
        let raw = "<b>Home</b>\u{0007}" + String(repeating: "n", count: 500)
        let shown = AuthServerName.display(raw)
        XCTAssertFalse(shown.contains("<"))
        XCTAssertFalse(shown.contains("\u{0007}"))
        XCTAssertEqual(shown.count, 64)
        XCTAssertEqual(shown, "Home" + String(repeating: "n", count: 60))
    }

    @MainActor
    func testT04_16_serverNameIsCappedOnAddressAndSavedUserPicker() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        try seed(rig.harness, version: "10.11.0", token: Sample.token)
        let repo = PreferencesRepository(store: rig.harness.settings)
        try repo.save(
            repo.load().upserting(
                user: StoredUser(
                    serverID: Sample.serverID, userID: Sample.otherUserID, userName: "**Bea**\u{202E}\u{0085}",
                    isAdministrator: false)))
        var server = rig.server()
        server.name = "<b>" + String(repeating: "n", count: 100) + "</b>"
        rig.backend.probeOutcome = .needsCleartext(server)
        rig.flow.submitAddress()
        await rig.wait(for: .cleartext)
        XCTAssertEqual(rig.flow.displayedName.count, 64)
        XCTAssertFalse(rig.flow.displayedName.contains("<"))
        await rig.flow.acceptCleartext()
        XCTAssertEqual(rig.flow.screen, .userPicker)
        XCTAssertEqual(rig.flow.displayedName.count, 64)
        XCTAssertEqual(rig.flow.publicUsers.count, 2)
        XCTAssertEqual(rig.flow.publicUsers.last?.name, "**Bea**")
    }

    @MainActor
    func testT04_26_rejectingCleartextDoesNotSaveTheServer() async {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .needsCleartext(rig.server())
        rig.flow.addressText = "http://192.168.1.10:8096"
        rig.flow.submitAddress()
        await rig.wait(for: .cleartext)
        XCTAssertEqual(rig.flow.screen, .cleartext)
        XCTAssertEqual(rig.flow.focus, .cancel)
        rig.flow.rejectCleartext()
        XCTAssertEqual(rig.flow.screen, .address)
        XCTAssertTrue(rig.harness.app.preferencesSnapshot().servers.isEmpty)
    }

    @MainActor
    func testT04_27_warningScreensFocusCancel() async {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .needsCleartext(rig.server())
        rig.flow.submitAddress()
        await rig.wait(for: .cleartext)
        XCTAssertEqual(rig.flow.focus, AuthFocusPolicy.cleartextAndCertificate)
        rig.flow.rejectCleartext()
        rig.backend.probeOutcome = .needsCertificate(sampleLeaf(), url: Sample.url("https://example.com"))
        rig.flow.submitAddress()
        await rig.wait(for: .certificate)
        XCTAssertEqual(rig.flow.screen, .certificate)
        XCTAssertEqual(rig.flow.focus, .cancel)
    }

    @MainActor
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
        await rig.wait(for: .certificateMismatch)
        XCTAssertEqual(rig.flow.screen, .certificateMismatch)
        XCTAssertNotNil(rig.flow.mismatchPrevious)
        XCTAssertEqual(rig.flow.mismatchPresented?.sha256, leaf.sha256)
        XCTAssertNotNil(try rig.harness.secure.data(for: Sample.account()))
        guard case .signedIn = rig.harness.app.phase else {
            return XCTFail("mismatch must not sign the user out")
        }
    }

    @MainActor
    func testS44_acceptCertificateRetriesWithPinAndPersistsOnlyAfterRealServerID() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        let url = Sample.url("https://media.example")
        rig.flow.addressText = url.absoluteString
        rig.backend.probeOutcome = .needsCertificate(sampleLeaf(), url: url)
        rig.backend.readyWithPin = rig.server()
        rig.flow.submitAddress()
        await rig.wait(for: .certificate)
        XCTAssertTrue(rig.flow.canAcceptCertificate)
        XCTAssertTrue(rig.pins.writes.isEmpty)
        let formatted = sampleLeaf().sha256.uppercased().map(String.init).joined(separator: ":")
        try rig.flow.acceptCertificate(userAcceptedFingerprint: formatted)
        // Acceptance is in memory until the retry learns ServerInfo.id.
        XCTAssertTrue(rig.pins.writes.isEmpty)
        await rig.wait(for: .loginMethod)
        XCTAssertEqual(rig.flow.screen, .loginMethod)
        XCTAssertEqual(rig.backend.probePins.count, 2)
        XCTAssertEqual(rig.backend.probePins.last.flatMap { $0 }?.fingerprint(for: url), sampleLeaf().sha256)
        XCTAssertEqual(rig.pins.writes.map(\.serverID), [Sample.serverID])
        XCTAssertEqual(rig.pins.writes.map(\.fingerprint), [sampleLeaf().sha256])
        XCTAssertFalse(rig.pins.writes.contains { $0.fingerprint == formatted || $0.serverID == "pending" })
        XCTAssertNil(try rig.pins.fingerprint(for: "pending"))
    }

    @MainActor
    func testS44_secondNewOriginDoesNotReceiveThePreviousAcceptance() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        let firstURL = Sample.url("https://media.example")
        rig.flow.addressText = firstURL.absoluteString
        rig.backend.probeOutcome = .needsCertificate(sampleLeaf(), url: firstURL)
        rig.backend.readyWithPin = rig.server()
        rig.flow.submitAddress()
        await rig.wait(for: .certificate)
        try rig.flow.acceptCertificate(userAcceptedFingerprint: sampleLeaf().sha256)
        await rig.wait(for: .loginMethod)
        for secondURL in ["https://other.example", "https://media.example:8920"] {
            rig.flow.goBack()
            let url = Sample.url(secondURL)
            rig.flow.addressText = secondURL
            rig.backend.probeOutcome = .needsCertificate(sampleLeaf(), url: url)
            rig.flow.submitAddress()
            await rig.wait(for: .certificate)
            XCTAssertEqual(rig.flow.screen, .certificate)
            XCTAssertNil(rig.backend.probePins.last!)
            XCTAssertEqual(rig.pins.writes.count, 1)
        }
    }

    @MainActor
    func testS44_certificateChangeRequiresMatchingConfirmationBeforeReplacingPin() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        try seed(rig.harness, version: "10.11.0", token: Sample.token)
        let previous = String(repeating: "cd", count: 32)
        try rig.pins.save(fingerprint: previous, serverID: Sample.serverID)
        let url = Sample.url("https://media.example:8096")
        var info = rig.server()
        info.url = url
        rig.flow.addressText = url.absoluteString
        rig.backend.probeOutcome = .needsCertificate(sampleLeaf(), url: url)
        rig.backend.readyWithPin = info
        rig.flow.submitAddress()
        await rig.wait(for: .certificateMismatch)
        XCTAssertEqual(rig.flow.screen, .certificateMismatch)
        let probes = rig.backend.probes
        try rig.flow.acceptCertificate(userAcceptedFingerprint: String(repeating: "ef", count: 32))
        XCTAssertEqual(rig.flow.screen, .certificateMismatch)
        XCTAssertEqual(rig.backend.probes, probes)
        XCTAssertEqual(try rig.pins.fingerprint(for: Sample.serverID), previous)
        try rig.flow.acceptCertificate(userAcceptedFingerprint: sampleLeaf().sha256)
        await rig.wait(for: .loginMethod)
        XCTAssertEqual(rig.flow.screen, .loginMethod)
        XCTAssertEqual(rig.pins.writes.map(\.serverID), [Sample.serverID, Sample.serverID])
        XCTAssertEqual(try rig.pins.fingerprint(for: Sample.serverID), sampleLeaf().sha256)
    }

    @MainActor
    func testS44_removingServerAlsoRevokesTheInMemoryAcceptance() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        let url = Sample.url("https://media.example")
        rig.flow.addressText = url.absoluteString
        rig.backend.probeOutcome = .needsCertificate(sampleLeaf(), url: url)
        rig.backend.readyWithPin = rig.server()
        rig.flow.submitAddress()
        await rig.wait(for: .certificate)
        try rig.flow.acceptCertificate(userAcceptedFingerprint: sampleLeaf().sha256)
        await rig.wait(for: .loginMethod)
        rig.flow.removeCurrentServer()
        XCTAssertNil(try rig.pins.fingerprint(for: Sample.serverID))
        rig.flow.submitAddress()
        await rig.wait(for: .certificate)
        XCTAssertNil(rig.backend.probePins.last!)
        XCTAssertEqual(rig.flow.screen, .certificate)
    }

    @MainActor
    func testS44_unknownLeafCannotBeAcceptedOrStored() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.flow.addressText = "https://media.example"
        rig.backend.probeOutcome = .needsCertificate(
            ProbeTransportError.unknownLeaf, url: Sample.url(rig.flow.addressText))
        rig.flow.submitAddress()
        await rig.wait(for: .certificate)
        let probes = rig.backend.probes
        XCTAssertFalse(rig.flow.canAcceptCertificate)
        try rig.flow.acceptCertificate(userAcceptedFingerprint: "")
        try rig.flow.acceptCertificate(userAcceptedFingerprint: sampleLeaf().sha256)
        await rig.wait(for: .certificate)
        XCTAssertEqual(rig.flow.screen, .certificate)
        XCTAssertEqual(rig.backend.probes, probes)
        XCTAssertTrue(rig.pins.writes.isEmpty)
    }

    @MainActor
    func testQ416_certificateAndMismatchUseSanitizedSavedNameOrHost() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        try seed(rig.harness, version: "10.11.0", token: Sample.token)
        let repo = PreferencesRepository(store: rig.harness.settings)
        var prefs = repo.load()
        prefs.servers[0].name = "**Home**\u{202E}\u{0085}"
        try repo.save(prefs)
        try rig.pins.save(fingerprint: String(repeating: "cd", count: 32), serverID: Sample.serverID)
        rig.flow.addressText = "https://media.example:8096"
        rig.backend.probeOutcome = .needsCertificate(sampleLeaf(), url: Sample.url(rig.flow.addressText))
        rig.flow.submitAddress()
        await rig.wait(for: .certificateMismatch)
        XCTAssertEqual(rig.flow.screen, .certificateMismatch)
        XCTAssertEqual(rig.flow.displayedName, "**Home**")
        rig.flow.rejectCertificate()
        rig.flow.addressText = "https://other.example"
        rig.backend.probeOutcome = .needsCertificate(sampleLeaf(), url: Sample.url(rig.flow.addressText))
        rig.flow.submitAddress()
        await rig.wait(for: .certificate)
        XCTAssertEqual(rig.flow.screen, .certificate)
        XCTAssertEqual(rig.flow.displayedName, "other.example")
    }

    @MainActor
    func testT04_34_disabledQuickConnectSkipsA3AndBackReturnsToA2() async {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.quickConnect = false
        rig.flow.addressText = "https://example.com"
        rig.backend.probeOutcome = .ready(rig.server())
        rig.flow.submitAddress()
        await rig.wait(for: .credentials)
        XCTAssertEqual(rig.flow.screen, .credentials)
        XCTAssertEqual(rig.flow.focus, .username)
        rig.flow.goBack()
        XCTAssertEqual(rig.flow.screen, .address)
        XCTAssertEqual(rig.flow.focus, .continueButton)
    }

    @MainActor
    func testT04_35_initiateIsPostOnlyAfterA4Opens() async {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server())
        let enabledGate = ResumeGate()
        rig.backend.enabledGate = enabledGate
        rig.flow.submitAddress()
        await rig.backend.enabledStarted.wait()
        // The probe is done, but the login method is still awaiting the enabled response.
        XCTAssertFalse(rig.flow.isProbing)
        XCTAssertFalse(rig.flow.quickConnectEnabled)
        XCTAssertEqual(rig.flow.screen, .welcome)
        enabledGate.releaseAll()
        await rig.wait(for: .loginMethod)
        XCTAssertEqual(rig.backend.initiates, 0)
        XCTAssertEqual(rig.backend.enabledCalls, 1)
        XCTAssertEqual(rig.backend.publicUserCalls, 0)
        await rig.flow.chooseQuickConnect()
        XCTAssertEqual(rig.backend.initiates, 1)
        XCTAssertEqual(rig.backend.initiateMethods, ["POST"])
        XCTAssertEqual(rig.flow.quickConnectCode, "482913")
        XCTAssertEqual(rig.flow.screen, .quickConnect)
        XCTAssertTrue(rig.flow.isPolling)
    }

    @MainActor
    func testT04_37_secretIsNotStoredOrLogged() async {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server())
        rig.backend.secret = "super-secret-value"
        rig.flow.submitAddress()
        await rig.wait(for: .loginMethod)
        await rig.flow.chooseQuickConnect()
        let settings = rig.harness.settings.allValues().values.joined()
        XCTAssertFalse(settings.contains("super-secret-value"))
        XCTAssertFalse(rig.harness.log.contains("super-secret-value"))
        XCTAssertEqual(rig.flow.quickConnectCode, "482913")
        let described = QuickConnectChallenge(code: "482913", secret: "super-secret-value", authenticated: false)
        XCTAssertFalse(String(describing: described).contains("super-secret-value"))
        XCTAssertFalse(String(reflecting: QuickConnectSecret("super-secret-value")).contains("super-secret-value"))
    }

    @MainActor
    func testT04_40_expiryRenewsAtMostThreeTimes() async {
        let clock = AdvancingClock()
        let rig = Rig(clock: clock)
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server())
        rig.backend.pollAuthenticated = false
        rig.flow.submitAddress()
        await rig.wait(for: .loginMethod)
        await rig.flow.chooseQuickConnect()
        await rig.wait(until: { rig.flow.quickConnectExpired })
        XCTAssertEqual(rig.backend.initiates, 4)
        XCTAssertEqual(rig.flow.quickConnectRenewals, 3)
        XCTAssertTrue(rig.flow.quickConnectExpired)
        XCTAssertFalse(rig.flow.isPolling)
        XCTAssertEqual(rig.flow.inlineError, .quickConnectExpired)
        XCTAssertEqual(rig.flow.focus, .newCode)
        rig.backend.pollAuthenticated = true
        await rig.flow.getNewQuickConnectCode()
        await rig.wait(for: .home)
        XCTAssertEqual(rig.backend.initiates, 5)
        XCTAssertFalse(rig.flow.quickConnectExpired)
        XCTAssertEqual(rig.flow.screen, .home)
    }

    @MainActor
    func testT04_41_transientPollFailureDoesNotSignOut() async {
        let rig = Rig(clock: AdvancingClock())
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server())
        rig.backend.pollError = .server(status: 503)
        rig.backend.pollThenAuthenticate = true
        let finishGate = ResumeGate()
        rig.backend.finishGate = finishGate
        rig.flow.submitAddress()
        await rig.wait(for: .loginMethod)
        await rig.flow.chooseQuickConnect()
        await rig.backend.finishStarted.wait()
        // Polling has stopped, but exchanging the secret has not published a session yet.
        XCTAssertFalse(rig.flow.isPolling)
        XCTAssertEqual(rig.flow.screen, .quickConnect)
        XCTAssertEqual(rig.harness.app.phase, .launching)
        XCTAssertEqual(rig.backend.polls, 2)
        finishGate.releaseAll()
        await rig.wait(for: .home)
        guard case .signedIn = rig.harness.app.phase else { return XCTFail("expected home") }
        XCTAssertNotEqual(rig.harness.app.phase, .needsLogin(rig.server()))
    }

    @MainActor
    func testT04_42_backgroundCancelsPolling() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server())
        rig.backend.blockPoll = true
        rig.flow.submitAddress()
        await rig.wait(for: .loginMethod)
        await rig.flow.chooseQuickConnect()
        XCTAssertTrue(rig.flow.isPolling)
        let pollTask = try XCTUnwrap(rig.flow.pollTask)
        await rig.backend.pollStarted.wait()
        rig.flow.sceneBecameBackground()
        XCTAssertFalse(rig.flow.isPolling)
        let calls = rig.backend.polls
        rig.backend.resumePoll(true)
        await pollTask.value
        XCTAssertEqual(rig.backend.polls, calls)
        XCTAssertEqual(rig.flow.screen, .quickConnect)
    }

    @MainActor
    func testT04_43_quickConnectUnauthorizedKeepsTheSession() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        try rig.harness.secure.set(Data(Sample.token.utf8), account: Sample.account(), attributes: .production)
        rig.backend.probeOutcome = .ready(rig.server())
        rig.backend.finishError = .unauthorized
        rig.flow.submitAddress()
        await rig.wait(for: .loginMethod)
        await rig.flow.chooseQuickConnect()
        await rig.wait(until: { rig.flow.inlineError == .quickConnectUnauthorized })
        XCTAssertEqual(rig.flow.inlineError, .quickConnectUnauthorized)
        XCTAssertNotEqual(rig.flow.inlineError, .invalidCredentials)
        XCTAssertNotNil(try rig.harness.secure.data(for: Sample.account()))
        guard case .launching = rig.harness.app.phase else {
            return XCTFail("Quick Connect 401 must not end a session")
        }
    }

    @MainActor
    func testT04_46_passwordSignInReachesHome() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server(id: AuthIDs.server))
        rig.backend.quickConnect = false
        rig.flow.submitAddress()
        await rig.wait(for: .credentials)
        rig.flow.choosePassword()
        rig.flow.username = "Ada"
        await rig.flow.signIn(password: "correct")
        guard case .signedIn(let session) = rig.harness.app.phase else { return XCTFail("expected signed in") }
        XCTAssertEqual(session.userID, AuthIDs.user)
        XCTAssertEqual(rig.flow.screen, .home)
        let account = try CredentialVault.tokenAccount(serverID: AuthIDs.server, userID: AuthIDs.user)
        let stored = try XCTUnwrap(try rig.harness.secure.data(for: account))
        XCTAssertEqual(String(decoding: stored, as: UTF8.self), "access-token")
        XCTAssertEqual(rig.harness.secure.writes().filter { $0.hasPrefix("token:") }, [account])
        XCTAssertFalse(rig.harness.secure.writes().contains { $0.hasPrefix("session-token/") })
        XCTAssertEqual(rig.backend.capabilityBodies.count, 1)
        let body = String(decoding: rig.backend.capabilityBodies[0], as: UTF8.self)
        XCTAssertTrue(body.contains("Video"))
        XCTAssertTrue(body.contains("Audio"))
        XCTAssertTrue(body.contains("SupportsMediaControl"))
        XCTAssertFalse(body.contains("DeviceProfile"))
    }

    @MainActor
    func testT04_47_wrongPasswordClearsTheFieldAndKeepsTheToken() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        try rig.harness.secure.set(Data(Sample.token.utf8), account: Sample.account(), attributes: .production)
        rig.backend.probeOutcome = .ready(rig.server())
        rig.backend.quickConnect = false
        rig.backend.signInError = .unauthorized
        rig.flow.submitAddress()
        await rig.wait(for: .credentials)
        rig.flow.choosePassword()
        await rig.flow.signIn(password: "wrong")
        XCTAssertEqual(rig.flow.inlineError, .invalidCredentials)
        XCTAssertEqual(rig.flow.focus, .password)
        XCTAssertTrue(rig.flow.passwordCleared)
        XCTAssertNotNil(try rig.harness.secure.data(for: Sample.account()))
        guard case .signedIn = rig.harness.app.phase else { return }
        XCTFail("login 401 must not end a session")
    }

    @MainActor
    func testT04_48_passwordIsAbsentAfterTheCall() async {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server(id: AuthIDs.server))
        rig.backend.quickConnect = false
        rig.flow.submitAddress()
        await rig.wait(for: .credentials)
        rig.flow.choosePassword()
        await rig.flow.signIn(password: "pässi🔑")
        XCTAssertTrue(rig.flow.passwordCleared)
        let settings = rig.harness.settings.allValues().values.joined()
        XCTAssertFalse(settings.contains("pässi"))
        XCTAssertFalse(rig.harness.log.contains("pässi"))
        XCTAssertFalse(rig.backend.seenPasswords.isEmpty)
    }

    @MainActor
    func testT04_50_serverFailureIsNotInvalidCredentials() async {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server())
        rig.backend.quickConnect = false
        rig.backend.signInError = .server(status: 500)
        rig.flow.submitAddress()
        await rig.wait(for: .credentials)
        rig.flow.choosePassword()
        await rig.flow.signIn(password: "secret")
        XCTAssertEqual(rig.flow.inlineError, .loginServerFailure)
        XCTAssertNotEqual(rig.flow.inlineError, .invalidCredentials)
    }

    @MainActor
    func testT04_52_capabilitiesFailureKeepsSignedInAndRetriesOnceOnForeground() async {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server(id: AuthIDs.server))
        rig.backend.quickConnect = false
        rig.backend.capabilitiesError = .server(status: 500)
        rig.flow.submitAddress()
        await rig.wait(for: .credentials)
        rig.flow.choosePassword()
        await rig.flow.signIn(password: "correct")
        guard case .signedIn = rig.harness.app.phase else { return XCTFail("sign-in should proceed") }
        XCTAssertEqual(rig.flow.screen, .home)
        XCTAssertEqual(rig.backend.capabilityBodies.count, 1)
        XCTAssertEqual(rig.harness.app.preferencesSnapshot().activeUser()?.capabilitiesRetryPending, true)
        XCTAssertFalse(rig.harness.log.contains("access-token"))
        await rig.flow.sceneBecameActive()
        XCTAssertEqual(rig.backend.capabilityBodies.count, 2)
        await rig.flow.sceneBecameActive()
        XCTAssertEqual(rig.backend.capabilityBodies.count, 2)
        XCTAssertEqual(rig.harness.app.preferencesSnapshot().activeUser()?.capabilitiesRetryPending, false)
    }

    @MainActor
    func testT04_54_tokenIsNotInTheSessionOrSettings() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server(id: AuthIDs.server))
        rig.backend.quickConnect = false
        rig.flow.submitAddress()
        await rig.wait(for: .credentials)
        rig.flow.choosePassword()
        await rig.flow.signIn(password: "correct")
        guard case .signedIn(let session) = rig.harness.app.phase else { return XCTFail("expected session") }
        XCTAssertFalse(String(describing: session).contains("access-token"))
        let snapshot = String(decoding: try JSONEncoder().encode(rig.harness.app.preferencesSnapshot()), as: UTF8.self)
        XCTAssertFalse(snapshot.contains("access-token"))
    }

    @MainActor
    func testT04_55_tenServersAndUsersStayUnderTheBudget() async throws {
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

    @MainActor
    func testT04_58_usersMeUnauthorizedLogsOutOnce() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        try seed(rig.harness, version: "10.11.0", token: Sample.token)
        rig.backend.currentUserError = .unauthorized
        await rig.flow.restoreSession()
        XCTAssertEqual(rig.backend.currentUserCalls, 1)
        XCTAssertEqual(rig.flow.noticeKey, .sessionExpired)
        XCTAssertNil(try rig.harness.secure.data(for: Sample.account()))
        guard case .needsLogin = rig.harness.app.phase else { return XCTFail("expected login") }
        await rig.flow.restoreSession()
        XCTAssertEqual(rig.backend.currentUserCalls, 1)
    }

    @MainActor
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

    @MainActor
    func testT04_61_usersMeFailuresKeepTheToken() async throws {
        for error in [
            APIError.forbidden, .server(status: 500), .server(status: 502), .server(status: 503), .server(status: 504),
            .tls, .timeout,
        ] {
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
            XCTAssertNil(rig.flow.inlineError)
            XCTAssertEqual(rig.flow.screen, .home)
            XCTAssertEqual(rig.flow.connectivity, .serverUnreachable)
            XCTAssertEqual(rig.flow.bannerKey, .serverUnreachable)
            XCTAssertEqual(rig.harness.app.bannerKey, AppErrorMessage.serverDownKey)
            XCTAssertEqual(rig.flow.bannerKey?.rawValue, rig.harness.app.bannerKey)
            XCTAssertEqual(rig.flow.homeErrorKey, .serverUnreachable)
            rig.cleanup()
        }
    }

    @MainActor
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

    @MainActor
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

    @MainActor
    func testT04_67_failedLogoutStillClearsAndReportsTheKey() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        try seed(rig.harness, version: "10.11.0", token: Sample.token)
        rig.harness.app.bootstrap()
        rig.backend.logoutError = .server(status: 500)
        rig.flow.requestLogout()
        XCTAssertEqual(rig.flow.confirmFocus, .cancel)
        await rig.flow.confirmLogout()
        XCTAssertNil(try rig.harness.secure.data(for: Sample.account()))
        XCTAssertEqual(rig.flow.noticeKey, .serverSessionMayRemain)
        XCTAssertEqual(rig.flow.screen, .loginMethod)
        XCTAssertEqual(rig.flow.focus, .quickConnect)
        XCTAssertEqual(rig.harness.app.preferencesSnapshot().servers.count, 1)
    }

    @MainActor
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

    @MainActor
    func testT04_93_probeFailureShowsTheSkippedHTTPFlag() async {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .notFound(ProbeFailureDetail(httpSkippedByPolicy: true))
        rig.flow.addressText = "203.0.113.5"
        rig.flow.submitAddress()
        await rig.wait(until: { rig.flow.inlineError == .serverNotFound })
        XCTAssertEqual(rig.flow.inlineError, .serverNotFound)
        XCTAssertTrue(rig.flow.httpSkippedByPolicy)
        rig.backend.probeOutcome = .publicHTTPRejected
        rig.flow.addressText = "http://203.0.113.5:8096"
        rig.flow.submitAddress()
        await rig.wait(until: { rig.flow.inlineError == .publicAddressRequiresHTTPS })
        XCTAssertEqual(rig.flow.inlineError, .publicAddressRequiresHTTPS)
        XCTAssertFalse(rig.flow.httpSkippedByPolicy)
    }

    @MainActor
    func testT04_92_setupRetryProbesAgainWithoutSaving() async {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .setupIncomplete(address: Sample.url("https://media.example"))
        rig.flow.submitAddress()
        await rig.wait(for: .setupIncomplete)
        XCTAssertEqual(rig.flow.screen, .setupIncomplete)
        XCTAssertEqual(rig.flow.focus, .tryAgain)
        XCTAssertTrue(rig.harness.app.preferencesSnapshot().servers.isEmpty)
        let calls = rig.backend.probes
        rig.flow.retrySetup()
        await rig.wait(for: .setupIncomplete)
        XCTAssertEqual(rig.backend.probes, calls + 1)
        XCTAssertEqual(rig.flow.screen, .setupIncomplete)
        XCTAssertEqual(rig.backend.enabledCalls, 0)
    }
    @MainActor
    func testT04_38_pollingChecksImmediatelyThenEveryFiveSeconds() async {
        let clock = SuspendingClock()
        let rig = Rig(clock: clock)
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server())
        rig.backend.pollAuthenticated = false
        rig.flow.submitAddress()
        await rig.wait(for: .loginMethod)
        await rig.flow.chooseQuickConnect()
        await clock.waitForSleeps(1)
        XCTAssertEqual(rig.backend.polls, 1)
        XCTAssertEqual(clock.sleeps(), [.seconds(5)])
        clock.advance(by: .seconds(5))
        clock.resumeAll()
        await clock.waitForSleeps(2)
        XCTAssertEqual(rig.backend.polls, 2)
        XCTAssertEqual(clock.sleeps(), [.seconds(5), .seconds(5)])
    }

    @MainActor
    func testT04_39_leavingA4CancelsAllFurtherRequests() async throws {
        let clock = SuspendingClock()
        let rig = Rig(clock: clock)
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server())
        rig.backend.pollAuthenticated = false
        rig.flow.submitAddress()
        await rig.wait(for: .loginMethod)
        await rig.flow.chooseQuickConnect()
        await clock.waitForSleeps(1)
        let pollTask = try XCTUnwrap(rig.flow.pollTask)
        rig.flow.goBack()
        let calls = rig.backend.polls
        clock.advance(by: .seconds(60))
        clock.resumeAll()
        await pollTask.value
        XCTAssertEqual(rig.backend.polls, calls)
        XCTAssertEqual(rig.backend.initiates, 1)
        XCTAssertFalse(rig.flow.isPolling)
        XCTAssertNil(rig.flow.quickConnectCode)
        XCTAssertEqual(rig.flow.screen, .loginMethod)
    }

    @MainActor
    func testT04_42_foregroundChecksYoungCodeImmediatelyAndKeepsOriginalExpiry() async {
        let clock = SuspendingClock()
        let rig = Rig(clock: clock)
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server())
        rig.backend.pollAuthenticated = false
        rig.flow.submitAddress()
        await rig.wait(for: .loginMethod)
        await rig.flow.chooseQuickConnect()
        await clock.waitForSleeps(1)
        rig.flow.sceneBecameBackground()
        clock.advance(by: .seconds(299))
        let calls = rig.backend.polls
        await rig.flow.sceneBecameActive()
        await clock.waitForSleeps(2)
        XCTAssertEqual(rig.backend.polls, calls + 1)
        XCTAssertEqual(rig.backend.initiates, 1)
        XCTAssertEqual(clock.sleeps().last, .seconds(1))
        rig.flow.sceneBecameBackground()
        clock.advance(by: .seconds(1))
        await rig.flow.sceneBecameActive()
        await clock.waitForSleeps(3)
        XCTAssertEqual(rig.backend.initiates, 2)
        XCTAssertEqual(rig.flow.quickConnectRenewals, 1)
    }

    @MainActor
    func testT04_42_oldForegroundCodesConsumeTheThreeRenewals() async {
        let clock = SuspendingClock()
        let rig = Rig(clock: clock)
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server())
        rig.backend.pollAuthenticated = false
        rig.flow.submitAddress()
        await rig.wait(for: .loginMethod)
        await rig.flow.chooseQuickConnect()
        await clock.waitForSleeps(1)
        for renewal in 1...3 {
            rig.flow.sceneBecameBackground()
            clock.advance(by: .seconds(300))
            await rig.flow.sceneBecameActive()
            await clock.waitForSleeps(renewal + 1)
            XCTAssertEqual(rig.flow.quickConnectRenewals, renewal)
        }
        rig.flow.sceneBecameBackground()
        clock.advance(by: .seconds(300))
        await rig.flow.sceneBecameActive()
        XCTAssertEqual(rig.backend.initiates, 4)
        XCTAssertTrue(rig.flow.quickConnectExpired)
        XCTAssertEqual(rig.flow.focus, .newCode)
    }

    @MainActor
    func testT04_50_passwordAndQuickConnectUseDistinctNetworkAndServerErrorKeys() async {
        for error in [APIError.network, .timeout, .server(status: 500), .server(status: 502), .server(status: 503)] {
            let rig = Rig()
            defer { rig.cleanup() }
            rig.backend.probeOutcome = .ready(rig.server())
            rig.flow.submitAddress()
            await rig.wait(for: .loginMethod)
            rig.backend.signInError = error
            rig.flow.choosePassword()
            await rig.flow.signIn(password: "sample")
            let expected: AuthCopy.Key = {
                if case .server = error { return .loginServerFailure }
                return .loginTransportFailure
            }()
            XCTAssertEqual(rig.flow.inlineError, expected)
            rig.flow.goBack()
            rig.backend.finishError = error
            await rig.flow.chooseQuickConnect()
            await rig.wait(until: { rig.flow.inlineError == expected })
            XCTAssertEqual(rig.flow.inlineError, expected)
            XCTAssertEqual(rig.flow.screen, .quickConnect)
        }
    }

    @MainActor
    func testT04_52_pendingCapabilitiesRetrySurvivesRelaunchAndIsConsumedOnce() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        rig.backend.probeOutcome = .ready(rig.server(id: AuthIDs.server))
        rig.backend.capabilitiesError = .server(status: 503)
        rig.flow.submitAddress()
        await rig.wait(for: .loginMethod)
        await rig.flow.signIn(password: "sample")
        XCTAssertEqual(rig.harness.app.preferencesSnapshot().activeUser()?.capabilitiesRetryPending, true)
        let restarted = AuthFlow(
            app: rig.harness.app, backend: rig.backend, pins: rig.pins,
            vault: CredentialVault(secureStore: rig.harness.secure, settings: rig.harness.settings, accessGroup: ""),
            clock: rig.harness.clock, log: rig.harness.log)
        await restarted.restoreSession()
        XCTAssertEqual(rig.backend.capabilityBodies.count, 2)
        await restarted.sceneBecameActive()
        XCTAssertEqual(rig.backend.capabilityBodies.count, 2)
        XCTAssertEqual(restarted.screen, .home)
        XCTAssertFalse(rig.harness.log.contains("access-token"))
    }

    @MainActor
    func testT04_59_launchFailureLoadsCachedHomeAndKeepsToken() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        try seed(rig.harness, version: "10.11.0", token: Sample.token)
        let snapshot = HomeSnapshot(resume: [], nextUp: [], latest: [])
        XCTAssertTrue(rig.harness.app.snapshots.save(snapshot))
        rig.backend.currentUserError = .network
        await rig.flow.restoreSession()
        XCTAssertEqual(rig.flow.screen, .home)
        XCTAssertEqual(rig.flow.cachedHome, snapshot)
        XCTAssertNil(rig.flow.homeErrorKey)
        XCTAssertEqual(rig.flow.connectivity, .serverUnreachable)
        XCTAssertEqual(rig.flow.bannerKey, .serverUnreachable)
        XCTAssertEqual(rig.harness.app.bannerKey, AppErrorMessage.serverDownKey)
        XCTAssertEqual(rig.flow.bannerKey?.rawValue, rig.harness.app.bannerKey)
        XCTAssertNotNil(try rig.harness.secure.data(for: Sample.account()))

        rig.harness.app.handle(.offline)
        XCTAssertEqual(rig.flow.bannerKey, .noNetworkConnection)
        XCTAssertEqual(rig.flow.bannerKey?.rawValue, rig.harness.app.bannerKey)
        XCTAssertEqual(rig.flow.cachedHome, snapshot)
        XCTAssertNil(rig.flow.homeErrorKey)

        rig.harness.app.beginServerSwitch()
        XCTAssertEqual(rig.flow.connectivity, .offline)
        XCTAssertEqual(rig.flow.bannerKey, .noNetworkConnection)
        XCTAssertEqual(rig.flow.bannerKey?.rawValue, rig.harness.app.bannerKey)

        rig.harness.app.handle(.serverUnreachable)
        XCTAssertEqual(rig.flow.bannerKey, .serverUnreachable)
        rig.harness.app.beginServerSwitch()
        XCTAssertEqual(rig.flow.connectivity, .online)
        XCTAssertNil(rig.flow.bannerKey)
        XCTAssertNil(rig.harness.app.bannerKey)
    }

    @MainActor
    func testT04_60_sixSecondRequestTimesOutAtFiveSecondsWithoutRetry() async throws {
        let clock = SuspendingClock()
        let rig = Rig(clock: clock)
        defer { rig.cleanup() }
        try seed(rig.harness, version: "10.11.0", token: Sample.token)
        rig.backend.currentUserDelay = true
        let launch = Task { await rig.flow.restoreSession() }
        await clock.waitForSleeps(1)
        await waitUntil { rig.backend.currentUserCalls == 1 }
        XCTAssertEqual(clock.sleeps(), [.seconds(5)])
        clock.advance(by: .seconds(5))
        clock.resumeAll()
        await launch.value
        XCTAssertEqual(rig.backend.currentUserCalls, 1)
        XCTAssertEqual(rig.flow.screen, .home)
        XCTAssertEqual(rig.flow.connectivity, .serverUnreachable)
        XCTAssertEqual(rig.flow.homeErrorKey, .serverUnreachable)
        XCTAssertNotNil(try rig.harness.secure.data(for: Sample.account()))
    }

    @MainActor
    func testT04_63_noCacheShowsHomeErrorAndRetryAndStillAllowsLogout() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        try seed(rig.harness, version: "10.11.0", token: Sample.token)
        rig.backend.currentUserError = .forbidden
        await rig.flow.restoreSession()
        XCTAssertEqual(rig.flow.screen, .home)
        XCTAssertNil(rig.flow.cachedHome)
        XCTAssertEqual(rig.flow.homeErrorKey, .serverUnreachable)
        XCTAssertEqual(rig.flow.focus, .tryAgain)
        rig.backend.currentUserError = nil
        await rig.flow.retryHome()
        XCTAssertEqual(rig.backend.currentUserCalls, 2)
        XCTAssertNil(rig.flow.homeErrorKey)
        XCTAssertNil(rig.flow.bannerKey)
        XCTAssertNil(rig.harness.app.bannerKey)
        rig.flow.requestLogout()
        XCTAssertEqual(rig.flow.screen, .logoutConfirm)
        XCTAssertEqual(rig.flow.confirmFocus, .cancel)
    }

    @MainActor
    func testT04_68_logoutChoosesSavedUsersOnTheSameServerAndKeepsServer() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        try seed(rig.harness, version: "10.11.0", token: Sample.token)
        let repo = PreferencesRepository(store: rig.harness.settings)
        let prefs = repo.load().upserting(
            user: StoredUser(
                serverID: Sample.serverID, userID: Sample.otherUserID, userName: "Bea", isAdministrator: false)
        )
        .upserting(
            user: StoredUser(
                serverID: Sample.otherServerID, userID: "elsewhere", userName: "Cal", isAdministrator: false))
        try repo.save(prefs)
        await rig.flow.restoreSession()
        rig.flow.requestLogout()
        XCTAssertEqual(rig.flow.confirmFocus, .cancel)
        await rig.flow.confirmLogout()
        XCTAssertEqual(rig.flow.screen, .userPicker)
        XCTAssertEqual(rig.flow.publicUsers.map(\.id), [Sample.otherUserID])
        XCTAssertEqual(repo.load().servers.count, 1)
        XCTAssertNil(try rig.harness.secure.data(for: Sample.account()))
    }

    @MainActor
    func testT04_68_logoutWithoutOtherUsersSkipsA3WhenQuickConnectDisabledOnRelaunch() async throws {
        let rig = Rig()
        defer { rig.cleanup() }
        try seed(rig.harness, version: "10.11.0", token: Sample.token)
        rig.backend.quickConnect = false
        await rig.flow.restoreSession()
        await rig.flow.confirmLogout()
        XCTAssertEqual(rig.flow.screen, .credentials)
        await rig.flow.restoreSession()
        XCTAssertEqual(rig.backend.currentUserCalls, 1)
        XCTAssertEqual(rig.flow.screen, .credentials)
        XCTAssertEqual(rig.harness.app.preferencesSnapshot().servers.count, 1)
    }

    @MainActor
    func testT04_87_launchFailurePingsEveryTenSecondsRecoversAndLater401SignsOut() async throws {
        let rig = Rig(automaticPing: true)
        defer { rig.cleanup() }
        try seed(rig.harness, version: "10.11.0", token: Sample.token)
        rig.backend.currentUserError = .server(status: 503)
        await rig.flow.restoreSession()
        await rig.harness.suspending?.waitForSleeps(2)
        // The first sleep is the launch timeout; the second is the recovery ping.
        XCTAssertEqual(rig.harness.suspending?.sleeps().last, .seconds(10))
        rig.harness.pinger.outcome = .ok
        rig.harness.suspending?.resumeAll()
        await waitUntil { rig.flow.connectivity == .online }
        XCTAssertNil(rig.flow.bannerKey)
        XCTAssertNil(rig.harness.app.bannerKey)
        XCTAssertEqual(rig.flow.screen, .home)
        XCTAssertNotNil(try rig.harness.secure.data(for: Sample.account()))
        rig.harness.app.handle(.serverUnreachable)
        rig.harness.pinger.outcome = .failed(.unauthorized)
        await rig.harness.app.retryNow()
        await rig.flow.synchronizeSession()
        XCTAssertEqual(rig.flow.noticeKey, .sessionExpired)
        XCTAssertNil(try rig.harness.secure.data(for: Sample.account()))
        XCTAssertEqual(rig.flow.screen, .loginMethod)
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

    init(clock: (any GlassfinClock)? = nil, automaticPing: Bool = false) {
        harness = Harness.make(automaticPing: automaticPing, suspendingClock: true)
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

    func cleanup() {
        flow.cancelProbe()
        flow.sceneBecameBackground()
        backend.enabledGate?.releaseAll()
        backend.finishGate?.releaseAll()
        backend.resumePoll(false)
        harness.app.signOutLocally(notice: nil)
        harness.cleanup()
    }

    func server(id: String = Sample.serverID, user: String = Sample.userID) -> ServerInfo {
        _ = user
        return ServerInfo(
            id: id, name: "Home", url: Sample.url("https://media.example"),
            version: SemVer(major: 10, minor: 11, patch: 0))
    }

    func wait(for screen: AuthScreen, file: StaticString = #filePath, line: UInt = #line) async {
        await wait(until: { flow.screen == screen && !flow.isProbing }, file: file, line: line)
    }

    func wait(
        until condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        let observation = AuthCondition(condition)
        observation.observe()
        // Preserve the old helper's 100 x 5 ms failure budget; state changes drive progress.
        let result = await XCTWaiter.fulfillment(of: [observation.fulfilled], timeout: 0.5)
        observation.stop()
        if result != .completed { XCTFail("authentication condition was not met", file: file, line: line) }
    }
}

/// Re-arm after each change because Observation callbacks fire before the new value is stored.
@MainActor
private final class AuthCondition {
    let fulfilled = XCTestExpectation(description: "authentication condition")
    private let condition: @MainActor () -> Bool
    private var completed = false

    init(_ condition: @escaping @MainActor () -> Bool) {
        self.condition = condition
    }

    func stop() {
        completed = true
    }

    func observe() {
        guard !completed else { return }
        if withObservationTracking(
            { condition() },
            onChange: { [weak self] in
                Task { @MainActor [weak self] in self?.observe() }
            })
        {
            completed = true
            fulfilled.fulfill()
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
    var readyWithPin: ServerInfo?
    var probePins: [OriginCertificatePin?] = []
    var quickConnect = true
    var enabledCalls = 0
    var enabledGate: ResumeGate?
    let enabledStarted = ResumeGate()
    var finishGate: ResumeGate?
    let finishStarted = ResumeGate()
    let pollStarted = ResumeGate()
    var publicUserCalls = 0
    var probes = 0
    var users: [PublicUser] = []
    var currentUserDelay = false
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

    func probe(_ address: String, certificatePin: OriginCertificatePin?) async -> ServerProbeOutcome {
        lock.withLock {
            probes += 1
            probePins.append(certificatePin)
        }
        if let readyWithPin, certificatePin?.fingerprint(for: readyWithPin.url) == sampleLeaf().sha256,
            RedirectPolicy.originsMatch(Sample.url(address), readyWithPin.url)
        {
            return .ready(readyWithPin)
        }
        return probeOutcome
    }

    func quickConnectEnabled(on server: ServerInfo) async throws(APIError) -> Bool {
        _ = server
        lock.withLock { enabledCalls += 1 }
        enabledStarted.releaseAll()
        if let enabledGate { await enabledGate.wait() }
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
        finishStarted.releaseAll()
        if let finishGate { await finishGate.wait() }
        if let finishError { throw finishError }
        let session = UserSession(server: server, userID: Sample.userID, userName: "Ada", isAdministrator: false)
        return AuthenticatedSession(session: session, accessToken: "access-token")
    }

    func currentUser(on server: ServerInfo, token: String) async throws(APIError) -> UserSession {
        _ = token
        recordCurrentUser()
        if currentUserDelay {
            do { try await Task.sleep(for: .seconds(60)) } catch { throw APIError.cancelled }
        }
        if let currentUserError { throw currentUserError }
        return UserSession(server: server, userID: Sample.userID, userName: "Ada", isAdministrator: false)
    }

    func publicUsers(on server: ServerInfo) async throws(APIError) -> [PublicUser] {
        _ = server
        lock.withLock { publicUserCalls += 1 }
        return users
    }

    func postCapabilities(on server: ServerInfo, token: String) async throws(APIError) {
        _ = server
        _ = token
        let body = Data(
            #"{"PlayableMediaTypes":["Video","Audio"],"SupportsMediaControl":false,"SupportedCommands":[]}"#.utf8)
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
        pollStarted.releaseAll()
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
    var failOnRead: Int?
    var reads = 0
    private var values: [String: String] = [:]
    var writes: [(serverID: String, fingerprint: String)] = []
    func fingerprint(for serverID: String) throws -> String? {
        reads += 1
        if reads == failOnRead { throw SecurityInvariantError.internalInvariant }
        return values[serverID]
    }
    func save(fingerprint: String, serverID: String) throws {
        writes.append((serverID, fingerprint))
        values[serverID] = fingerprint
    }
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
