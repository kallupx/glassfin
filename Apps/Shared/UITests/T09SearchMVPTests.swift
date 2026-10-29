import CoreModels
import XCTest

final class T09SearchMVPTests: XCTestCase {
    private let movie = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    private let secondMovie = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    private let series = "cccccccccccccccccccccccccccccccc"
    private let secondSeries = "dddddddddddddddddddddddddddddddd"
    private let episode = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

    /// T09-01: entering the native Search tab focuses the input and shows populated recents.
    @MainActor
    func testT09_01_openTabShowsFocusedSystemInputAndRecentSearches() async {
        let app = launch("-uitest-search-tabs", "-uitest-search-recents")
        openTab("Search", identifier: "design.tab.search", in: app)
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        #if os(tvOS)
            XCTAssertTrue(app.keyboards.firstMatch.wait(for: \.hasFocus, toEqual: true, timeout: 5))
        #endif
        let recent = app.buttons["search.recent.0"]
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        XCTAssertEqual(recent.label, "previous")
        XCTAssertGreaterThan(recent.frame.minY, field.frame.minY)
        // Typing immediately, with no activation, also checks iOS initial input focus.
        field.typeText("st")
        XCTAssertEqual(field.value as? String, "st")
        XCTAssertTrue(card(movie, in: app).waitForExistence(timeout: 10))
    }

    /// T09-03: an ineligible Latin query leaves recent searches usable in the rendered view.
    @MainActor
    func testT09_03_singleLatinCharacterKeepsRecentSearchesVisible() async {
        let app = launch("-uitest-search-recents")
        enter("s", in: app)
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "s")
        XCTAssertTrue(app.buttons["search.recent.0"].exists)
        XCTAssertFalse(card(movie, in: app).exists)
        activate(app.buttons["search.recent.0"], in: app)
        #if os(tvOS)
            focusSearchKeyboard(in: app)
        #endif
        assertSearchText("previous", in: app)
        XCTAssertTrue(card(movie, in: app).waitForExistence(timeout: 10))
        #if os(tvOS)
            enter("s", in: app)
            XCTAssertEqual(app.searchFields.firstMatch.value as? String, "previouss")
        #endif
    }

    /// T09-09: clearing the real system field removes results and restores recents.
    @MainActor
    func testT09_09_clearFieldRemovesRowsAndRestoresRecentSearches() async {
        let app = launch("-uitest-search-recents")
        enter("star", in: app)
        XCTAssertTrue(card(movie, in: app).waitForExistence(timeout: 10))
        enter(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4), in: app)
        XCTAssertTrue(card(movie, in: app).waitForNonExistence(timeout: 5))
        XCTAssertFalse(element("search.header.Movie", in: app).exists)
        XCTAssertTrue(app.buttons["search.recent.0"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["search.recent.0"].label, "previous")
    }

    /// T09-12: switching native tabs preserves both the query and the loaded results.
    @MainActor
    func testT09_12_tabRoundTripKeepsQueryAndResults() async {
        let app = launch("-uitest-search-tabs")
        openTab("Search", identifier: "design.tab.search", in: app)
        enter("star", in: app)
        XCTAssertTrue(card(secondMovie, in: app).waitForExistence(timeout: 10))
        openTab("Home", identifier: "design.tab.home", in: app)
        XCTAssertTrue(element("search.fixture.home", in: app).waitForExistence(timeout: 10))
        openTab("Search", identifier: "design.tab.search", in: app)
        XCTAssertTrue(card(secondMovie, in: app).waitForExistence(timeout: 10))
        assertSearchText("star", in: app)
        #if os(tvOS)
            enter("s", in: app)
            XCTAssertEqual(app.searchFields.firstMatch.value as? String, "stars")
        #endif
    }

    /// T09-31: all three rendered headers use the English catalog labels.
    @MainActor
    func testT09_31_groupedResultsHaveMoviesSeriesAndEpisodesHeaders() async {
        let app = launch()
        enter("star", in: app)
        XCTAssertTrue(card(movie, in: app).waitForExistence(timeout: 10))
        #if os(tvOS)
            focusFirstMovie(in: app)
        #endif
        for (kind, title) in [("Movie", "Movies"), ("Series", "Series"), ("Episode", "Episodes")] {
            revealRow(kind, in: app)
            let header = element("search.header.\(kind)", in: app)
            XCTAssertTrue(header.exists)
            XCTAssertEqual(header.label, title)
        }
    }

    /// T09-29: a single failed request does not hide the successful sibling rows.
    @MainActor
    func testT09_29_failedSeriesRequestKeepsMoviesAndEpisodesVisible() async {
        let app = launch("-uitest-search-partial-error")
        enter("star", in: app)
        XCTAssertTrue(card(movie, in: app).waitForExistence(timeout: 10))
        #if os(tvOS)
            focusFirstMovie(in: app)
        #endif
        revealRow("Episode", in: app)
        XCTAssertTrue(card(episode, in: app).exists)
        XCTAssertFalse(element("search.header.Series", in: app).exists)
        XCTAssertFalse(element("search.error", in: app).exists)
    }

    /// T09-32: a successful empty group has neither a header nor result cards.
    @MainActor
    func testT09_32_emptySeriesGroupHasNoHeader() async {
        let app = launch("-uitest-search-empty-series")
        enter("star", in: app)
        XCTAssertTrue(card(movie, in: app).waitForExistence(timeout: 10))
        #if os(tvOS)
            focusFirstMovie(in: app)
        #endif
        revealRow("Episode", in: app)
        XCTAssertTrue(element("search.header.Episode", in: app).exists)
        XCTAssertFalse(element("search.header.Series", in: app).exists)
        XCTAssertFalse(element("search.row.Series", in: app).exists)
        XCTAssertFalse(card(series, in: app).exists)
    }

    /// T09-41: every card in a full row is reachable, with no P0 See more control.
    @MainActor
    func testT09_41_all24CardsAreReachableWithoutSeeMore() async {
        let app = launch("-uitest-search-24")
        enter("star", in: app)
        let firstID = String(format: "%032x", 1)
        XCTAssertTrue(card(firstID, in: app).waitForExistence(timeout: 10))
        #if os(tvOS)
            focusFirstMovie(in: app, id: firstID)
            for index in 1...24 {
                let item = card(String(format: "%032x", index), in: app)
                XCTAssertTrue(item.wait(for: \.hasFocus, toEqual: true, timeout: 5))
                XCTAssertEqual(item.label, "Result \(index)")
                if index < 24 { XCUIRemote.shared.press(.right) }
            }
            XCUIRemote.shared.press(.right)
            XCTAssertTrue(card(String(format: "%032x", 24), in: app).hasFocus)
        #else
            // Submit without clearing the query so the keyboard cannot cover the row's gestures.
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists {
                keyboard.buttons["Search"].tap()
                XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
            }
            let row = element("search.row.Movie", in: app)
            for index in 1...24 {
                let item = card(String(format: "%032x", index), in: app)
                for _ in 0..<8 {
                    if item.exists && item.isHittable { break }
                    row.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
                        .press(
                            forDuration: 0.05,
                            thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)))
                }
                XCTAssertTrue(item.isHittable)
                XCTAssertEqual(item.label, "Result \(index)")
            }
        #endif
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "See more")).firstMatch.exists)
    }

    /// T09-43: typing is not a save; opening a result is the explicit history write.
    @MainActor
    func testT09_43_onlyOpeningAResultAddsTheQueryToRecents() async {
        let app = launch()
        enter("star", in: app)
        XCTAssertTrue(card(movie, in: app).waitForExistence(timeout: 10))
        enter(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4), in: app)
        XCTAssertTrue(card(movie, in: app).waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["search.recent.0"].exists)
        enter("star", in: app)
        XCTAssertTrue(card(movie, in: app).waitForExistence(timeout: 10))
        activate(card(movie, in: app), in: app)
        XCTAssertTrue(app.buttons["search.detail.back"].waitForExistence(timeout: 10))
        activate(app.buttons["search.detail.back"], in: app)
        enter(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4), in: app)
        let recent = app.buttons["search.recent.0"]
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        XCTAssertEqual(recent.label, "star")
        XCTAssertFalse(app.buttons["search.recent.1"].exists)
    }

    /// T09-56: offline recents fill the field while the shared offline banner remains visible.
    @MainActor
    func testT09_56_offlineBannerKeepsRecentQueryUsable() async {
        let app = launch("-uitest-search-offline", "-uitest-search-recents")
        let recent = app.buttons["search.recent.0"]
        XCTAssertTrue(recent.waitForExistence(timeout: 10))
        activate(recent, in: app)
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "previous")
        let banner = element("search.banner", in: app)
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertEqual(banner.value as? String, AppErrorMessage.offlineKey)
        XCTAssertTrue(recent.exists)
        XCTAssertFalse(card(movie, in: app).exists)
    }

    /// T09-58: the no-content server error stays inside Search and leaves its input editable.
    @MainActor
    func testT09_58_serverDownWithoutContentKeepsSearchInputEditable() async {
        let app = launch("-uitest-search-down")
        enter("star", in: app)
        let error = element("search.error", in: app)
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertEqual(error.value as? String, AppErrorMessage.serverDownKey)
        XCTAssertTrue(app.buttons["search.retry"].exists)
        enter("s", in: app)
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "stars")
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertFalse(card(movie, in: app).exists)
    }

    #if os(tvOS)
        /// T09-11: Down reaches content and Up returns to the native inline keyboard.
        @MainActor
        func testT09_11_downReachesResultsAndUpReturnsToKeyboard() async {
            let app = launch()
            enter("star", in: app)
            focusFirstMovie(in: app)
            let keyboard = app.keyboards.firstMatch
            for _ in 0..<24 {
                XCUIRemote.shared.press(.up)
                if keyboard.wait(for: \.hasFocus, toEqual: true, timeout: 1) { break }
            }
            XCTAssertTrue(keyboard.hasFocus)
            app.searchFields.firstMatch.typeText("s")
            XCTAssertEqual(app.searchFields.firstMatch.value as? String, "stars")
        }

        /// T09-20: the focused identity survives a reordered refresh with updated metadata.
        @MainActor
        func testT09_20_refreshKeepsFocusOnSurvivingReorderedItem() async {
            let app = launch("-uitest-search-refresh")
            enter("star", in: app)
            focusFirstMovie(in: app)
            XCUIRemote.shared.press(.right)
            let second = card(secondMovie, in: app)
            XCTAssertTrue(second.wait(for: \.hasFocus, toEqual: true, timeout: 5))
            XCUIRemote.shared.press(.playPause)
            XCTAssertTrue(second.wait(for: \.label, toEqual: "Updated second result", timeout: 10))
            XCTAssertTrue(second.hasFocus)
            XCTAssertEqual(app.searchFields.firstMatch.value as? String, "star")
        }

        /// T09-20: disappearing identities allow focus to move to an actual surviving card.
        @MainActor
        func testT09_20_removedFocusedItemFallsBackToSurvivingResult() async {
            let app = launch("-uitest-search-refresh", "-uitest-search-remove-focused")
            enter("star", in: app)
            focusFirstMovie(in: app)
            XCUIRemote.shared.press(.right)
            let second = card(secondMovie, in: app)
            XCTAssertTrue(second.wait(for: \.hasFocus, toEqual: true, timeout: 5))
            XCUIRemote.shared.press(.playPause)
            XCTAssertTrue(second.waitForNonExistence(timeout: 10))
            XCTAssertTrue(card(movie, in: app).wait(for: \.label, toEqual: "Updated first result", timeout: 10))
            XCTAssertTrue(card(movie, in: app).wait(for: \.hasFocus, toEqual: true, timeout: 5))
        }

        /// T09-40: rows remember different horizontal positions across repeated Down/Up moves.
        @MainActor
        func testT09_40_verticalNavigationRestoresEachRowsRememberedItem() async {
            let app = launch()
            enter("star", in: app)
            focusFirstMovie(in: app)
            XCUIRemote.shared.press(.right)
            XCTAssertTrue(card(secondMovie, in: app).wait(for: \.hasFocus, toEqual: true, timeout: 5))
            XCUIRemote.shared.press(.down)
            let firstSeries = card(series, in: app)
            let otherSeries = card(secondSeries, in: app)
            XCTAssertTrue(element("search.row.Series", in: app).waitForExistence(timeout: 5))
            if otherSeries.hasFocus { XCUIRemote.shared.press(.left) }
            XCTAssertTrue(firstSeries.wait(for: \.hasFocus, toEqual: true, timeout: 5))
            for _ in 0..<3 {
                XCUIRemote.shared.press(.up)
                XCTAssertTrue(card(secondMovie, in: app).wait(for: \.hasFocus, toEqual: true, timeout: 5))
                XCUIRemote.shared.press(.down)
                XCTAssertTrue(firstSeries.wait(for: \.hasFocus, toEqual: true, timeout: 5))
            }
        }

        /// T09-57: a server failure during refresh retains the loaded cards and their focus.
        @MainActor
        func testT09_57_serverDownRefreshKeepsResultsAndShowsBanner() async {
            let app = launch("-uitest-search-refresh", "-uitest-search-refresh-down")
            enter("star", in: app)
            focusFirstMovie(in: app)
            XCUIRemote.shared.press(.right)
            let second = card(secondMovie, in: app)
            XCTAssertTrue(second.wait(for: \.hasFocus, toEqual: true, timeout: 5))
            XCUIRemote.shared.press(.playPause)
            let banner = element("search.banner", in: app)
            XCTAssertTrue(banner.waitForExistence(timeout: 10))
            XCTAssertEqual(banner.value as? String, AppErrorMessage.serverDownKey)
            XCTAssertTrue(second.exists)
            XCTAssertTrue(second.hasFocus)
            XCTAssertTrue(app.buttons["search.retry"].exists)
            XCTAssertFalse(element("search.error", in: app).exists)
            XCTAssertEqual(app.searchFields.firstMatch.value as? String, "star")
        }

        /// T09-69: a failed thumbnail leaves sibling cards and directional focus usable.
        @MainActor
        func testT09_69_imageFailureLeavesRowAndFocusUsable() async {
            let app = launch("-uitest-search-images-fail")
            enter("star", in: app)
            focusFirstMovie(in: app)
            XCTAssertTrue(element("search.fixture.imageFailures", in: app).waitForExistence(timeout: 10))
            XCUIRemote.shared.press(.right)
            XCTAssertTrue(card(secondMovie, in: app).wait(for: \.hasFocus, toEqual: true, timeout: 5))
            XCUIRemote.shared.press(.left)
            XCTAssertTrue(card(movie, in: app).wait(for: \.hasFocus, toEqual: true, timeout: 5))
            XCTAssertFalse(element("search.error", in: app).exists)
            XCTAssertFalse(element("search.banner", in: app).exists)
        }
    #endif

    @MainActor
    private func launch(_ flags: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            [
                "-uitest-search", "-uitest-mock-server", "-uitest-reset", "-AppleLanguages", "(en)",
                "-AppleLocale", "en_US",
            ] + flags
        app.launch()
        return app
    }

    @MainActor
    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    @MainActor
    private func card(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons["search.item.\(id)"]
    }

    @MainActor
    private func assertSearchText(
        _ text: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        let field = app.searchFields.firstMatch
        #if os(tvOS)
            // Native selection can append changing keyboard instructions to the AX
            // value. Editing exposes the actual text without accepting any suffix.
            field.typeText("s")
            XCTAssertEqual(field.value as? String, text + "s", file: file, line: line)
            field.typeText(XCUIKeyboardKey.delete.rawValue)
        #endif
        XCTAssertEqual(field.value as? String, text, file: file, line: line)
    }

    @MainActor
    private func openTab(_ title: String, identifier: String, in app: XCUIApplication) {
        #if os(tvOS)
            activate(element(identifier, in: app), in: app)
            // Selecting a native tvOS tab leaves focus in the tab strip until Down enters its content.
            if identifier == "design.tab.search" {
                let keyboard = app.keyboards.firstMatch
                if keyboard.waitForExistence(timeout: 5), !keyboard.hasFocus { XCUIRemote.shared.press(.down) }
                focusSearchKeyboard(in: app)
            }
        #else
            // Submit through the native keyboard so Search ends editing without clearing its query.
            if title != "Search", app.keyboards.firstMatch.exists {
                app.keyboards.buttons["Search"].tap()
                _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 5)
            }
            activate(app.tabBars.buttons[title], in: app)
        #endif
    }

    @MainActor
    private func enter(_ text: String, in app: XCUIApplication) {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        #if os(tvOS)
            let keyboard = app.keyboards.firstMatch
            XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
            for _ in 0..<24 {
                if keyboard.hasFocus { break }
                XCUIRemote.shared.press(.up)
                if keyboard.wait(for: \.hasFocus, toEqual: true, timeout: 1) { break }
            }
            guard keyboard.hasFocus else {
                XCTFail("Search keyboard did not receive input focus")
                return
            }
            field.typeText(text)
        #else
            typeText(text, into: field, in: app)
        #endif
    }

    @MainActor
    private func revealRow(_ kind: String, in app: XCUIApplication) {
        let header = element("search.header.\(kind)", in: app)
        for _ in 0..<6 {
            if header.exists && header.isHittable { break }
            #if os(tvOS)
                XCUIRemote.shared.press(.down)
            #else
                app.swipeUp()
            #endif
        }
        XCTAssertTrue(header.waitForExistence(timeout: 5))
    }

    #if os(tvOS)
        @MainActor
        private func focusSearchKeyboard(in app: XCUIApplication) {
            let keyboard = app.keyboards.firstMatch
            guard keyboard.waitForExistence(timeout: 5) else {
                XCTFail("Search keyboard did not appear before reading its field")
                return
            }
            for _ in 0..<24 {
                if keyboard.hasFocus { return }
                XCUIRemote.shared.press(.up)
                if keyboard.wait(for: \.hasFocus, toEqual: true, timeout: 1) { return }
            }
            XCTFail("Search keyboard did not receive focus before reading its field")
        }

        @MainActor
        private func focusFirstMovie(in app: XCUIApplication, id: String? = nil) {
            let first = card(id ?? movie, in: app)
            XCTAssertTrue(first.waitForExistence(timeout: 10))
            for _ in 0..<24 {
                if first.hasFocus { break }
                XCUIRemote.shared.press(.down)
                if first.wait(for: \.hasFocus, toEqual: true, timeout: 1) { break }
            }
            XCTAssertTrue(first.hasFocus)
        }
    #endif
}
