import CoreModels
import CoreNetworking
import CoreState
import CoreTestSupport
import Foundation
import GlassfinServices
import XCTest

final class T07ScreenLifecycleTests: XCTestCase {
    /// Extra regression: screen entry selects the exact instance without starting a request.
    @MainActor
    func testOnAppearRegistersEachFeatureViewModel() async {
        let rig = Harness.make()
        defer { rig.cleanup() }
        let home = rig.home()
        let grid = browser(rig)
        let series = SeriesViewModel(library: rig.library, userData: rig.app.userData, app: rig.app)
        let detail = ItemDetailViewModel(library: rig.library, app: rig.app)
        home.onAppear()
        XCTAssertTrue(rig.app.currentView === home)
        grid.onAppear()
        XCTAssertTrue(rig.app.currentView === grid)
        detail.onAppear()
        XCTAssertTrue(rig.app.currentView === detail)
        series.onAppear()
        XCTAssertTrue(rig.app.currentView === series)
        home.onAppear()
        XCTAssertTrue(rig.app.currentView === home)
        XCTAssertFalse(series.hasContent)
        XCTAssertFalse(home.hasContent)
        XCTAssertFalse(grid.hasContent)
        XCTAssertFalse(detail.hasContent)
        XCTAssertEqual(rig.library.resumeCallCount(), 0)
        XCTAssertEqual(rig.library.itemCallCount(), 0)
    }

    /// T02-35a: each Home section can retain content when returning without a reload.
    @MainActor
    func testT02_35a_returningToHomeKeepsBannerWithContent() async throws {
        for section in 0..<3 {
            let rig = Harness.make()
            defer { rig.cleanup() }
            try rig.signIn()
            let items = [Sample.movie()]
            rig.library.resumeItems = section == 0 ? items : []
            rig.library.nextItems = section == 1 ? items : []
            rig.library.latestByID[Sample.library] = .success(section == 2 ? items : [])
            let model = rig.home()
            await model.reload(libraryIDs: [Sample.library])
            await assertReturningContent(model, onAppear: model.onAppear, rig: rig)
            // Retained previous values during a failed reload also count as displayable content.
            rig.app.snapshots.purge()
            await rig.app.responses.invalidateAll()
            rig.library.resumeError = .network
            rig.library.nextError = .network
            rig.library.latestByID[Sample.library] = .failure(.network)
            await model.reload(libraryIDs: [Sample.library])
            await assertReturningContent(model, onAppear: model.onAppear, rig: rig)
            let sections = [model.resume.value, model.nextUp.value, model.latest.value]
            XCTAssertEqual(sections[section], items)
            XCTAssertEqual(rig.library.resumeCallCount(), 2)
            XCTAssertEqual(rig.library.nextCallCount(), 2)
            XCTAssertEqual(rig.library.latestIdentifiers(), [Sample.library, Sample.library])
        }
    }

    /// T07-63: a retained grid becomes the current screen again after navigation or a tab switch.
    @MainActor
    func testT07_63_returningToLibraryKeepsBannerWithContent() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let items = [Sample.movie()]
        rig.library.pages[0] = Page(items: items, totalCount: 1)
        let model = browser(rig)
        await model.reload(libraryID: Sample.library)
        await assertReturningContent(model, onAppear: model.onAppear, rig: rig)
        rig.library.error = .network
        await model.reload(libraryID: Sample.library, force: true)
        await assertReturningContent(model, onAppear: model.onAppear, rig: rig)
        XCTAssertEqual(model.state, .failed(.serverUnreachable, previous: items))
        XCTAssertEqual(rig.library.itemCallCount(), 2)
    }

    /// T07-63: movie, series, season and episode heroes remain displayable on return.
    @MainActor
    func testT07_63_returningToDetailKeepsBannerWithContent() async throws {
        for id in [100, 1000, 2001, 30101] {
            let rig = Harness.make()
            defer { rig.cleanup() }
            try rig.signIn()
            let fixture = LibraryFixtureClient()
            let client = MockAPIClient { request async throws(APIError) -> Data in try await fixture.send(request) }
            let model = ItemDetailViewModel(library: JellyfinLibraryService(client: client), app: rig.app)
            await model.load(id: LibraryFixtureClient.id(id))
            let previous = try XCTUnwrap(model.state.value)
            let loadedCalls = await client.calls.count
            await assertReturningContent(model, onAppear: model.onAppear, rig: rig)
            let returnedCalls = await client.calls.count
            XCTAssertEqual(returnedCalls, loadedCalls)
            await client.setHandler { _ async throws(APIError) -> Data in throw .network }
            await model.load(id: previous.id)
            await assertReturningContent(model, onAppear: model.onAppear, rig: rig)
            XCTAssertEqual(model.state, .failed(.serverUnreachable, previous: previous))
            let failedCalls = await client.calls.count
            XCTAssertEqual(failedCalls, loadedCalls + 1)
        }
    }

    /// T02-35b: loaded empty Home sections cannot suppress the full-screen state.
    @MainActor
    func testT02_35b_returningToEmptyHomeShowsFullScreen() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let retained = browser(rig)
        rig.library.pages[0] = Page(items: [Sample.movie()], totalCount: 1)
        await retained.reload(libraryID: Sample.library)
        let model = rig.home()
        await model.reload(libraryIDs: [])
        retained.onAppear()
        rig.app.handle(.serverUnreachable)
        XCTAssertFalse(rig.app.showsServerDown)
        model.onAppear()
        assertEmptyScreen(model, app: rig.app)
    }

    /// T07-64: an empty library stays blocking even while a populated Home is kept alive.
    @MainActor
    func testT07_64_returningToEmptyLibraryShowsFullScreen() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let retained = rig.home()
        rig.library.resumeItems = [Sample.movie()]
        await retained.reload(libraryIDs: [])
        let model = browser(rig)
        await model.reload(libraryID: Sample.library)
        retained.onAppear()
        rig.app.handle(.serverUnreachable)
        XCTAssertFalse(rig.app.showsServerDown)
        model.onAppear()
        assertEmptyScreen(model, app: rig.app)
    }

    /// T07-64: a failed first detail request has no content even with a retained Home.
    @MainActor
    func testT07_64_returningToEmptyDetailShowsFullScreen() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let retained = rig.home()
        rig.library.resumeItems = [Sample.movie()]
        await retained.reload(libraryIDs: [])
        let client = MockAPIClient { _ async throws(APIError) -> Data in throw .network }
        let model = ItemDetailViewModel(library: JellyfinLibraryService(client: client), app: rig.app)
        await model.load(id: Sample.movie)
        retained.onAppear()
        XCTAssertFalse(rig.app.showsServerDown)
        model.onAppear()
        assertEmptyScreen(model, app: rig.app)
        XCTAssertEqual(model.state, .failed(.serverUnreachable, previous: nil))
    }

    /// T07-63: standalone series hosts can also restore their retained seasons and episodes.
    @MainActor
    func testT07_63_returningToSeriesKeepsBannerWithContent() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        rig.library.seasons = [Sample.movie(id: Sample.season)]
        rig.library.episodes = [Sample.movie()]
        let model = SeriesViewModel(library: rig.library, userData: rig.app.userData, app: rig.app)
        model.onAppear()
        await model.load(seriesID: Sample.other)
        await assertReturningContent(model, onAppear: model.onAppear, rig: rig)
        rig.library.seasonError = .network
        await model.load(seriesID: Sample.other)
        await assertReturningContent(model, onAppear: model.onAppear, rig: rig)
        XCTAssertEqual(model.seasons.value, rig.library.seasons)
        XCTAssertEqual(model.episodes.value, rig.library.episodes)
    }

    /// T07-64: a standalone series without seasons or episodes has no displayable content.
    @MainActor
    func testT07_64_returningToEmptySeriesShowsFullScreen() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let model = SeriesViewModel(library: rig.library, userData: rig.app.userData, app: rig.app)
        await model.load(seriesID: Sample.other)
        let retained = ItemDetailViewModel(library: rig.library, app: rig.app)
        await retained.load(id: Sample.movie)
        rig.app.handle(.serverUnreachable)
        XCTAssertFalse(rig.app.showsServerDown)
        model.onAppear()
        assertEmptyScreen(model, app: rig.app)
    }

    /// T07-63: empty or failed episode sections must not hide a loaded series hero.
    @MainActor
    func testT07_63_seriesSectionDoesNotReplaceDetailContentProvider() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let model = ItemDetailViewModel(library: JellyfinLibraryService(client: LibraryFixtureClient()), app: rig.app)
        await model.load(id: LibraryFixtureClient.series)
        let section = SeriesViewModel(library: rig.library, userData: rig.app.userData, app: rig.app)
        await section.load(seriesID: LibraryFixtureClient.series)
        XCTAssertFalse(section.hasContent)
        rig.library.seasonError = .network
        await section.load(seriesID: LibraryFixtureClient.series)
        XCTAssertEqual(rig.app.connectivity, .serverUnreachable)
        XCTAssertTrue(rig.app.currentView === model)
        XCTAssertTrue(model.hasContent)
        XCTAssertFalse(rig.app.showsServerDown)
        XCTAssertEqual(rig.app.bannerKey, AppErrorMessage.serverDownKey)
    }

    @MainActor
    private func browser(_ rig: Harness) -> LibraryViewModel {
        LibraryViewModel(
            library: rig.library, userData: rig.app.userData, responses: rig.app.responses,
            app: rig.app, clock: rig.clock)
    }

    @MainActor
    private func assertReturningContent(
        _ model: any ViewContentProviding, onAppear: () -> Void, rig: Harness,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        let other = ItemDetailViewModel(library: rig.library, app: rig.app)
        for outageBeforeReturn in [false, true] {
            await rig.app.probeServer()
            onAppear()
            XCTAssertTrue(rig.app.currentView === model, file: file, line: line)
            other.onAppear()
            XCTAssertTrue(rig.app.currentView === other, file: file, line: line)
            if outageBeforeReturn {
                rig.app.handle(.serverUnreachable)
                XCTAssertTrue(rig.app.showsServerDown, file: file, line: line)
            }
            onAppear()
            if !outageBeforeReturn { rig.app.handle(.serverUnreachable) }
            XCTAssertTrue(rig.app.currentView === model, file: file, line: line)
            XCTAssertTrue(model.hasContent, file: file, line: line)
            XCTAssertEqual(rig.app.connectivity, .serverUnreachable, file: file, line: line)
            XCTAssertEqual(rig.app.bannerKey, AppErrorMessage.serverDownKey, file: file, line: line)
            XCTAssertEqual(
                rig.app.banner, AppErrorMessage.localized(AppErrorMessage.serverDownKey), file: file, line: line)
            XCTAssertFalse(rig.app.showsServerDown, file: file, line: line)
        }
    }

    @MainActor
    private func assertEmptyScreen(
        _ model: any ViewContentProviding, app: AppState, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(app.currentView === model, file: file, line: line)
        XCTAssertFalse(model.hasContent, file: file, line: line)
        XCTAssertEqual(app.connectivity, .serverUnreachable, file: file, line: line)
        XCTAssertTrue(app.showsServerDown, file: file, line: line)
        XCTAssertEqual(app.serverDownTitleKey, AppErrorMessage.serverDownKey, file: file, line: line)
        XCTAssertEqual(app.retryTitleKey, AppErrorMessage.retryKey, file: file, line: line)
        XCTAssertEqual(app.changeServerTitleKey, AppErrorMessage.changeServerKey, file: file, line: line)
    }
}
