import CorePlayback
import Foundation
import XCTest

final class PlayerFailureDiagnosticTests: XCTestCase {
    func testIncludesItemAndUnderlyingDomainAndCodeOnly() {
        let underlying = NSError(
            domain: "CoreMediaErrorDomain", code: -12881,
            userInfo: [NSLocalizedDescriptionKey: "https://private.invalid/video?ApiKey=synthetic-secret"])
        let error = NSError(
            domain: "AVFoundationErrorDomain", code: -11800,
            userInfo: [NSUnderlyingErrorKey: underlying, NSURLErrorKey: URL(string: "https://private.invalid")!])
        XCTAssertEqual(
            PlayerFailureDiagnostic(error: error).description,
            "AVPlayer failure: AVFoundationErrorDomain(-11800) <- CoreMediaErrorDomain(-12881)")
    }

    func testUnknownDomainsCannotInjectURLsOrCredentials() {
        let error = NSError(domain: "https://private.invalid/?ApiKey=synthetic-secret", code: 401)
        XCTAssertEqual(PlayerFailureDiagnostic(error: error).description, "AVPlayer failure: <redacted-domain>(401)")
    }

    func testMissingErrorHasControlledSummary() {
        XCTAssertEqual(PlayerFailureDiagnostic(error: nil).description, "AVPlayer failure: item error unavailable")
    }

    func testNestedErrorsAreBounded() {
        var error = NSError(domain: NSURLErrorDomain, code: -1001)
        for index in 0..<10 {
            error = NSError(domain: "CoreMediaErrorDomain", code: index, userInfo: [NSUnderlyingErrorKey: error])
        }
        XCTAssertEqual(
            PlayerFailureDiagnostic(error: error).description,
            "AVPlayer failure: CoreMediaErrorDomain(9) <- CoreMediaErrorDomain(8) <- CoreMediaErrorDomain(7)"
                + " <- CoreMediaErrorDomain(6) <- CoreMediaErrorDomain(5)")
    }
}
