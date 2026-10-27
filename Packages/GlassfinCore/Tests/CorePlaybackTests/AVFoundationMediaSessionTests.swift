#if canImport(AVFoundation) && canImport(Security)
    import AVFoundation
    import CoreModels
    import Foundation
    import Synchronization
    import XCTest

    @testable import CorePlayback

    final class AVFoundationMediaSessionTests: XCTestCase {
        /// T08-2-39. A mocked HTTP 401 reaches complete(), lastFailure and onFailure as unauthorized.
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

        /// T08-2-39, T08-2-40. Cancelling another request cannot erase an earlier media 401.
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
