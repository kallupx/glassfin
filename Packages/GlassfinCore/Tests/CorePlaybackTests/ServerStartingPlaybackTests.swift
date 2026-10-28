import CoreModels
import CoreNetworking
import CorePlayback
import Foundation
import XCTest

@MainActor
final class ServerStartingPlaybackTests: XCTestCase {
    func testMedia401FollowedByCurrentUser503KeepsSessionAndShowsStartup() async {
        let outcome = await MediaUnauthorizedPolicy.decide(probe: StartingCurrentUser())
        XCTAssertEqual(outcome, .serverStarting)
    }

    func testStartup503DoesNotFallBackOrExpireSessionAndManualRetryCanRecover() async throws {
        for failItem in [false, true] {
            let fixture = try playbackFixture()
            let item = try playbackItemFixture(from: fixture)
            let client = PoCAPIClient { request throws(APIError) in
                if request.method == "GET" && request.path.contains("/Items/") {
                    if failItem { throw .server(status: 503) }
                    return item
                }
                throw .server(status: 503)
            }
            let session = makeSession(client)
            let engine = MockPlaybackEngine()
            let timer = ManualPlaybackTimer()
            let coordinator = PlaybackCoordinator(
                session: session, engine: engine, origin: MockPlaybackOrigin(), timer: timer, configuration: .poc)
            await coordinator.play(itemID: pocItemID, choice: .startOver)
            XCTAssertEqual(coordinator.state, .failed(localizedKey: AppErrorMessage.serverStartingKey))
            XCTAssertEqual(coordinator.appError, .serverStarting)
            XCTAssertNil(coordinator.failure)
            XCTAssertEqual(session.expirationCount, 0)
            XCTAssertTrue(engine.loadAttempts.isEmpty)
            XCTAssertFalse(timer.isRunning)
            let failedCalls = await client.calls
            XCTAssertEqual(failedCalls.count, failItem ? 1 : 2)

            await client.setHandler { request throws(APIError) in
                if request.method == "GET" && request.path.contains("/Items/") { return item }
                if request.path.hasSuffix("PlaybackInfo") { return fixture }
                return Data()
            }
            await coordinator.retryServerStarting()
            await settle { coordinator.state == .playing && timer.isRunning }
            XCTAssertEqual(coordinator.state, .playing)
            XCTAssertNil(coordinator.appError)
            XCTAssertEqual(session.expirationCount, 0)
            await coordinator.stop()
        }
    }

    func testPlayingReport503StopsWithoutAutomaticRetryAndKeepsSession() async throws {
        let fixture = try playbackFixture()
        let item = try playbackItemFixture(from: fixture)
        let client = PoCAPIClient { request throws(APIError) in
            if request.method == "GET" && request.path.contains("/Items/") { return item }
            if request.path.hasSuffix("PlaybackInfo") { return fixture }
            throw .server(status: 503)
        }
        let session = makeSession(client)
        let timer = ManualPlaybackTimer()
        let coordinator = PlaybackCoordinator(
            session: session, engine: MockPlaybackEngine(), origin: MockPlaybackOrigin(),
            timer: timer, configuration: .poc)
        await coordinator.play(itemID: pocItemID, choice: .startOver)
        await settle { coordinator.appError == .serverStarting }
        await settle { await client.calls.contains { $0.path == "/Sessions/Playing/Stopped" } }
        XCTAssertEqual(coordinator.state, .failed(localizedKey: AppErrorMessage.serverStartingKey))
        XCTAssertEqual(session.expirationCount, 0)
        XCTAssertFalse(timer.isRunning)
        let calls = await client.calls
        XCTAssertEqual(calls.filter { $0.path == "/Sessions/Playing" }.count, 1)
        XCTAssertEqual(calls.filter { $0.path == "/Sessions/Playing/Stopped" }.count, 1)
    }

    private func makeSession(_ client: any JellyfinAPIClient) -> MockPlaybackSession {
        MockPlaybackSession(
            serverURL: URL(string: "https://server.example/jellyfin")!, userID: pocUserID,
            identity: ClientIdentity(deviceName: "TV", deviceID: "test-device", version: "test", token: "mock-token"),
            apiClient: client)
    }

    private func settle(_ condition: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await condition()), ContinuousClock.now < deadline { await Task.yield() }
        let fulfilled = await condition()
        XCTAssertTrue(fulfilled, file: file, line: line)
    }
}

private struct StartingCurrentUser: CurrentUserProbing {
    func currentUser() async throws(APIError) { throw .server(status: 503) }
}
