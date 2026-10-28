import CoreModels
import Foundation
import XCTest

final class T09MetadataTests: XCTestCase {
    /// T09-64: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.
    func testT09_64_allLimitsCountGraphemesAfterCleaning() {
        for limit in [
            MetadataPolicy.overviewMax, MetadataPolicy.taglineMax,
            MetadataPolicy.genreMax, MetadataPolicy.nameMax, MetadataPolicy.displayNameMax,
        ] {
            for grapheme in ["👩🏽‍🚀", "e\u{301}"] {
                for count in [limit - 1, limit, limit + 1] {
                    let source = "\u{202E}\u{200F}\u{0000}" + String(repeating: grapheme, count: count)
                    let cleaned = MetadataPolicy.clean(source, limit: limit)
                    XCTAssertEqual(cleaned.count, min(count, limit))
                    XCTAssertEqual(cleaned, String(repeating: grapheme, count: min(count, limit)))
                }
            }
        }
        XCTAssertEqual(MetadataPolicy.clean("<b>x</b>&amp;", limit: MetadataPolicy.nameMax), "<b>x</b>&amp;")
    }

    /// T09-64: S6.1/S6.7 media stays literal; server/user display names follow M04 sanitization.
    func testT09_64_literalMediaAndSanitizedDisplayNames() throws {
        XCTAssertEqual(
            [
                MetadataPolicy.overviewMax, MetadataPolicy.taglinesMax, MetadataPolicy.taglineMax,
                MetadataPolicy.genresMax, MetadataPolicy.genreMax, MetadataPolicy.nameMax,
                MetadataPolicy.displayNameMax, MetadataPolicy.recentSearchesMax, MetadataPolicy.imageMaxBytes,
            ],
            [2000, 3, 200, 10, 64, 200, 64, 20, 20 * 1024 * 1024])
        let literal = "<script>x</script>&amp;&#x202E; **title** [link](https://e.test)"
        let raw = "\u{202E}\u{0000}" + literal
        let displayName = "& **title** [link](https://e.test)"
        XCTAssertEqual(MetadataSanitizer.displayText(raw, limit: MetadataPolicy.nameMax), literal)
        XCTAssertEqual(MetadataSanitizer.plainText(raw), displayName)
        let server = ServerInfo(
            id: "server", name: raw, url: try XCTUnwrap(URL(string: "https://media.example")),
            version: SemVer(major: 12, minor: 2, patch: 0))
        XCTAssertEqual(server.name, displayName)
        XCTAssertEqual(PublicUser(id: "user", name: raw).name, server.name)
        let data = Data("{\"Id\":\"id\",\"Name\":\"<b>x</b>&amp;\",\"Overview\":\"<p>text</p>&lt;\"}".utf8)
        let item = try XCTUnwrap(
            DTOMapper.mediaItem(JSONDecoder().decode(BaseItemDTO.self, from: data), log: SilentLog()))
        XCTAssertEqual(item.name, "<b>x</b>&amp;")
        XCTAssertEqual(item.overview, "<p>text</p>&lt;")

        let longName = "\u{202E}\u{0000}" + literal + String(repeating: "e\u{301}👩🏽‍🚀", count: 200)
        let expected = MetadataSanitizer.displayText(longName, limit: MetadataPolicy.nameMax)
        let resultData = try JSONSerialization.data(withJSONObject: ["Id": "id", "Name": longName])
        let result = try XCTUnwrap(
            DTOMapper.mediaItem(JSONDecoder().decode(BaseItemDTO.self, from: resultData), log: SilentLog()))
        let hintData = try JSONSerialization.data(withJSONObject: [
            "SearchHints": [["ItemId": "id", "Name": longName, "Type": "Movie"]]
        ])
        let hint = try XCTUnwrap(ResilientItemDecoder.searchHints(from: hintData, log: SilentLog()).first)
        for name in [result.name, hint.name, MediaItem(id: "id", kind: .movie, name: longName).searchDisplayItem.name] {
            XCTAssertEqual(name, expected)
            XCTAssertEqual(name.count, 200)
        }
    }
}
