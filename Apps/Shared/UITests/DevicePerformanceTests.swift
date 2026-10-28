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
