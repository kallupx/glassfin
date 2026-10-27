import CorePlayback
import XCTest

final class MediaLogRedactorTests: XCTestCase {
    /// T08-2-26. Escaped JSON quotes must not hide an AccessToken value.
    func testEscapedJSON() {
        assertRedacted(#"{\"AccessToken\":\"secret-value\"}"#)
    }

    /// T08-2-26. A literal question mark may precede an encoded equals sign.
    func testLiteralQuestionMarkWithEncodedEquals() {
        assertRedacted("https://example.invalid/v?ApiKey%3Dsecret-value")
    }

    /// T08-2-26. A literal ampersand may precede an encoded equals sign.
    func testLiteralAmpersandWithEncodedEquals() {
        assertRedacted("https://example.invalid/v?x=1&ApiKey%3Dsecret-value")
    }

    /// T08-2-26. Two percent-encoding layers must not hide a query credential.
    func testDoubleEncodedQuery() {
        assertRedacted(
            "%2526ApiKey%253D%2573ecret%252Dvalue", encodedSecrets: ["%2573ecret%252Dvalue", "%73ecret%2Dvalue"])
    }

    /// T08-2-26. The legacy Emby JSON key is a credential key too.
    func testJSONEmbyToken() {
        assertRedacted("{\"X-Emby-" + "Token\":\"secret-value\"}")
    }

    /// T08-2-26. The legacy MediaBrowser JSON key is a credential key too.
    func testJSONMediaBrowserToken() {
        assertRedacted("{\"X-MediaBrowser-" + "Token\":\"secret-value\"}")
    }

    /// T08-2-26. Credential names are case insensitive in every supported form.
    func testMixedCaseKeys() {
        for input in [
            #"{\"aCcEsStOkEn\":\"secret-value\"}"#,
            "?aPiKeY%3dsecret-value", "%2526tOkEn%253dsecret-value",
            "{\"x-eMbY-tOkEn\":\"secret-value\"}",
            "x-mEdIaBrOwSeR-tOkEn: secret-value",
        ] {
            assertRedacted(input)
        }
    }

    /// T08-2-26. Both legacy token headers are redacted without consuming adjacent lines.
    func testLegacyTokenHeaderLines() {
        for name in ["X-Emby-" + "Token", "X-MediaBrowser-" + "Token"] {
            let input = "Before: ok\r\n\(name): secret-value\r\nAfter: ok"
            assertRedacted(input)
            XCTAssertEqual(MediaLogRedactor.redact(input), "Before: ok\r\n\(name): <redacted>\r\nAfter: ok")
        }
    }

    /// T08-2-26. All credential keys share the same matching rules.
    func testCredentialKeyListAcrossForms() {
        for name in [
            "token", "ApiKey", "api" + "_key", "AccessToken",
            "X-Emby-" + "Token", "X-MediaBrowser-" + "Token", "secret", "pw",
        ] {
            for input in [
                "?\(name)=secret-value", "&\(name)%3Dsecret-value", "%26\(name)%3Dsecret-value",
                "{\"\(name)\":\"secret-value\"}", "{\\\"\(name)\\\":\\\"secret-value\\\"}",
            ] {
                assertRedacted(input)
            }
        }
    }

    /// T08-2-26. A newly revealed credential selects the decoded view, with at most two decodes.
    func testDecodedViewIsRedactedAndDecodingIsBounded() {
        let input = "%2526%2541piKey%253D%2573ecret%252Dvalue&note=%252541"
        assertRedacted(input, encodedSecrets: ["%2573ecret%252Dvalue", "%73ecret%2Dvalue"])
        XCTAssertEqual(MediaLogRedactor.redact(input), "&ApiKey=<redacted>&note=%41")
        XCTAssertEqual(MediaLogRedactor.redact("note=%252541"), "note=%252541")
    }

    private func assertRedacted(
        _ input: String, encodedSecrets: [String] = [], file: StaticString = #filePath, line: UInt = #line
    ) {
        let output = MediaLogRedactor.redact(input)
        for secret in ["secret-value"] + encodedSecrets {
            XCTAssertFalse(output.contains(secret), file: file, line: line)
        }
        XCTAssertTrue(output.contains("<redacted>"), file: file, line: line)
    }
}
