import CoreModels
import CoreNetworking
import Foundation
import XCTest

@testable import CoreState

final class PinFailureTests: XCTestCase {
    func testPinReadFailurePreventsClientCreation() {
        let backend = LiveAuthBackend(secureStore: InMemorySecureStore(), pins: UnreadablePins())
        XCTAssertThrowsError(try backend.makeClient(for: Sample.server(), token: Sample.token)) { error in
            XCTAssertEqual(error as? APIError, .tls)
            XCTAssertEqual(
                AppErrorMapping.map(.tls, context: .authenticated, deviceOffline: false),
                .tlsUntrusted(.unavailable))
        }
    }

    func testPinReadFailureNeverSendsThroughOverride() async {
        let client = PinRequestRecorder()
        let backend = LiveAuthBackend(secureStore: InMemorySecureStore(), client: client, pins: UnreadablePins())
        do {
            _ = try await backend.currentUser(on: Sample.server(), token: Sample.token)
            XCTFail("An unreadable stored pin must fail before a request is sent")
        } catch {
            XCTAssertEqual(error, .tls)
        }
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testMissingPinAndUnconfiguredStoreKeepDefaultTrust() throws {
        let stores: [(any CertificatePinStore)?] = [
            nil, SettingsCertificatePinStore(settings: InMemorySettingsStore()),
        ]
        for pins in stores {
            let backend = LiveAuthBackend(secureStore: InMemorySecureStore(), pins: pins)
            let client = try XCTUnwrap(
                backend.makeClient(for: Sample.server(), token: Sample.token) as? HTTPJellyfinClient)
            defer { client.session.invalidateAndCancel() }
            XCTAssertNil(client.certificatePin)
            XCTAssertEqual(client.identity.token, Sample.token)
        }
    }

    func testMalformedStoredPinFailsInsteadOfUsingDefaultTrust() {
        let settings = InMemorySettingsStore()
        let pins = SettingsCertificatePinStore(settings: settings)
        let backend = LiveAuthBackend(secureStore: InMemorySecureStore(), pins: pins)
        for malformed in ["", "not-a-fingerprint", String(repeating: "a", count: 63)] {
            settings.set(malformed, forKey: SettingsCertificatePinStore.key(Sample.serverID))
            XCTAssertThrowsError(try pins.fingerprint(for: Sample.serverID))
            XCTAssertThrowsError(try backend.makeClient(for: Sample.server(), token: nil)) { error in
                XCTAssertEqual(error as? APIError, .tls)
            }
        }
    }

    func testInvalidFingerprintFromCustomStoreFailsClosed() {
        let pins = InvalidPins()
        XCTAssertThrowsError(try pins.certificatePin(for: Sample.serverID, url: Sample.server().url)) { error in
            XCTAssertEqual(error as? APIError, .tls)
        }
    }

    func testUndecodableStoredValueIsNotTreatedAsMissingPin() throws {
        let suite = "glassfin-pin-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = UserDefaultsSettingsStore(defaults: defaults)
        let pins = SettingsCertificatePinStore(settings: settings)
        let backend = LiveAuthBackend(secureStore: InMemorySecureStore(), pins: pins)
        let key = SettingsCertificatePinStore.key(Sample.serverID)
        defaults.set(["invalid": "pin"], forKey: key)
        XCTAssertNil(settings.string(forKey: key))
        XCTAssertTrue(settings.containsValue(forKey: key))
        XCTAssertThrowsError(try backend.makeClient(for: Sample.server(), token: nil)) { error in
            XCTAssertEqual(error as? APIError, .tls)
        }
        defaults.removeObject(forKey: key)
        XCTAssertNil(try pins.fingerprint(for: Sample.serverID))
    }

    @MainActor
    func testHomeFactoriesPropagatePinReadFailure() throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        let pins = UnreadablePins()
        let flow = AuthFlow(
            app: harness.app, backend: LiveAuthBackend(secureStore: harness.secure, pins: pins), pins: pins,
            vault: CredentialVault(secureStore: harness.secure, settings: harness.settings, accessGroup: ""),
            clock: harness.clock)
        XCTAssertThrowsError(try flow.makeHomeClient()) { error in
            XCTAssertEqual(error as? APIError, .tls)
        }
        XCTAssertThrowsError(try flow.makeHomeEvents()) { error in
            XCTAssertEqual(error as? APIError, .tls)
        }
        guard case .signedIn = harness.app.phase else { return XCTFail("A pin read failure must keep the session") }
    }

    @MainActor
    func testSearchFactoryPropagatesPinReadFailureBeforeUsingAnyClient() throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        let pins = UnreadablePins()
        let flow = AuthFlow(
            app: harness.app, backend: LiveAuthBackend(secureStore: harness.secure, pins: pins), pins: pins,
            vault: CredentialVault(secureStore: harness.secure, settings: harness.settings, accessGroup: ""),
            clock: harness.clock)
        let client = PinRequestRecorder()
        let overrides: [(any JellyfinAPIClient)?] = [nil, client]
        for override in overrides {
            XCTAssertThrowsError(try flow.makeSearchFeature(client: override)) { error in
                XCTAssertEqual(error as? APIError, .tls)
            }
        }
        XCTAssertTrue(client.requests.isEmpty)
        guard case .signedIn = harness.app.phase else { return XCTFail("A pin read failure must keep the session") }
    }

    @MainActor
    func testSearchFactoryWithMissingPinAllowsClientCreation() throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        let pins = SettingsCertificatePinStore(settings: harness.settings)
        let flow = AuthFlow(
            app: harness.app, backend: LiveAuthBackend(secureStore: harness.secure, pins: pins), pins: pins,
            vault: CredentialVault(secureStore: harness.secure, settings: harness.settings, accessGroup: ""),
            clock: harness.clock)
        let client = PinRequestRecorder()
        let overrides: [(any JellyfinAPIClient)?] = [nil, client]
        for override in overrides {
            XCTAssertNotNil(try flow.makeSearchFeature(client: override))
        }
        XCTAssertTrue(client.requests.isEmpty)
    }
}

private struct UnreadablePins: CertificatePinStore {
    func fingerprint(for serverID: String) throws -> String? { throw CocoaError(.fileReadNoPermission) }
    func save(fingerprint: String, serverID: String) throws { throw SecurityInvariantError.internalInvariant }
    func remove(serverID: String) throws {}
}

private struct InvalidPins: CertificatePinStore {
    func fingerprint(for serverID: String) throws -> String? { "invalid" }
    func save(fingerprint: String, serverID: String) throws {}
    func remove(serverID: String) throws {}
}

private final class PinRequestRecorder: JellyfinAPIClient, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [APIRequest] = []
    var requests: [APIRequest] { lock.withLock { recorded } }

    func send(_ request: APIRequest) async throws(APIError) -> Data {
        lock.withLock { recorded.append(request) }
        throw .network
    }
}
