import XCTest

final class T09SearchUITests: XCTestCase {
    /// T09-07: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.
    @MainActor
    func testT09_07_fastTypingRetainsAllTwentyCharacters() async {
        let app = launch()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let term = "abcdefghijklmnopqrst"
        typeText(term, into: field, in: app)
        XCTAssertEqual(field.value as? String, term)
        XCTAssertTrue(app.buttons["search.item.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"].waitForExistence(timeout: 10))
    }

    /// T09-33: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    @MainActor
    func testT09_33_emptyStateUsesCatalogKey() async {
        let app = launch(extra: ["-uitest-search-empty"])
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        typeText("absent", into: field, in: app)
        let empty = app.descendants(matching: .any)["search.empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        XCTAssertEqual(empty.value as? String, "search.empty")
    }

    /// T09-29: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    @MainActor
    func testT09_29_errorShowsRetryAndSharedCoreKey() async {
        let app = launch(extra: ["-uitest-search-error"])
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        typeText("failure", into: field, in: app)
        let error = app.descendants(matching: .any)["search.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        activate(app.buttons["search.retry"], in: app)
        XCTAssertTrue(error.waitForExistence(timeout: 10))
    }

    /// T09-37: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    @MainActor
    func testT09_37_backRestoresTextResultsAndSelectedCardFocus() async {
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
            waitForFocusRestoration()
        #endif
    }

    #if os(tvOS)
        /// T09-11: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.
        @MainActor
        func testT09_11_keyboardToRowsAndVerticalFocusSections() async {
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

    /// T09-53: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    @MainActor
    func testT09_53_recentSearchesAreUserClearable() async {
        let app = launch()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        typeText("star", into: field, in: app)
        XCTAssertTrue(app.buttons["search.item.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"].waitForExistence(timeout: 10))
        activate(app.buttons["search.item.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"], in: app)
        XCTAssertTrue(app.buttons["search.detail.back"].waitForExistence(timeout: 10))
        activate(app.buttons["search.detail.back"], in: app)
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4), into: field, in: app)
        let clear = app.buttons["search.clearRecent"]
        XCTAssertTrue(clear.waitForExistence(timeout: 10))
        activate(clear, in: app)
        XCTAssertTrue(app.buttons["search.recent.0"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(clear.exists)
    }

    @MainActor
    private func waitForFocusRestoration() {
        waitForExpectations(timeout: 5)
    }

    @MainActor
    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            ["-uitest-search", "-uitest-mock-server", "-uitest-reset", "-AppleLanguages", "(en)"] + extra
        app.launch()
        return app
    }
}
