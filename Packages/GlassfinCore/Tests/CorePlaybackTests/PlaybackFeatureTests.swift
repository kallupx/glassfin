import CoreModels
import CoreNetworking
import CorePlayback
import Foundation
import XCTest

final class SegmentTimelineTests: XCTestCase {
    func testIntroUsesHalfOpenBoundaries() throws {
        let intro = try XCTUnwrap(TimedSegment(kind: .intro, start: 600_000_000, end: 1_500_000_000))
        XCTAssertNil(SegmentTimeline.active(at: 599_999_999, segments: [intro]))
        XCTAssertEqual(SegmentTimeline.active(at: 600_000_000, segments: [intro]), intro)
        XCTAssertEqual(SegmentTimeline.active(at: 1_499_999_999, segments: [intro]), intro)
        XCTAssertNil(SegmentTimeline.active(at: 1_500_000_000, segments: [intro]))
    }

    func testInvalidAndOutOfRuntimeSegmentsAreDiscarded() {
        XCTAssertNil(TimedSegment(kind: .intro, start: -1, end: 100))
        XCTAssertNil(TimedSegment(kind: .intro, start: 100, end: 100))
        XCTAssertNil(TimedSegment(kind: .intro, start: 200, end: 100))
        XCTAssertNil(TimedSegment(kind: .intro, start: 100, end: 200, runtime: 50))
        XCTAssertEqual(TimedSegment(kind: .intro, start: 10, end: 200, runtime: 100)?.end, 100)
    }

    func testOverlapsHaveStableOrdering() throws {
        let first = try XCTUnwrap(TimedSegment(kind: .recap, start: 10, end: 40))
        let second = try XCTUnwrap(TimedSegment(kind: .intro, start: 10, end: 50))
        XCTAssertEqual(SegmentTimeline.active(at: 20, segments: [second, first]), first)
        XCTAssertEqual(SegmentTimeline.active(at: 45, segments: [first, second]), second)
    }

    func testOutroTakesPrecedenceOverRuntimeFallback() throws {
        let outro = try XCTUnwrap(TimedSegment(kind: .outro, start: 800, end: 900))
        XCTAssertEqual(SegmentTimeline.nextEpisodeTrigger(segments: [outro], runtime: 1000), 800)
    }

    func testThirtySecondFallbackHandlesUnknownAndShortRuntime() {
        XCTAssertNil(SegmentTimeline.nextEpisodeTrigger(segments: [], runtime: nil))
        XCTAssertNil(SegmentTimeline.nextEpisodeTrigger(segments: [], runtime: 0))
        XCTAssertEqual(SegmentTimeline.nextEpisodeTrigger(segments: [], runtime: 600_000_000), 300_000_000)
        XCTAssertEqual(SegmentTimeline.nextEpisodeTrigger(segments: [], runtime: 100), 0)
    }

    func testSettingsDefaultToAskAndAutoplayAndRoundTrip() throws {
        let store = InMemorySettingsStore()
        var settings = PlaybackFeatureSettings.load(from: store)
        XCTAssertTrue(settings.autoplay)
        for kind in SegmentKind.allCases { XCTAssertEqual(settings.behavior(for: kind), .ask) }
        settings.autoplay = false
        settings.segments[.intro] = .automatic
        settings.segments[.commercial] = .ignore
        settings.save(to: store)
        XCTAssertEqual(PlaybackFeatureSettings.load(from: store), settings)
        XCTAssertLessThan(try JSONEncoder().encode(settings).count, 1024)
        store.set("invalid", forKey: PlaybackFeatureSettings.storageKey)
        XCTAssertEqual(PlaybackFeatureSettings.load(from: store), .init())
    }
}

final class NextEpisodeTests: XCTestCase {
    func testResolvesImmediateEpisodeAcrossSeasonBoundary() throws {
        let next = NextEpisodeResolver.resolve(currentID: featureItem, seriesID: featureSeries, items: try episodes())
        XCTAssertEqual(next?.id, featureNext)
        XCTAssertEqual(next?.title, "S2E1 – Next <b>episode</b>")
    }

    func testLastEpisodeOrMissingCurrentHasNoNext() throws {
        XCTAssertNil(
            NextEpisodeResolver.resolve(currentID: featureNext, seriesID: featureSeries, items: try episodes()))
        XCTAssertNil(
            NextEpisodeResolver.resolve(currentID: featureSource, seriesID: featureSeries, items: try episodes()))
        XCTAssertNil(NextEpisodeResolver.resolve(currentID: featureItem, seriesID: featureSeries, items: []))
    }

    func testWrongSeriesAndMalformedNextAreRejected() throws {
        for extra in ["\"SeriesId\":\"\(featureSource)\"", "\"Type\":\"Movie\"", "\"Id\":\"../escape\""] {
            var list = try episodes()
            list[1] = try JSONDecoder().decode(BaseItemDTO.self, from: Data("{\(extra)}".utf8))
            XCTAssertNil(NextEpisodeResolver.resolve(currentID: featureItem, seriesID: featureSeries, items: list))
        }
    }

    func testDuplicateCurrentCannotReplayItself() throws {
        let items = try episodes()
        XCTAssertNil(
            NextEpisodeResolver.resolve(currentID: featureItem, seriesID: featureSeries, items: [items[0], items[0]]))
    }

    func testCountdownUsesTenMonotonicSecondsAndFiresOnce() {
        var countdown = NextEpisodeCountdown()
        XCTAssertFalse(countdown.update(now: .seconds(25), eligible: true))
        XCTAssertEqual(countdown.remaining(now: .seconds(25)), 10)
        XCTAssertFalse(countdown.update(now: .seconds(34.5), eligible: true))
        XCTAssertEqual(countdown.remaining(now: .seconds(34.5)), 1)
        XCTAssertTrue(countdown.update(now: .seconds(35), eligible: true))
        XCTAssertFalse(countdown.update(now: .seconds(45), eligible: true))
    }

    func testCancelSuppressesFurtherPromptsForTheSession() {
        var countdown = NextEpisodeCountdown()
        _ = countdown.update(now: .zero, eligible: true)
        countdown.cancel()
        XCTAssertNil(countdown.remaining(now: .seconds(1)))
        XCTAssertFalse(countdown.update(now: .seconds(100), eligible: true))
    }

    func testSeekingAwayOrPausingRestartsFullCountdown() {
        var countdown = NextEpisodeCountdown()
        _ = countdown.update(now: .zero, eligible: true)
        _ = countdown.update(now: .seconds(5), eligible: false)
        XCTAssertNil(countdown.remaining(now: .seconds(5)))
        XCTAssertFalse(countdown.update(now: .seconds(50), eligible: true))
        XCTAssertEqual(countdown.remaining(now: .seconds(50)), 10)
    }
}

final class TrickplayTests: XCTestCase {
    func testTileMathUsesMillisecondsAndRowMajorCoordinates() throws {
        let layout = try layout()
        XCTAssertEqual(layout.frame(at: .seconds(0)), TrickplayFrame(tile: 0, column: 0, row: 0))
        let frame = layout.frame(at: .seconds(5.999))
        XCTAssertEqual(frame.tile, 0)
        XCTAssertEqual(frame.column, 2)
        XCTAssertEqual(frame.row, 0)
        XCTAssertEqual(layout.frame(at: .seconds(10)).row, 1)
        XCTAssertEqual(layout.frame(at: .seconds(40)).tile, 1)
        XCTAssertEqual(layout.frame(at: .seconds(-5)).column, 0)
    }

    func testFinalPartialTileAndHugePositionsClamp() throws {
        let layout = try layout()
        XCTAssertEqual(layout.tileCount, 6)
        let frame = layout.frame(at: .seconds(Int64.max))
        XCTAssertEqual(frame.tile, 5)
        XCTAssertEqual(frame.row, 0)
        XCTAssertEqual(frame.column, 0)
    }

    func testPrefetchIncludesCurrentPlusMinusTwoWithinBounds() throws {
        let layout = try layout()
        XCTAssertEqual(layout.prefetchTiles(at: .zero), [0, 1, 2])
        XCTAssertEqual(layout.prefetchTiles(at: .seconds(80)), [2, 1, 3, 0, 4])
        XCTAssertEqual(layout.prefetchTiles(at: .seconds(200)), [5, 4, 3])
    }

    func testMetadataRejectsInvalidAndExcessiveDimensionsWithoutOverflow() throws {
        for replacement in [
            "\"Width\":0", "\"Height\":-1", "\"TileWidth\":0", "\"TileHeight\":999999999", "\"ThumbnailCount\":0",
            "\"Interval\":0", "\"Width\":9223372036854775807",
        ] {
            let base =
                "{\"Width\":320,\"Height\":180,\"TileWidth\":5,\"TileHeight\":4,\"ThumbnailCount\":101,\"Interval\":2000,\(replacement)}"
            // JSON duplicate keys have decoder-specific precedence; replace the original field explicitly.
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(base.utf8)) as? [String: Any])
            let pair = replacement.split(separator: ":", maxSplits: 1).map(String.init)
            object[pair[0].replacingOccurrences(of: "\"", with: "")] = Int64(pair[1])
            let dto = try JSONDecoder().decode(
                TrickplayInfoDTO.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertNil(TrickplayLayout(dto))
        }
    }

    func testSelectsSmallestAdequateResolutionAndRejectsMissingFields() throws {
        let data = Data("{\"Width\":320}".utf8)
        XCTAssertNil(TrickplayLayout(try JSONDecoder().decode(TrickplayInfoDTO.self, from: data)))
        let info = try info()
        XCTAssertEqual(TrickplayLayout.select(["320": info])?.width, 320)
        XCTAssertNil(TrickplayLayout.select([:]))
    }

    func testTileRequestCarriesByteCapAndNoCredentialQuery() throws {
        let request = try resource(2).request()
        XCTAssertEqual(request.path, "/Videos/\(featureItem)/Trickplay/320/2.jpg")
        XCTAssertEqual(request.maximumResponseBytes, MetadataPolicy.imageMaxBytes)
        XCTAssertEqual(request.query, [URLQueryItem(name: "mediaSourceId", value: featureSource)])
        XCTAssertThrowsError(
            try TrickplayTileResource(itemID: "../x", mediaSourceID: featureSource, width: 320, index: 0).request())
        XCTAssertThrowsError(
            try TrickplayTileResource(itemID: featureItem, mediaSourceID: featureSource, width: 320, index: -1)
                .request())
    }

    func testCacheCountLimitIsHardAndEvictsLeastRecentlyUsed() async {
        let cache = TrickplayCache(maximumTiles: 500)
        for index in 0..<20 { await cache.store(Data([UInt8(index)]), for: resource(index)) }
        _ = await cache.data(for: resource(0))
        await cache.store(Data([20]), for: resource(20))
        let count = await cache.count
        let first = await cache.data(for: resource(0))
        let evicted = await cache.data(for: resource(1))
        XCTAssertEqual(count, 20)
        XCTAssertNotNil(first)
        XCTAssertNil(evicted)
    }

    func testCacheByteBudgetReplacementAndMemoryWarningClear() async {
        let cache = TrickplayCache(maximumBytes: 10)
        await cache.store(Data(repeating: 1, count: 6), for: resource(0))
        await cache.store(Data(repeating: 2, count: 6), for: resource(1))
        let evicted = await cache.data(for: resource(0))
        XCTAssertNil(evicted)
        await cache.store(Data(repeating: 3, count: 3), for: resource(1))
        let bytes = await cache.byteCount
        XCTAssertEqual(bytes, 3)
        await cache.store(Data(repeating: 4, count: 11), for: resource(2))
        let count = await cache.count
        XCTAssertEqual(count, 1)
        await cache.removeAll()
        let cleared = await cache.byteCount
        XCTAssertEqual(cleared, 0)
    }

    func testZeroBudgetDisablesCaching() async {
        let cache = TrickplayCache(maximumTiles: 0)
        await cache.store(Data([1]), for: resource(0))
        let count = await cache.count
        XCTAssertEqual(count, 0)
    }

    private func info() throws -> TrickplayInfoDTO {
        try JSONDecoder().decode(TrickplayInfoDTO.self, from: Data(trickplayJSON.utf8))
    }
    private func layout() throws -> TrickplayLayout { try XCTUnwrap(TrickplayLayout(info())) }
    private func resource(_ index: Int) -> TrickplayTileResource {
        TrickplayTileResource(itemID: featureItem, mediaSourceID: featureSource, width: 320, index: index)
    }
}

@MainActor
final class PlaybackCompanionTests: XCTestCase {
    private var seeks: [Duration] = []
    private var played: [String] = []
    private var stopped = 0
    private var expired = 0
    private var completed: [String] = []

    private func rig(
        segments: String = "{\"Items\":[{\"Type\":\"Intro\",\"StartTicks\":600000000,\"EndTicks\":1500000000}]}",
        error: APIError? = nil, runtime: Int64 = 600_000_0000
    ) async -> (PlaybackCompanion, PoCAPIClient) {
        let client = PoCAPIClient { request throws(APIError) in
            if let error { throw error }
            if request.path.hasPrefix("/MediaSegments/") { return Data(segments.utf8) }
            if request.path.hasPrefix("/Shows/") { return Data(episodesJSON.utf8) }
            if request.path.contains("/Trickplay/") { return Data([1, 2, 3]) }
            if request.path.contains("/PlayedItems/") { return Data() }
            return Data(
                "{\"Id\":\"\(featureItem)\",\"Type\":\"Episode\",\"SeriesId\":\"\(featureSeries)\",\"RunTimeTicks\":\(runtime),\"Trickplay\":{\"\(featureSource)\":{\"320\":\(trickplayJSON)}}}"
                    .utf8)
        }
        let companion = PlaybackCompanion(
            client: client, userID: featureUser,
            seek: { self.seeks.append($0) }, stop: { self.stopped += 1 },
            play: { self.played.append($0) }, unauthorized: { self.expired += 1 },
            completed: { id, _ in self.completed.append(id) })
        await companion.load(itemID: featureItem, mediaSourceID: featureSource)
        return (companion, client)
    }

    func testAskAppearsAt60DisappearsAt150AndPressSeeksToEnd() async {
        let (model, _) = await rig()
        await model.update(position: .seconds(59.99), isPlaying: true, now: .zero)
        XCTAssertNil(model.segment)
        await model.update(position: .seconds(60), isPlaying: true, now: .zero)
        XCTAssertEqual(model.segment?.kind, .intro)
        await model.skipSegment()
        XCTAssertEqual(seeks, [.seconds(150)])
        await model.update(position: .seconds(150), isPlaying: true, now: .zero)
        XCTAssertNil(model.segment)
    }

    func testAutomaticSkipsOnlyOnceUntilLeavingSegmentAndIgnoreDoesNothing() async {
        let (model, _) = await rig()
        model.settings.segments[.intro] = .automatic
        await model.update(position: .seconds(60), isPlaying: true, now: .zero)
        await model.update(position: .seconds(60), isPlaying: true, now: .seconds(1))
        XCTAssertNil(model.segment)
        XCTAssertEqual(seeks, [.seconds(150)])
        await model.update(position: .seconds(0), isPlaying: true, now: .seconds(2))
        await model.update(position: .seconds(60), isPlaying: true, now: .seconds(3))
        XCTAssertEqual(seeks.count, 2)
        model.settings.segments[.intro] = .ignore
        await model.update(position: .seconds(70), isPlaying: true, now: .seconds(4))
        XCTAssertNil(model.segment)
        XCTAssertEqual(seeks.count, 2)
    }

    func testMissingSegmentsAndMetadataRemainOptional() async {
        for error in [APIError.notFound, .network, .decoding, .server(status: 500)] {
            let (model, _) = await rig(error: error)
            XCTAssertNil(model.layout)
            XCTAssertNil(model.next)
            XCTAssertNil(model.segment)
            XCTAssertEqual(expired, 0)
        }
    }

    func testAuthenticated401ExpiresOnceAndDoesNotContinueRequests() async {
        let (_, client) = await rig(error: .unauthorized)
        XCTAssertEqual(expired, 1)
        let calls = await client.calls
        XCTAssertEqual(calls.count, 1)
    }

    func testCancelKeepsPlayingAndProvidesNextEpisodeReturnFocus() async {
        let (model, _) = await rig()
        await model.update(position: .seconds(570), isPlaying: true, now: .zero)
        XCTAssertEqual(model.countdownSeconds, 10)
        model.cancelNext()
        await model.update(position: .seconds(599), isPlaying: true, now: .seconds(20))
        XCTAssertNil(model.countdownSeconds)
        XCTAssertTrue(played.isEmpty)
        XCTAssertEqual(model.returnFocusItemID, featureNext)
        XCTAssertEqual(stopped, 0)
    }

    func testAutoplayStopsMarksPlayedAndStartsNextOnce() async {
        let (model, client) = await rig()
        await model.update(position: .seconds(570), isPlaying: true, now: .zero)
        await model.update(position: .seconds(580), isPlaying: true, now: .seconds(10))
        for _ in 0..<100 where model.advancing { await Task.yield() }
        XCTAssertEqual(stopped, 1)
        XCTAssertEqual(played, [featureNext])
        XCTAssertEqual(completed, [featureItem])
        let calls = await client.calls
        XCTAssertEqual(calls.filter { $0.path.contains("/PlayedItems/") }.map(\.method), ["POST"])
        await model.update(position: .seconds(590), isPlaying: true, now: .seconds(20))
        XCTAssertEqual(stopped, 1)
    }

    func testAutoplayDisabledAndPausedDoNotPrompt() async {
        let (model, _) = await rig()
        model.settings.autoplay = false
        await model.update(position: .seconds(590), isPlaying: true, now: .zero)
        XCTAssertNil(model.countdownSeconds)
        model.settings.autoplay = true
        await model.update(position: .seconds(590), isPlaying: false, now: .zero)
        XCTAssertNil(model.countdownSeconds)
    }

    func testOutroCountdownWinsOverAutomaticOutroSkip() async {
        let (model, _) = await rig(
            segments: "{\"Items\":[{\"Type\":\"Outro\",\"StartTicks\":5000000000,\"EndTicks\":6000000000}]}")
        model.settings.segments[.outro] = .automatic
        await model.update(position: .seconds(500), isPlaying: true, now: .zero)
        XCTAssertEqual(model.countdownSeconds, 10)
        XCTAssertTrue(seeks.isEmpty)
    }

    func testUnknownRuntimeHasNoFallbackPromptOrScrubBar() async {
        let (model, _) = await rig(runtime: 0)
        await model.update(position: .seconds(590), isPlaying: true, now: .zero)
        model.scrub(to: .seconds(10))
        XCTAssertNil(model.countdownSeconds)
        XCTAssertNil(model.scrubPosition)
    }

    func testScrubbingPrefetchesFiveBoundedTilesAndCancelDoesNotSeek() async {
        let (model, client) = await rig()
        model.scrub(to: .seconds(80))
        for _ in 0..<100 {
            if await model.cache.count == 5 { break }
            await Task.yield()
        }
        let calls = await client.calls.filter { $0.path.contains("/Trickplay/") }
        XCTAssertEqual(calls.count, 5)
        XCTAssertTrue(calls.allSatisfy { $0.maximumResponseBytes == MetadataPolicy.imageMaxBytes })
        XCTAssertEqual(model.previewBytes, Data([1, 2, 3]))
        await model.endScrubbing(commit: false)
        XCTAssertNil(model.scrubPosition)
        XCTAssertTrue(seeks.isEmpty)
        model.scrub(to: .seconds(90))
        await model.endScrubbing(commit: true)
        XCTAssertEqual(seeks, [.seconds(90)])
        await model.shutdown()
        let count = await model.cache.count
        XCTAssertEqual(count, 0)
    }

    func testHandoffOrderingAndManualPlayIsConsumedOnce() async {
        let recorder = FeatureEventRecorder()
        let client = PoCAPIClient { request throws(APIError) in
            if request.path.contains("/PlayedItems/") {
                await recorder.append("played")
                return Data()
            }
            if request.path.hasPrefix("/Shows/") { return Data(episodesJSON.utf8) }
            if request.path.hasPrefix("/MediaSegments/") { return Data("{\"Items\":[]}".utf8) }
            return Data("{\"Type\":\"Episode\",\"SeriesId\":\"\(featureSeries)\"}".utf8)
        }
        let model = PlaybackCompanion(
            client: client, userID: featureUser, seek: { _ in },
            stop: { await recorder.append("stopped") },
            play: { _ in await recorder.append("next") }, unauthorized: {},
            completed: { _, _ in await recorder.append("store") })
        await model.load(itemID: featureItem, mediaSourceID: featureSource)
        model.playNext()
        for _ in 0..<500 where model.advancing { await Task.yield() }
        model.playNext()
        let events = await recorder.values
        XCTAssertEqual(events, ["stopped", "played", "store", "next"])
    }

    func testOldMetadataCannotReplaceNewEpisodeAfterSuspension() async {
        let gate = FeatureGate()
        let client = PoCAPIClient { request throws(APIError) in
            if request.path == "/Users/\(featureUser)/Items/\(featureItem)" {
                await gate.wait()
                return Data("{\"RunTimeTicks\":100000000}".utf8)
            }
            if request.path.hasPrefix("/MediaSegments/") { return Data("{\"Items\":[]}".utf8) }
            return Data("{\"RunTimeTicks\":400000000}".utf8)
        }
        let model = PlaybackCompanion(
            client: client, userID: featureUser, seek: { _ in }, stop: {}, play: { _ in }, unauthorized: {})
        let old = Task { await model.load(itemID: featureItem, mediaSourceID: featureSource) }
        for _ in 0..<500 {
            if await gate.waiting { break }
            await Task.yield()
        }
        await model.load(itemID: featureNext, mediaSourceID: featureSource)
        await gate.release()
        await old.value
        XCTAssertEqual(model.runtime, .seconds(40))
        let calls = await client.calls
        XCTAssertFalse(calls.contains { $0.path == "/MediaSegments/\(featureItem)" })
    }

    func testUnknownSegmentKindsAndInvalidIntervalsAreIgnored() async {
        let (model, _) = await rig(
            segments: """
                {"Items":[{"Type":"Plugin","StartTicks":0,"EndTicks":1500000000},
                {"Type":"Intro","StartTicks":-1,"EndTicks":1500000000},
                {"Type":"Recap","StartTicks":600000000,"EndTicks":1500000000}]}
                """)
        await model.update(position: .seconds(60), isPlaying: true, now: .zero)
        XCTAssertEqual(model.segment?.kind, .recap)
    }

    func testInvalidItemOrSourceSendsNoRequests() async {
        let (model, client) = await rig()
        let before = await client.calls.count
        await model.load(itemID: "../invalid", mediaSourceID: featureSource)
        await model.load(itemID: featureItem, mediaSourceID: "../invalid")
        let after = await client.calls.count
        XCTAssertEqual(after, before)
        XCTAssertNil(model.next)
    }

    func testEpisodeRequestIsBoundedAndExcludesMissingEpisodes() async {
        let (_, client) = await rig()
        let calls = await client.calls
        let request = calls.first { $0.path == "/Shows/\(featureSeries)/Episodes" }
        XCTAssertEqual(request?.maximumResponseBytes, 1_048_576)
        XCTAssertEqual(request?.query.first { $0.name == "startItemId" }?.value, featureItem)
        XCTAssertEqual(request?.query.first { $0.name == "limit" }?.value, "2")
        XCTAssertEqual(request?.query.first { $0.name == "isMissing" }?.value, "false")
    }
}

private actor FeatureEventRecorder {
    var values: [String] = []
    func append(_ value: String) { values.append(value) }
}

private actor FeatureGate {
    private var continuation: CheckedContinuation<Void, Never>?
    var waiting: Bool { continuation != nil }
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private let featureItem = "11111111111111111111111111111111"
private let featureNext = "22222222222222222222222222222222"
private let featureSeries = "33333333333333333333333333333333"
private let featureSource = "44444444444444444444444444444444"
private let featureUser = "55555555555555555555555555555555"
private let trickplayJSON =
    "{\"Width\":320,\"Height\":180,\"TileWidth\":5,\"TileHeight\":4,\"ThumbnailCount\":101,\"Interval\":2000}"
private let episodesJSON = """
    {"Items":[{"Id":"\(featureItem)","Type":"Episode","SeriesId":"\(featureSeries)","IndexNumber":10,"ParentIndexNumber":1},
    {"Id":"\(featureNext)","Type":"Episode","SeriesId":"\(featureSeries)","Name":"Next <b>episode</b>","IndexNumber":1,"ParentIndexNumber":2}]}
    """
private func episodes() throws -> [BaseItemDTO] {
    try JSONDecoder().decode(QueryResultDTO.self, from: Data(episodesJSON.utf8)).Items ?? []
}
