import CoreModels
import XCTest

final class MetadataSanitizerTests: XCTestCase {
    func testServerVersionSanitizerStripsControlAndBidiAndCapsAt200Graphemes() {
        let raw = "10.\n11.\u{202E}11\u{0000}"
        let sanitized = MetadataSanitizer.displayText(raw, limit: 200)
        XCTAssertEqual(sanitized, "10.11.11")
        for scalar in ["\n", "\u{202E}", "\u{0000}"].joined().unicodeScalars {
            XCTAssertFalse(sanitized.unicodeScalars.contains(scalar))
        }

        let graphemePair = "👩‍👩‍👧e\u{0301}"
        let cleaned = String(repeating: graphemePair, count: 110)
        XCTAssertGreaterThan(cleaned.count, 200)
        let longRaw = "\n\u{202E}" + cleaned + "\u{0000}"
        let capped = MetadataSanitizer.displayText(longRaw, limit: 200)
        XCTAssertEqual(capped.count, 200)
        XCTAssertGreaterThan(capped.unicodeScalars.count, 200)
        XCTAssertEqual(capped, String(repeating: graphemePair, count: 100))
        XCTAssertTrue(cleaned.hasPrefix(capped))
        XCTAssertEqual(Array(capped), Array(cleaned.prefix(200)))
    }
}
