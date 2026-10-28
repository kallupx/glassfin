import XCTest

final class DesignSystemFocusTests: XCTestCase {
    @MainActor
    func testT05_22_demoIdentifiersExist() async {
        let app = launch("-uitest-design-system")
        for identifier in [
            "design.shell.root",
            "design.root",
            "design.hero.root",
            "design.hero.title",
            "design.hero.meta",
            "design.hero.play",
            "design.hero.watched",
            "design.hero.favorite",
            "design.hero.more",
            "design.hero.overview.collapsed",
            "design.banner.offline",
            "design.banner.offline.icon",
            "design.row.primary",
            "design.row.primary.item.0",
            "design.row.posters",
            "design.row.posters.item.0",
            "design.playback.target",
        ] {
            require(element(app, identifier))
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: identifier).count, 1, identifier)
        }
    }

    #if os(tvOS)
        @MainActor
        func testT05_10_longPressOpensTheContextMenu() async {
            let app = launch("-uitest-design-system")
            let card = element(app, "design.row.primary.item.0")
            require(element(app, "design.hero.play"))
            remote(.down)
            waitUntilFocused(card)
            remote(.select, forDuration: 1.5)
            // tvOS exposes the native menu action as an identified Other inside a focused Cell.
            let play = app.cells.containing(.any, identifier: "design.context.play").firstMatch
            require(play, timeout: 8)
            waitUntilFocused(play)
        }

        @MainActor
        func testT05_12_rowFocusReturnsToTheRememberedPoster() async {
            let app = launch("-uitest-design-system")
            let play = element(app, "design.hero.play")
            require(play)
            waitUntilFocused(play)
            let focused = app.screenshot().pngRepresentation
            save(app, name: "design-demo-focused")
            remote(.down)
            let primary = element(app, "design.row.primary.item.0")
            waitUntilFocused(primary)
            remote(.down)
            let poster = element(app, "design.row.posters.item.0")
            waitUntilFocused(poster)
            for _ in 0..<5 {
                remote(.right)
            }
            let remembered = element(app, "design.row.posters.item.5")
            waitUntilFocused(remembered)
            remote(.up)
            waitUntilFocused(primary)
            remote(.down)
            waitUntilFocused(remembered)
            let unfocused = app.screenshot().pngRepresentation
            save(app, name: "design-demo-unfocused")
            XCTAssertNotEqual(focused, unfocused)
            XCTAssertFalse(play.hasFocus)
        }

        @MainActor
        func testT05_13_playStartsFocused() async {
            let app = launch("-uitest-design-system")
            let play = element(app, "design.hero.play")
            require(play)
            waitUntilFocused(play)
            save(app, name: "design-hero-play-focused")
        }

        @MainActor
        func testT05_14_overviewIsSkippedAndMoreExpandsIt() async {
            let app = launch("-uitest-design-system")
            let play = element(app, "design.hero.play")
            require(play)
            waitUntilFocused(play)
            let collapsed = element(app, "design.hero.overview.collapsed")
            require(collapsed)
            XCTAssertFalse(collapsed.hasFocus)
            remote(.up)
            XCTAssertFalse(collapsed.hasFocus)
            remote(.down)
            waitUntilFocused(play)
            for _ in 0..<3 {
                remote(.right)
            }
            waitUntilFocused(element(app, "design.hero.more"))
            remote(.select)
            let expanded = element(app, "design.hero.overview.expanded")
            require(expanded)
            XCTAssertFalse(expanded.hasFocus)
        }

        @MainActor
        func testT05_16_actionBarExitsDownward() async {
            let app = launch("-uitest-design-system")
            let play = element(app, "design.hero.play")
            require(play)
            waitUntilFocused(play)
            remote(.right)
            waitUntilFocused(element(app, "design.hero.watched"))
            remote(.left)
            waitUntilFocused(play)
            remote(.down)
            waitUntilFocused(element(app, "design.row.primary.item.0"))
            XCTAssertFalse(play.hasFocus)
        }

        @MainActor
        func testT05_18_offlineBannerIsNotFocusable() async {
            let app = launch("-uitest-design-system")
            let banner = element(app, "design.banner.offline")
            require(banner)
            XCTAssertFalse(banner.hasFocus)
            remote(.up)
            XCTAssertFalse(banner.hasFocus)
            remote(.down)
            XCTAssertFalse(banner.hasFocus)
        }

        @MainActor
        func testT05_21_retryIncrementsTheAttemptCount() async {
            let app = launch("-uitest-design-system-error")
            let retry = element(app, "design.error.retry")
            require(retry)
            waitUntilFocused(retry)
            let attempts = element(app, "design.error.attempts")
            require(attempts)
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "design.error.root").count, 1)
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "design.error.attempts").count, 1)
            XCTAssertEqual(attempts.value as? String, "0")
            remote(.select)
            let updated = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", "1"),
                object: attempts
            )
            XCTAssertEqual(XCTWaiter().wait(for: [updated], timeout: 5), .completed)
        }

        @MainActor
        func testT05_27_threeLibrariesHaveNoOverflowTab() async {
            let app = launch("-uitest-design-system-tabs-3")
            require(element(app, "design.tab.home"))
            require(element(app, "design.tab.search"))
            require(element(app, "design.tab.settings"))
            require(element(app, "design.tab.library.0"))
            require(element(app, "design.tab.library.2"))
            XCTAssertFalse(element(app, "design.tab.libraries").exists)
        }

        @MainActor
        func testT05_27_sevenLibrariesKeepFiveInline() async {
            let app = launch("-uitest-design-system-tabs-7")
            require(element(app, "design.tab.libraries"))
            require(element(app, "design.tab.library.0"))
            require(element(app, "design.tab.library.4"))
            XCTAssertFalse(element(app, "design.tab.library.5").exists)
            require(element(app, "design.tab.search"))
        }

        @MainActor
        func testT05_28_menuWalksBackToTheTabBar() async {
            let app = launch("-uitest-design-system-nav")
            let detail = element(app, "design.nav.detail")
            require(detail)
            waitUntilFocused(detail)
            remote(.menu)
            let library = element(app, "design.nav.library")
            require(library)
            waitUntilFocused(library)
            remote(.menu)
            let root = element(app, "design.nav.root")
            require(root)
            waitUntilFocused(root)
            remote(.menu)
            let tab = element(app, "design.tab.home")
            waitUntilFocused(tab)
            remote(.menu)
            let still = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: tab)
            still.isInverted = true
            XCTAssertEqual(XCTWaiter().wait(for: [still], timeout: 5), .completed)
        }

        @MainActor
        func testT05_29_upLeavesTheHeroForAnotherTarget() async {
            let app = launch("-uitest-design-system")
            let play = element(app, "design.hero.play")
            require(play)
            waitUntilFocused(play)
            remote(.up)
            XCTAssertFalse(element(app, "design.banner.offline").hasFocus)
            let tab = element(app, "design.tab.home")
            XCTAssertTrue(tab.hasFocus || play.hasFocus)
            remote(.down)
            waitUntilFocused(play)
        }

        @MainActor
        func testT05_30_playPauseRecordsTheFocusedIdentifier() async {
            let app = launch("-uitest-design-system")
            let primary = element(app, "design.row.primary.item.0")
            require(element(app, "design.hero.play"))
            remote(.down)
            waitUntilFocused(primary)
            remote(.playPause)
            let target = element(app, "design.playback.target")
            let updated = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", "primary-0"),
                object: target
            )
            XCTAssertEqual(XCTWaiter().wait(for: [updated], timeout: 5), .completed)
        }

        @MainActor
        func testT05_33_iconsExposeAnAccessibilityLabel() async {
            let app = launch("-uitest-design-system")
            let icon = element(app, "design.action.play.icon")
            require(icon)
            XCTAssertFalse(icon.label.isEmpty)
            XCTAssertEqual(icon.identifier, "design.action.play.icon")
        }
    #endif

    #if os(iOS)
        @MainActor
        func testT05_08_focusDemoLaunches() async {
            let app = launch("-uitest-design-system")
            require(element(app, "design.root"))
            require(element(app, "design.hero.play"))
        }

        @MainActor
        func testT05_54_tabShellExposesHomeSearchAndSettings() async {
            let app = launch("-uitest-design-system-tabs-3")
            require(element(app, "design.shell.root"))
            require(app.tabBars.buttons["design.tab.library.0"])
            selectTab(app, "design.tab.home")
            require(element(app, "design.home.root"))
            selectTab(app, "design.tab.search")
            require(element(app, "design.search.root"))
            selectTab(app, "design.tab.settings")
            require(element(app, "design.settings.root"))
        }

        private func selectTab(
            _ app: XCUIApplication,
            _ identifier: String,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            let button = app.tabBars.buttons[identifier]
            if button.exists {
                button.tap()
            } else {
                // Six tabs exceed the iPhone tab bar capacity; the system puts the rest under More.
                let more = app.tabBars.buttons["More"]
                require(more, file: file, line: line)
                more.tap()
                let overflowTab = element(app, identifier)
                require(overflowTab, file: file, line: line)
                overflowTab.tap()
            }
        }
    #endif

    @MainActor
    private func launch(_ argument: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [argument]
        #if os(iOS)
            // Keep the system-generated More button deterministic as well as the app's catalog copy.
            app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        #endif
        app.launch()
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    @MainActor
    private func require(
        _ element: XCUIElement,
        timeout: TimeInterval = 20,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), file: file, line: line)
    }

    @MainActor
    private func waitUntilFocused(
        _ element: XCUIElement,
        timeout: TimeInterval = 8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, file: file, line: line)
    }

    @MainActor
    private func save(_ app: XCUIApplication, name: String) {
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let directory = ProcessInfo.processInfo.environment["GLASSFIN_SCREENSHOT_DIR"], !directory.isEmpty else {
            return
        }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
    }

    #if os(tvOS)
        @MainActor
        private func remote(_ button: XCUIRemote.Button, forDuration duration: TimeInterval = 0) {
            if duration > 0 {
                XCUIRemote.shared.press(button, forDuration: duration)
            } else {
                XCUIRemote.shared.press(button)
            }
        }
    #endif
}
