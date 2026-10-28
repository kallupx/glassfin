import XCTest

/// Activates a control using the interaction supported by the test platform.
@MainActor
@discardableResult
func activate(
    _ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
) -> Bool {
    guard element.waitForExistence(timeout: 10) else {
        XCTFail("Element '\(element.identifier)' did not appear before activation", file: file, line: line)
        return false
    }
    #if os(tvOS)
        guard moveFocus(to: element, in: app, file: file, line: line) else { return false }
        // Native tabs select their content as focus moves onto them. Home can
        // immediately restore focus to a card, so an extra Select would open it.
        if !element.identifier.hasPrefix("design.tab.") {
            XCUIRemote.shared.press(.select)
        }
    #elseif os(iOS)
        element.tap()
    #endif
    return true
}

/// Opens the field's editor and returns to the form after typing on tvOS.
@MainActor
@discardableResult
func typeText(
    _ text: String, into element: XCUIElement, in app: XCUIApplication,
    file: StaticString = #filePath, line: UInt = #line
) -> Bool {
    #if os(tvOS)
        // A field can open its editor automatically when the screen gains focus.
        // Close that editor first so activation always targets the requested field.
        guard dismissKeyboard(in: app, for: element, file: file, line: line) else { return false }
        guard activate(element, in: app, file: file, line: line) else { return false }
        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 5) else {
            XCTFail("Keyboard did not appear for element '\(element.identifier)'", file: file, line: line)
            return false
        }
        // The fullscreen system editor owns keyboard focus, rather than the form field.
        app.typeText(text)
        return dismissKeyboard(in: app, for: element, file: file, line: line)
    #elseif os(iOS)
        guard activate(element, in: app, file: file, line: line) else { return false }
        element.typeText(text)
        return true
    #endif
}

#if os(tvOS)
    @MainActor
    private func dismissKeyboard(
        in app: XCUIApplication, for element: XCUIElement, file: StaticString, line: UInt
    ) -> Bool {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return true }
        // Menu closes the system editor, preserving the entered text. Only send it
        // while the keyboard is present, so it cannot invoke the form's back action.
        XCUIRemote.shared.press(.menu)
        guard keyboard.waitForNonExistence(timeout: 5) else {
            XCTFail("Keyboard did not close for element '\(element.identifier)'", file: file, line: line)
            return false
        }
        return true
    }

    @MainActor
    private func moveFocus(
        to element: XCUIElement, in app: XCUIApplication, file: StaticString, line: UInt
    ) -> Bool {
        let maxAttempts = 64
        var attempts: [String: [XCUIRemote.Button: Int]] = [:]
        for _ in 0..<maxAttempts {
            if element.hasFocus { return true }
            let focused = app.descendants(matching: .any)
                .matching(NSPredicate(format: "hasFocus == true")).firstMatch
            let directions: [XCUIRemote.Button]
            let focusID: String
            if focused.exists {
                let frame = focused.frame
                let target = element.frame
                let dx = target.midX - frame.midX
                let dy = target.midY - frame.midY
                let horizontal: XCUIRemote.Button = dx < 0 ? .left : .right
                let vertical: XCUIRemote.Button = dy < 0 ? .up : .down
                let oppositeHorizontal: XCUIRemote.Button = dx < 0 ? .right : .left
                let oppositeVertical: XCUIRemote.Button = dy < 0 ? .down : .up
                directions =
                    abs(dy) >= abs(dx)
                    ? [vertical, horizontal, oppositeHorizontal, oppositeVertical]
                    : [horizontal, vertical, oppositeVertical, oppositeHorizontal]
                focusID = "\(focused.elementType.rawValue):\(focused.identifier):\(frame)"
            } else {
                directions = [.down, .up, .left, .right]
                focusID = "no-focus"
            }
            // Prefer movement toward the target, but explore other directions if
            // an edge or a focus cycle prevents progress (including tab bars).
            let tried = attempts[focusID, default: [:]]
            let direction = directions.min { tried[$0, default: 0] < tried[$1, default: 0] } ?? .down
            attempts[focusID, default: [:]][direction, default: 0] += 1
            XCUIRemote.shared.press(direction)
        }
        if element.hasFocus { return true }
        XCTFail(
            "Could not focus element '\(element.identifier)' after \(maxAttempts) remote presses",
            file: file, line: line)
        return false
    }
#endif
