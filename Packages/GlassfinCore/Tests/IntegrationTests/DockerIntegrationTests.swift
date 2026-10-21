import XCTest

/// Docker integration against jellyfin/jellyfin 10.10.7, 10.11.11, and 12.2 is confirmed
/// but intentionally deferred until after M00 and M01. Credentials must come from GitHub
/// Secrets only. See `.github/workflows/integration.yml`.
final class DockerIntegrationTests: XCTestCase {
    func testDeferredDockerMatrix() throws {
        throw XCTSkip(
            "TODO: run jellyfin/jellyfin 10.10.7, 10.11.11, and 12.2 with throwaway credentials after M00 and M01."
        )
    }
}
