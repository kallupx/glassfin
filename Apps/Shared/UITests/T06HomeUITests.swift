import XCTest

@MainActor
final class T06HomeUITests: XCTestCase {
    // T06-09: canonical spec/TESTPLAN-M06.md.
    func testT06_09_allRowsAndLibraryTabsExist() {
        let app = launch()
        require(element(app, "home.resume"))
        require(element(app, "home.nextUp"))
        require(element(app, "design.tab.library.cccccccccccccccccccccccccccccccc"))
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
    func testT06_04_emptyLibraryHasGuidanceAndRetry() {
        let app = launch("-uitest-home-empty")
        require(element(app, "home.empty"))
        require(element(app, "home.empty.retry"))
    }

    // T06-13: canonical spec/TESTPLAN-M06.md.
    func testT06_13_partialErrorKeepsOtherRowsAndHasSectionRetry() {
        let app = launch("-uitest-home-partial")
        require(element(app, "home.resume.retry"))
        require(element(app, "home.nextUp"))
        XCTAssertFalse(element(app, "home.error").exists)
    }

    // T06-56: canonical spec/TESTPLAN-M06.md.
    func testT06_56_cachedServerDownKeepsCardsAndNonFocusableBanner() {
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
    func testT06_46_serverDownStillAllowsSettingsAndSignOut() {
        let app = launch("-uitest-home-down")
        require(element(app, "home.error"))
        activate(element(app, "design.tab.settings"), in: app)
        require(element(app, "settings.signOut"))
        activate(element(app, "settings.signOut"), in: app)
        require(element(app, "logout.cancel"))
    }

    #if os(tvOS)
        // T06-01, T06-31: default focus and detail/back navigation.
        func testT06_01_resumeFirstCardHasDefaultFocusAndDetailBackRestoresIt() {
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
        func testT06_02_nextUpGetsDefaultFocusWhenResumeIsEmpty() {
            let app = launch("-uitest-home-next-only")
            focused(element(app, "home.nextUp.item.00000000000000000000000000000015"))
        }

        // T06-64: canonical spec/TESTPLAN-M06.md.
        func testT06_64_backgroundRefreshKeepsTheFocusedItem() {
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
        func testT06_32_playPauseUsesFocusedResumePosition() {
            let app = launch()
            focused(element(app, "home.resume.item.00000000000000000000000000000001"))
            XCUIRemote.shared.press(.playPause)
            let target = element(app, "home.playback")
            require(target)
            XCTAssertEqual(target.value as? String, "1200000000")
        }

        // T06-34: canonical spec/TESTPLAN-M06.md.
        func testT06_34_longPressShowsContextActions() {
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
    func testT06_70_accessibilityScreenshots() {
        let app = launch("-uitest-home-reduce-transparency", "-uitest-home-cached-down")
        require(element(app, "home.banner"))
        save(app, name: "home-reduce-transparency")
    }

    private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments +=
            ["-uitest-mock-server", "-uitest-reset", "-uitest-home", "-AppleLanguages", "(en)"] + arguments
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func require(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), element.identifier)
    }

    #if os(tvOS)
        private func focused(_ element: XCUIElement) {
            require(element)
            let predicate = NSPredicate(format: "hasFocus == true")
            let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed, element.identifier)
        }
    #endif

    private func save(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
