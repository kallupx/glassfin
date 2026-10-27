import CoreModels
import Foundation
import XCTest

final class T09MetadataTests: XCTestCase {
    func testT09_17_allLimitsCountGraphemesAfterCleaning() {
        for limit in [
            MetadataPolicy.overviewMax, MetadataPolicy.taglineMax,
            MetadataPolicy.genreMax, MetadataPolicy.nameMax, MetadataPolicy.displayNameMax,
        ] {
            for grapheme in ["👩🏽‍🚀", "e\u{301}"] {
                let source = "\u{202E}\u{0000}" + String(repeating: grapheme, count: limit) + "x"
                let cleaned = MetadataPolicy.clean(source, limit: limit)
                XCTAssertEqual(cleaned.count, limit)
                XCTAssertEqual(cleaned, String(repeating: grapheme, count: limit))
            }
        }
        XCTAssertEqual(MetadataPolicy.clean("<b>x</b>&amp;", limit: MetadataPolicy.nameMax), "<b>x</b>&amp;")
    }
}
