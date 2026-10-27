import CoreModels
import XCTest

@testable import CorePlayback

final class MediaFailurePrecedenceTests: XCTestCase {
    /// T08-2-39. Cancellation after a media 401 preserves the unauthorized diagnostic.
    func testCancellationPreservesUnauthorized() {
        let first = MediaFailurePrecedence.recording(.unauthorized, after: nil)
        XCTAssertEqual(MediaFailurePrecedence.recording(.cancelled, after: first), .unauthorized)
    }

    /// T08-2-38. Cancellation never overwrites any previously recorded error.
    func testCancellationPreservesEveryStoredFailure() {
        for error: APIError in [
            .unauthorized, .forbidden, .notFound, .server(status: 503), .timeout, .network,
            .tls, .decoding, .cancelled, .redirectRejected(.notFollowed), .invalidURL,
            .headerRejected, .invalidItemID,
        ] {
            XCTAssertEqual(MediaFailurePrecedence.recording(.cancelled, after: error), error)
        }
    }

    /// T08-2-40. Cancellation remains visible when it is the first failure.
    func testInitialCancellationIsRecorded() {
        XCTAssertEqual(MediaFailurePrecedence.recording(.cancelled, after: nil), .cancelled)
    }

    /// T08-2-38. A later non-cancellation error still updates the diagnostic.
    func testNonCancellationUpdatesStoredFailure() {
        for previous: APIError? in [nil, .cancelled, .unauthorized, .network] {
            XCTAssertEqual(MediaFailurePrecedence.recording(.timeout, after: previous), .timeout)
        }
    }
}
