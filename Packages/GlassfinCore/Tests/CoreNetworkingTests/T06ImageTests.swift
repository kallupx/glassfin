import CoreModels
import Foundation
import XCTest

@testable import CoreNetworking

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

final class T06ImageTests: XCTestCase {
    private let resource = ImageResource(
        serverID: "server", itemID: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", type: .primary,
        tag: "a&b?#", width: 250, height: 375)

    func testT06_20_imageURLHasNoCredentialQueryAndRequestHasAuthorization() throws {
        let client = HTTPJellyfinClient(
            server: try XCTUnwrap(URL(string: "https://media.example/jellyfin")),
            identity: ClientIdentity(deviceName: "TV", deviceID: "device", version: "1", token: "secret"))
        let request = try client.makeURLRequest(resource.request())
        let url = try XCTUnwrap(request.url)
        let names = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.map { $0.name.lowercased() }
        XCTAssertEqual(Set(names ?? []), Set(["tag", "maxwidth", "maxheight"]))
        XCTAssertFalse(url.absoluteString.contains("secret"))
        XCTAssertTrue(request.value(forHTTPHeaderField: "Authorization")?.contains("Token=\"secret\"") == true)
        XCTAssertTrue(url.path.hasSuffix("/Images/Primary"))
        XCTAssertEqual(client.session.configuration.urlCache, nil)
    }

    func testT06_20_inheritedCredentialQueriesAreRejected() throws {
        for name in ["token", "Token", "ApiKey", "api" + "_key"] {
            let server = try XCTUnwrap(URL(string: "https://media.example?\(name)=secret"))
            let client = HTTPJellyfinClient(
                server: server, identity: ClientIdentity(deviceName: "TV", deviceID: "d", version: "1", token: "secret")
            )
            XCTAssertThrowsError(try client.makeURLRequest(resource.request()))
        }
    }

    func testT06_21_imageCacheKeyIsStableSHA256OfIdentityTuple() {
        let expected = CertificateFingerprint.sha256Hex(
            Data("6:server32:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa7:Primary5:a&b?#3:2503:375".utf8))
        XCTAssertEqual(resource.cacheKey, expected)
        XCTAssertEqual(resource.cacheKey.count, 64)
        XCTAssertEqual(resource.cacheKey, resource.cacheKey)
        let other = ImageResource(
            serverID: "other", itemID: resource.itemID, type: .primary, tag: resource.tag, width: 250, height: 375)
        XCTAssertNotEqual(resource.cacheKey, other.cacheKey)
    }

    func testT06_22_imageByteLimitRejectsOversize() throws {
        try ImageDataPolicy.validate(Data(count: MetadataPolicy.imageMaxBytes))
        XCTAssertThrowsError(try ImageDataPolicy.validate(Data(count: MetadataPolicy.imageMaxBytes + 1))) {
            XCTAssertEqual($0 as? ImageDataError, .oversized)
        }
        let invalid = ImageResource(serverID: "s", itemID: "../bad", type: .primary, tag: "", width: 1, height: 1)
        XCTAssertThrowsError(try invalid.request())
    }
}
