#if canImport(AVFoundation) && canImport(Security)
    import AVFoundation
    import CoreModels
    import Foundation
    import Synchronization
    import XCTest

    @testable import CorePlayback

    final class AVFoundationMediaSessionTests: XCTestCase {
        /// T08P-101: the actual AVURLAsset receives only the credential-free wrapper.
        func testT08P_101_assetURLNeverContainsServerCredential() throws {
            let url = try XCTUnwrap(URL(string: "https://example.invalid/master.m3u8?ApiKey=server-canary"))
            let plan = MediaOpenPlanner.plan(
                delivery: .serverHLS, resolvedURL: url, authorizationHeader: "header-canary",
                options: MediaOpenOptions(trust: .publiclyTrusted, headerFieldsKeyAvailable: false))
            guard case .resourceLoader(let carrier) = plan.primary else { return XCTFail("No loader") }
            let session = try XCTUnwrap(AVPlayerMediaSession(carrier: carrier, origin: MockPlaybackOrigin()))
            XCTAssertEqual(session.asset.url, carrier.assetURL)
            XCTAssertFalse(session.asset.url.absoluteString.contains("canary"))
            XCTAssertFalse(MediaCredentialQuery.contains(session.asset.url))
        }

        /// T08P-100 (a/b/c + control): exercise the native session with a substituted AVPlayer byte sink.
        func testT08P_100_userInfoPlaylistsRejectBeforeAVPlayerDelivery() async throws {
            let base = try XCTUnwrap(URL(string: "https://example.invalid/master.m3u8"))
            let cleanSegment = "https://example.invalid/segment.m4s"
            let cleanKey = "https://example.invalid/key"
            for (segment, key, rejected) in [
                ("https://user:pw@example.invalid/segment.m4s", cleanKey, true),
                ("https://user@example.invalid/segment.m4s", cleanKey, true),
                (cleanSegment, "https://user:pw@example.invalid/key", true),
                (cleanSegment, cleanKey, false),
            ] {
                let playlist = """
                    #EXTM3U
                    #EXT-X-TARGETDURATION:6
                    #EXT-X-KEY:METHOD=AES-128,URI="\(key)"
                    #EXTINF:6,
                    \(segment)
                    #EXT-X-ENDLIST
                    """
                let origin = MockPlaybackOrigin(
                    response: OriginMediaResponse(
                        status: 200, contentType: "application/vnd.apple.mpegurl", body: Data(playlist.utf8)))
                let callbacks = FailureRecorder()
                let carrier = ResourceLoaderCarrier(
                    assetURL: try XCTUnwrap(MediaAssetScheme.wrap(base)), originURL: base,
                    authorizationHeader: "fake-token", trust: .publiclyTrusted, segmentPolicy: .leaveServerURLs)
                let session = try XCTUnwrap(
                    AVPlayerMediaSession(carrier: carrier, origin: origin, onFailure: { callbacks.record($0) }))
                let request = try XCTUnwrap(
                    ResourceLoadPlanner.originRequest(
                        assetURL: carrier.assetURL, authorizationHeader: carrier.authorizationHeader,
                        trust: carrier.trust, range: nil, allowedOrigin: base))
                let loading = RecordingLoadingRequest()
                await session.load(loading, request: request, range: nil)

                XCTAssertEqual(loading.replyCount, rejected ? 0 : 1)
                XCTAssertEqual(loading.completions, rejected ? [.decoding] : [nil])
                XCTAssertEqual(callbacks.errors, rejected ? [.decoding] : [])
                XCTAssertEqual(session.lastFailure, rejected ? .decoding : nil)
                let requests = await origin.requests
                XCTAssertEqual(requests.map(\.url), [base])
                XCTAssertEqual(requests.map(\.authorizationHeader), ["fake-token"])
            }
        }

        /// T08-2-39 (loader-level partial coverage). A mocked HTTP 401 reaches complete(), lastFailure
        /// and onFailure as unauthorized. M08a covers the /Users/Me check and T08-2-49 sign-out flow.
        // TODO(M08a): T08-2-39 /Users/Me check and T08-2-49 end-to-end via MediaUnauthorizedPolicy production caller.
        func testHTTP401CompletionPreservesUnauthorized() async throws {
            let origin = UnauthorizedOrigin()
            let callbacks = FailureRecorder()
            let session = try makeSession(origin: origin, callbacks: callbacks)
            let loading = RecordingLoadingRequest()
            let request = try originRequest()

            // AVAssetResourceLoadingRequest has no public constructor. Substitute only its
            // queue-confined sink; run the session's real load(), complete() and failure store.
            await session.load(loading, request: request, range: request.range)

            XCTAssertEqual(session.lastFailure, .unauthorized)
            XCTAssertEqual(callbacks.errors, [.unauthorized])
            XCTAssertEqual(loading.completions, [.unauthorized])
            XCTAssertEqual(loading.replyCount, 0)
            let fetched = await origin.requests
            XCTAssertEqual(fetched, [request])
        }

        /// T08-2-39 (loader-level partial coverage), T08-2-40. Cancelling another request cannot erase
        /// an earlier media 401. M08a covers the /Users/Me check and T08-2-49 sign-out flow.
        // TODO(M08a): T08-2-39 /Users/Me check and T08-2-49 end-to-end via MediaUnauthorizedPolicy production caller.
        func testCancellationAfterUnauthorizedPreservesLastFailure() async throws {
            let origin = UnauthorizedOrigin()
            let callbacks = FailureRecorder()
            let session = try makeSession(origin: origin, callbacks: callbacks)
            let request = try originRequest()
            let unauthorized = RecordingLoadingRequest()
            await session.load(unauthorized, request: request, range: request.range)
            XCTAssertEqual(session.lastFailure, .unauthorized)

            session.cancel()
            let cancelled = RecordingLoadingRequest()
            await session.load(cancelled, request: request, range: request.range)

            XCTAssertEqual(session.lastFailure, .unauthorized)
            XCTAssertEqual(callbacks.errors, [.unauthorized, .cancelled])
            XCTAssertEqual(unauthorized.completions, [.unauthorized])
            XCTAssertEqual(cancelled.completions, [.cancelled])
            XCTAssertEqual(cancelled.replyCount, 0)
            let fetched = await origin.requests
            XCTAssertEqual(fetched, [request])
        }

        private func makeSession(origin: UnauthorizedOrigin, callbacks: FailureRecorder) throws -> AVPlayerMediaSession
        {
            let url = try originRequest().url
            let carrier = ResourceLoaderCarrier(
                assetURL: try XCTUnwrap(MediaAssetScheme.wrap(url)), originURL: url,
                authorizationHeader: "fake-token", trust: .publiclyTrusted, segmentPolicy: .leaveServerURLs)
            return try XCTUnwrap(
                AVPlayerMediaSession(carrier: carrier, origin: origin, onFailure: { callbacks.record($0) }))
        }

        private func originRequest() throws -> OriginMediaRequest {
            try XCTUnwrap(
                OriginMediaRequest(
                    method: "GET", url: URL(string: "https://example.invalid/video.mp4")!,
                    authorizationHeader: "fake-token", range: HTTPByteRange(start: 0, end: 1), trust: .publiclyTrusted))
        }
    }

    private actor UnauthorizedOrigin: MediaOriginClient {
        private(set) var requests: [OriginMediaRequest] = []

        func fetch(_ request: OriginMediaRequest) async throws(APIError) -> OriginMediaResponse {
            requests.append(request)
            return OriginMediaResponse(status: 401)
        }
    }

    private final class FailureRecorder: Sendable {
        private let stored = Mutex<[APIError]>([])
        var errors: [APIError] { stored.withLock { $0 } }

        func record(_ error: APIError) { stored.withLock { $0.append(error) } }
    }

    private final class RecordingLoadingRequest: MediaLoadingRequest, Sendable {
        private struct State: Sendable {
            var completions: [APIError?] = []
            var replyCount = 0
        }

        private let state = Mutex(State())
        var isCancelled: Bool { false }
        var completions: [APIError?] { state.withLock { $0.completions } }
        var replyCount: Int { state.withLock { $0.replyCount } }

        func respond(with reply: PlayerByteReply) { state.withLock { $0.replyCount += 1 } }
        func finishLoading(with error: APIError?) { state.withLock { $0.completions.append(error) } }
    }
#endif
