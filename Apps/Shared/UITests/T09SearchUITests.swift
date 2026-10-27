import XCTest

@MainActor
final class T09SearchUITests: XCTestCase {
    func testT09_04_fastTypingRetainsAllTwentyCharacters() {
        let app = launch()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let term = "abcdefghijklmnopqrst"
        typeText(term, into: field, in: app)
        XCTAssertEqual(field.value as? String, term)
        XCTAssertTrue(app.buttons["search.item.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"].waitForExistence(timeout: 10))
    }

    func testT09_08_emptyStateUsesCatalogKey() {
        let app = launch(extra: ["-uitest-search-empty"])
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        typeText("absent", into: field, in: app)
        let empty = app.descendants(matching: .any)["search.empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        XCTAssertEqual(empty.value as? String, "search.empty")
    }

    func testT09_09_errorShowsRetryAndSharedCoreKey() {
        let app = launch(extra: ["-uitest-search-error"])
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        typeText("failure", into: field, in: app)
        let error = app.descendants(matching: .any)["search.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertEqual(error.value as? String, "The server returned an error")
        activate(app.buttons["search.retry"], in: app)
        XCTAssertTrue(error.waitForExistence(timeout: 10))
    }

    func testT09_10_backRestoresTextResultsAndSelectedCardFocus() {
        let app = launch()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        typeText("star", into: field, in: app)
        let second = app.buttons["search.item.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        activate(second, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["search.detail.title"].waitForExistence(timeout: 10))
        activate(app.buttons["search.detail.back"], in: app)
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        XCTAssertEqual(field.value as? String, "star")
        #if os(tvOS)
            let restored = NSPredicate(format: "hasFocus == true")
            expectation(for: restored, evaluatedWith: second)
            waitForExpectations(timeout: 5)
        #endif
    }

    #if os(tvOS)
        func testT09_11_keyboardToRowsAndVerticalFocusSections() {
            let app = launch()
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 10))
            typeText("star", into: field, in: app)
            let movie = app.buttons["search.item.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
            XCTAssertTrue(movie.waitForExistence(timeout: 10))
            for _ in 0..<24 {
                if movie.hasFocus { break }
                XCUIRemote.shared.press(.down)
            }
            XCTAssertTrue(movie.hasFocus)
            let series = app.buttons["search.item.cccccccccccccccccccccccccccccccc"]
            XCUIRemote.shared.press(.down)
            XCTAssertTrue(series.waitForExistence(timeout: 5))
            XCTAssertTrue(series.hasFocus)
            XCUIRemote.shared.press(.up)
            XCTAssertTrue(movie.hasFocus)
        }
    #endif

    func testT09_28_recentSearchesAreUserClearable() {
        let app = launch()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        typeText("star", into: field, in: app)
        XCTAssertTrue(app.buttons["search.item.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"].waitForExistence(timeout: 10))
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4), into: field, in: app)
        let clear = app.buttons["search.clearRecent"]
        XCTAssertTrue(clear.waitForExistence(timeout: 10))
        activate(clear, in: app)
        XCTAssertTrue(app.buttons["search.recent.0"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(clear.exists)
    }

    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            ["-uitest-search", "-uitest-mock-server", "-uitest-reset", "-AppleLanguages", "(en)"] + extra
        app.launch()
        return app
    }
}
