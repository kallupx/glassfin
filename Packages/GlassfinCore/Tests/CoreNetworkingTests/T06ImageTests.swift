import CoreModels
import Foundation
import XCTest

@testable import CoreNetworking

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

final class T06ImageTests: XCTestCase {
    private let resource = JellyfinImageResource(
        serverID: "server", itemID: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", type: .primary,
        tag: "a&b?#", width: 250, height: 375)

    // T06-71: canonical spec/TESTPLAN-M06.md.
    func testT06_71_imageURLHasNoCredentialQueryAndRequestHasAuthorization() throws {
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
        XCTAssertEqual(try resource.request().maximumResponseBytes, MetadataPolicy.imageMaxBytes)
        // T06-29: all image types request displayed dimensions, already multiplied by display scale.
        for type in [ItemImageType.primary, .thumb, .logo, .backdrop] {
            let image = JellyfinImageResource(
                serverID: resource.serverID, itemID: resource.itemID, type: type, tag: "t", width: 500, height: 750)
            let call = try image.request()
            XCTAssertEqual(call.query.first { $0.name == "maxWidth" }?.value, "500")
            XCTAssertEqual(call.query.first { $0.name == "maxHeight" }?.value, "750")
            let built = try client.makeURLRequest(call)
            XCTAssertNotNil(built.value(forHTTPHeaderField: "Authorization"))
            XCTAssertFalse(try XCTUnwrap(built.url).absoluteString.contains("secret"))
        }
    }

    // T06-71: canonical spec/TESTPLAN-M06.md.
    func testT06_71_inheritedCredentialQueriesAreRejected() throws {
        for name in ["token", "Token", "ApiKey", "api" + "_key"] {
            let server = try XCTUnwrap(URL(string: "https://media.example?\(name)=secret"))
            let client = HTTPJellyfinClient(
                server: server, identity: ClientIdentity(deviceName: "TV", deviceID: "d", version: "1", token: "secret")
            )
            XCTAssertThrowsError(try client.makeURLRequest(resource.request()))
        }
    }

    // T06-72: canonical spec/TESTPLAN-M06.md.
    func testT06_72_imageCacheKeyIsStableSHA256OfIdentityTuple() {
        let expected = CertificateFingerprint.sha256Hex(
            Data("6:server32:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa7:Primary5:a&b?#3:2503:375".utf8))
        XCTAssertEqual(resource.cacheKey, expected)
        XCTAssertEqual(resource.cacheKey.count, 64)
        XCTAssertEqual(resource.cacheKey, resource.cacheKey)
        let other = JellyfinImageResource(
            serverID: "other", itemID: resource.itemID, type: .primary, tag: resource.tag, width: 250, height: 375)
        XCTAssertNotEqual(resource.cacheKey, other.cacheKey)
        for changed in [
            JellyfinImageResource(
                serverID: resource.serverID, itemID: resource.itemID, type: .thumb, tag: resource.tag, width: 250,
                height: 375),
            JellyfinImageResource(
                serverID: resource.serverID, itemID: resource.itemID, type: .primary, tag: "new", width: 250,
                height: 375),
            JellyfinImageResource(
                serverID: resource.serverID, itemID: resource.itemID, type: .primary, tag: resource.tag, width: 500,
                height: 750),
        ] {
            XCTAssertNotEqual(resource.cacheKey, changed.cacheKey)
        }
    }

    // T06-82: canonical spec/TESTPLAN-M06.md.
    func testT06_82_imageByteLimitRejectsOversize() throws {
        try ImageDataPolicy.validate(Data(count: MetadataPolicy.imageMaxBytes))
        XCTAssertThrowsError(try ImageDataPolicy.validate(Data(count: MetadataPolicy.imageMaxBytes + 1))) {
            XCTAssertEqual($0 as? ImageDataError, .oversized)
        }
        let invalid = JellyfinImageResource(
            serverID: "s", itemID: "../bad", type: .primary, tag: "", width: 1, height: 1)
        XCTAssertThrowsError(try invalid.request())
    }
}
