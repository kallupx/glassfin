import XCTest

@MainActor
final class DesignSystemFocusTests: XCTestCase {
    func testT05_22_demoIdentifiersExist() {
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
        func testT05_10_longPressOpensTheContextMenu() {
            let app = launch("-uitest-design-system")
            let card = element(app, "design.row.primary.item.0")
            require(element(app, "design.hero.play"))
            remote(.down)
            waitUntilFocused(card)
            remote(.select, forDuration: 1.5)
            require(app.buttons["design.context.play"], timeout: 8)
        }

        func testT05_12_rowFocusReturnsToTheRememberedPoster() {
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

        func testT05_13_playStartsFocused() {
            let app = launch("-uitest-design-system")
            let play = element(app, "design.hero.play")
            require(play)
            waitUntilFocused(play)
            save(app, name: "design-hero-play-focused")
        }

        func testT05_14_overviewIsSkippedAndMoreExpandsIt() {
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

        func testT05_16_actionBarExitsDownward() {
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

        func testT05_18_offlineBannerIsNotFocusable() {
            let app = launch("-uitest-design-system")
            let banner = element(app, "design.banner.offline")
            require(banner)
            XCTAssertFalse(banner.hasFocus)
            remote(.up)
            XCTAssertFalse(banner.hasFocus)
            remote(.down)
            XCTAssertFalse(banner.hasFocus)
        }

        func testT05_21_retryIncrementsTheAttemptCount() {
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

        func testT05_27_threeLibrariesHaveNoOverflowTab() {
            let app = launch("-uitest-design-system-tabs-3")
            require(element(app, "design.tab.home"))
            require(element(app, "design.tab.search"))
            require(element(app, "design.tab.settings"))
            require(element(app, "design.tab.library.0"))
            require(element(app, "design.tab.library.2"))
            XCTAssertFalse(element(app, "design.tab.libraries").exists)
        }

        func testT05_27_sevenLibrariesKeepFiveInline() {
            let app = launch("-uitest-design-system-tabs-7")
            require(element(app, "design.tab.libraries"))
            require(element(app, "design.tab.library.0"))
            require(element(app, "design.tab.library.4"))
            XCTAssertFalse(element(app, "design.tab.library.5").exists)
            require(element(app, "design.tab.search"))
        }

        func testT05_28_menuWalksBackToTheTabBar() {
            let app = launch("-uitest-design-system-nav")
            let detail = element(app, "design.nav.detail")
            require(detail)
            remote(.menu)
            require(element(app, "design.nav.library"))
            remote(.menu)
            let root = element(app, "design.nav.root")
            require(root)
            remote(.menu)
            let tab = element(app, "design.tab.home")
            waitUntilFocused(tab)
            remote(.menu)
            let still = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: tab)
            still.isInverted = true
            XCTAssertEqual(XCTWaiter().wait(for: [still], timeout: 5), .completed)
        }

        func testT05_29_upLeavesTheHeroForAnotherTarget() {
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

        func testT05_30_playPauseRecordsTheFocusedIdentifier() {
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

        func testT05_33_iconsExposeAnAccessibilityLabel() {
            let app = launch("-uitest-design-system")
            let icon = element(app, "design.action.play.icon")
            require(icon)
            XCTAssertFalse(icon.label.isEmpty)
            XCTAssertEqual(icon.identifier, "design.action.play.icon")
        }
    #endif

    #if os(iOS)
        func testT05_08_focusDemoLaunches() {
            let app = launch("-uitest-design-system")
            require(element(app, "design.root"))
            require(element(app, "design.hero.play"))
        }

        func testT05_54_tabShellExposesHomeSearchAndSettings() {
            let app = launch("-uitest-design-system-tabs-3")
            require(element(app, "design.shell.root"))
            require(element(app, "design.tab.home"))
            require(element(app, "design.tab.search"))
            require(element(app, "design.tab.settings"))
            require(element(app, "design.tab.library.0"))
        }
    #endif

    private func launch(_ argument: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [argument]
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func require(
        _ element: XCUIElement,
        timeout: TimeInterval = 20,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), file: file, line: line)
    }

    private func waitUntilFocused(
        _ element: XCUIElement,
        timeout: TimeInterval = 8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, file: file, line: line)
    }

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
        private func remote(_ button: XCUIRemote.Button, forDuration duration: TimeInterval = 0) {
            if duration > 0 {
                XCUIRemote.shared.press(button, forDuration: duration)
            } else {
                XCUIRemote.shared.press(button)
            }
        }
    #endif
}
