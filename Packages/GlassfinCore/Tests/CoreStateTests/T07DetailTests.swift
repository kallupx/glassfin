import CoreModels
import CoreNetworking
import CoreState
import CoreTestSupport
import Foundation
import GlassfinServices
import XCTest

@MainActor
final class T07DetailTests: XCTestCase {
    func testT07_06_seriesOpensAtInProgressSeasonTwoEpisodeFiveAndSpecialsLast() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let model = series(rig)
        await model.load(seriesID: LibraryFixtureClient.series)
        XCTAssertEqual(model.selectedSeasonID, LibraryFixtureClient.seasonTwo)
        XCTAssertEqual(model.playTarget?.id, LibraryFixtureClient.episodeID(season: 2, episode: 5))
        XCTAssertEqual(model.initialEpisodeID, model.playTarget?.id)
        XCTAssertEqual(model.focus, .play)
        XCTAssertEqual(model.seasons.value?.last?.indexNumber, 0)
        XCTAssertEqual(model.episodes.value?.count, 8)
    }

    func testT07_07_seasonFocusDebouncesAndLatestSelectionWinsWithoutMovingToEpisodes() async throws {
        let rig = Harness.make(suspendingClock: true)
        defer { rig.cleanup() }
        try rig.signIn()
        let clock = try XCTUnwrap(rig.suspending)
        let model = series(rig, clock: clock)
        await model.load(seriesID: LibraryFixtureClient.series)
        model.focusSeason(LibraryFixtureClient.seasonOne)
        await clock.waitForSleeps(1)
        XCTAssertEqual(model.selectedSeasonID, LibraryFixtureClient.seasonTwo)
        XCTAssertEqual(clock.sleeps().last, SeriesViewModel.seasonDebounce)
        model.focusSeason(LibraryFixtureClient.specials)
        for _ in 0..<20 { await Task.yield() }
        clock.resumeAll()
        for _ in 0..<100 where model.selectedSeasonID != LibraryFixtureClient.specials { await Task.yield() }
        XCTAssertEqual(model.selectedSeasonID, LibraryFixtureClient.specials)
        XCTAssertEqual(model.focus, .season(LibraryFixtureClient.specials))
    }

    func testT07_08_downTargetsFirstUnplayedAndUpReturnsToSelectedSeason() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let model = series(rig)
        await model.load(seriesID: LibraryFixtureClient.series)
        model.moveDownFromSeason()
        XCTAssertEqual(model.focus, .episode(LibraryFixtureClient.episodeID(season: 2, episode: 5)))
        model.moveUpFromEpisodes()
        XCTAssertEqual(model.focus, .season(LibraryFixtureClient.seasonTwo))
        await model.select(seasonID: LibraryFixtureClient.seasonOne)
        model.moveDownFromSeason()
        XCTAssertEqual(model.focus, .episode(LibraryFixtureClient.episodeID(season: 1, episode: 1)))
    }

    func testT07_09_playbackReturnKeepsEpisodeOrAdvancesToNextUnplayed() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let model = series(rig)
        await model.load(seriesID: LibraryFixtureClient.series)
        let current = LibraryFixtureClient.episodeID(season: 2, episode: 5)
        await model.returnedFromPlayback(itemID: current, finished: false)
        XCTAssertEqual(model.focus, .episode(current))
        await rig.app.userData.recordPlayback(id: current, position: .seconds(2700), played: true, log: SilentLog())
        await model.returnedFromPlayback(itemID: current, finished: true)
        XCTAssertEqual(model.focus, .episode(LibraryFixtureClient.episodeID(season: 2, episode: 6)))
    }

    func testT07_10_selectedOverviewFollowsFocusedEpisodeAsLiteralText() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let model = series(rig)
        await model.load(seriesID: LibraryFixtureClient.series)
        model.focusEpisode(LibraryFixtureClient.episodeID(season: 2, episode: 6))
        XCTAssertEqual(model.selectedOverview, "Overview 2-6")
    }

    func testT07_11_episodeFailureKeepsPreviousSeasonAndContent() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        rig.library.seasons = [MediaItem(id: Sample.season, kind: .season, name: "Season", indexNumber: 1)]
        rig.library.episodes = [
            MediaItem(
                id: Sample.movie, kind: .episode, name: "<b>x</b>\u{202E}", overview: "Literal &amp;",
                seasonID: Sample.season)
        ]
        let model = SeriesViewModel(library: rig.library, userData: rig.app.userData, app: rig.app)
        await model.load(seriesID: Sample.other)
        let before = model.episodes.value
        rig.library.episodeError = .network
        await model.select(seasonID: Sample.library)
        XCTAssertEqual(model.episodes.value, before)
        XCTAssertEqual(model.selectedSeasonID, Sample.season)
        XCTAssertEqual(model.episodes.value?.first?.name, "<b>x</b>")
        XCTAssertEqual(rig.app.bannerKey, .serverUnreachable)
    }

    func testT07_12_playedIsOptimisticAndFailureRollsBackAndShowsAKey() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let gate = T07GatedClient(error: .server(status: 500))
        let actions = LibraryUserActions(service: JellyfinLibraryService(client: gate), app: rig.app)
        let item = Sample.movie()
        let edit = Task { await actions.togglePlayed(item) }
        await gate.waitForRequest()
        XCTAssertTrue(actions.visible(item).userData.played)
        let pending = await rig.app.userData.isPending(id: item.id)
        XCTAssertTrue(pending)
        await gate.release()
        await edit.value
        XCTAssertFalse(actions.visible(item).userData.played)
        XCTAssertEqual(actions.lastError.flatMap(AppErrorMessage.key), .serverError)
        let stored = await rig.app.userData.state(for: item.id)
        XCTAssertEqual(stored?.played, false)
        let requests = await gate.requests
        XCTAssertEqual(requests.first?.path, "/UserPlayedItems/\(item.id)")
        XCTAssertEqual(requests.first?.method, "POST")
    }

    func testT07_13_favoriteAndPlayedTogglesUsePOSTAndDELETE() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let client = MockAPIClient { _ in Data("{}".utf8) }
        let actions = LibraryUserActions(service: JellyfinLibraryService(client: client), app: rig.app)
        let item = Sample.movie()
        await actions.toggleFavorite(item)
        XCTAssertTrue(actions.visible(item).userData.isFavorite)
        await actions.toggleFavorite(item)
        await actions.togglePlayed(item)
        await actions.togglePlayed(item)
        let calls = await client.calls
        XCTAssertEqual(calls.map(\.method), ["POST", "DELETE", "POST", "DELETE"])
        XCTAssertEqual(
            calls.map(\.path),
            [
                "/UserFavoriteItems/\(item.id)", "/UserFavoriteItems/\(item.id)", "/UserPlayedItems/\(item.id)",
                "/UserPlayedItems/\(item.id)",
            ])
    }

    func testT07_14_movieSeriesSeasonAndEpisodeDetailRequests() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let service = JellyfinLibraryService(client: LibraryFixtureClient())
        for (id, kind) in [
            (LibraryFixtureClient.id(100), MediaKind.movie), (LibraryFixtureClient.series, .series),
            (LibraryFixtureClient.seasonTwo, .season),
            (LibraryFixtureClient.episodeID(season: 2, episode: 5), .episode),
        ] {
            let model = ItemDetailViewModel(library: service, app: rig.app)
            await model.load(id: id)
            XCTAssertEqual(model.state.value?.kind, kind)
        }
    }

    func testT07_28_staleQueryResponseCannotReplaceNewQuery() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let gate = T07GatedClient()
        let model = LibraryViewModel(
            library: JellyfinLibraryService(client: gate), userData: rig.app.userData, responses: rig.app.responses,
            app: rig.app, clock: rig.clock)
        let first = Task { await model.reload(libraryID: Sample.library) }
        await gate.waitForRequest()
        let second = Task { await model.reload(libraryID: Sample.other) }
        for _ in 0..<20 { await Task.yield() }
        await gate.release()
        await first.value
        await second.value
        XCTAssertEqual(model.state.value?.first?.name, Sample.other)
    }

    private func series(_ rig: Harness, clock: any GlassfinClock = SystemGlassfinClock()) -> SeriesViewModel {
        SeriesViewModel(
            library: JellyfinLibraryService(client: LibraryFixtureClient()), userData: rig.app.userData, app: rig.app,
            clock: clock)
    }
}

private actor T07GatedClient: JellyfinAPIClient {
    let error: APIError?
    var requests: [APIRequest] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var observers: [CheckedContinuation<Void, Never>] = []
    private var released = false

    init(error: APIError? = nil) { self.error = error }
    func send(_ request: APIRequest) async throws(APIError) -> Data {
        requests.append(request)
        observers.forEach { $0.resume() }
        observers.removeAll()
        if !released { await withCheckedContinuation { waiting.append($0) } }
        if let error { throw error }
        let parent = request.query.first { $0.name == "parentId" }?.value ?? Sample.movie
        return Data(
            "{\"Items\":[{\"Id\":\"\(parent)\",\"Name\":\"\(parent)\",\"Type\":\"Movie\"}],\"TotalRecordCount\":1}".utf8
        )
    }
    func waitForRequest() async {
        if !requests.isEmpty { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func release() {
        released = true
        let current = waiting
        waiting.removeAll()
        current.forEach { $0.resume() }
    }
}
