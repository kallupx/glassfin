import CoreModels
import CoreNetworking
import CoreState
import Foundation
import XCTest

@MainActor
final class T09RetryTests: XCTestCase {
    /// T09-60: transient gateway failures retry twice with the shared 0.5/1.5 second delays.
    func testT09_60_gatewayFailuresRetryTwiceWithSharedBackoff() async throws {
        for status in [502, 503, 504] {
            let wire = GatewaySearchClient(status: status)
            let clock = ManualClock()
            let client = RetryingAPIClient(inner: wire, clock: clock)
            let data = try await client.send(QueryTransport.searchHints(term: "current", limit: 24))
            XCTAssertEqual(data, Data("ok".utf8))
            XCTAssertEqual(wire.attempts, 3)
            XCTAssertEqual(clock.sleeps(), [.milliseconds(500), .milliseconds(1500)])
        }
    }

    /// T09-60, T09-13: cancellation while waiting for retry prevents another request for the old query.
    func testT09_60_cancelledQueryDoesNotRetryAfterBackoff() async throws {
        let wire = GatewaySearchClient(status: 503)
        let clock = SuspendingClock()
        let client = RetryingAPIClient(inner: wire, clock: clock)
        let work = Task { try await client.send(QueryTransport.searchHints(term: "old", limit: 24)) }
        await clock.waitForSleeps(1)
        work.cancel()
        clock.resumeAll()
        do {
            _ = try await work.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertEqual(error as? APIError, .cancelled) }
        XCTAssertEqual(wire.attempts, 1)
    }
}

private final class GatewaySearchClient: JellyfinAPIClient, @unchecked Sendable {
    private let status: Int
    private let lock = NSLock()
    private var count = 0
    var attempts: Int { lock.withLock { count } }
    init(status: Int) { self.status = status }
    func send(_ request: APIRequest) async throws(APIError) -> Data {
        let attempt = lock.withLock {
            count += 1
            return count
        }
        if attempt <= 2 { throw .server(status: status) }
        return Data("ok".utf8)
    }
}
