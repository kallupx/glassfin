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

    /// T09-64: final S6.1/S6.7 budgets and all public metadata paths preserve markup/entities.
    func testT09_64_sharedConstantsAndDisplayNamesKeepLiteralMarkup() throws {
        XCTAssertEqual(
            [
                MetadataPolicy.overviewMax, MetadataPolicy.taglinesMax, MetadataPolicy.taglineMax,
                MetadataPolicy.genresMax, MetadataPolicy.genreMax, MetadataPolicy.nameMax,
                MetadataPolicy.displayNameMax, MetadataPolicy.recentSearchesMax, MetadataPolicy.imageMaxBytes,
            ],
            [2000, 3, 200, 10, 64, 200, 64, 20, 20 * 1024 * 1024])
        let literal = "<script>x</script>&amp;&#x202E; **title** [link](https://e.test)"
        let raw = "\u{202E}\u{0000}" + literal
        XCTAssertEqual(MetadataSanitizer.plainText(raw), literal)
        let server = ServerInfo(
            id: "server", name: raw, url: try XCTUnwrap(URL(string: "https://media.example")),
            version: SemVer(major: 12, minor: 2, patch: 0))
        XCTAssertEqual(server.name, String(literal.prefix(MetadataPolicy.displayNameMax)))
        XCTAssertEqual(PublicUser(id: "user", name: raw).name, server.name)
        let data = Data("{\"Id\":\"id\",\"Name\":\"<b>x</b>&amp;\",\"Overview\":\"<p>text</p>&lt;\"}".utf8)
        let item = try XCTUnwrap(
            DTOMapper.mediaItem(JSONDecoder().decode(BaseItemDTO.self, from: data), log: SilentLog()))
        XCTAssertEqual(item.name, "<b>x</b>&amp;")
        XCTAssertEqual(item.overview, "<p>text</p>&lt;")
    }
}
