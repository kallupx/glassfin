import CoreModels
import CoreNetworking
import CoreTestSupport
import Foundation
import GlassfinServices
import XCTest

final class T06HomeServiceTests: XCTestCase {
    // T06-06, T06-07, T06-08: canonical endpoint parameters.
    func testT06_06_homeEndpointParametersMatchSpec() async throws {
        let client = MockAPIClient { _ in Data("[]".utf8) }
        let service = JellyfinLibraryService(client: client)
        _ = try await service.resume(limit: 20)
        _ = try await service.nextUp(limit: 20)
        _ = try await service.latest(in: "cccccccccccccccccccccccccccccccc", limit: 20)
        let calls = await client.calls
        XCTAssertEqual(calls.map(\.path), ["/UserItems/Resume", "/Shows/NextUp", "/Items/Latest"])
        for call in calls {
            XCTAssertEqual(call.query.first { $0.name == "limit" }?.value, "20")
        }
        XCTAssertEqual(calls[0].query.first { $0.name == "mediaTypes" }?.value, "Video")
        XCTAssertEqual(calls[0].query.first { $0.name == "fields" }?.value, "PrimaryImageAspectRatio,Overview")
        XCTAssertEqual(calls[0].query.first { $0.name == "enableUserData" }?.value, "true")
        XCTAssertEqual(calls[1].query.first { $0.name == "enableResumable" }?.value, "false")
        XCTAssertEqual(calls[1].query.first { $0.name == "enableRewatching" }?.value, "false")
        XCTAssertEqual(calls[2].query.first { $0.name == "groupItems" }?.value, "true")
    }
}
