import XCTest

@MainActor
final class T07LibraryUITests: XCTestCase {
    /// T07-43/T07-48/T07-49: Q7-25 keeps the single-season picker visible and reachable.
    func testT07_43_singleSeasonPickerStaysVisible() {
        let app = launch("series-single-season")
        let picker = element(app, "series.seasons")
        let season = element(app, "series.season.000000000000000000000000000007d1")
        require(picker)
        require(season)
        require(element(app, "series.episode.00000000000000000000000000007595"))
        XCTAssertTrue(season.isSelected)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'series.season.'")).count, 1)
        #if os(tvOS)
            focused(element(app, "detail.play"))
            XCUIRemote.shared.press(.down)
            focused(season)
            XCUIRemote.shared.press(.down)
            focused(element(app, "series.episode.00000000000000000000000000007595"))
            XCUIRemote.shared.press(.up)
            focused(season)
        #endif
        save(app, name: "T07-43-single-season-picker")
    }

    #if os(tvOS)
        /// T07-44/T07-50: only the selected season's row is visible, including a one-episode season.
        func testT07_44_twoSeasonPickerReplacesEpisodesAndKeepsFocus() {
            let app = launch("series-two-seasons")
            focused(element(app, "detail.play"))
            let seasonOne = element(app, "series.season.000000000000000000000000000007d1")
            let seasonTwo = element(app, "series.season.000000000000000000000000000007d2")
            let firstEpisode = element(app, "series.episode.00000000000000000000000000007595")
            let shortEpisode = element(app, "series.episode.000000000000000000000000000075f9")
            require(firstEpisode)
            XCTAssertFalse(shortEpisode.exists)
            XCUIRemote.shared.press(.down)
            focused(seasonOne)
            XCUIRemote.shared.press(.right)
            focused(seasonTwo)
            require(shortEpisode)
            XCTAssertTrue(seasonTwo.isSelected)
            XCTAssertTrue(seasonTwo.hasFocus)
            XCTAssertFalse(firstEpisode.exists)
            XCTAssertEqual(
                app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'series.episode.'")).count, 1)
            XCUIRemote.shared.press(.left)
            focused(seasonOne)
            require(firstEpisode)
            XCTAssertTrue(seasonOne.isSelected)
            XCTAssertTrue(seasonOne.hasFocus)
            XCTAssertFalse(shortEpisode.exists)
            save(app, name: "T07-44-two-season-switch")
        }

        /// T07-48/T07-49/T07-51: returning from detail keeps the short episode and its season reachable.
        func testT07_51_shortSecondSeasonEpisodeDetailReturnsToSameEpisode() {
            let app = launch("series-two-seasons")
            focused(element(app, "detail.play"))
            XCUIRemote.shared.press(.down)
            focused(element(app, "series.season.000000000000000000000000000007d1"))
            XCUIRemote.shared.press(.right)
            let season = element(app, "series.season.000000000000000000000000000007d2")
            focused(season)
            let episode = element(app, "series.episode.000000000000000000000000000075f9")
            require(episode)
            XCUIRemote.shared.press(.down)
            focused(episode)
            XCUIRemote.shared.press(.select)
            require(element(app, "detail.play"))
            let hidden = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: element(app, "series.seasons"))
            XCTAssertEqual(XCTWaiter().wait(for: [hidden], timeout: 10), .completed)
            XCUIRemote.shared.press(.menu)
            focused(episode)
            XCTAssertTrue(season.isSelected)
            XCTAssertFalse(element(app, "series.episode.00000000000000000000000000007595").exists)
            XCUIRemote.shared.press(.up)
            focused(season)
            XCUIRemote.shared.press(.down)
            focused(episode)
            save(app, name: "T07-51-short-season-detail-return")
        }

        /// T07-19: canonical spec/TESTPLAN-M07.md.
        func testT07_19_detailBackRestoresTheSameGridCardAndScrollPosition() {
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
            save(app, name: "T07-19-grid-restored")
        }

        /// T07-46: canonical spec/TESTPLAN-M07.md.

        func testT07_46_playIsDefaultAndInProgressEpisodeIsVisible() {
            let app = launch("series")
            let play = element(app, "detail.play")
            focused(play)
            XCTAssertEqual(play.value as? String, "detail.resumeEpisode")
            let season = element(app, "series.season.000000000000000000000000000007d2")
            require(season)
            XCTAssertTrue(season.isSelected)
            XCTAssertTrue(element(app, "series.episode.000000000000000000000000000075fd").isHittable)
            save(app, name: "T07-46-default-play")
        }

        /// T07-50: canonical spec/TESTPLAN-M07.md.

        func testT07_50_focusOnSeasonChangesRowWithoutSelectingOrLeavingPicker() {
            let app = launch("series")
            focused(element(app, "detail.play"))
            XCUIRemote.shared.press(.down)
            focused(element(app, "series.season.000000000000000000000000000007d2"))
            XCUIRemote.shared.press(.left)
            let seasonOne = element(app, "series.season.000000000000000000000000000007d1")
            focused(seasonOne)
            require(element(app, "series.episode.00000000000000000000000000007595"))
            XCTAssertTrue(seasonOne.hasFocus)
            save(app, name: "T07-50-season-focus")
        }

        /// T07-48: canonical spec/TESTPLAN-M07.md.

        func testT07_48_downFromSeasonTargetsThatSeasonsFirstUnplayedEpisode() {
            let app = launch("series")
            enterEpisodes(app)
            focused(element(app, "series.episode.000000000000000000000000000075fd"))
            save(app, name: "T07-48-first-unplayed")
        }

        /// T07-49: canonical spec/TESTPLAN-M07.md.

        func testT07_49_upFromEpisodeReturnsToSelectedSeason() {
            let app = launch("series")
            enterEpisodes(app)
            XCUIRemote.shared.press(.right)
            XCUIRemote.shared.press(.up)
            focused(element(app, "series.season.000000000000000000000000000007d2"))
            save(app, name: "T07-49-up-to-season")
        }

        /// T07-51: canonical spec/TESTPLAN-M07.md.

        func testT07_51_playbackReturnHookRestoresSameEpisode() {
            let app = launch("series-return")
            enterEpisodes(app)
            XCUIRemote.shared.press(.right)
            let episode = element(app, "series.episode.000000000000000000000000000075fe")
            focused(episode)
            XCUIRemote.shared.press(.playPause)
            require(element(app, "library.playback.returned"))
            focused(episode)
            save(app, name: "T07-51-return-same-episode")
        }

        /// T07-51: canonical spec/TESTPLAN-M07.md.

        func testT07_51_finishedPlaybackReturnHookMovesToNextEpisode() {
            let app = launch("series-finished")
            enterEpisodes(app)
            XCUIRemote.shared.press(.playPause)
            require(element(app, "library.playback.returned"))
            focused(element(app, "series.episode.000000000000000000000000000075fe"))
            save(app, name: "T07-51-return-next-episode")
        }

        /// T07-52: canonical spec/TESTPLAN-M07.md.

        func testT07_52_episodeOverviewNeverReceivesFocus() {
            let app = launch("series")
            enterEpisodes(app)
            let overview = element(app, "series.overview")
            require(overview)
            XCTAssertFalse(overview.hasFocus)
            XCUIRemote.shared.press(.down)
            XCTAssertFalse(overview.hasFocus)
            XCUIRemote.shared.press(.up)
            XCTAssertFalse(overview.hasFocus)
            save(app, name: "T07-52-overview")
        }

        /// T07-53: canonical spec/TESTPLAN-M07.md.

        func testT07_53_episodeCardNavigatesToEpisodeDetail() {
            let app = launch("series")
            enterEpisodes(app)
            XCUIRemote.shared.press(.select)
            require(element(app, "detail.root"))
            require(element(app, "detail.startOver"))
            XCTAssertFalse(element(app, "series.seasons").exists)
            save(app, name: "T07-53-episode-detail")
        }

        /// T07-63: canonical spec/TESTPLAN-M07.md.

        func testT07_63_serverDownMidBrowseKeepsCardsAndShowsBanner() {
            let app = launch("down")
            require(element(app, "library.item.00000000000000000000000000000064"))
            for _ in 0..<8 { XCUIRemote.shared.press(.down) }
            require(element(app, "library.banner"))
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library.item.'")).count > 0)
            XCTAssertFalse(element(app, "design.error.root").exists)
            save(app, name: "T07-63-retained-content")
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
