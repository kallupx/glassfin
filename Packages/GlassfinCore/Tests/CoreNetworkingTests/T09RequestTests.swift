import CoreModels
import Foundation
import XCTest

@testable import CoreNetworking

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

final class T09RequestTests: XCTestCase {
    func testT09_07_queryEncodingRoundTripsSpecialCharactersAndSubpath() throws {
        let server = try XCTUnwrap(URL(string: "https://media.example/jellyfin/"))
        let client = HTTPJellyfinClient(
            server: server, identity: ClientIdentity(deviceName: "TV", deviceID: "test", version: "1"))
        for term in ["&", "#", "ä", "日本", "x&ApiKey=secret#fragment+ /?", "a+b"] {
            let request = try client.makeURLRequest(QueryTransport.searchHints(term: term, limit: 24))
            let parts = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
            XCTAssertEqual(parts.path, "/jellyfin/Search/Hints")
            XCTAssertEqual(parts.queryItems?.first { $0.name == "searchTerm" }?.value, term)
            if term.contains("+") { XCTAssertTrue(request.url?.absoluteString.contains("%2B") == true) }
            XCTAssertNil(parts.fragment)
            XCTAssertEqual(parts.queryItems?.count, 2)
        }
    }

    func testT09_25_transportFailureLogsNoSearchTextOrRawImageURL() async throws {
        let log = SearchLogSpy()
        let client = HTTPJellyfinClient(
            server: try XCTUnwrap(URL(string: "https://media.example")),
            identity: ClientIdentity(deviceName: "TV", deviceID: "test", version: "1"),
            transport: SearchFailingTransport(), log: log)
        let image = ItemImageRequest(
            serverID: "server", itemID: try XCTUnwrap(ItemID("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")),
            type: .primary, tag: "private-image-tag", width: 300, height: 450)
        for request in [QueryTransport.searchHints(term: "private-search-marker", limit: 24), image.request] {
            do { _ = try await client.send(request) } catch { XCTAssertEqual(error, .network) }
        }
        XCTAssertFalse(log.lines.isEmpty)
        XCTAssertFalse(log.lines.joined().contains("private-search-marker"))
        XCTAssertFalse(log.lines.joined().contains("private-image-tag"))
        XCTAssertFalse(log.lines.joined().contains("https://"))
    }

    func testT09_18_imageURLHasNoCredentialAndRequestCarriesAuthorization() throws {
        let server = try XCTUnwrap(URL(string: "https://media.example/jellyfin"))
        let identity = ClientIdentity(deviceName: "TV", deviceID: "test", version: "1", token: "secret-token")
        let client = HTTPJellyfinClient(server: server, identity: identity)
        let image = ItemImageRequest(
            serverID: "server", itemID: try XCTUnwrap(ItemID("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")),
            type: .primary, tag: "tag & #", width: 300, height: 450)
        let request = try client.makeURLRequest(image.request)
        let url = try XCTUnwrap(request.url)
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let names = parts.queryItems?.map { $0.name.lowercased() } ?? []
        for forbidden in ["apikey", "api" + "_key", "token"] { XCTAssertFalse(names.contains(forbidden)) }
        XCTAssertFalse(url.absoluteString.contains("secret-token"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), try identity.authorizationHeader())
        XCTAssertEqual(request.allHTTPHeaderFields?.keys.filter { $0.lowercased() == "authorization" }.count, 1)
        XCTAssertEqual(parts.queryItems?.first { $0.name == "tag" }?.value, "tag & #")
        XCTAssertEqual(parts.path, "/jellyfin/Items/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/Images/Primary")
        XCTAssertNil(client.session.configuration.urlCache)
    }
}

private struct SearchFailingTransport: RequestTransport {
    enum Failure: Error { case failed }
    func data(for request: URLRequest) async throws -> (Data, URLResponse, Int?) { throw Failure.failed }
}

private final class SearchLogSpy: GlassfinLog, @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []
    var lines: [String] { lock.withLock { messages } }
    func warning(_ message: String) { lock.withLock { messages.append(message) } }
    func debug(_ message: String) { lock.withLock { messages.append(message) } }
    func error(_ message: String) { lock.withLock { messages.append(message) } }
}
