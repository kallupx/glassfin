import GlassfinCore
import XCTest

final class T06HomeUITests: XCTestCase {
    // T06-09: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_09_allRowsAndLibraryTabsExist() async {
        let app = launch()
        require(element(app, "home.resume"))
        require(element(app, "home.nextUp"))
        #if os(iOS)
            // The mock library's native tab button uses its title, as in the M05 shell tests.
            require(app.tabBars.buttons["1"])
        #else
            require(element(app, "design.tab.library.cccccccccccccccccccccccccccccccc"))
        #endif
        save(app, name: "home-top")
        #if os(tvOS)
            for _ in 0..<3 { XCUIRemote.shared.press(.down) }
        #else
            app.swipeUp()
        #endif
        require(element(app, "home.cccccccccccccccccccccccccccccccc"))
        require(element(app, "home.dddddddddddddddddddddddddddddddd"))
        save(app, name: "home-latest")
    }

    // T06-04: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_04_emptyLibraryHasGuidanceAndRetry() async {
        let app = launch("-uitest-home-empty")
        require(element(app, "home.empty"))
        require(element(app, "home.empty.retry"))
    }

    // T06-13: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_13_partialErrorKeepsOtherRowsAndHasSectionRetry() async {
        let app = launch("-uitest-home-partial")
        require(element(app, "home.resume.retry"))
        require(element(app, "home.nextUp"))
        XCTAssertFalse(element(app, "home.error").exists)
    }

    // T06-56: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_56_cachedServerDownKeepsCardsAndNonFocusableBanner() async {
        let app = launch("-uitest-home-cached-down")
        require(element(app, "home.resume.item.00000000000000000000000000000001"))
        require(element(app, "home.banner"))
        XCTAssertFalse(element(app, "home.error").exists)
        #if os(tvOS)
            XCTAssertFalse(element(app, "home.banner").hasFocus)
        #endif
        save(app, name: "home-cached-down")
    }

    // T06-46: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_46_serverDownStillAllowsSettingsAndSignOut() async {
        let app = launch("-uitest-home-down")
        require(element(app, "home.error"))
        #if os(iOS)
            activate(app.tabBars.buttons["Settings"], in: app)
        #else
            activate(element(app, "design.tab.settings"), in: app)
        #endif
        require(element(app, "settings.signOut"))
        activate(element(app, "settings.signOut"), in: app)
        require(element(app, "logout.cancel"))
    }

    #if os(tvOS)
        // T06-05: Up and Menu reach the native tab bar. System exit is a manual sub-step.
        @MainActor
        func testT06_05_upAndMenuFromHomeContentReachTabBar() async {
            let app = launch()
            let first = card(app, row: "resume", id: 1)
            let tab = element(app, "design.tab.home")
            guard focused(first), press(.up, expecting: tab), press(.down, expecting: first),
                press(.down, expecting: card(app, row: "nextUp", id: 21)), press(.menu, expecting: tab)
            else { return }
            XCTAssertEqual(app.state, .runningForeground)
        }

        // T06-30: exercise five cards in both rows and make geometry disagree with row memory.
        @MainActor
        func testT06_30_directionsAndCrossRowFocusMemoryReturnToFifthCard() async {
            let app = launch()
            let first = card(app, row: "resume", id: 1)
            guard focused(first) else { return }
            for id in 2...5 {
                guard press(.right, expecting: card(app, row: "resume", id: id)) else { return }
            }
            for id in (1...4).reversed() {
                guard press(.left, expecting: card(app, row: "resume", id: id)) else { return }
            }
            guard press(.down, expecting: card(app, row: "nextUp", id: 21)) else { return }
            for id in 22...25 {
                guard press(.right, expecting: card(app, row: "nextUp", id: id)) else { return }
            }
            let fifth = card(app, row: "nextUp", id: 25)
            guard press(.up, expecting: first) else { return }
            // Row 1 remembers its first card; row 2's fifth card is horizontally elsewhere.
            XCTAssertGreaterThan(abs(fifth.frame.midX - first.frame.midX), first.frame.width / 2)
            guard press(.down, expecting: fifth) else { return }
            save(app, name: "home-row-focus-memory")
        }

        // T06-40: Menu dismisses the native menu and restores a nondefault card.
        @MainActor
        func testT06_40_contextMenuDismissalRestoresSameCard() async {
            let app = launch()
            let second = card(app, row: "resume", id: 2)
            guard focused(card(app, row: "resume", id: 1)), press(.right, expecting: second) else { return }
            XCUIRemote.shared.press(.select, forDuration: 1.5)
            let action = element(app, "home.context.played")
            guard action.waitForExistence(timeout: 5) else {
                XCTFail("home.context.played did not appear")
                return
            }
            XCUIRemote.shared.press(.menu)
            guard action.waitForNonExistence(timeout: 5) else {
                XCTFail("home.context.played did not close")
                return
            }
            guard focused(second) else { return }
            XCTAssertFalse(element(app, "home.detail").exists)
            XCTAssertEqual(app.state, .runningForeground)
        }

        // T06-42: deliver a path change through AppState, retaining the on-screen cards.
        @MainActor
        func testT06_42_networkDropShowsNonFocusableBannerAndKeepsCardsBrowsable() async {
            let app = launch("-uitest-home-network-controls")
            guard focused(card(app, row: "resume", id: 1)), completedResumeRequests(in: app) != nil else { return }
            let banner = element(app, "home.banner")
            XCTAssertFalse(banner.exists)
            // This DEBUG-only remote control never changes the focused element.
            XCUIRemote.shared.press(.playPause)
            guard banner.waitForExistence(timeout: 2) else {
                XCTFail("home.banner did not appear within 2 s of the path drop")
                return
            }
            XCTAssertEqual(banner.value as? String, AppErrorMessage.offlineKey)
            XCTAssertFalse(banner.hasFocus)
            guard focused(card(app, row: "resume", id: 1)),
                press(.right, expecting: card(app, row: "resume", id: 2)),
                press(.left, expecting: card(app, row: "resume", id: 1)),
                press(.down, expecting: card(app, row: "nextUp", id: 21)),
                press(.up, expecting: card(app, row: "resume", id: 1)),
                press(.up, expecting: element(app, "design.tab.home"))
            else { return }
            // Moving through the banner's region must skip the banner and its children.
            XCTAssertFalse(banner.hasFocus)
            XCTAssertEqual(
                banner.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).count, 0)
            XCTAssertFalse(element(app, "home.error").exists)
            XCTAssertFalse(element(app, "home.playback").exists)
            guard press(.down, expecting: card(app, row: "resume", id: 1)) else { return }
            // Context-menu Play keeps its production behavior when the test remote control is enabled.
            XCUIRemote.shared.press(.select, forDuration: 1.5)
            let play = app.cells.containing(.any, identifier: "home.context.play").firstMatch
            guard focused(play) else { return }
            XCUIRemote.shared.press(.select)
            let blocked = element(app, "home.playback.blocked")
            guard blocked.waitForExistence(timeout: 2) else {
                XCTFail("Offline playback did not show feedback")
                return
            }
            XCTAssertEqual(blocked.value as? String, AppErrorMessage.playbackOfflineKey)
            XCTAssertFalse(blocked.hasFocus)
            XCTAssertFalse(element(app, "home.playback").exists)
            guard focused(card(app, row: "resume", id: 1)) else { return }
            save(app, name: "home-network-drop")
        }

        // T06-43: recovery triggers a real service refetch, with no test-directed focus restoration.
        @MainActor
        func testT06_43_networkRecoveryRefreshesHomeWithoutMovingFocus() async {
            let app = launch("-uitest-home-network-controls")
            let second = card(app, row: "resume", id: 2)
            guard focused(card(app, row: "resume", id: 1)), press(.right, expecting: second),
                let before = completedResumeRequests(in: app)
            else { return }
            let banner = element(app, "home.banner")
            XCTAssertFalse(banner.exists)
            XCUIRemote.shared.press(.playPause)
            guard banner.waitForExistence(timeout: 2), focused(second) else {
                XCTFail("Network drop did not retain the focused card")
                return
            }
            XCUIRemote.shared.press(.playPause)
            guard banner.waitForNonExistence(timeout: 2) else {
                XCTFail("home.banner did not disappear within 2 s of path recovery")
                return
            }
            let counter = element(app, "home.test.resumeRequests")
            let refreshed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true AND value != %@", String(before)), object: counter)
            let lostFocus = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hasFocus == false"), object: second)
            lostFocus.isInverted = true
            let result = XCTWaiter.wait(for: [refreshed, lostFocus], timeout: 5)
            guard result == .completed, let after = Int(counter.value as? String ?? ""), after > before else {
                XCTFail("Recovery must complete a new Resume request and keep the same card focused: \(result)")
                return
            }
            // Only wait/assert here: a remote press could conceal an unwanted focus jump.
            guard focused(second) else { return }
            XCTAssertFalse(banner.exists)
            XCTAssertFalse(element(app, "home.error").exists)
            save(app, name: "home-network-recovered")
        }

        // T06-01, T06-31: default focus and detail/back navigation.
        @MainActor
        func testT06_01_resumeFirstCardHasDefaultFocusAndDetailBackRestoresIt() async {
            let app = launch()
            let first = element(app, "home.resume.item.00000000000000000000000000000001")
            focused(first)
            XCUIRemote.shared.press(.right)
            let second = element(app, "home.resume.item.00000000000000000000000000000002")
            focused(second)
            XCUIRemote.shared.press(.select)
            require(element(app, "home.detail"))
            XCUIRemote.shared.press(.menu)
            focused(second)
        }

        // T06-02: canonical spec/TESTPLAN-M06.md.
        @MainActor
        func testT06_02_nextUpGetsDefaultFocusWhenResumeIsEmpty() async {
            let app = launch("-uitest-home-next-only")
            focused(element(app, "home.nextUp.item.00000000000000000000000000000015"))
        }

        // T06-64: canonical spec/TESTPLAN-M06.md.
        @MainActor
        func testT06_64_backgroundRefreshKeepsTheFocusedItem() async {
            let app = launch("-uitest-home-refresh")
            let first = element(app, "home.resume.item.00000000000000000000000000000001")
            focused(first)
            XCUIRemote.shared.press(.right)
            let second = element(app, "home.resume.item.00000000000000000000000000000002")
            focused(second)
            require(element(app, "home.test.refreshed"))
            focused(second)
        }

        // T06-32: canonical spec/TESTPLAN-M06.md.
        @MainActor
        func testT06_32_playPauseUsesFocusedResumePosition() async {
            let app = launch()
            focused(element(app, "home.resume.item.00000000000000000000000000000001"))
            XCUIRemote.shared.press(.playPause)
            let target = element(app, "home.playback")
            require(target)
            XCTAssertEqual(target.value as? String, "1200000000")
        }

        // T06-34: canonical spec/TESTPLAN-M06.md.
        @MainActor
        func testT06_34_longPressShowsContextActions() async {
            let app = launch()
            focused(element(app, "home.resume.item.00000000000000000000000000000001"))
            XCUIRemote.shared.press(.select, forDuration: 1.5)
            require(element(app, "home.context.played"))
            require(element(app, "home.context.removeResume"))
            require(element(app, "home.context.series"))
            require(element(app, "home.context.favorite"))
            save(app, name: "home-context")
        }
    #endif

    // T06-70: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_70_accessibilityScreenshots() async {
        let app = launch("-uitest-home-reduce-transparency", "-uitest-home-cached-down")
        require(element(app, "home.banner"))
        save(app, name: "home-reduce-transparency")
    }

    @MainActor
    private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments +=
            ["-uitest-mock-server", "-uitest-reset", "-uitest-home", "-AppleLanguages", "(en)"] + arguments
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func require(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), element.identifier)
    }

    #if os(tvOS)
        @MainActor
        @discardableResult
        private func focused(
            _ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line
        ) -> Bool {
            guard element.waitForExistence(timeout: 10) else {
                XCTFail("Missing element '\(element.identifier)'", file: file, line: line)
                return false
            }
            let predicate = NSPredicate(format: "hasFocus == true")
            let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
            guard XCTWaiter.wait(for: [expectation], timeout: 8) == .completed else {
                XCTFail("Element '\(element.identifier)' did not receive focus", file: file, line: line)
                return false
            }
            return true
        }

        @MainActor
        private func press(
            _ button: XCUIRemote.Button, expecting element: XCUIElement,
            file: StaticString = #filePath, line: UInt = #line
        ) -> Bool {
            XCUIRemote.shared.press(button)
            return focused(element, file: file, line: line)
        }

        @MainActor
        private func card(_ app: XCUIApplication, row: String, id: Int) -> XCUIElement {
            element(app, "home.\(row).item.\(String(format: "%032x", id))")
        }

        @MainActor
        private func completedResumeRequests(in app: XCUIApplication) -> Int? {
            let counter = element(app, "home.test.resumeRequests")
            guard counter.waitForExistence(timeout: 10), let count = Int(counter.value as? String ?? ""), count > 0
            else {
                XCTFail("Home did not finish its initial load")
                return nil
            }
            return count
        }
    #endif

    @MainActor
    private func save(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
