import XCTest

/// Mock UI regression trends. Absolute P1/P3/P11 acceptance uses the device runbook.
final class DevicePerformanceTests: XCTestCase {
    @MainActor
    func testP1_mockHomeLaunch() {
        let app = homeApp()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(
            metrics: [
                XCTApplicationLaunchMetric(), XCTClockMetric(),
                XCTOSSignpostMetric(
                    subsystem: "org.glassfin.app", category: "DevicePerformance", name: "launch.homeRowVisible"),
            ], options: options
        ) {
            app.launch()
            XCTAssertTrue(card(app, index: 1).waitForExistence(timeout: 10))
            app.terminate()
        }
    }

    #if os(tvOS)
        @MainActor
        func testP3_P11_mockHomeFocusAndBrowse() {
            let app = homeApp()
            app.launch()
            XCTAssertTrue(card(app, index: 1).waitForExistence(timeout: 10))
            let firstFocused = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hasFocus == true"), object: card(app, index: 1))
            XCTAssertEqual(XCTWaiter.wait(for: [firstFocused], timeout: 10), .completed)
            let options = XCTMeasureOptions()
            options.iterationCount = 3
            measure(
                metrics: [
                    XCTClockMetric(), XCTMemoryMetric(application: app), XCTCPUMetric(application: app),
                    XCTOSSignpostMetric(
                        subsystem: "org.glassfin.app", category: "DevicePerformance", name: "browse.focusUpdate"),
                ], options: options
            ) {
                for _ in 0..<8 { XCUIRemote.shared.press(.right) }
                for _ in 0..<8 { XCUIRemote.shared.press(.left) }
                XCTAssertTrue(card(app, index: 1).hasFocus)
            }
            app.terminate()
        }
        @MainActor
        func testP3_P11_mockTwoThousandItemGrid() {
            let app = XCUIApplication()
            app.launchArguments = [
                "-uitest-mock-server", "-uitest-library", "grid",
                "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            ]
            app.launch()
            let count = app.descendants(matching: .any).matching(identifier: "library.count").firstMatch
            XCTAssertTrue(count.waitForExistence(timeout: 20))
            XCTAssertTrue(count.label.contains("2,000"))
            let focusedCard = app.buttons.matching(
                NSPredicate(format: "hasFocus == true AND identifier BEGINSWITH 'library.item.'")
            ).firstMatch
            for _ in 0..<4 {
                if focusedCard.exists { break }
                XCUIRemote.shared.press(.down)
            }
            XCTAssertTrue(focusedCard.exists)
            let startingCard = app.buttons[focusedCard.identifier]
            let options = XCTMeasureOptions()
            options.iterationCount = 3
            measure(
                metrics: [
                    XCTClockMetric(), XCTMemoryMetric(application: app), XCTCPUMetric(application: app),
                    XCTOSSignpostMetric(
                        subsystem: "org.glassfin.app", category: "DevicePerformance", name: "browse.focusUpdate"),
                ], options: options
            ) {
                for _ in 0..<12 { XCUIRemote.shared.press(.down) }
                for _ in 0..<12 { XCUIRemote.shared.press(.up) }
                // Lazy scrolling can finish after the last remote press returns.
                let restored = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "exists == true AND hasFocus == true"), object: startingCard)
                XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 10), .completed)
                XCTAssertTrue(focusedCard.exists)
            }
            app.terminate()
        }
    #endif

    @MainActor
    private func homeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-mock-server", "-uitest-reset", "-uitest-home", "-AppleLanguages", "(en)"]
        return app
    }

    @MainActor
    private func card(_ app: XCUIApplication, index: Int) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(identifier: "home.resume.item.\(String(format: "%032x", index))").firstMatch
    }
}
