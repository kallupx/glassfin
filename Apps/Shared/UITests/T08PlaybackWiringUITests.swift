import XCTest

final class T08PlaybackWiringUITests: XCTestCase {
    @MainActor
    func testDetailPlayOpensPlayerAndReturnsToDetail() async {
        let app = launch()
        let play = element(app, "detail.play")
        XCTAssertTrue(activate(play, in: app))
        XCTAssertTrue(element(app, "playback.root").waitForExistence(timeout: 10))
        closePlayer(app)
        XCTAssertTrue(element(app, "playback.root").waitForNonExistence(timeout: 10))
        XCTAssertTrue(element(app, "detail.root").exists)
        #if os(tvOS)
            assertFocused(play)
        #endif
    }

    @MainActor
    func testFromBeginningReturnsFocusToItsButton() async {
        let app = launch()
        let startOver = element(app, "detail.startOver")
        XCTAssertTrue(activate(startOver, in: app))
        XCTAssertTrue(element(app, "playback.root").waitForExistence(timeout: 10))
        closePlayer(app)
        XCTAssertTrue(element(app, "playback.root").waitForNonExistence(timeout: 10))
        #if os(tvOS)
            assertFocused(startOver)
        #endif
    }

    #if os(tvOS)
        @MainActor
        func testEpisodeSelectStartsPlayerAndMenuRestoresEpisode() async {
            let app = launch()
            assertFocused(element(app, "detail.play"))
            XCUIRemote.shared.press(.down)
            assertFocused(element(app, "series.season.000000000000000000000000000007d2"))
            XCUIRemote.shared.press(.down)
            let episode = element(app, "series.episode.000000000000000000000000000075fd")
            assertFocused(episode)
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(element(app, "playback.root").waitForExistence(timeout: 10))
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(element(app, "playback.root").waitForNonExistence(timeout: 10))
            assertFocused(episode)
        }

        @MainActor
        func testHomePlayPauseStartsPlayerAndMenuRestoresCard() async {
            let app = XCUIApplication()
            app.launchArguments = ["-uitest-mock-server", "-uitest-reset", "-uitest-home", "-AppleLanguages", "(en)"]
            app.launch()
            let card = element(app, "home.resume.item.00000000000000000000000000000001")
            assertFocused(card)
            XCUIRemote.shared.press(.playPause)
            XCTAssertTrue(element(app, "playback.root").waitForExistence(timeout: 10))
            XCTAssertEqual(element(app, "home.playback").value as? String, "1200000000")
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(element(app, "playback.root").waitForNonExistence(timeout: 10))
            assertFocused(card)
        }

        @MainActor
        private func assertFocused(_ element: XCUIElement) {
            XCTAssertTrue(element.waitForExistence(timeout: 10))
            let expectation = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hasFocus == true"), object: element)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
        }
    #endif

    @MainActor
    func testStartupFailureShowsLocalizedError() async {
        let app = launch("series-playback-error")
        XCTAssertTrue(activate(element(app, "detail.play"), in: app))
        XCTAssertTrue(element(app, "playback.root").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "playback.error").waitForExistence(timeout: 10))
        XCTAssertEqual(element(app, "playback.error").label, "This file could not be played")
        closePlayer(app)
        XCTAssertTrue(element(app, "playback.root").waitForNonExistence(timeout: 10))
        XCTAssertTrue(element(app, "detail.root").exists)
    }

    @MainActor
    private func launch(_ scenario: String = "series-playback") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-library", scenario, "-AppleLanguages", "(en)"]
        app.launch()
        return app
    }

    @MainActor
    private func closePlayer(_ app: XCUIApplication) {
        #if os(tvOS)
            XCUIRemote.shared.press(.menu)
        #else
            activate(element(app, "playback.close"), in: app)
        #endif
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        // Keep the original journeys and assertions while following the renamed native player.
        let current = id == "home.playback" ? "playback.native" : id
        return app.descendants(matching: .any).matching(identifier: current).firstMatch
    }
}
