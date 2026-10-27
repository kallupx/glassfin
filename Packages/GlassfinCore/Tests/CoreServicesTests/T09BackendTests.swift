import CoreAPI
import CoreModels
import CoreNetworking
import Foundation
import GlassfinServices
import XCTest

final class T09BackendTests: XCTestCase, @unchecked Sendable {
    /// T09-23: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.
    func testT09_23_threeItemsRequestsStartInParallelWithIndependentLimits() async throws {
        let client = SearchRequestGate()
        let work = Task {
            try await ItemsSearchBackend(client: client).results(
                term: "star", kind: nil, page: PageRequest(limit: SearchPolicy.pageSize))
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while client.requests.count < 3 && ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertEqual(client.requests.count, 3, "All requests must start before any response is released")
        client.releaseAll()
        let response = try await work.value
        XCTAssertEqual(response.groups.map(\.id), SearchKind.allCases)
        XCTAssertEqual(response.groups.map { $0.items.count }, [2, 2, 2])
        for request in client.requests {
            XCTAssertEqual(request.path, "/Items")
            XCTAssertEqual(request.query.first { $0.name == "limit" }?.value, String(SearchPolicy.pageSize))
            XCTAssertEqual(request.query.first { $0.name == "fields" }?.value, "PrimaryImageAspectRatio")
            XCTAssertEqual(request.query.first { $0.name == "enableUserData" }?.value, "true")
            XCTAssertEqual(request.query.first { $0.name == "recursive" }?.value, "true")
        }
        XCTAssertEqual(
            Set(client.requests.compactMap { $0.query.first { $0.name == "includeItemTypes" }?.value }),
            Set(SearchKind.allCases.map(\.rawValue)))
    }

    /// T09-26: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    func testT09_26_bothBackendsPassSpecialTermsAsQueryItems() async throws {
        let client = SearchRequestGate(open: true)
        for backend: any SearchBackend in [ItemsSearchBackend(client: client), SearchHintsBackend(client: client)] {
            for term in ["&", "#", "ä", "日本", "a&b#c?x=y+z/%"] {
                _ = try await backend.results(term: term, kind: nil, page: PageRequest(limit: SearchPolicy.pageSize))
                for request in client.requests.suffix(requestCount(backend)) {
                    XCTAssertEqual(request.query.first { $0.name == "searchTerm" }?.value, term)
                    XCTAssertFalse(request.path.contains(term))
                }
            }
        }
    }

    /// T09-26: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    func testT09_26_sdkQueryBuilderPreservesSpecialTerms() async throws {
        let wire = SearchRequestGate(open: true)
        let client = SearchQueryClient(inner: wire)
        for backend: any SearchBackend in [ItemsSearchBackend(client: client), SearchHintsBackend(client: client)] {
            _ = try await backend.results(term: "& # ä 日本", kind: nil, page: PageRequest(limit: SearchPolicy.pageSize))
        }
        XCTAssertEqual(wire.requests.count, 4)
        XCTAssertTrue(wire.requests.allSatisfy { $0.query.first { $0.name == "searchTerm" }?.value == "& # ä 日本" })
    }

    /// T09-28: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    func testT09_28_serverOrderAndLiteralMetadataArePreserved() async throws {
        let client = SearchRequestGate(open: true)
        let result = try await ItemsSearchBackend(client: client).results(
            term: "star", kind: .movies, page: PageRequest(limit: 2))
        XCTAssertEqual(result.groups.first?.items.map(\.name), ["<b>Zeta</b>&amp;", "Alpha"])
        XCTAssertEqual(result.groups.first?.items.first?.overview, "<i>literal</i>")
        XCTAssertEqual(result.groups.first?.nextIndex, 2)
    }

    /// T09-59: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    func testT09_59_bothBackendsPropagateEveryFailureWithoutRetry() async {
        for error in [APIError.unauthorized, .forbidden, .notFound, .server(status: 500), .timeout, .decoding] {
            for backend: any SearchBackend in [
                ItemsSearchBackend(client: FailedSearchClient(error: error)),
                SearchHintsBackend(client: FailedSearchClient(error: error)),
            ] {
                do {
                    _ = try await backend.results(
                        term: "star", kind: nil, page: PageRequest(limit: SearchPolicy.pageSize))
                    XCTFail("Expected failure")
                } catch let received { XCTAssertEqual(received, error) }
            }
        }
    }

    /// T09-24: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    func testT09_24_hintsGroupInServerOrderRetainImagesAndPageByType() async throws {
        let data = Data(
            """
            {"SearchHints":[
              {"ItemId":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","Type":"Movie","Name":"<b>Z</b>","PrimaryImageTag":"primary"},
              {"ItemId":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","Type":"Series","Name":"Series"},
              {"ItemId":"cccccccccccccccccccccccccccccccc","Type":"Movie","Name":"A","ThumbImageTag":"thumb"},
              {"ItemId":"dddddddddddddddddddddddddddddddd","Type":"Episode","Name":"Episode"}
            ]}
            """.utf8)
        let backend = SearchHintsBackend(client: FixedSearchClient(data: data))
        let result = try await backend.results(term: "star", kind: nil, page: PageRequest(limit: 2))
        XCTAssertEqual(result.groups.map(\.id), SearchKind.allCases)
        XCTAssertEqual(result.groups[0].items.map(\.name), ["<b>Z</b>", "A"])
        XCTAssertEqual(result.groups[0].items.first?.images.primaryTag, "primary")
        XCTAssertEqual(result.groups[0].items.last?.images.thumbTag, "thumb")
        XCTAssertEqual(result.groups[0].nextIndex, 2)
        let client = SearchRequestGate(open: true)
        _ = try await SearchHintsBackend(client: client).results(
            term: "star", kind: .episodes, page: PageRequest(startIndex: 24, limit: SearchPolicy.pageSize))
        let query = try XCTUnwrap(client.requests.first).query
        XCTAssertEqual(query.first { $0.name == "includeItemTypes" }?.value, "Episode")
        XCTAssertEqual(query.first { $0.name == "startIndex" }?.value, "24")
    }

    private func requestCount(_ backend: any SearchBackend) -> Int { backend is ItemsSearchBackend ? 3 : 1 }
}

private struct FixedSearchClient: JellyfinAPIClient {
    var data: Data
    func send(_ request: APIRequest) async throws(APIError) -> Data { data }
}

private struct FailedSearchClient: JellyfinAPIClient {
    var error: APIError
    func send(_ request: APIRequest) async throws(APIError) -> Data { throw error }
}

private final class SearchRequestGate: JellyfinAPIClient, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [APIRequest] = []
    private var pending: [CheckedContinuation<Void, Never>] = []
    private var open: Bool
    var requests: [APIRequest] { lock.withLock { recorded } }
    init(open: Bool = false) { self.open = open }

    func send(_ request: APIRequest) async throws(APIError) -> Data {
        await withCheckedContinuation { continuation in
            lock.lock()
            recorded.append(request)
            if open {
                lock.unlock()
                continuation.resume()
            } else {
                pending.append(continuation)
                lock.unlock()
            }
        }
        let kind = request.query.first { $0.name == "includeItemTypes" }?.value ?? "Movie"
        if request.path == "/Search/Hints" { return Data("{\"SearchHints\":[]}".utf8) }
        let items: [[String: String]] = [
            [
                "Id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "Name": "\u{202E}<b>Zeta</b>&amp;", "Type": kind,
                "Overview": "<i>literal</i>",
            ],
            ["Id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "Name": "Alpha", "Type": kind],
        ]
        do { return try JSONSerialization.data(withJSONObject: ["Items": items, "TotalRecordCount": 30]) } catch {
            throw .decoding
        }
    }

    func releaseAll() {
        let values = lock.withLock {
            open = true
            let values = pending
            pending = []
            return values
        }
        for value in values { value.resume() }
    }
}
