import CoreModels
import CoreNetworking
import Foundation
import XCTest

@testable import CoreState

final class T04LiveAuthTests: XCTestCase {
    func testT04_52_productionCapabilitiesUseTheFinalPayload() async throws {
        let client = AuthWireClient()
        let backend = LiveAuthBackend(secureStore: InMemorySecureStore(), client: client)
        try await backend.postCapabilities(on: server(), token: "sample-token")
        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/Sessions/Capabilities/Full")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
        XCTAssertEqual(body["PlayableMediaTypes"] as? [String], ["Video", "Audio"])
        XCTAssertEqual(body["SupportsMediaControl"] as? Bool, false)
        XCTAssertNil(body["DeviceProfile"])
    }

    func testT04_35_productionMethodCheckNeverInitiatesQuickConnect() async throws {
        let client = AuthWireClient()
        client.payload = Data("true".utf8)
        let backend = LiveAuthBackend(secureStore: InMemorySecureStore(), client: client)
        let enabled = try await backend.quickConnectEnabled(on: server())
        XCTAssertTrue(enabled)
        XCTAssertEqual(client.requests.map(\.method), ["GET"])
        XCTAssertEqual(client.requests.map(\.path), ["/QuickConnect/Enabled"])
        client.payload = Data(#"{"Code":"482913","Secret":"sample-secret","Authenticated":false}"#.utf8)
        _ = try await backend.beginQuickConnect(on: server())
        XCTAssertEqual(client.requests.map(\.method), ["GET", "POST"])
        XCTAssertEqual(client.requests.map(\.path), ["/QuickConnect/Enabled", "/QuickConnect/Initiate"])
    }

    func testT04_60_productionCurrentUserNeverRetries() async {
        let client = AuthWireClient()
        client.error = .timeout
        let backend = LiveAuthBackend(secureStore: InMemorySecureStore(), client: client)
        do {
            _ = try await backend.currentUser(on: server(), token: "sample-token")
            XCTFail("expected timeout")
        } catch {
            XCTAssertEqual(error, .timeout)
        }
        XCTAssertEqual(client.requests.map(\.path), ["/Users/Me"])
    }

    func testS44_productionSessionUsesTheSavedServerPin() throws {
        let settings = InMemorySettingsStore()
        let pins = SettingsCertificatePinStore(settings: settings)
        let fingerprint = String(repeating: "ab", count: 32)
        try pins.save(fingerprint: fingerprint, serverID: server().id)
        let backend = LiveAuthBackend(secureStore: InMemorySecureStore(), pins: pins)
        let client = try XCTUnwrap(backend.makeClient(for: server(), token: nil) as? HTTPJellyfinClient)
        defer { client.session.invalidateAndCancel() }
        XCTAssertEqual(client.certificatePin?.fingerprint(for: server().url), fingerprint)
        XCTAssertNil(client.certificatePin?.fingerprint(for: URL(string: "https://other.example")!))
        var second = server()
        second.id = "cccccccccccccccccccccccccccccccc"
        second.url = URL(string: "https://other.example")!
        let secondClient = try XCTUnwrap(backend.makeClient(for: second, token: nil) as? HTTPJellyfinClient)
        defer { secondClient.session.invalidateAndCancel() }
        XCTAssertNil(secondClient.certificatePin)
    }

    private func server() -> ServerInfo {
        ServerInfo(
            id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", name: "Home", url: URL(string: "https://example.com/jellyfin")!,
            version: SemVer(major: 10, minor: 10, patch: 0))
    }
}

private final class AuthWireClient: JellyfinAPIClient, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [APIRequest] = []
    var payload = Data("{}".utf8)
    var error: APIError?
    var requests: [APIRequest] { lock.withLock { recorded } }

    func send(_ request: APIRequest) async throws(APIError) -> Data {
        lock.withLock { recorded.append(request) }
        if let error { throw error }
        return payload
    }
}
