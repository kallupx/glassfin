import XCTest

@MainActor
final class T07LibraryUITests: XCTestCase {
    #if os(tvOS)
        func testT07_15_detailBackRestoresTheSameGridCardAndScrollPosition() {
            let app = launch("grid")
            let first = element(app, "library.item.00000000000000000000000000000064")
            require(first)
            XCTAssertTrue(activate(first, in: app))
            require(element(app, "detail.play"))
            XCUIRemote.shared.press(.menu)
            focused(first)
            for _ in 0..<3 { XCUIRemote.shared.press(.down) }
            let current = app.buttons.matching(
                NSPredicate(format: "hasFocus == true AND identifier BEGINSWITH 'library.item.'")
            ).firstMatch
            require(current)
            let identifier = current.identifier
            let before = current.frame
            XCUIRemote.shared.press(.select)
            require(element(app, "detail.play"))
            XCUIRemote.shared.press(.menu)
            let restored = element(app, identifier)
            focused(restored)
            XCTAssertEqual(restored.frame.minY, before.minY, accuracy: 2)
            save(app, name: "T07-15-grid-restored")
        }

        func testT07_06_playIsDefaultAndInProgressEpisodeIsVisible() {
            let app = launch("series")
            let play = element(app, "detail.play")
            focused(play)
            XCTAssertEqual(play.value as? String, "detail.resumeEpisode")
            let season = element(app, "series.season.000000000000000000000000000007d2")
            require(season)
            XCTAssertTrue(season.isSelected)
            XCTAssertTrue(element(app, "series.episode.000000000000000000000000000075fd").isHittable)
            save(app, name: "T07-06-default-play")
        }

        func testT07_07_focusOnSeasonChangesRowWithoutSelectingOrLeavingPicker() {
            let app = launch("series")
            focused(element(app, "detail.play"))
            XCUIRemote.shared.press(.down)
            focused(element(app, "series.season.000000000000000000000000000007d2"))
            XCUIRemote.shared.press(.left)
            let seasonOne = element(app, "series.season.000000000000000000000000000007d1")
            focused(seasonOne)
            require(element(app, "series.episode.00000000000000000000000000007595"))
            XCTAssertTrue(seasonOne.hasFocus)
            save(app, name: "T07-07-season-focus")
        }

        func testT07_08_downFromSeasonTargetsThatSeasonsFirstUnplayedEpisode() {
            let app = launch("series")
            enterEpisodes(app)
            focused(element(app, "series.episode.000000000000000000000000000075fd"))
            save(app, name: "T07-08-first-unplayed")
        }

        func testT07_30_upFromEpisodeReturnsToSelectedSeason() {
            let app = launch("series")
            enterEpisodes(app)
            XCUIRemote.shared.press(.right)
            XCUIRemote.shared.press(.up)
            focused(element(app, "series.season.000000000000000000000000000007d2"))
            save(app, name: "T07-30-up-to-season")
        }

        func testT07_09_playbackReturnHookRestoresSameEpisode() {
            let app = launch("series-return")
            enterEpisodes(app)
            XCUIRemote.shared.press(.right)
            let episode = element(app, "series.episode.000000000000000000000000000075fe")
            focused(episode)
            XCUIRemote.shared.press(.playPause)
            focused(episode)
            save(app, name: "T07-09-return-same-episode")
        }

        func testT07_09_finishedPlaybackReturnHookMovesToNextEpisode() {
            let app = launch("series-finished")
            enterEpisodes(app)
            XCUIRemote.shared.press(.playPause)
            focused(element(app, "series.episode.000000000000000000000000000075fe"))
            save(app, name: "T07-09-return-next-episode")
        }

        func testT07_10_episodeOverviewNeverReceivesFocus() {
            let app = launch("series")
            enterEpisodes(app)
            let overview = element(app, "series.overview")
            require(overview)
            XCTAssertFalse(overview.hasFocus)
            XCUIRemote.shared.press(.down)
            XCTAssertFalse(overview.hasFocus)
            XCUIRemote.shared.press(.up)
            XCTAssertFalse(overview.hasFocus)
            save(app, name: "T07-10-overview")
        }

        func testT07_14_episodeCardNavigatesToEpisodeDetail() {
            let app = launch("series")
            enterEpisodes(app)
            XCUIRemote.shared.press(.select)
            require(element(app, "detail.root"))
            require(element(app, "detail.startOver"))
            XCTAssertFalse(element(app, "series.seasons").exists)
            save(app, name: "T07-14-episode-detail")
        }

        func testT07_18_serverDownMidBrowseKeepsCardsAndShowsBanner() {
            let app = launch("down")
            require(element(app, "library.item.00000000000000000000000000000064"))
            for _ in 0..<8 { XCUIRemote.shared.press(.down) }
            require(element(app, "library.banner"))
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.item.'")).count > 0)
            XCTAssertFalse(element(app, "design.error.root").exists)
            save(app, name: "T07-18-retained-content")
        }

        private func enterEpisodes(_ app: XCUIApplication) {
            focused(element(app, "detail.play"))
            XCUIRemote.shared.press(.down)
            focused(element(app, "series.season.000000000000000000000000000007d2"))
            XCUIRemote.shared.press(.down)
        }

        private func focused(_ element: XCUIElement) {
            require(element)
            let expectation = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hasFocus == true"), object: element)
            XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed)
        }
    #endif

    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-library", scenario, "-AppleLanguages", "(en)"]
        app.launch()
        return app
    }
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    private func require(_ element: XCUIElement) { XCTAssertTrue(element.waitForExistence(timeout: 20)) }
    private func save(_ app: XCUIApplication, name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let directory = ProcessInfo.processInfo.environment["GLASSFIN_SCREENSHOT_DIR"] else { return }
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: root.appendingPathComponent(name + ".png"))
    }
}
