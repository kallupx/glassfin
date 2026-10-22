import CoreNetworking
import Foundation
import XCTest

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Docker integration against jellyfin/jellyfin 10.10.7, 10.11.11, and 12.2 is confirmed
/// but intentionally deferred until after M00 and M01. Credentials must come from GitHub
/// Secrets only. See `.github/workflows/integration.yml`. This file does not start containers.
final class DockerIntegrationTests: XCTestCase {
    func testDeferredDockerMatrix() throws {
        throw XCTSkip(
            "TODO: run jellyfin/jellyfin 10.10.7, 10.11.11, and 12.2 with throwaway credentials after M00 and M01."
        )
    }

    /// Follow-up, not this change. For 10.10.7, 10.11.11, and 12.2, open `{base}/socket`
    /// with only the Authorization header (no `ApiKey` query) and wait for the first
    /// KeepAlive or ForceKeepAlive frame.
    func testWebSocketHeaderOnlyWaitsForKeepAliveOnServerMatrix() throws {
        let versions = ["10.10.7", "10.11.11", "12.2"]
        let request = try SocketRequestBuilder.make(
            server: URL(string: "https://media.example/jellyfin")!,
            identity: ClientIdentity(
                deviceName: "Living Room", deviceID: "device-1", version: "0.1.0", token: "token-secret")
        )
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.path, "/jellyfin/socket")
        XCTAssertFalse(url.absoluteString.contains("ApiKey"))
        XCTAssertNotNil(request.value(forHTTPHeaderField: "Authorization"))
        throw XCTSkip(
            "Deferred. Against jellyfin \(versions.joined(separator: ", ")), open this header-only socket and wait for the first KeepAlive or ForceKeepAlive. Docker is not started."
        )
    }
}
