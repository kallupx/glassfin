import CoreModels
import CoreNetworking
import CorePlayback
import CoreState
import CoreTestSupport
import Foundation
import GlassfinServices
import XCTest

@MainActor
final class T08PlaybackWiringTests: XCTestCase {
    func testResumeAndFromBeginningReachPlaybackInfoAndEngine() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        let model = ItemDetailViewModel(library: rig.library, app: rig.app)
        let item = MediaItem(
            id: Sample.movie, kind: .movie, name: "Fixture", userData: UserItemState(playbackPosition: .seconds(123)))
        for (startOver, expected) in [(false, Int64(1_230_000_000)), (true, Int64(0))] {
            let intent = try XCTUnwrap(model.playbackIntent(for: item, startOver: startOver))
            let client = client()
            let engine = MockPlaybackEngine()
            let coordinator = coordinator(client: client, engine: engine, app: rig.app)
            await coordinator.play(
                PlaybackRequest(itemID: intent.itemID, startTicks: Ticks.outboundPositionTicks(from: intent.start)),
                returnFocusID: startOver ? "detail.startOver" : "detail.play")
            let calls = await client.calls
            let request = try XCTUnwrap(calls.first { $0.path.hasSuffix("/PlaybackInfo") })
            let body = try XCTUnwrap(request.body)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual((json["StartTimeTicks"] as? NSNumber)?.int64Value, expected)
            XCTAssertEqual(engine.loads.first?.start, .seconds(startOver ? 0 : 123))
            await coordinator.dismiss()
        }
    }

    func testDismissReportsStoppedUpdatesStoreAndReturnsStartingFocus() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        _ = await rig.app.userData.project([
            MediaItem(id: Sample.movie, kind: .movie, name: "Fixture", userData: UserItemState(isFavorite: true))
        ])
        let client = client()
        let engine = MockPlaybackEngine()
        let coordinator = coordinator(client: client, engine: engine, app: rig.app)
        await coordinator.play(request(), returnFocusID: "series.episode.\(Sample.movie)")
        engine.position = .seconds(456)
        let focus = await coordinator.dismiss()
        XCTAssertEqual(focus, "series.episode.\(Sample.movie)")
        let state = await rig.app.userData.state(for: Sample.movie)
        XCTAssertEqual(state?.playbackPosition, .seconds(456))
        XCTAssertEqual(state?.played, false)
        XCTAssertEqual(state?.isFavorite, true)
        let pending = await rig.app.userData.isPending(id: Sample.movie)
        XCTAssertTrue(pending)
        let calls = await client.calls
        let stopped = try XCTUnwrap(calls.first { $0.path == "/Sessions/Playing/Stopped" })
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(stopped.body)) as? [String: Any])
        XCTAssertEqual(json["ItemId"] as? String, Sample.movie)
        XCTAssertEqual((json["PositionTicks"] as? NSNumber)?.int64Value, 4_560_000_000)
        await coordinator.dismiss()
        let repeated = await client.calls
        XCTAssertEqual(repeated.filter { $0.path == "/Sessions/Playing/Stopped" }.count, 1)
    }

    func testNaturalEndDismissWaitsForStoppedAndMarksPlayed() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        let gate = StopGate()
        let client = MockAPIClient { request throws(APIError) in
            if request.path.hasSuffix("/Stopped") { await gate.wait() }
            return MockPlaybackFactory.response(for: request)
        }
        let engine = MockPlaybackEngine()
        let coordinator = coordinator(client: client, engine: engine, app: rig.app)
        await coordinator.play(request(), returnFocusID: "detail.play")
        await settle { coordinator.state == .playing }
        engine.position = .seconds(900)
        engine.emit(.ended)
        await settle { await gate.waiting }
        var dismissed = false
        let dismissal = Task {
            await coordinator.dismiss()
            dismissed = true
        }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(dismissed)
        let state = await rig.app.userData.state(for: Sample.movie)
        XCTAssertEqual(state?.played, true)
        XCTAssertEqual(state?.playbackPosition, .zero)
        await gate.release()
        await dismissal.value
        XCTAssertTrue(dismissed)
        XCTAssertEqual(coordinator.returnFocusID, "detail.play")
        let calls = await client.calls
        XCTAssertEqual(calls.filter { $0.path.hasSuffix("/Stopped") }.count, 1)
    }

    func testTrackOptionsReachNegotiationWithoutCredentialsInRequest() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        let client = client()
        let coordinator = coordinator(client: client, engine: MockPlaybackEngine(), app: rig.app)
        let request = PlaybackRequest(
            itemID: try XCTUnwrap(ItemID(Sample.movie)), startTicks: -1, audioStreamIndex: 2, subtitleStreamIndex: 3)
        XCTAssertEqual(request.startTicks, 0)
        await coordinator.play(request, returnFocusID: "detail.startOver")
        let calls = await client.calls
        let body = try XCTUnwrap(calls.first { $0.path.hasSuffix("/PlaybackInfo") }?.body)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["AudioStreamIndex"] as? Int, 2)
        XCTAssertEqual(json["SubtitleStreamIndex"] as? Int, 3)
        XCTAssertNil(json["AccessToken"])
        await coordinator.dismiss()
    }

    func testFailureUsesLocalizedErrorAndStillReturnsFocus() async throws {
        let coordinator = MockPlaybackFactory.makeCoordinator(cannotPlay: true)
        await coordinator.play(request(), returnFocusID: "detail.play")
        XCTAssertEqual(coordinator.state, .failed(localizedKey: PlaybackCopy.couldNotPlayKey))
        let focus = await coordinator.dismiss()
        XCTAssertEqual(focus, "detail.play")
    }

    private func request() -> PlaybackRequest {
        PlaybackRequest(itemID: ItemID(Sample.movie)!, startTicks: 0)
    }

    private func client() -> MockAPIClient {
        MockAPIClient { request throws(APIError) in MockPlaybackFactory.response(for: request) }
    }

    private func coordinator(client: MockAPIClient, engine: MockPlaybackEngine, app: AppState) -> PlaybackCoordinator {
        PlaybackCoordinator(
            session: MockPlaybackSession(
                serverURL: URL(string: "https://fixture.example")!, userID: Sample.session().userID,
                identity: ClientIdentity(deviceName: "Fixture", deviceID: "fixture", version: "1", token: "fixture"),
                apiClient: client), engine: engine, origin: MockPlaybackOrigin(), timer: ManualPlaybackTimer(),
            onStopped: { await app.recordPlaybackStop($0) })
    }

    private func settle(_ condition: @MainActor () async -> Bool, file: StaticString = #filePath, line: UInt = #line)
        async
    {
        for _ in 0..<2_000 {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("Playback did not settle", file: file, line: line)
    }
}

private actor StopGate {
    private var continuation: CheckedContinuation<Void, Never>?
    var waiting: Bool { continuation != nil }
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func release() {
        continuation?.resume()
        continuation = nil
    }
}
