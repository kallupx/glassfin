import CoreModels
import CoreNetworking
import CoreState
import CoreTestSupport
import Foundation
import GlassfinServices
import XCTest

final class T07DetailTests: XCTestCase {
    /// T07-68: forbidden actions roll back optimistic state and keep the signed-in session.
    @MainActor
    func testT07_68_forbiddenActionRollsBackAndUsesTheCatalogKey() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let gate = T07GatedClient(error: .forbidden)
        let actions = LibraryUserActions(service: JellyfinLibraryService(client: gate), app: rig.app)
        let item = Sample.movie()
        let edit = Task { await actions.togglePlayed(item) }
        await gate.waitForRequest()
        XCTAssertTrue(actions.visible(item).userData.played)
        await gate.release()
        await edit.value
        XCTAssertFalse(actions.visible(item).userData.played)
        XCTAssertEqual(actions.lastError.flatMap(AppErrorMessage.messageKey), AppErrorMessage.forbiddenKey)
        guard case .signedIn = rig.app.phase else { return XCTFail("Forbidden action signed out") }
        XCTAssertNil(rig.app.sessionNoticeKey)
    }

    /// T07-63: movie detail retains its content and the shared server-unreachable banner.
    @MainActor
    func testT07_63_movieDetailRetainsContentWhenTheServerBecomesUnreachable() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let fixture = LibraryFixtureClient()
        let client = MockAPIClient { request async throws(APIError) -> Data in try await fixture.send(request) }
        let model = ItemDetailViewModel(library: JellyfinLibraryService(client: client), app: rig.app)
        await model.load(id: LibraryFixtureClient.id(100))
        let previous = try XCTUnwrap(model.state.value)
        await client.setHandler { _ async throws(APIError) -> Data in throw .network }
        await model.load(id: previous.id)
        XCTAssertEqual(model.state.value, previous)
        XCTAssertEqual(model.state.presentedError.flatMap(AppErrorMessage.messageKey), AppErrorMessage.serverDownKey)
        XCTAssertEqual(rig.app.connectivity, .serverUnreachable)
        XCTAssertEqual(rig.app.bannerKey, AppErrorMessage.serverDownKey)
    }

    /// T07-64: no detail content means the same key is used by the blocking error component.
    @MainActor
    func testT07_64_emptyDetailUsesTheSharedServerDownKey() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let client = MockAPIClient { _ async throws(APIError) -> Data in throw .network }
        let model = ItemDetailViewModel(library: JellyfinLibraryService(client: client), app: rig.app)
        await model.load(id: Sample.movie)
        XCTAssertNil(model.state.value)
        XCTAssertEqual(model.state.presentedError.flatMap(AppErrorMessage.messageKey), AppErrorMessage.serverDownKey)
    }

    /// T07-43: Q7-25 also requires a picker for a single-season series.
    @MainActor
    func testT07_43_singleSeasonKeepsPickerVisibleAndItsEpisodesSelected() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let model = series(rig, scenario: "series-single-season")
        XCTAssertFalse(model.showsSeasonPicker)
        await model.load(seriesID: LibraryFixtureClient.series)
        XCTAssertTrue(model.showsSeasonPicker)
        XCTAssertEqual(model.seasons.value?.map(\.id), [LibraryFixtureClient.seasonOne])
        XCTAssertEqual(model.selectedSeasonID, LibraryFixtureClient.seasonOne)
        XCTAssertEqual(model.episodes.value?.count, 2)
        XCTAssertEqual(Set(model.episodes.value?.compactMap(\.seasonID) ?? []), [LibraryFixtureClient.seasonOne])
        model.moveDownFromSeason()
        XCTAssertEqual(model.focus, .episode(LibraryFixtureClient.episodeID(season: 1, episode: 1)))
        model.moveUpFromEpisodes()
        XCTAssertEqual(model.focus, .season(LibraryFixtureClient.seasonOne))
    }

    /// T07-43: an empty series has no season to select and no empty glass picker.
    @MainActor
    func testT07_43_noSeasonsHidesPicker() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let model = SeriesViewModel(library: rig.library, userData: rig.app.userData, app: rig.app)
        await model.load(seriesID: Sample.other)
        XCTAssertFalse(model.showsSeasonPicker)
        XCTAssertTrue(model.episodes.value?.isEmpty == true)
    }

    /// T07-44/T07-48/T07-49/T07-50: replace the row, retain picker focus, then navigate the short season.
    @MainActor
    func testT07_44_twoSeasonsReplaceEpisodesAndKeepFocusInTheSelectedSeason() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let fixture = LibraryFixtureClient(scenario: "series-two-seasons")
        let client = MockAPIClient { request async throws(APIError) -> Data in try await fixture.send(request) }
        let model = SeriesViewModel(
            library: JellyfinLibraryService(client: client), userData: rig.app.userData, app: rig.app)
        await model.load(seriesID: LibraryFixtureClient.series)
        let firstEpisodes = try XCTUnwrap(model.episodes.value)
        XCTAssertEqual(firstEpisodes.count, 2)
        XCTAssertEqual(
            model.seasons.value?.map(\.id), [LibraryFixtureClient.seasonOne, LibraryFixtureClient.seasonTwo])
        model.focusSeason(LibraryFixtureClient.seasonTwo)
        await model.select(seasonID: LibraryFixtureClient.seasonTwo)
        let shortEpisode = LibraryFixtureClient.episodeID(season: 2, episode: 1)
        XCTAssertEqual(model.episodes.value?.map(\.id), [shortEpisode])
        XCTAssertEqual(model.episodes.value?.first?.seasonID, LibraryFixtureClient.seasonTwo)
        XCTAssertEqual(model.episodes.value?.first?.runtime, .seconds(2))
        XCTAssertEqual(model.focus, .season(LibraryFixtureClient.seasonTwo))
        model.moveDownFromSeason()
        XCTAssertEqual(model.focus, .episode(shortEpisode))
        model.moveUpFromEpisodes()
        XCTAssertEqual(model.focus, .season(LibraryFixtureClient.seasonTwo))
        model.focusSeason(LibraryFixtureClient.seasonOne)
        await model.select(seasonID: LibraryFixtureClient.seasonOne)
        XCTAssertEqual(model.episodes.value, firstEpisodes)
        XCTAssertEqual(model.focus, .season(LibraryFixtureClient.seasonOne))
        let calls = await client.calls.filter { $0.path.hasSuffix("/Episodes") }
        XCTAssertEqual(
            calls.compactMap { $0.query.first { $0.name == "seasonId" }?.value },
            [LibraryFixtureClient.seasonOne, LibraryFixtureClient.seasonTwo])
        model.onDisappear()
    }

    /// T07-51: the last short episode remains a valid return target when no later season exists.
    @MainActor
    func testT07_51_shortFinalSeasonReturnsToItsOnlyEpisode() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let model = series(rig, scenario: "series-two-seasons")
        await model.load(seriesID: LibraryFixtureClient.series)
        await model.select(seasonID: LibraryFixtureClient.seasonTwo)
        let episode = LibraryFixtureClient.episodeID(season: 2, episode: 1)
        model.focusEpisode(episode)
        await model.returnedFromPlayback(itemID: episode, finished: false)
        XCTAssertEqual(model.focus, .episode(episode))
        await rig.app.userData.recordPlayback(id: episode, position: .seconds(2), played: true, log: SilentLog())
        await model.returnedFromPlayback(itemID: episode, finished: true)
        XCTAssertEqual(model.selectedSeasonID, LibraryFixtureClient.seasonTwo)
        XCTAssertEqual(model.focus, .episode(episode))
        XCTAssertEqual(model.episodes.value?.first?.userData.played, true)
        model.moveUpFromEpisodes()
        XCTAssertEqual(model.focus, .season(LibraryFixtureClient.seasonTwo))
    }

    /// T07-42/T07-43: five seasons; only the selected season's episodes are requested and displayed.
    @MainActor
    func testT07_43_fiveSeasonsFetchAndShowOnlyTheSelectedSeason() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let client = T07SeasonClient()
        let model = SeriesViewModel(
            library: JellyfinLibraryService(client: client), userData: rig.app.userData, app: rig.app)
        await model.load(seriesID: LibraryFixtureClient.series)
        XCTAssertEqual(model.seasons.value?.count, 5)
        XCTAssertEqual(model.selectedSeasonID, LibraryFixtureClient.seasonTwo)
        XCTAssertEqual(Set(model.episodes.value?.compactMap(\.seasonID) ?? []), [LibraryFixtureClient.seasonTwo])
        let initial = await client.requests
        let episodes = initial.filter { $0.path.hasSuffix("/Episodes") }
        XCTAssertEqual(episodes.count, 1)
        XCTAssertEqual(episodes.first?.query.first { $0.name == "seasonId" }?.value, LibraryFixtureClient.seasonTwo)
        XCTAssertEqual(episodes.first?.query.first { $0.name == "fields" }?.value, "Overview,PrimaryImageAspectRatio")
        XCTAssertEqual(episodes.first?.query.first { $0.name == "enableUserData" }?.value, "true")
        let next = try XCTUnwrap(initial.first { $0.path == "/Shows/NextUp" })
        XCTAssertEqual(next.query.first { $0.name == "seriesId" }?.value, LibraryFixtureClient.series)
        XCTAssertEqual(next.query.first { $0.name == "enableResumable" }?.value, "true")
        let fifth = LibraryFixtureClient.id(2005)
        await model.select(seasonID: fifth)
        XCTAssertEqual(Set(model.episodes.value?.compactMap(\.seasonID) ?? []), [fifth])
        let final = await client.requests.filter { $0.path.hasSuffix("/Episodes") }
        XCTAssertEqual(
            final.compactMap { $0.query.first { $0.name == "seasonId" }?.value },
            [LibraryFixtureClient.seasonTwo, fifth])
    }

    /// T07-44: switching cancels an in-flight request; completed rows are cached for this view.
    @MainActor
    func testT07_44_switchingSeasonCancelsPreviousRequestAndReusesCachedRows() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let client = T07SeasonClient(blockSeasonOne: true)
        let model = SeriesViewModel(
            library: JellyfinLibraryService(client: client), userData: rig.app.userData, app: rig.app)
        await model.load(seriesID: LibraryFixtureClient.series)
        let first = Task { await model.select(seasonID: LibraryFixtureClient.seasonOne) }
        await client.waitForBlockedRequest()
        await model.select(seasonID: LibraryFixtureClient.id(2003))
        await first.value
        let cancelled = await client.cancelledSeasonIDs
        XCTAssertEqual(cancelled, [LibraryFixtureClient.seasonOne])
        XCTAssertEqual(model.selectedSeasonID, LibraryFixtureClient.id(2003))
        XCTAssertEqual(Set(model.episodes.value?.compactMap(\.seasonID) ?? []), [LibraryFixtureClient.id(2003)])
        await model.select(seasonID: LibraryFixtureClient.seasonTwo)
        let calls = await client.requests.filter { $0.path.hasSuffix("/Episodes") }
        XCTAssertEqual(calls.count, 3)
        XCTAssertEqual(model.selectedSeasonID, LibraryFixtureClient.seasonTwo)
        XCTAssertEqual(Set(model.episodes.value?.compactMap(\.seasonID) ?? []), [LibraryFixtureClient.seasonTwo])
    }

    /// T07-45: canonical spec/TESTPLAN-M07.md.
    @MainActor
    func testT07_45_seriesOpensAtInProgressSeasonTwoEpisodeFiveAndSpecialsLast() async throws {
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

    /// T07-50: canonical spec/TESTPLAN-M07.md.
    @MainActor
    func testT07_50_seasonFocusDebouncesAndLatestSelectionWinsWithoutMovingToEpisodes() async throws {
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

    /// T07-48: canonical spec/TESTPLAN-M07.md.
    @MainActor
    func testT07_48_downTargetsFirstUnplayedAndUpReturnsToSelectedSeason() async throws {
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

    /// T07-51: canonical spec/TESTPLAN-M07.md.
    @MainActor
    func testT07_51_playbackReturnKeepsEpisodeOrAdvancesToNextUnplayed() async throws {
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

    /// T07-51: canonical spec/TESTPLAN-M07.md.
    @MainActor
    func testT07_51_finishedLastEpisodeCanAdvanceToTheNextSeason() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let model = series(rig)
        await model.load(seriesID: LibraryFixtureClient.series, seasonID: LibraryFixtureClient.seasonOne)
        XCTAssertEqual(model.playTarget?.seasonID, LibraryFixtureClient.seasonOne)
        await model.returnedFromPlayback(itemID: LibraryFixtureClient.episodeID(season: 1, episode: 8), finished: true)
        XCTAssertEqual(model.selectedSeasonID, LibraryFixtureClient.seasonTwo)
        XCTAssertEqual(model.focus, .episode(LibraryFixtureClient.episodeID(season: 2, episode: 5)))
    }

    /// T07-52: canonical spec/TESTPLAN-M07.md.
    @MainActor
    func testT07_52_selectedOverviewFollowsFocusedEpisodeAsLiteralText() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let model = series(rig)
        await model.load(seriesID: LibraryFixtureClient.series)
        model.focusEpisode(LibraryFixtureClient.episodeID(season: 2, episode: 6))
        XCTAssertEqual(model.selectedOverview, "Overview 2-6")
    }

    /// T07-63: canonical spec/TESTPLAN-M07.md.
    @MainActor
    func testT07_63_episodeFailureKeepsPreviousSeasonAndContent() async throws {
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
        XCTAssertEqual(rig.app.bannerKey, AppErrorMessage.serverDownKey)
    }

    /// T07-27: canonical spec/TESTPLAN-M07.md.
    @MainActor
    func testT07_27_playedIsOptimisticAndFailureRollsBackAndShowsAKey() async throws {
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
        XCTAssertEqual(actions.lastError.flatMap(AppErrorMessage.messageKey), AppErrorMessage.serverErrorKey)
        let stored = await rig.app.userData.state(for: item.id)
        XCTAssertEqual(stored?.played, false)
        let requests = await gate.requests
        XCTAssertEqual(requests.first?.path, "/UserPlayedItems/\(item.id)")
        XCTAssertEqual(requests.first?.method, "POST")
    }

    /// T07-28: canonical spec/TESTPLAN-M07.md.
    @MainActor
    func testT07_28_favoriteAndPlayedTogglesUsePOSTAndDELETE() async throws {
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

    /// T07-21: canonical spec/TESTPLAN-M07.md.
    @MainActor
    func testT07_21_movieSeriesSeasonAndEpisodeDetailRequests() async throws {
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

    /// T07-09: canonical spec/TESTPLAN-M07.md.
    @MainActor
    func testT07_09_staleQueryResponseCannotReplaceNewQuery() async throws {
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

    /// T07-29: canonical spec/TESTPLAN-M07.md.
    @MainActor
    func testT07_29_storeRefreshAndReloadPreserveEpisodeFocusAndSeason() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let model = series(rig)
        await model.load(seriesID: LibraryFixtureClient.series)
        let id = LibraryFixtureClient.episodeID(season: 2, episode: 6)
        model.focusEpisode(id)
        await rig.app.userData.applyRemote(
            UserDataChange(itemID: id, played: true, positionTicks: 0, isFavorite: true), log: SilentLog())
        await model.refreshFromStore()
        XCTAssertEqual(model.episodes.value?.first(where: { $0.id == id })?.userData.isFavorite, true)
        await model.load(seriesID: LibraryFixtureClient.series)
        XCTAssertEqual(model.focus, .episode(id))
        XCTAssertEqual(model.focusedEpisodeID, id)
        XCTAssertEqual(model.selectedSeasonID, LibraryFixtureClient.seasonTwo)
    }

    @MainActor
    private func series(
        _ rig: Harness, clock: any GlassfinClock = SystemGlassfinClock(), scenario: String = "grid"
    ) -> SeriesViewModel {
        SeriesViewModel(
            library: JellyfinLibraryService(client: LibraryFixtureClient(scenario: scenario)),
            userData: rig.app.userData, app: rig.app,
            clock: clock)
    }
}

private actor T07SeasonClient: JellyfinAPIClient {
    private let fixture = LibraryFixtureClient()
    private let blockSeasonOne: Bool
    private var blocked = false
    private var observers: [CheckedContinuation<Void, Never>] = []
    var requests: [APIRequest] = []
    var cancelledSeasonIDs: [String] = []

    init(blockSeasonOne: Bool = false) { self.blockSeasonOne = blockSeasonOne }

    func send(_ request: APIRequest) async throws(APIError) -> Data {
        requests.append(request)
        if request.path.hasSuffix("/Seasons") {
            let seasons = (1...5).map {
                ["Id": LibraryFixtureClient.id(2000 + $0), "Type": "Season", "IndexNumber": $0] as [String: Any]
            }
            return (try? JSONSerialization.data(withJSONObject: ["Items": seasons, "TotalRecordCount": 5])) ?? Data()
        }
        if request.path.hasSuffix("/Episodes") {
            guard let season = request.query.first(where: { $0.name == "seasonId" })?.value else {
                throw .decoding
            }
            if blockSeasonOne, season == LibraryFixtureClient.seasonOne {
                blocked = true
                for observer in observers { observer.resume() }
                observers.removeAll()
                do { try await Task.sleep(for: .seconds(60)) } catch {
                    cancelledSeasonIDs.append(season)
                    throw .cancelled
                }
            }
        }
        return try await fixture.send(request)
    }

    func waitForBlockedRequest() async {
        if blocked { return }
        await withCheckedContinuation { observers.append($0) }
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
        for observer in observers { observer.resume() }
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
        for waiter in current { waiter.resume() }
    }
}
