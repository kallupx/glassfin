import CoreModels
import XCTest

final class T06MetadataTests: XCTestCase {
    // T06-73: canonical spec/TESTPLAN-M06.md.
    func testT06_73_metadataPreservesLiteralMarkupAndEntities() {
        let literal = "<b>x</b>&amp;<script>x</script>**x**[x](https://example.invalid)"
        let source = "\u{202e}\u{200f}\u{0000}" + literal + "\u{0007}"
        XCTAssertEqual(MetadataPolicy.clean(source, limit: MetadataPolicy.nameMax), literal)
        XCTAssertEqual(MetadataSanitizer.plainText(source), literal)
    }

    // T06-73: canonical spec/TESTPLAN-M06.md.
    func testT06_73_limitsCountCleanedGraphemeClusters() {
        let pair = "👩‍👩‍👧‍👦e\u{0301}"
        for limit in [
            MetadataPolicy.nameMax, MetadataPolicy.overviewMax, MetadataPolicy.taglineMax,
            MetadataPolicy.genreMax, MetadataPolicy.displayNameMax,
        ] {
            for count in [limit - 1, limit, limit + 1] {
                let payload = String(String(repeating: pair, count: count).prefix(count))
                let source = "\u{202e}\u{0007}" + payload
                let cleaned = MetadataPolicy.clean(source, limit: limit)
                XCTAssertEqual(cleaned.count, min(count, limit))
                XCTAssertEqual(cleaned, String(payload.prefix(limit)))
            }
        }
        XCTAssertEqual(MetadataPolicy.overviewMax, 2000)
        XCTAssertEqual(MetadataPolicy.taglineMax, 200)
        XCTAssertEqual(MetadataPolicy.genreMax, 64)
        XCTAssertEqual(MetadataPolicy.nameMax, 200)
        XCTAssertEqual(MetadataPolicy.displayNameMax, 64)
        XCTAssertEqual(MetadataPolicy.imageMaxBytes, 20 * 1024 * 1024)
        XCTAssertEqual(MetadataPolicy.taglinesMax, 3)
        XCTAssertEqual(MetadataPolicy.genresMax, 10)
        XCTAssertEqual(MetadataPolicy.recentSearchesMax, 20)
    }
}
