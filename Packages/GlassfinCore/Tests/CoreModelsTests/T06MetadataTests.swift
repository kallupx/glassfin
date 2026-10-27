import CoreModels
import XCTest

final class T06MetadataTests: XCTestCase {
    func testT06_23_metadataPreservesLiteralMarkupAndEntities() {
        let source = "\u{202e}<b>x</b>&amp;<script>x</script>\u{0007}"
        XCTAssertEqual(MetadataPolicy.clean(source, limit: MetadataPolicy.nameMax), "<b>x</b>&amp;<script>x</script>")
        XCTAssertEqual(MetadataSanitizer.plainText(source), "<b>x</b>&amp;<script>x</script>")
    }

    func testT06_24_limitsCountCleanedGraphemeClusters() {
        let pair = "👩‍👩‍👧‍👦e\u{0301}"
        for limit in [
            MetadataPolicy.nameMax, MetadataPolicy.overviewMax, MetadataPolicy.taglineMax,
            MetadataPolicy.genreMax, MetadataPolicy.displayNameMax,
        ] {
            let source = "\u{202e}\u{0007}" + String(repeating: pair, count: limit)
            let cleaned = MetadataPolicy.clean(source, limit: limit)
            XCTAssertEqual(cleaned.count, limit)
            XCTAssertEqual(cleaned, String(String(repeating: pair, count: limit).prefix(limit)))
        }
        XCTAssertEqual(MetadataPolicy.taglinesMax, 3)
        XCTAssertEqual(MetadataPolicy.genresMax, 10)
        XCTAssertEqual(MetadataPolicy.recentSearchesMax, 20)
    }
}
