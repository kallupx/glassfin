import CoreModels
import CoreNetworking
import CorePlayback
import Foundation
import XCTest

/// T08P-100: userinfo rejection is separate from RFC 6454 origin identity (T08-2-52).
final class MediaUserInfoSecurityTests: XCTestCase {
    private let base = URL(string: "https://example.invalid/master.m3u8")!
    private let userInfo = ["user:pw@", "user@", ":password@", "@", ":@", "user:@", "%75ser:%70w@"]

    func testT08P_100_userInfoSegmentsAndKeysRejectServerPlaylistBeforeDelivery() async throws {
        for credentials in userInfo {
            let target = "https://\(credentials)example.invalid/segment.m4s"
            for line in [
                "#EXTINF:6,\n\(target)",
                "#EXT-X-MAP:URI=\"\(target)\"",
                "#EXT-X-PART:URI=\"\(target)\"",
                "#EXT-X-KEY:METHOD=AES-128,URI=\"\(target)\"",
            ] {
                try await assertServerPlaylistRejected(line)
            }
        }
    }

    func testUserInfoVariantPlaylistsRejectServerMasterBeforeDelivery() async throws {
        for credentials in userInfo {
            let target = "https://\(credentials)example.invalid/variant.m3u8"
            for line in [
                "#EXT-X-STREAM-INF:BANDWIDTH=160000\n\(target)",
                "#EXT-X-STREAM-INF:BANDWIDTH=160000\n//\(credentials)example.invalid/variant.m3u8",
                "#EXT-X-MEDIA:TYPE=AUDIO,URI=\"\(target)\"",
                "#EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=160000,URI=\"\(target)\"",
            ] {
                try await assertServerPlaylistRejected(line)
            }
        }
    }

    func testUserInfoTranscodingURLsAndServerURLsAreRejected() throws {
        let identity = ClientIdentity(deviceName: "TV", deviceID: "device", version: "1", token: "secret")
        for credentials in userInfo {
            let target = try XCTUnwrap(URL(string: "https://\(credentials)example.invalid/master.m3u8"))
            XCTAssertNil(MediaURLBuilder.resolveTranscodingURL(server: base, transcodingURL: target.absoluteString))
            XCTAssertNil(
                MediaURLBuilder.resolveTranscodingURL(
                    server: base, transcodingURL: "//\(credentials)example.invalid/master.m3u8"))
            XCTAssertNil(MediaURLBuilder.resolveTranscodingURL(server: target, transcodingURL: "/master.m3u8"))
            XCTAssertThrowsError(
                try MediaURLBuilder.videoCopyHLS(
                    server: base, transcodingURL: target.absoluteString, conversion: .remux)
            ) { XCTAssertEqual($0 as? PlaybackFailure, .insecureRedirect) }
            XCTAssertThrowsError(
                try MediaURLBuilder.directPlay(
                    server: target, identity: identity, itemID: pocItemID,
                    mediaSourceID: pocSourceID, playSessionID: "play-session")
            ) { XCTAssertEqual($0 as? APIError, .invalidURL) }
            XCTAssertNil(MediaAssetScheme.wrap(target))
            XCTAssertNil(MediaURLBuilder.queryCredentialFallback(strippedURL: target, token: "secret"))
            XCTAssertEqual(
                HLSPlaylistRewriter.rewrite(playlist: "#EXTM3U\nsegment.m4s", baseURL: target),
                .failure(.userInfo))
        }
    }

    func testT08P_100_userInfoInitialAndResolvedURLsNeverReachTransportOrPlayer() async throws {
        for credentials in userInfo {
            let target = try XCTUnwrap(URL(string: "https://\(credentials)example.invalid/master.m3u8"))
            for delivery in [MediaDelivery.directFile, .serverHLS] {
                let options = MediaOpenOptions(trust: .publiclyTrusted, headerFieldsKeyAvailable: false)
                let client = MockPlaybackOrigin()
                let result = try await PlaybackPreparation(client: client).prepare(
                    delivery: delivery, initialURL: target, authorizationHeader: "header-secret", options: options)
                XCTAssertEqual(result, .rejected(.insecureRedirect))
                let requests = await client.requests
                XCTAssertTrue(requests.isEmpty)
                let plan = MediaOpenPlanner.plan(
                    delivery: delivery, resolvedURL: target, authorizationHeader: "header-secret", options: options)
                XCTAssertEqual(plan.primary, .blocked(.missingMediaURL))
                XCTAssertTrue(plan.measuredFallbacks.isEmpty)
            }
        }
    }

    func testUserInfoRedirectNeverReachesTransport() async throws {
        for credentials in userInfo {
            let target = try XCTUnwrap(URL(string: "https://\(credentials)example.invalid/variant.m3u8"))
            for mode in [MediaCredentialMode.authorizationHeader, .queryCredential] {
                let client = MockPlaybackOrigin(response: OriginMediaResponse(status: 302, location: target))
                let result = try await PlaybackURLResolver(client: client).resolve(
                    start: base, method: "GET", authorizationHeader: "header-secret", trust: .publiclyTrusted,
                    mode: mode)
                XCTAssertEqual(result, .rejected(.insecureRedirect))
                let requests = await client.requests
                XCTAssertEqual(requests.map(\.url), [base])
                assertNoUserInfo(requests)
            }
        }
    }

    func testUserInfoLoaderRequestsAreRejectedEvenAfterMutation() async throws {
        for credentials in userInfo {
            let target = try XCTUnwrap(URL(string: "https://\(credentials)example.invalid/variant.m3u8"))
            XCTAssertNil(
                OriginMediaRequest(method: "GET", url: target, authorizationHeader: nil, trust: .publiclyTrusted))
            // Build a wrapper directly to verify the planner cannot sanitize the rejected URL.
            let encoded = try XCTUnwrap(
                target.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
            let asset = try XCTUnwrap(URL(string: "glassfin-media://origin/\(encoded)"))
            XCTAssertNil(
                ResourceLoadPlanner.originRequest(
                    assetURL: asset, authorizationHeader: "header-secret", trust: .publiclyTrusted,
                    range: nil, allowedOrigin: base))
            var request = try XCTUnwrap(
                OriginMediaRequest(
                    method: "GET", url: base, authorizationHeader: "header-secret", trust: .publiclyTrusted))
            request.url = target
            let client = MockPlaybackOrigin()
            do {
                try await ChunkedMediaLoader.load(
                    request: request, range: nil, client: client, isCancelled: { false },
                    receive: { _ async throws(APIError) in XCTFail("Delivered credential URL bytes") })
                XCTFail("Loaded a credential URL")
            } catch { XCTAssertEqual(error, .invalidURL) }
            let requests = await client.requests
            XCTAssertTrue(requests.isEmpty)
        }
    }

    func testAtSignInPathAndQueryDoesNotRejectSafePlayback() async throws {
        let target = try XCTUnwrap(URL(string: "https://example.invalid/user@name/master.m3u8?label=user:pw@host"))
        let client = MockPlaybackOrigin()
        let result = try await PlaybackURLResolver(client: client).resolve(
            start: target, method: "GET", authorizationHeader: "header-secret", trust: .publiclyTrusted)
        XCTAssertEqual(result, .resolved(target))
        let requests = await client.requests
        XCTAssertEqual(requests.map(\.url), [target])
        assertNoUserInfo(requests)
    }

    private func assertServerPlaylistRejected(
        _ line: String, file: StaticString = #filePath, lineNumber: UInt = #line
    ) async throws {
        let playlist = "#EXTM3U\n\(line)\n"
        XCTAssertEqual(
            HLSPlaylistRewriter.rewrite(playlist: playlist, baseURL: base), .failure(.userInfo),
            file: file, line: lineNumber)
        let client = MockPlaybackOrigin(
            response: OriginMediaResponse(
                status: 200, contentType: "application/vnd.apple.mpegurl", body: Data(playlist.utf8)))
        let request = try XCTUnwrap(
            OriginMediaRequest(method: "GET", url: base, authorizationHeader: "header-secret", trust: .publiclyTrusted))
        do {
            try await ChunkedMediaLoader.load(
                request: request, range: nil, client: client, isCancelled: { false },
                receive: { _ async throws(APIError) in
                    XCTFail("Delivered a playlist with userinfo", file: file, line: lineNumber)
                })
            XCTFail("Loaded a playlist with userinfo", file: file, line: lineNumber)
        } catch { XCTAssertEqual(error, .decoding, file: file, line: lineNumber) }
        let requests = await client.requests
        XCTAssertEqual(requests.map(\.url), [base], file: file, line: lineNumber)
        assertNoUserInfo(requests, file: file, lineNumber: lineNumber)
    }

    private func assertNoUserInfo(
        _ requests: [OriginMediaRequest], file: StaticString = #filePath, lineNumber: UInt = #line
    ) {
        for request in requests {
            let components = URLComponents(url: request.url, resolvingAgainstBaseURL: true)
            XCTAssertNotNil(components, file: file, line: lineNumber)
            XCTAssertNil(components?.user, file: file, line: lineNumber)
            XCTAssertNil(components?.password, file: file, line: lineNumber)
            XCTAssertFalse(
                request.authorizationHeader?.lowercased().hasPrefix("basic ") == true, file: file, line: lineNumber)
        }
    }
}
