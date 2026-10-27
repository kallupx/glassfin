import CoreModels
import Foundation
import XCTest

@testable import CoreNetworking

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

final class T07ImageTests: XCTestCase {
    func testT07_22_imageURLHasNoCredentialQueryAndRequestUsesAuthorization() throws {
        let descriptor = LibraryImageRequest(
            serverID: "server", itemID: try XCTUnwrap(ItemID("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")),
            type: .primary, tag: "image tag", width: 250, height: 375)
        let client = HTTPJellyfinClient(
            server: try XCTUnwrap(URL(string: "https://media.example/jellyfin")),
            identity: ClientIdentity(deviceName: "TV", deviceID: "device", version: "1", token: "secret"))
        let request = try client.makeURLRequest(descriptor.apiRequest)
        let url = try XCTUnwrap(request.url)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertFalse(query.contains { ["apikey", "api" + "_key", "token"].contains($0.name.lowercased()) })
        XCTAssertFalse(url.absoluteString.contains("secret"))
        XCTAssertTrue(try XCTUnwrap(request.value(forHTTPHeaderField: "Authorization")).contains("Token=\"secret\""))
        XCTAssertEqual(descriptor.apiRequest.maximumResponseBytes, MetadataPolicy.imageMaxBytes)
        XCTAssertEqual(url.path, "/jellyfin/Items/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/Images/Primary")
    }

    func testT07_23_cacheKeyIsStableSHA256OfTheWholeTuple() throws {
        let item = try XCTUnwrap(ItemID("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
        let request = LibraryImageRequest(serverID: "s", itemID: item, type: .primary, tag: "t", width: 250, height: 375)
        let framed = "1:s32:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa7:Primary1:t3:2503:375"
        XCTAssertEqual(request.cacheKey, CertificateFingerprint.sha256Hex(Data(framed.utf8)))
        XCTAssertEqual(request.cacheKey.count, 64)
        XCTAssertEqual(request.cacheKey, request.cacheKey)
        for other in [
            LibraryImageRequest(serverID: "other", itemID: item, type: .primary, tag: "t", width: 250, height: 375),
            LibraryImageRequest(serverID: "s", itemID: item, type: .logo, tag: "t", width: 250, height: 375),
            LibraryImageRequest(serverID: "s", itemID: item, type: .primary, tag: "new", width: 250, height: 375),
            LibraryImageRequest(serverID: "s", itemID: item, type: .primary, tag: "t", width: 500, height: 750),
        ] { XCTAssertNotEqual(other.cacheKey, request.cacheKey) }
    }

    func testT07_24_HTTPClientRejectsOversizeImage() async throws {
        let url = try XCTUnwrap(URL(string: "https://media.example"))
        let client = HTTPJellyfinClient(
            server: url, identity: ClientIdentity(deviceName: "TV", deviceID: "d", version: "1"),
            transport: OversizeImageTransport(url: url))
        do {
            _ = try await client.send(APIRequest(method: "GET", path: "/image", maximumResponseBytes: MetadataPolicy.imageMaxBytes))
            XCTFail("Oversize image accepted")
        } catch { XCTAssertEqual(error, .decoding) }
    }
}

private struct OversizeImageTransport: RequestTransport {
    let url: URL
    func data(for request: URLRequest) async throws -> (Data, URLResponse, Int?) {
        (Data(repeating: 0, count: MetadataPolicy.imageMaxBytes + 1),
         HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
    }
}
