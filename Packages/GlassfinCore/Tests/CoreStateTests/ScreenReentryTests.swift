import CoreModels
import CoreState
import XCTest

final class ScreenReentryTests: XCTestCase {
    // Extra: screen-entry identity is not a separate canonical test-plan scenario.
    @MainActor
    func testHomeOnAppearSelectsCurrentView() async {
        let h = Harness.make()
        defer { h.cleanup() }
        let home = h.home()
        XCTAssertNil(h.app.currentView)
        home.onAppear()
        XCTAssertTrue(h.app.currentView === home)
        XCTAssertFalse(home.hasContent)
        XCTAssertEqual(h.library.resumeCallCount(), 0)
    }

    // Extra: the Library screen is not implemented in M06; its shared model already exists.
    @MainActor
    func testLibraryOnAppearSelectsCurrentView() async {
        let h = Harness.make()
        defer { h.cleanup() }
        let library = makeLibrary(h)
        XCTAssertNil(h.app.currentView)
        library.onAppear()
        XCTAssertTrue(h.app.currentView === library)
        XCTAssertFalse(library.hasContent)
        XCTAssertEqual(h.library.itemCallCount(), 0)
    }

    // Extra: Series is the existing detail model; M07 owns its SwiftUI destination.
    @MainActor
    func testSeriesOnAppearSelectsCurrentView() async {
        let h = Harness.make()
        defer { h.cleanup() }
        let series = makeSeries(h)
        XCTAssertNil(h.app.currentView)
        series.onAppear()
        XCTAssertTrue(h.app.currentView === series)
        XCTAssertFalse(series.hasContent)
    }

    // T06-49: re-entry selects the kept Home content before the server-down presentation decision.
    @MainActor
    func testT06_49_homeReentryKeepsContentAndShowsBanner() async throws {
        for row in ["resume", "nextUp", "latest"] {
            let h = Harness.make()
            defer { h.cleanup() }
            try h.signIn()
            let item = Sample.movie()
            if row == "resume" { h.library.resumeItems = [item] }
            if row == "nextUp" { h.library.nextItems = [item] }
            if row == "latest" {
                h.library.viewItems = [Library(id: Sample.library, name: "Library", collectionType: "movies")]
                h.library.latestByID[Sample.library] = .success([item])
            }
            let home = h.home()
            home.onAppear()
            await home.load()
            XCTAssertTrue(home.hasContent, row)
            let resume = home.resume
            let nextUp = home.nextUp
            let latest = home.latestRows.map(\.state)
            let calls = h.library.resumeCallCount()
            let other = makeLibrary(h)
            other.onAppear()
            XCTAssertTrue(h.app.currentView === other)
            home.onAppear()
            XCTAssertTrue(h.app.currentView === home)

            h.app.handle(.serverUnreachable)
            assertBanner(h.app)
            XCTAssertNil(home.serverDownTitleKey)
            // Also return after connectivity has already failed, without another load.
            other.onAppear()
            XCTAssertTrue(h.app.showsServerDown)
            home.onAppear()
            assertBanner(h.app)
            XCTAssertNil(home.serverDownTitleKey)
            XCTAssertEqual(home.resume, resume)
            XCTAssertEqual(home.nextUp, nextUp)
            XCTAssertEqual(home.latestRows.map(\.state), latest)
            XCTAssertEqual(h.library.resumeCallCount(), calls)
        }
    }

    // T06-46: idle and successfully loaded empty Home states both have nothing displayable.
    @MainActor
    func testT06_46_homeReentryWithoutContentShowsFullScreen() async throws {
        for loadEmpty in [false, true] {
            let h = Harness.make()
            defer { h.cleanup() }
            try h.signIn()
            let home = h.home()
            home.onAppear()
            if loadEmpty { await home.load() }
            h.library.pages[0] = Page(items: [Sample.movie()], totalCount: 1)
            let other = makeLibrary(h)
            await other.reload(libraryID: Sample.library)
            XCTAssertTrue(other.hasContent)
            XCTAssertTrue(h.app.currentView === other)
            home.onAppear()
            XCTAssertTrue(h.app.currentView === home)
            XCTAssertFalse(home.hasContent)

            h.app.handle(.serverUnreachable)
            assertFullScreen(h.app)
            XCTAssertEqual(home.serverDownTitleKey, h.app.serverDownTitleKey)
        }
    }

    // Extra: extends the T02-35a presentation rule to a retained Library grid model.
    @MainActor
    func testLibraryReentryKeepsContentAndShowsBanner() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        h.library.pages[0] = Page(items: [Sample.movie()], totalCount: 1)
        let library = makeLibrary(h)
        library.onAppear()
        await library.reload(libraryID: Sample.library)
        XCTAssertTrue(library.hasContent)
        let state = library.state
        let calls = h.library.itemCallCount()
        let other = makeSeries(h)
        other.onAppear()
        XCTAssertTrue(h.app.currentView === other)
        library.onAppear()
        XCTAssertTrue(h.app.currentView === library)

        h.app.handle(.serverUnreachable)
        assertBanner(h.app)
        other.onAppear()
        XCTAssertTrue(h.app.showsServerDown)
        library.onAppear()
        assertBanner(h.app)
        XCTAssertEqual(library.state, state)
        XCTAssertEqual(h.library.itemCallCount(), calls)
    }

    // Extra: extends the T02-35b presentation rule to idle and empty Library models.
    @MainActor
    func testLibraryReentryWithoutContentShowsFullScreen() async throws {
        for loadEmpty in [false, true] {
            let h = Harness.make()
            defer { h.cleanup() }
            try h.signIn()
            let library = makeLibrary(h)
            library.onAppear()
            if loadEmpty { await library.reload(libraryID: Sample.library) }
            h.library.resumeItems = [Sample.movie()]
            let other = h.home()
            await other.load()
            XCTAssertTrue(other.hasContent)
            XCTAssertTrue(h.app.currentView === other)
            library.onAppear()
            XCTAssertTrue(h.app.currentView === library)
            XCTAssertFalse(library.hasContent)

            h.app.handle(.serverUnreachable)
            assertFullScreen(h.app)
        }
    }

    // Extra: extends the T02-35a rule to Series detail content, including seasons without episodes.
    @MainActor
    func testSeriesReentryKeepsContentAndShowsBanner() async throws {
        for hasEpisodes in [false, true] {
            let h = Harness.make()
            defer { h.cleanup() }
            try h.signIn()
            h.library.seasons = [Sample.movie(id: Sample.season)]
            if hasEpisodes { h.library.episodes = [Sample.movie()] }
            let series = makeSeries(h)
            series.onAppear()
            await series.load(seriesID: Sample.other)
            XCTAssertTrue(series.hasContent)
            let seasons = series.seasons
            let episodes = series.episodes
            let other = makeLibrary(h)
            other.onAppear()
            XCTAssertTrue(h.app.currentView === other)
            series.onAppear()
            XCTAssertTrue(h.app.currentView === series)

            h.app.handle(.serverUnreachable)
            assertBanner(h.app)
            other.onAppear()
            XCTAssertTrue(h.app.showsServerDown)
            series.onAppear()
            assertBanner(h.app)
            XCTAssertEqual(series.seasons, seasons)
            XCTAssertEqual(series.episodes, episodes)
        }
    }

    // Extra: extends the T02-35b rule to idle and empty Series detail models.
    @MainActor
    func testSeriesReentryWithoutContentShowsFullScreen() async throws {
        for loadEmpty in [false, true] {
            let h = Harness.make()
            defer { h.cleanup() }
            try h.signIn()
            let series = makeSeries(h)
            series.onAppear()
            if loadEmpty { await series.load(seriesID: Sample.other) }
            h.library.resumeItems = [Sample.movie()]
            let other = h.home()
            await other.load()
            XCTAssertTrue(other.hasContent)
            XCTAssertTrue(h.app.currentView === other)
            series.onAppear()
            XCTAssertTrue(h.app.currentView === series)
            XCTAssertFalse(series.hasContent)

            h.app.handle(.serverUnreachable)
            assertFullScreen(h.app)
        }
    }

    @MainActor
    private func makeLibrary(_ h: Harness) -> LibraryViewModel {
        LibraryViewModel(
            library: h.library, userData: h.app.userData, responses: h.app.responses,
            app: h.app, clock: h.clock, log: h.log)
    }

    @MainActor
    private func makeSeries(_ h: Harness) -> SeriesViewModel {
        SeriesViewModel(library: h.library, userData: h.app.userData, app: h.app, log: h.log)
    }

    @MainActor
    private func assertBanner(_ app: AppState, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(app.connectivity, .serverUnreachable, file: file, line: line)
        XCTAssertEqual(app.bannerKey, AppErrorMessage.serverDownKey, file: file, line: line)
        XCTAssertEqual(app.banner, AppErrorMessage.localized(AppErrorMessage.serverDownKey), file: file, line: line)
        XCTAssertFalse(app.showsServerDown, file: file, line: line)
    }

    @MainActor
    private func assertFullScreen(_ app: AppState, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(app.connectivity, .serverUnreachable, file: file, line: line)
        XCTAssertTrue(app.showsServerDown, file: file, line: line)
        XCTAssertEqual(app.serverDownTitleKey, AppErrorMessage.serverDownKey, file: file, line: line)
    }
}
