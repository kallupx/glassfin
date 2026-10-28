import CoreModels
import Foundation
import XCTest

final class SecurityNameTests: XCTestCase {
    private let url = URL(string: "https://media.example")!

    func testQ416_sharedSanitizerStripsAllControlCharactersAfterEntityDecoding() {
        let raw = "A\u{0000}\u{0007}\n\r\t\u{007F}\u{0085}\u{009F}B&#x07;"
        XCTAssertEqual(MetadataSanitizer.plainText(raw), "AB")
        XCTAssertEqual(server(raw).name, "AB")
        XCTAssertEqual(PublicUser(id: "user", name: raw, host: "media.example").name, "AB")
    }

    func testQ416_sharedSanitizerStripsEveryBidiControl() {
        let controls = [
            0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
            0x2066, 0x2067, 0x2068, 0x2069,
        ]
        let raw = "A" + controls.compactMap(Unicode.Scalar.init).map(String.init).joined() + "B&#x202e;"
        XCTAssertEqual(MetadataSanitizer.plainText(raw), "AB")
        XCTAssertEqual(server(raw).name, "AB")
        XCTAssertEqual(PublicUser(id: "user", name: raw).name, "AB")
    }

    func testQ416_limitCountsGraphemeClustersAndPreservesEmojiAndCombiningMarks() {
        let pair = "👩‍👩‍👧‍👦e\u{0301}"
        let raw = String(repeating: pair, count: 40)
        let expected = String(repeating: pair, count: 32)
        XCTAssertEqual(server(raw).name, expected)
        XCTAssertEqual(server(raw).name.count, 64)
        XCTAssertEqual(PublicUser(id: "user", name: raw).name, expected)
        XCTAssertGreaterThan(expected.unicodeScalars.count, 64)
    }

    func testQ416_markdownLookingNamesStayLiteralAtModelLevel() {
        let raw = "**Home** _Ada_ [link](https://example.test) `code`"
        XCTAssertEqual(server(raw).name, raw)
        XCTAssertEqual(PublicUser(id: "user", name: raw).name, raw)
    }

    func testQ416_emptyOrWhitespaceOnlySanitizedNamesFallBackToHost() {
        for raw in ["", " \t\n\r", "\u{00A0}\u{2003}", "<b> </b>\u{202E}\u{0007}"] {
            XCTAssertEqual(server(raw).name, "media.example")
            XCTAssertEqual(PublicUser(id: "user", name: raw, host: "media.example").name, "media.example")
        }
    }

    func testQ416_longFallbackHostAlsoRespectsTheDisplayLimit() {
        let host = String(repeating: "a", count: 50) + "." + String(repeating: "b", count: 50) + ".example"
        let info = ServerInfo(
            id: "server", name: " ", url: URL(string: "https://" + host)!,
            version: SemVer(major: 10, minor: 11, patch: 0))
        XCTAssertEqual(info.name, String(host.prefix(64)))
        XCTAssertEqual(PublicUser(id: "user", name: " ", host: host).name, String(host.prefix(64)))
    }

    func testQ416_mutatingNamesStillUsesTheSharedDisplayRules() {
        var info = server("Home")
        info.name = "<b>A</b>\u{202E}\u{0007}"
        XCTAssertEqual(info.name, "A")
        var user = PublicUser(id: "user", name: "Ada", host: "media.example")
        user.name = " \u{202E}"
        XCTAssertEqual(user.name, "media.example")
    }

    func testQ416_decodingPreviouslyStoredServerNamesAlsoSanitizes() throws {
        let encoded = try JSONEncoder().encode(server("Home"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["name"] = "<b>Home</b>\u{202E}\u{0007}"
        let decoded = try JSONDecoder().decode(ServerInfo.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.name, "Home")
    }

    private func server(_ name: String) -> ServerInfo {
        ServerInfo(id: "server", name: name, url: url, version: SemVer(major: 10, minor: 11, patch: 0))
    }
}
