import CoreModels
import XCTest

final class T10SettingsUITests: XCTestCase {
    @MainActor
    func testTPOC_42_settingsContainsPlaybackPreferencesSignOutAndVersion() async {
        let app = openSettings()
        let root = app.descendants(matching: .any)["settings.root"]
        XCTAssertTrue(root.waitForExistence(timeout: 10))
        let expectedButtons = Set([
            "settings.signOut", "settings.playback.segment.intro", "settings.playback.segment.recap",
            "settings.playback.segment.outro", "settings.playback.segment.preview",
            "settings.playback.segment.commercial",
        ])
        // The autoplay toggle can be exposed as a switch or button by the platform.
        // All remaining buttons must match this exact set, including the five pickers.
        let buttons = root.buttons.matching(NSPredicate(format: "identifier != %@", "settings.playback.autoplay"))
        XCTAssertEqual(buttons.count, expectedButtons.count)
        XCTAssertEqual(Set(buttons.allElementsBoundByIndex.map(\.identifier)), expectedButtons)
        XCTAssertTrue(root.descendants(matching: .any)["settings.playback.autoplay"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["settings.signOut"].exists)
        let version = app.staticTexts["settings.version"]
        XCTAssertTrue(version.exists)
        XCTAssertFalse(version.label.isEmpty)
        XCTAssertFalse(app.descendants(matching: .any)["settings.serverName"].exists)
        save(app, name: "TPOC-42-settings")
    }

    @MainActor
    func testTPOC_43_cancelAndMenuReturnToSettingsWithFocus() async {
        let app = openSettings()
        let signOut = app.descendants(matching: .any)["settings.signOut"]
        activate(signOut, in: app)
        let cancel = app.descendants(matching: .any)["logout.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        #if os(tvOS)
            XCTAssertTrue(cancel.hasFocus)
        #endif
        save(app, name: "TPOC-43-confirmation")
        activate(cancel, in: app)
        XCTAssertTrue(signOut.waitForExistence(timeout: 10))
        #if os(tvOS)
            XCTAssertTrue(signOut.hasFocus)
        #endif
        activate(signOut, in: app)
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        #if os(tvOS)
            XCTAssertTrue(cancel.hasFocus)
            XCUIRemote.shared.press(.menu)
        #else
            activate(cancel, in: app)
        #endif
        XCTAssertTrue(signOut.waitForExistence(timeout: 10))
        // Leaving and re-entering the tab must remain possible with the remote.
        activate(app.descendants(matching: .any)[AuthCopy.Key.home.rawValue], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 10))
        activate(app.descendants(matching: .any)[AuthCopy.Key.settings.rawValue], in: app)
        XCTAssertTrue(signOut.waitForExistence(timeout: 10))
    }

    @MainActor
    func testTPOC_44_TPOC_46_confirmSignOutThenSignInWithPassword() async {
        let app = openSettings()
        activate(app.descendants(matching: .any)["settings.signOut"], in: app)
        activate(app.descendants(matching: .any)["logout.confirm"], in: app)
        let password = app.descendants(matching: .any)["login.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["login.serverName"].exists)
        save(app, name: "TPOC-44-signed-out")
        activate(password, in: app)
        typeText("Ada", into: app.descendants(matching: .any)["credentials.username"], in: app)
        typeText(UUID().uuidString, into: app.secureTextFields["credentials.password"], in: app)
        activate(app.descendants(matching: .any)["credentials.signIn"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 10))
        save(app, name: "TPOC-46-signed-in")
    }

    @MainActor
    private func openSettings() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-uitest-mock-server", "-uitest-reset", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
        ]
        app.launch()
        activate(app.descendants(matching: .any)[WelcomeCopy.Key.connect.rawValue], in: app)
        typeText("media.example", into: app.descendants(matching: .any)["address.field"], in: app)
        activate(app.descendants(matching: .any)["address.continue"], in: app)
        activate(app.descendants(matching: .any)["login.quickConnect"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 10))
        activate(app.descendants(matching: .any)[AuthCopy.Key.settings.rawValue], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["settings.signOut"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func save(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
