import CoreModels
import CoreNetworking
import CoreTestSupport
import Foundation
import GlassfinServices
import XCTest

final class T06HomeServiceTests: XCTestCase {
    // T06-06: Resume sends exactly the canonical video-row parameters.
    func testT06_06_resumeEndpointParametersMatchSpec() async throws {
        let client = MockAPIClient { _ in Data("[]".utf8) }
        _ = try await JellyfinLibraryService(client: client).resume(limit: 20)
        let calls = await client.calls
        XCTAssertEqual(calls.count, 1)
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(call.method, "GET")
        XCTAssertEqual(call.path, "/UserItems/Resume")
        XCTAssertEqual(
            parameters(call),
            [
                "mediaTypes": "Video", "limit": "20", "fields": "PrimaryImageAspectRatio,Overview",
                "enableImageTypes": "Primary,Backdrop,Thumb,Logo", "enableUserData": "true",
            ])
    }

    // T06-07: Next Up excludes resumable and rewatched episodes and requests the agreed fields.
    func testT06_07_nextUpEndpointParametersMatchSpec() async throws {
        let client = MockAPIClient { _ in Data("[]".utf8) }
        _ = try await JellyfinLibraryService(client: client).nextUp(limit: 20)
        let calls = await client.calls
        XCTAssertEqual(calls.count, 1)
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(call.method, "GET")
        XCTAssertEqual(call.path, "/Shows/NextUp")
        XCTAssertEqual(
            parameters(call),
            [
                "enableResumable": "false", "enableRewatching": "false", "limit": "20",
                "fields": "PrimaryImageAspectRatio,Overview", "enableImageTypes": "Primary,Backdrop,Thumb,Logo",
                "enableUserData": "true",
            ])
    }

    // T06-08: every Latest request has its own parent library, fixed cap and server grouping.
    func testT06_08_latestEndpointParametersMatchSpec() async throws {
        let client = MockAPIClient { _ in Data("[]".utf8) }
        let library = "cccccccccccccccccccccccccccccccc"
        _ = try await JellyfinLibraryService(client: client).latest(in: library, limit: 20)
        let calls = await client.calls
        XCTAssertEqual(calls.count, 1)
        let call = try XCTUnwrap(calls.first)
        XCTAssertEqual(call.method, "GET")
        XCTAssertEqual(call.path, "/Items/Latest")
        XCTAssertEqual(parameters(call), ["parentId": library, "limit": "20", "groupItems": "true"])
    }

    private func parameters(_ request: MockAPIClient.Call) -> [String: String] {
        Dictionary(uniqueKeysWithValues: request.query.map { ($0.name, $0.value ?? "") })
    }
}
