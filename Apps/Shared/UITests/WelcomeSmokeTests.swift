import XCTest

final class WelcomeSmokeTests: XCTestCase {
    @MainActor
    func testWelcomeScreenAppears() async {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["-uitest-mock-server", "-uitest-reset"])
        app.launch()

        let root = app.descendants(matching: .any)["welcome.root"]
        XCTAssertTrue(root.waitForExistence(timeout: 20))

        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "welcome"
        attachment.lifetime = .keepAlways
        add(attachment)

        if let directory = ProcessInfo.processInfo.environment["GLASSFIN_SCREENSHOT_DIR"], !directory.isEmpty {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: folder.appendingPathComponent("welcome.png"))
        }
    }
}
