import CoreModels
import CoreNetworking
import CoreState
import Foundation
import XCTest

@MainActor
final class T06SessionTests: XCTestCase {
    // T06-51: canonical spec/TESTPLAN-M06.md.
    func testT06_51_image401CancelsOtherRequestsAndDoesNotRetry() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        let transport = SessionProbeClient()
        let client = HomeSessionClient(inner: transport, app: h.app, scope: h.app.scope)
        let pending = Task { try await client.send(APIRequest(method: "GET", path: "/slow")) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await transport.started) && ContinuousClock.now < deadline { await Task.yield() }
        let started = await transport.started
        XCTAssertTrue(started)
        let resource = ImageResource(
            serverID: Sample.serverID, itemID: Sample.movie, type: .primary, tag: "t", width: 1, height: 1)
        do {
            _ = try await client.send(resource.request())
            XCTFail("Expected authenticated image 401")
        } catch { XCTAssertEqual(error, .unauthorized) }
        do {
            _ = try await pending.value
            XCTFail("Expected cancelled sibling request")
        } catch { XCTAssertEqual(error as? APIError, .cancelled) }
        XCTAssertEqual(h.app.sessionNoticeKey, .sessionExpired)
        XCTAssertEqual(h.secure.removed().count, 1)
        do { _ = try await client.send(resource.request()) } catch { XCTAssertEqual(error, .cancelled) }
        let count = await transport.calls
        XCTAssertEqual(count, 2)
    }
}

private actor SessionProbeClient: JellyfinAPIClient {
    var started = false
    var calls = 0
    func send(_ request: APIRequest) async throws(APIError) -> Data {
        calls += 1
        if request.path == "/slow" {
            started = true
            do { try await Task.sleep(for: .seconds(30)) } catch { throw .cancelled }
            return Data()
        }
        throw .unauthorized
    }
}
