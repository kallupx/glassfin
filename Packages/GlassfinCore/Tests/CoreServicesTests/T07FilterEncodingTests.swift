import CoreModels
import Foundation
import GlassfinServices
import XCTest

@testable import CoreNetworking

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

final class T07FilterEncodingTests: XCTestCase {
    /// T07-79/S6.5: exercise the service and real HTTP URL builder through a recording transport.
    func testT07_79_specialCharacterGenresAreEncodedAndRoundTripWithoutChangingThePath() async throws {
        let server = try XCTUnwrap(URL(string: "https://media.example/jellyfin/"))
        let transport = T07FilterTransport()
        let client = HTTPJellyfinClient(
            server: server, identity: ClientIdentity(deviceName: "TV", deviceID: "d", version: "1"),
            transport: transport)
        let service = JellyfinLibraryService(client: client)
        let genres = ["Drama & Comedy", "A=B", "Genre#1", "Action/Adventure", "\u{00E4} genre", "A &=#/\u{00E4} B"]
        for genre in genres {
            _ = try await service.items(
                in: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                query: ItemQuery(includeItemTypes: ["Movie"], sortBy: ["SortName"], genres: [genre]),
                page: PageRequest())
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, genres.count)
        for (request, genre) in zip(requests, genres) {
            XCTAssertEqual(request.httpMethod, "GET")
            let url = try XCTUnwrap(request.url)
            let parsed = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            XCTAssertEqual(parsed.scheme, "https")
            XCTAssertEqual(parsed.host, "media.example")
            XCTAssertEqual(parsed.path, "/jellyfin/Items")
            XCTAssertNil(parsed.fragment)
            XCTAssertEqual(
                parsed.queryItems?.filter { $0.name == "genres" }, [URLQueryItem(name: "genres", value: genre)])
            XCTAssertEqual(
                parsed.queryItems?.first { $0.name == "parentId" }?.value, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
            XCTAssertEqual(parsed.queryItems?.first { $0.name == "sortBy" }?.value, "SortName")
            XCTAssertEqual(parsed.queryItems?.count, 10)
            let encoded = try XCTUnwrap(parsed.percentEncodedQuery)
            for (character, escape) in [("&", "%26"), ("=", "%3D"), ("#", "%23"), ("\u{00E4}", "%C3%A4"), (" ", "%20")]
            {
                if genre.contains(character) { XCTAssertTrue(encoded.contains(escape), genre) }
            }
            // URLComponents permits '/' inside a query value; it must never create path components.
            if genre.contains("/") { XCTAssertTrue(encoded.contains("/") || encoded.contains("%2F")) }
        }
    }
}

private actor T07FilterTransport: RequestTransport {
    var requests: [URLRequest] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse, Int?) {
        requests.append(request)
        let url = try XCTUnwrap(request.url)
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        return (Data(#"{"Items":[],"TotalRecordCount":0}"#.utf8), response, nil)
    }
}
