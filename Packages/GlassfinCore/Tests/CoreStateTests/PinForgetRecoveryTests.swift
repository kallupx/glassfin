import CoreModels
import CoreNetworking
import Foundation
import XCTest

@testable import CoreState

final class PinForgetRecoveryTests: XCTestCase {
    @MainActor
    func testRemovingServerRecoversFromMalformedPin() async throws {
        try await verifyRecovery(corruption: .malformed, forgetUsingFlow: false)
    }

    @MainActor
    func testRemovingServerRecoversFromUndecodablePin() async throws {
        try await verifyRecovery(corruption: .undecodable, forgetUsingFlow: false)
    }

    @MainActor
    func testForgettingCurrentServerRecoversFromMalformedPin() async throws {
        try await verifyRecovery(corruption: .malformed, forgetUsingFlow: true)
    }

    @MainActor
    func testForgettingCurrentServerRecoversFromUndecodablePin() async throws {
        try await verifyRecovery(corruption: .undecodable, forgetUsingFlow: true)
    }

    private enum PinCorruption {
        case malformed
        case undecodable
    }

    @MainActor
    private func verifyRecovery(corruption: PinCorruption, forgetUsingFlow: Bool) async throws {
        let suite = "glassfin-pin-recovery-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let settings = UserDefaultsSettingsStore(defaults: defaults)
        let secure = InMemorySecureStore()
        let pins = SettingsCertificatePinStore(settings: settings)
        let vault = CredentialVault(secureStore: secure, settings: settings, accessGroup: "")
        let log = CapturingLog()
        let clock = SuspendingClock()
        defer { clock.resumeAll() }
        let app = AppState(
            secureStore: secure, settings: settings, path: PipePath(online: true), pinger: StubPinger(),
            cacheRoot: root, clock: clock, automaticPing: false, log: log)
        try app.didSignIn(Sample.session(), token: Sample.token)
        // Also cover an indexed credential whose user is absent from the preferences list.
        try vault.save(
            token: "fixture-second-token", serverID: Sample.serverID, userID: Sample.otherUserID,
            profile: StoredSessionProfile(
                serverID: Sample.serverID, serverName: Sample.server().name,
                serverURL: Sample.server().url.absoluteString, userID: Sample.otherUserID,
                userName: "Bea", isAdministrator: false))

        let pinKey = SettingsCertificatePinStore.key(Sample.serverID)
        switch corruption {
        case .malformed:
            defaults.set("not-a-fingerprint", forKey: pinKey)
        case .undecodable:
            defaults.set(["invalid": "pin"], forKey: pinKey)
        }
        XCTAssertTrue(settings.containsValue(forKey: pinKey))
        XCTAssertThrowsError(try pins.fingerprint(for: Sample.serverID))

        let candidates = RecoveryCandidates()
        let wire = ScriptedClient(results: [
            .success(Data("false".utf8)),
            .success(
                Data(
                    """
                    {"AccessToken":"fixture-fresh-token","ServerId":"\(Sample.serverID)",
                    "User":{"Id":"\(Sample.userID)","Name":"Ada"}}
                    """.utf8)),
            .success(Data()),
        ])
        let backend = LiveAuthBackend(
            secureStore: secure, log: log, probeClient: candidates, clock: clock, client: wire, pins: pins)
        let flow = AuthFlow(app: app, backend: backend, pins: pins, vault: vault, clock: clock, log: log)
        defer { flow.cancelProbe() }

        do {
            _ = try await backend.currentUser(on: Sample.server(), token: Sample.token)
            XCTFail("A corrupted pin must prevent connecting")
        } catch {
            XCTAssertEqual(error, .tls)
        }
        flow.connect()
        flow.addressText = Sample.server().url.absoluteString
        flow.submitAddress()
        XCTAssertEqual(flow.screen, .address)
        XCTAssertEqual(flow.inlineError, .loginTransportFailure)
        XCTAssertFalse(flow.isProbing)
        await flow.restoreSession()
        XCTAssertEqual(app.securityNotice, .tlsUntrusted(.unavailable))
        XCTAssertNotNil(try vault.loadToken(serverID: Sample.serverID, userID: Sample.userID))
        guard case .signedIn = app.phase else { return XCTFail("TLS failure must keep the saved session") }
        XCTAssertTrue(wire.requests().isEmpty)
        let blockedProbes = await candidates.pins
        XCTAssertTrue(blockedProbes.isEmpty)

        if forgetUsingFlow {
            flow.removeCurrentServer()
        } else {
            app.removeServer(id: Sample.serverID)
            await flow.synchronizeSession()
        }
        XCTAssertEqual(app.phase, .needsServer)
        XCTAssertNil(app.activeServer)
        XCTAssertEqual(flow.screen, .welcome)
        XCTAssertFalse(settings.containsValue(forKey: pinKey))
        XCTAssertNil(defaults.object(forKey: pinKey))
        XCTAssertNil(try pins.fingerprint(for: Sample.serverID))
        XCTAssertNil(try vault.loadToken(serverID: Sample.serverID, userID: Sample.userID))
        XCTAssertNil(try vault.loadToken(serverID: Sample.serverID, userID: Sample.otherUserID))
        XCTAssertTrue(app.preferencesSnapshot().servers.isEmpty)
        XCTAssertTrue(app.preferencesSnapshot().users.isEmpty)
        XCTAssertNil(app.preferencesSnapshot().activeServerID)
        XCTAssertNil(app.preferencesSnapshot().activeUserID)
        XCTAssertTrue(wire.requests().isEmpty)

        // Reuse the same origin and server ID: forgetting must permit fresh, explicit trust.
        flow.connect()
        flow.addressText = Sample.server().url.absoluteString
        flow.submitAddress()
        await waitUntil { flow.screen == .certificate && !flow.isProbing }
        XCTAssertEqual(flow.certificate, RecoveryCandidates.leaf)
        XCTAssertTrue(flow.canAcceptCertificate)
        XCTAssertNil(try pins.fingerprint(for: Sample.serverID))
        let unpinnedProbes = await candidates.pins
        XCTAssertEqual(unpinnedProbes.count, 1)
        XCTAssertNil(try XCTUnwrap(unpinnedProbes.first))
        XCTAssertTrue(wire.requests().isEmpty)

        try flow.acceptCertificate(userAcceptedFingerprint: RecoveryCandidates.leaf.sha256)
        XCTAssertNil(try pins.fingerprint(for: Sample.serverID))
        await waitUntil { flow.screen == .credentials && !flow.isProbing }
        let acceptedProbes = await candidates.pins
        XCTAssertEqual(acceptedProbes.count, 2)
        XCTAssertEqual(
            acceptedProbes.last.flatMap { $0 }?.fingerprint(for: Sample.server().url),
            RecoveryCandidates.leaf.sha256)
        XCTAssertEqual(try pins.fingerprint(for: Sample.serverID), RecoveryCandidates.leaf.sha256)

        flow.username = Sample.session().userName
        await flow.signIn(password: "fixture-password")
        XCTAssertEqual(flow.screen, .home)
        XCTAssertNil(flow.inlineError)
        XCTAssertEqual(app.phase, .signedIn(Sample.session()))
        XCTAssertNotNil(try vault.loadToken(serverID: Sample.serverID, userID: Sample.userID))
        XCTAssertNil(try vault.loadToken(serverID: Sample.serverID, userID: Sample.otherUserID))
        XCTAssertEqual(app.preferencesSnapshot().servers.map(\.id), [Sample.serverID])
        XCTAssertEqual(
            wire.requests().map(\.path),
            ["/QuickConnect/Enabled", "/Users/AuthenticateByName", "/Sessions/Capabilities/Full"])

        // Inspect production client configuration without making any network requests.
        let live = LiveAuthBackend(secureStore: secure, pins: pins)
        let client = try XCTUnwrap(live.makeClient(for: Sample.server(), token: nil) as? HTTPJellyfinClient)
        defer { client.session.invalidateAndCancel() }
        XCTAssertEqual(client.certificatePin?.fingerprint(for: Sample.server().url), RecoveryCandidates.leaf.sha256)
        XCTAssertNil(client.certificatePin?.fingerprint(for: Sample.url("https://other.example")))
        XCTAssertNil(client.session.configuration.urlCache)
        XCTAssertFalse(log.contains(Sample.token))
        XCTAssertFalse(log.contains("fixture-second-token"))
        XCTAssertFalse(log.contains("fixture-fresh-token"))
        XCTAssertFalse(log.contains("fixture-password"))
    }
}

/// A self-signed transport fixture that succeeds only after receiving the matching origin pin.
private actor RecoveryCandidates: ServerCandidateClient {
    static let leaf = CertificatePresentation(
        sha256: String(repeating: "ab", count: 32), subject: "CN=media.example",
        notBefore: Date(timeIntervalSince1970: 1), notAfter: Date(timeIntervalSince1970: 2))
    private(set) var pins: [OriginCertificatePin?] = []

    func fetchPublicInfo(url: URL, timeout: Duration, certificatePin: OriginCertificatePin?) async
        -> ServerCandidateResult
    {
        pins.append(certificatePin)
        guard certificatePin?.fingerprint(for: url) == Self.leaf.sha256 else { return .tls(Self.leaf) }
        return .jellyfin(Sample.server(), startupComplete: true)
    }
}
