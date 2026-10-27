import XCTest

final class T04AuthUITests: XCTestCase {
    @MainActor
    func testT04_01_welcomeIsTheConnectButton() async {
        let app = launch()
        let root = app.descendants(matching: .any)["welcome.root"]
        XCTAssertTrue(root.waitForExistence(timeout: 20))
        let connect = app.descendants(matching: .any)["welcome.connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["navigation.back"].exists)
        save(app.screenshot(), name: "welcome")
    }

    @MainActor
    func testT04_02_welcomeHasNoCustomMenuHandler() async {
        let app = launch()
        XCTAssertTrue(app.descendants(matching: .any)["welcome.root"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.descendants(matching: .any)["navigation.back"].exists)
    }

    @MainActor
    func testT04_03_quickConnectReachesHome() async {
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

    @MainActor
    func testT04_11_explicitPublicHTTPShowsTheKey() async {
        let app = launch()
        openAddress(app)
        let field = app.descendants(matching: .any)["address.field"]
        typeText("http://203.0.113.5:8096", into: field, in: app)
        activate(app.descendants(matching: .any)["address.continue"], in: app)
        let error = app.descendants(matching: .any)["address.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertEqual(error.value as? String, publicHTTPSKey)
        XCTAssertFalse(app.descendants(matching: .any)["address.httpSkipped"].exists)
    }

    @MainActor
    func testT04_25_privateHTTPShowsCleartextCancelFirst() async {
        let app = launch()
        openAddress(app)
        let field = app.descendants(matching: .any)["address.field"]
        typeText("http://192.168.1.10:8096", into: field, in: app)
        activate(app.descendants(matching: .any)["address.continue"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["cleartext.cancel"].waitForExistence(timeout: 10))
        activate(app.descendants(matching: .any)["cleartext.accept"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["login.quickConnect"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testT04_45_passwordFieldIsSecure() async {
        let app = launch()
        openPassword(app)
        let password = app.secureTextFields["credentials.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["credentials.username"].exists)
        save(app.screenshot(), name: "password")
    }

    @MainActor
    func testT04_49_backFromQuickConnectReturnsToTheMethodScreen() async {
        let app = launch()
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

    @MainActor
    func testT04_34_disabledQuickConnectSkipsMethodAndBackReturnsToAddress() async {
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

    @MainActor
    func testT04_40_expiredCodeOffersFocusedNewCodeButton() async {
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
        XCTAssertEqual(app.descendants(matching: .any)["address.error"].value as? String, "The code expired")
        save(app.screenshot(), name: "quick-connect-expired")
        activate(renew, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["quickconnect.root"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testT04_68_settingsSignOutDefaultsToCancelAndKeepsServer() async {
        let app = launch()
        openPassword(app)
        let username = app.descendants(matching: .any)["credentials.username"]
        typeText("Ada", into: username, in: app)
        let password = app.secureTextFields["credentials.password"]
        typeText("sample", into: password, in: app)
        activate(app.descendants(matching: .any)["credentials.signIn"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 10))
        // Settings is a catalog key used for the tab label on both platforms.
        activate(app.descendants(matching: .any).matching(identifier: "Settings").firstMatch, in: app)
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
        XCTAssertTrue(app.descendants(matching: .any)["home.root"].waitForExistence(timeout: 10))
        activate(app.descendants(matching: .any).matching(identifier: "Settings").firstMatch, in: app)
        XCTAssertTrue(signOut.waitForExistence(timeout: 10))
        activate(signOut, in: app)
        activate(app.descendants(matching: .any)["logout.confirm"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["login.quickConnect"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["login.serverName"].exists)
    }

    @MainActor
    private func launch(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["-uitest-mock-server", "-uitest-reset"] + arguments)
        app.launch()
        return app
    }

    @MainActor
    private func openAddress(_ app: XCUIApplication) {
        XCTAssertTrue(app.descendants(matching: .any)["welcome.connect"].waitForExistence(timeout: 20))
        activate(app.descendants(matching: .any)["welcome.connect"], in: app)
        XCTAssertTrue(app.descendants(matching: .any)["address.field"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func openPassword(_ app: XCUIApplication) {
        openAddress(app)
        let field = app.descendants(matching: .any)["address.field"]
        typeText("media.example", into: field, in: app)
        activate(app.descendants(matching: .any)["address.continue"], in: app)
        let password = app.descendants(matching: .any)["login.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 10))
        activate(password, in: app)
    }

    @MainActor
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

    /// Catalog key, not a translated sentence.
    @MainActor
    private var publicHTTPSKey: String {
        "Public addresses require HTTPS. Use an IP address, a .local name, or an HTTPS reverse proxy."
    }
}
