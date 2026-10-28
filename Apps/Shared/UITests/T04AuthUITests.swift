import CoreModels
import XCTest

@MainActor
final class T04AuthUITests: XCTestCase {
    func testT04_01_welcomeIsTheConnectButton() {
        let app = launch()
        let root = app.descendants(matching: .any)["welcome.root"]
        XCTAssertTrue(root.waitForExistence(timeout: 20))
        let connect = app.descendants(matching: .any)[WelcomeCopy.Key.connect.rawValue]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["navigation.back"].exists)
        save(app.screenshot(), name: "welcome")
    }

    func testT04_02_welcomeHasNoCustomMenuHandler() {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["welcome.root"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.descendants(matching: .any)["navigation.back"].exists)
    }

    func testT04_03_quickConnectReachesHome() {
        let app = launch()
        openAddress(app)
        let field = app.descendants(matching: .any)["address.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        typeText("media.example", into: field, in: app)
        activate(app.descendants(matching: .any)["address.continue"], in: app)
        let quick = app.descendants(matching: .any)["login.quickConnect"]
        XCTAssertTrue(quick.waitForExistence(timeout: 10))
        save(app.screenshot(), name: "login-method")
        activate(quick, in: app)
        let code = app.descendants(matching: .any)["quickconnect.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 10))
        XCTAssertTrue(code.label.contains("482913") || (code.value as? String)?.contains("482913") == true)
        save(app.screenshot(), name: "quick-connect")
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 10))
        save(app.screenshot(), name: "home")
    }

    func testT04_11_explicitPublicHTTPShowsTheKey() {
        let app = launch()
        openAddress(app)
        let field = app.descendants(matching: .any)["address.field"]
        typeText("http://203.0.113.5:8096", into: field, in: app)
        activate(app.descendants(matching: .any)["address.continue"], in: app)
        let error = app.descendants(matching: .any)["address.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertEqual(error.value as? String, AuthCopy.Key.publicAddressRequiresHTTPS.rawValue)
        XCTAssertFalse(app.descendants(matching: .any)["address.httpSkipped"].exists)
    }

    func testT04_25_privateHTTPShowsCleartextCancelFirst() {
        let app = launch()
        openAddress(app)
        let field = app.descendants(matching: .any)["address.field"]
        typeText("http://192.168.1.10:8096", into: field, in: app)
        activate(app.descendants(matching: .any)["address.continue"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["cleartext.cancel"].waitForExistence(timeout: 10))
        activate(app.descendants(matching: .any)["cleartext.accept"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["login.quickConnect"].waitForExistence(timeout: 10))
    }

    func testT04_45_passwordFieldIsSecure() {
        let app = launch()
        openPassword(app)
        let password = app.secureTextFields["credentials.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["credentials.username"].exists)
        save(app.screenshot(), name: "password")
    }

    func testT04_49_backFromQuickConnectReturnsToTheMethodScreen() {
        let app = launch(arguments: ["-uitest-qc-pending"])
        openAddress(app)
        let field = app.descendants(matching: .any)["address.field"]
        typeText("media.example", into: field, in: app)
        activate(app.descendants(matching: .any)["address.continue"], in: app)
        let quick = app.descendants(matching: .any)["login.quickConnect"]
        XCTAssertTrue(quick.waitForExistence(timeout: 10))
        activate(quick, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["quickconnect.code"].waitForExistence(timeout: 10))
        activate(app.descendants(matching: .any)["navigation.back"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["login.quickConnect"].waitForExistence(timeout: 10))
    }

    func testT04_34_disabledQuickConnectSkipsMethodAndBackReturnsToAddress() {
        let app = launch(arguments: ["-uitest-qc-disabled"])
        openAddress(app)
        let field = app.descendants(matching: .any)["address.field"]
        typeText("example.com", into: field, in: app)
        activate(app.descendants(matching: .any)["address.continue"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["credentials.root"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["login.root"].exists)
        save(app.screenshot(), name: "password-quick-connect-disabled")
        activate(app.descendants(matching: .any)["navigation.back"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["address.root"].waitForExistence(timeout: 10))
    }

    func testT04_40_expiredCodeOffersFocusedNewCodeButton() {
        let app = launch(arguments: ["-uitest-qc-expired"])
        openAddress(app)
        let field = app.descendants(matching: .any)["address.field"]
        typeText("example.com", into: field, in: app)
        activate(app.descendants(matching: .any)["address.continue"], in: app)
        let quick = app.descendants(matching: .any)["login.quickConnect"]
        XCTAssertTrue(quick.waitForExistence(timeout: 10))
        activate(quick, in: app)
        let renew = app.descendants(matching: .any)["quickconnect.newCode"]
        XCTAssertTrue(renew.waitForExistence(timeout: 10))
        #if os(tvOS)
            XCTAssertTrue(renew.hasFocus)
        #endif
        XCTAssertEqual(
            app.descendants(matching: .any)["address.error"].value as? String, AuthCopy.Key.quickConnectExpired.rawValue
        )
        save(app.screenshot(), name: "quick-connect-expired")
        activate(renew, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["quickconnect.root"].waitForExistence(timeout: 10))
    }

    func testT04_68_settingsSignOutDefaultsToCancelAndKeepsServer() {
        let app = launch()
        openPassword(app)
        let username = app.descendants(matching: .any)["credentials.username"]
        typeText("Ada", into: username, in: app)
        let password = app.secureTextFields["credentials.password"]
        typeText("sample", into: password, in: app)
        activate(app.descendants(matching: .any)["credentials.signIn"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 10))
        // Settings is a catalog key used for the tab label on both platforms.
        activate(
            app.descendants(matching: .any).matching(identifier: AuthCopy.Key.settings.rawValue).firstMatch, in: app)
        let signOut = app.descendants(matching: .any)["settings.signOut"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["settings.version"].exists)
        save(app.screenshot(), name: "settings")
        activate(signOut, in: app)
        let cancel = app.descendants(matching: .any)["logout.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        #if os(tvOS)
            XCTAssertTrue(cancel.hasFocus)
        #endif
        save(app.screenshot(), name: "sign-out-confirmation")
        activate(cancel, in: app)
        XCTAssertTrue(signOut.waitForExistence(timeout: 10))
        activate(signOut, in: app)
        activate(app.descendants(matching: .any)["logout.confirm"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["login.quickConnect"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["login.serverName"].exists)
    }

    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["-uitest-mock-server", "-uitest-reset"] + arguments)
        app.launch()
        return app
    }

    private func openAddress(_ app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any)[WelcomeCopy.Key.connect.rawValue].waitForExistence(timeout: 20))
        activate(app.descendants(matching: .any)[WelcomeCopy.Key.connect.rawValue], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["address.field"].waitForExistence(timeout: 10))
    }

    private func openPassword(_ app: XCUIApplication) {
        openAddress(app)
        let field = app.descendants(matching: .any)["address.field"]
        typeText("media.example", into: field, in: app)
        activate(app.descendants(matching: .any)["address.continue"], in: app)
        let password = app.descendants(matching: .any)["login.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 10))
        activate(password, in: app)
    }

    private func save(_ shot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["GLASSFIN_SCREENSHOT_DIR"], !directory.isEmpty {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
        }
    }

}
