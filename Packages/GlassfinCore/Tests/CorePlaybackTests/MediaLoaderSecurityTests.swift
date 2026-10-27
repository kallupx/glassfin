import CoreModels
import CorePlayback
import Foundation
import XCTest

final class MediaLoaderSecurityTests: XCTestCase {
    private let url = URL(string: "https://example.invalid/video.mp4")!
    private let cap = Int64(MediaLoaderLimits.chunkBytes)

    func testOriginRequestRequiresSameHTTPOrigin() throws {
        let allowed = URL(string: "https://example.invalid/base")!
        for candidate in ["https://example.invalid/video", "https://example.invalid:443/video"] {
            XCTAssertNotNil(try plan(candidate, allowed: allowed), candidate)
        }
        XCTAssertNotNil(try plan("https://example.invalid/video", allowed: URL(string: "https://example.invalid:443")!))
        XCTAssertNotNil(try plan("http://example.invalid:80/video", allowed: URL(string: "http://example.invalid")!))
        for candidate in [
            "https://example.invalid:444/video", "http://example.invalid/video",
            "https://other.invalid/video", "ftp://example.invalid:443/video", "file:///video",
        ] {
            XCTAssertNil(try plan(candidate, allowed: allowed), candidate)
        }
        XCTAssertNil(try plan("https://example.invalid/video", allowed: URL(string: "http://example.invalid")!))
    }

    /// T08-2-50. An absolute cross-origin key rejects the playlist and cannot produce a loader request.
    func testCrossOriginKeyIsRejected() async throws {
        try await assertPlaylistRejects(
            #"#EXT-X-KEY:METHOD=AES-128,URI="https://evil.example/key""#,
            uri: "https://evil.example/key")
    }

    /// T08-2-50. An absolute cross-origin audio rendition cannot produce a loader request.
    func testCrossOriginMediaIsRejected() async throws {
        try await assertPlaylistRejects(
            #"#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="x",URI="https://evil.example/a.m3u8""#,
            uri: "https://evil.example/a.m3u8")
    }

    /// T08-2-50. A same-host absolute URI with a different port is still cross-origin.
    func testPlaylistPortChangeIsRejected() async throws {
        try await assertPlaylistRejects(
            "https://example.invalid:444/variant.m3u8", uri: "https://example.invalid:444/variant.m3u8")
    }

    func testMedia401IsDistinctFromOtherHTTPFailures() {
        XCTAssertEqual(
            ResourceLoaderOutcome.classify(OriginMediaResponse(status: 401), requestURL: url),
            .failure(.unauthorized))
        for status in [301, 403, 404, 416, 500, 503] {
            let result = ResourceLoaderOutcome.classify(OriginMediaResponse(status: status), requestURL: url)
            guard case .failure(let error) = result else { return XCTFail("HTTP \(status) returned bytes") }
            XCTAssertNotEqual(error, .unauthorized)
            XCTAssertFalse(LogoutPolicy.shouldLogOut(error))
            XCTAssertEqual(MediaStatusPolicy.decide(status: status), .failed)
        }
        XCTAssertEqual(
            ResourceLoaderOutcome.classify(OriginMediaResponse(status: 403), requestURL: url),
            .failure(.forbidden))
        XCTAssertEqual(
            ResourceLoaderOutcome.classify(OriginMediaResponse(status: 503), requestURL: url),
            .failure(.server(status: 503)))
    }

    func testJSONCredentialsRedactOnlyExactKeys() {
        for key in ["ApiKey", "aPiKeY", "api" + "_key", "API" + "_KEY", "AccessToken", "accesstoken", "Token", "tOkEn"]
        {
            for spacing in ["", " ", "\n  "] {
                let input = "{\"\(key)\":\(spacing)\"fake-token\"}"
                XCTAssertEqual(MediaLogRedactor.redact(input), "{\"\(key)\":\(spacing)\"<redacted>\"}")
            }
        }
        let innocent = #"{"ApiKeyName":"x","MonkeyName":"x","TokenCount":2}"#
        XCTAssertEqual(MediaLogRedactor.redact(innocent), innocent)
        XCTAssertEqual(MediaLogRedactor.redact(#"{"ApiKey":"fake-\"token"}"#), #"{"ApiKey":"<redacted>"}"#)
    }

    func testEncodedCredentialsStopAtEveryDelimiter() {
        for prefix in [
            "%26ApiKey%3D", "%3FApiKey%3D", "%3fapikey%3d", "%26ACCESSToken%3d", "%26api" + "_key%3D", "%26Token%3D",
        ] {
            for suffix in ["%26next=value", "&next=value", "#fragment", " next", "\nnext", "\"next", "'next"] {
                XCTAssertEqual(MediaLogRedactor.redact(prefix + "fake-token" + suffix), prefix + "<redacted>" + suffix)
            }
        }
        let innocent = "%26ApiKeyName%3Dx%26MonkeyName%3Dx"
        XCTAssertEqual(MediaLogRedactor.redact(innocent), innocent)
    }

    func testChunkPlannerBoundsOpenSmallAndLargeRanges() throws {
        XCTAssertEqual(
            ChunkedRangePlanner.next(range: nil, received: 0, totalLength: nil),
            HTTPByteRange(start: 0, end: cap - 1))
        XCTAssertEqual(
            ChunkedRangePlanner.next(range: HTTPByteRange(start: 7, end: nil), received: cap, totalLength: nil),
            HTTPByteRange(start: 7 + cap, end: 6 + 2 * cap))
        XCTAssertEqual(
            ChunkedRangePlanner.next(range: HTTPByteRange(start: 7, end: 10), received: 0, totalLength: nil),
            HTTPByteRange(start: 7, end: 10))
        XCTAssertEqual(
            ChunkedRangePlanner.next(range: HTTPByteRange(start: 7, end: 2 * cap), received: 0, totalLength: nil),
            HTTPByteRange(start: 7, end: cap + 6))
        let planned = try XCTUnwrap(plan(url.absoluteString, allowed: url))
        XCTAssertEqual(planned.range, HTTPByteRange(start: 0, end: cap - 1))
        let playlist = try XCTUnwrap(plan("https://example.invalid/master.m3u8", allowed: url))
        XCTAssertNil(playlist.range)
    }

    func testChunkPlannerStopsAtRequestedEndAndResourceEndWithoutOverflow() {
        XCTAssertEqual(
            ChunkedRangePlanner.next(range: nil, received: cap, totalLength: cap + 3),
            HTTPByteRange(start: cap, end: cap + 2))
        XCTAssertNil(ChunkedRangePlanner.next(range: nil, received: 20, totalLength: 20))
        XCTAssertNil(ChunkedRangePlanner.next(range: nil, received: 0, totalLength: 0))
        XCTAssertNil(ChunkedRangePlanner.next(range: HTTPByteRange(start: 7, end: 10), received: 4, totalLength: nil))
        XCTAssertNil(ChunkedRangePlanner.next(range: HTTPByteRange(start: -1, end: nil), received: 0, totalLength: nil))
        XCTAssertNil(ChunkedRangePlanner.next(range: nil, received: -1, totalLength: nil))
        XCTAssertNil(
            ChunkedRangePlanner.next(range: HTTPByteRange(start: Int64.max, end: nil), received: 1, totalLength: nil))
        XCTAssertEqual(
            ChunkedRangePlanner.next(
                range: HTTPByteRange(start: Int64.max - 1, end: nil), received: 0, totalLength: nil),
            HTTPByteRange(start: Int64.max - 1, end: Int64.max))
    }

    func testBoundedBodyRejectsIgnoredRangeAndOversizedPlaylist() throws {
        var small = BoundedMediaBody(contentType: "video/mp4", url: url, range: HTTPByteRange(start: 0, end: 1))
        try small.append(1)
        try small.append(2)
        XCTAssertThrowsError(try small.append(3)) { XCTAssertEqual($0 as? APIError, .decoding) }
        XCTAssertEqual(small.data, Data([1, 2]))
        var playlist = BoundedMediaBody(contentType: "application/vnd.apple.mpegurl", url: url, range: nil)
        for _ in 0..<MediaLoaderLimits.playlistBytes { try playlist.append(32) }
        XCTAssertThrowsError(try playlist.append(32)) { XCTAssertEqual($0 as? APIError, .decoding) }
        XCTAssertEqual(playlist.data.count, MediaLoaderLimits.playlistBytes)
        var sniffed = BoundedMediaBody(contentType: nil, url: url, range: nil)
        for byte in Data("#EXTM3U\n".utf8) { try sniffed.append(byte) }
        XCTAssertEqual(sniffed.data, Data("#EXTM3U\n".utf8))
    }

    func testOversizedPlaylistAndProgressiveResponsesFailSafely() {
        let oversized = OriginMediaResponse(
            status: 200, contentType: "application/vnd.apple.mpegurl",
            body: Data(repeating: 32, count: MediaLoaderLimits.playlistBytes + 1))
        XCTAssertNil(PlayerResponseBuilder.build(origin: oversized, requestURL: url))
        XCTAssertEqual(ResourceLoaderOutcome.classify(oversized, requestURL: url), .failure(.decoding))
        let progressive = OriginMediaResponse(
            status: 200, contentType: "video/mp4",
            body: Data(repeating: 0, count: MediaLoaderLimits.chunkBytes + 1))
        XCTAssertEqual(ResourceLoaderOutcome.classify(progressive, requestURL: url), .failure(.decoding))
    }

    func testOpenAndLargeRangesDeliverIncrementally() async throws {
        for requested in [nil, HTTPByteRange(start: 0, end: cap + 2)] {
            let client = ChunkOrigin([
                OriginMediaResponse(status: 206, body: Data(repeating: 1, count: Int(cap)), totalLength: cap + 3),
                OriginMediaResponse(status: 206, body: Data([2, 3, 4]), totalLength: cap + 3),
            ])
            let sink = ChunkSink()
            try await ChunkedMediaLoader.load(
                request: request(), range: requested, client: client,
                isCancelled: { false }, receive: { reply async throws(APIError) in await sink.receive(reply) })
            let ranges = await client.ranges
            let counts = await sink.counts
            XCTAssertEqual(ranges, [HTTPByteRange(start: 0, end: cap - 1), HTTPByteRange(start: cap, end: cap + 2)])
            XCTAssertEqual(counts, [Int(cap), 3])
        }
    }

    func testSmallRangeAndUnknownTotalStopWithoutExtraFetches() async throws {
        for range in [HTTPByteRange(start: 9, end: 10), HTTPByteRange(start: 9, end: nil)] {
            let client = ChunkOrigin([OriginMediaResponse(status: 206, body: Data([1, 2]))])
            let sink = ChunkSink()
            try await ChunkedMediaLoader.load(
                request: request(), range: range, client: client,
                isCancelled: { false }, receive: { reply async throws(APIError) in await sink.receive(reply) })
            let ranges = await client.ranges
            let counts = await sink.counts
            XCTAssertEqual(ranges.count, 1)
            XCTAssertEqual(counts, [2])
        }
    }

    func testUnknownTotalContinuesUntilShortChunkOrEOF() async throws {
        for last in [
            OriginMediaResponse(status: 206, body: Data([1])), OriginMediaResponse(status: 416, totalLength: cap),
        ] {
            let client = ChunkOrigin([
                OriginMediaResponse(status: 206, body: Data(repeating: 0, count: Int(cap))), last,
            ])
            let sink = ChunkSink()
            try await ChunkedMediaLoader.load(
                request: request(), range: nil, client: client,
                isCancelled: { false }, receive: { reply async throws(APIError) in await sink.receive(reply) })
            let ranges = await client.ranges
            XCTAssertEqual(
                ranges, [HTTPByteRange(start: 0, end: cap - 1), HTTPByteRange(start: cap, end: 2 * cap - 1)])
        }
    }

    func testCancellationBetweenChunksStopsDeliveryAndFetching() async throws {
        let gate = PlaybackFetchGate()
        let client = ChunkOrigin([OriginMediaResponse(status: 206, body: Data(repeating: 1, count: Int(cap)))])
        do {
            try await ChunkedMediaLoader.load(
                request: request(), range: nil, client: client,
                isCancelled: { gate.isCancelled }, receive: { _ async throws(APIError) in gate.cancel() })
            XCTFail("Cancelled loader completed")
        } catch { XCTAssertEqual(error, .cancelled) }
        let ranges = await client.ranges
        XCTAssertEqual(ranges.count, 1)
        let stopped = ChunkOrigin([])
        do {
            try await ChunkedMediaLoader.load(
                request: request(), range: nil, client: stopped,
                isCancelled: { true }, receive: { _ async throws(APIError) in XCTFail("Delivered after cancellation") })
            XCTFail("Cancelled loader completed")
        } catch { XCTAssertEqual(error, .cancelled) }
        let stoppedRanges = await stopped.ranges
        XCTAssertTrue(stoppedRanges.isEmpty)
    }

    func testCancellationAfterFetchPreventsDelivery() async throws {
        let gate = PlaybackFetchGate()
        let client = ChunkOrigin([OriginMediaResponse(status: 206, body: Data([1]))], onFetch: { gate.cancel() })
        do {
            try await ChunkedMediaLoader.load(
                request: request(), range: nil, client: client,
                isCancelled: { gate.isCancelled },
                receive: { _ async throws(APIError) in XCTFail("Delivered after cancellation during fetch") })
            XCTFail("Cancelled loader completed")
        } catch { XCTAssertEqual(error, .cancelled) }
        let ranges = await client.ranges
        XCTAssertEqual(ranges.count, 1)
    }

    func testTaskCancellationBetweenChunksStopsFetching() async throws {
        let mediaRequest = request()
        let client = ChunkOrigin([OriginMediaResponse(status: 206, body: Data(repeating: 1, count: Int(cap)))])
        let task = Task<APIError?, Never> { () async -> APIError? in
            do {
                try await ChunkedMediaLoader.load(
                    request: mediaRequest, range: nil, client: client,
                    isCancelled: { false },
                    receive: { _ async throws(APIError) in
                        withUnsafeCurrentTask { $0?.cancel() }
                    })
                return nil
            } catch { return error as? APIError }
        }
        let error = await task.value
        XCTAssertEqual(error, .cancelled)
        let ranges = await client.ranges
        XCTAssertEqual(ranges.count, 1)
    }

    func testLoaderSurfacesUnauthorizedAndRejectsIgnoredRanges() async throws {
        for (response, range, expected) in [
            (OriginMediaResponse(status: 401), HTTPByteRange(start: 0, end: 1), APIError.unauthorized),
            (OriginMediaResponse(status: 403), HTTPByteRange(start: 0, end: 1), APIError.forbidden),
            (OriginMediaResponse(status: 503), HTTPByteRange(start: 0, end: 1), APIError.server(status: 503)),
            (
                OriginMediaResponse(status: 200, body: Data([1, 2])), HTTPByteRange(start: 9, end: 10),
                APIError.decoding
            ),
            (
                OriginMediaResponse(status: 206, body: Data([1, 2, 3])), HTTPByteRange(start: 0, end: 1),
                APIError.decoding
            ),
        ] {
            do {
                try await ChunkedMediaLoader.load(
                    request: request(), range: range, client: ChunkOrigin([response]),
                    isCancelled: { false },
                    receive: { _ async throws(APIError) in XCTFail("Delivered a failed response") })
                XCTFail("Failed response completed")
            } catch { XCTAssertEqual(error, expected) }
        }
    }

    func testPlaylistsAreFetchedWholeAndRewritten() async throws {
        for path in ["master.m3u8", "master"] {
            let playlistURL = URL(string: "https://example.invalid/\(path)")!
            var playlistRequest = request()
            playlistRequest.url = playlistURL
            let playlist = OriginMediaResponse(
                status: 200, contentType: "application/vnd.apple.mpegurl",
                body: Data("#EXTM3U\nvariant.m3u8\n".utf8))
            let responses = path == "master" ? [playlist, playlist] : [playlist]
            let client = ChunkOrigin(responses)
            let sink = ChunkSink()
            try await ChunkedMediaLoader.load(
                request: playlistRequest, range: nil, client: client,
                isCancelled: { false }, receive: { reply async throws(APIError) in await sink.receive(reply) })
            let ranges = await client.ranges
            let text = await sink.text
            XCTAssertNil(ranges.last!)
            XCTAssertEqual(ranges.count, responses.count)
            XCTAssertTrue(text.contains("glassfin-media"))
        }
    }

    func testHeaderFieldsKeyPolicyDisablesReleaseFallback() {
        XCTAssertFalse(HeaderFieldsKeyPolicy.isAllowed(buildIsDebug: false))
        XCTAssertTrue(HeaderFieldsKeyPolicy.isAllowed(buildIsDebug: true))
        XCTAssertFalse(
            MediaOpenOptions(trust: .publiclyTrusted, headerFieldsKeyAvailable: false).headerFieldsKeyAvailable)
        XCTAssertEqual(
            MediaOpenOptions(trust: .publiclyTrusted, headerFieldsKeyAvailable: true).headerFieldsKeyAvailable,
            HeaderFieldsKeyPolicy.isAllowedInCurrentBuild)
    }

    private func request() -> OriginMediaRequest {
        OriginMediaRequest(method: "GET", url: url, authorizationHeader: "fake-token", trust: .publiclyTrusted)!
    }

    private func assertPlaylistRejects(
        _ line: String, uri: String, file: StaticString = #filePath, lineNumber: UInt = #line
    ) async throws {
        let base = URL(string: "https://example.invalid/master.m3u8")!
        let playlist = "#EXTM3U\n\(line)\n"
        XCTAssertEqual(
            HLSPlaylistRewriter.rewrite(playlist: playlist, baseURL: base), .failure(.crossOrigin),
            file: file, line: lineNumber)
        XCTAssertNil(try plan(uri, allowed: base), file: file, line: lineNumber)
        let response = OriginMediaResponse(
            status: 200, contentType: "application/vnd.apple.mpegurl", body: Data(playlist.utf8))
        XCTAssertNil(PlayerResponseBuilder.build(origin: response, requestURL: base), file: file, line: lineNumber)
        var playlistRequest = request()
        playlistRequest.url = base
        let client = ChunkOrigin([response])
        do {
            try await ChunkedMediaLoader.load(
                request: playlistRequest, range: nil, client: client, isCancelled: { false },
                receive: { _ async throws(APIError) in
                    XCTFail("Delivered a rejected playlist", file: file, line: lineNumber)
                })
            XCTFail("Rejected playlist completed", file: file, line: lineNumber)
        } catch {
            XCTAssertEqual(error, .decoding, file: file, line: lineNumber)
        }
        let requestedURLs = await client.urls
        XCTAssertEqual(requestedURLs, [base], file: file, line: lineNumber)
    }

    private func plan(_ value: String, allowed: URL) throws -> OriginMediaRequest? {
        // Construct the wrapper directly so non-HTTP schemes also exercise the planner's guard.
        let encoded = try XCTUnwrap(value.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        let asset = try XCTUnwrap(URL(string: "glassfin-media://origin/\(encoded)"))
        return ResourceLoadPlanner.originRequest(
            assetURL: asset, authorizationHeader: "fake-token",
            trust: .publiclyTrusted, range: nil, allowedOrigin: allowed)
    }
}

private actor ChunkOrigin: MediaOriginClient {
    private var responses: [OriginMediaResponse]
    private let onFetch: @Sendable () -> Void
    private(set) var ranges: [HTTPByteRange?] = []
    private(set) var urls: [URL] = []

    init(_ responses: [OriginMediaResponse], onFetch: @escaping @Sendable () -> Void = {}) {
        self.responses = responses
        self.onFetch = onFetch
    }

    func fetch(_ request: OriginMediaRequest) async throws(APIError) -> OriginMediaResponse {
        ranges.append(request.range)
        urls.append(request.url)
        guard !responses.isEmpty else { throw .network }
        onFetch()
        return responses.removeFirst()
    }
}

private actor ChunkSink {
    private(set) var counts: [Int] = []
    private(set) var text = ""

    func receive(_ reply: PlayerByteReply) {
        counts.append(reply.data.count)
        if !reply.isByteRangeAccessSupported { text += String(decoding: reply.data, as: UTF8.self) }
    }
}
