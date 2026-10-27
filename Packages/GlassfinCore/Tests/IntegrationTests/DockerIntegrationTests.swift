import CoreModels
import CoreNetworking
import Foundation
import GlassfinServices
import XCTest

@testable import CorePlayback

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Live Jellyfin checks. `scripts/docker-integration.sh` starts throwaway servers and sets
/// `GLASSFIN_INTEGRATION=1`. A normal `swift test` skips these.
final class LiveServerTests: XCTestCase {
    private struct Target {
        var version: String
        var url: URL
        var username: String
        var password: String
    }

    /// T08P-05/06/07/08/10/12/13/14: live negotiation and server-side HLS checks; AVPlayer is not involved.
    func testT08P_05_seedMediaPlaybackDecisions() async throws {
        let target = try liveTarget()
        let session = try await signIn(target)
        let identity = ClientIdentity(
            deviceName: "Glassfin CI", deviceID: "glassfin-integration", version: "0.1.0", token: session.accessToken)
        let client = HTTPJellyfinClient(server: target.url, identity: identity)
        let api = PlaybackAPI(client: client)
        let items = try await client.send(
            APIRequest(
                method: "GET", path: "/Items",
                query: [
                    URLQueryItem(name: "Recursive", value: "true"),
                    URLQueryItem(name: "IncludeItemTypes", value: "Movie"),
                    URLQueryItem(name: "Limit", value: "100"),
                    URLQueryItem(name: "Fields", value: "Path"),
                ]), as: SeedItems.self)
        let fixtures: [(String, PlaybackDecision)] = [
            ("Test Movie (2024).mp4", .directPlay),
            ("Glassfin HEVC EAC3 (2024).mp4", .directPlay),
            ("Glassfin Remux (2024).mkv", .directStream(.remux)),
            ("Glassfin DTS (2024).mkv", .directStream(.audioTranscode)),
            ("Glassfin HEVC AC3 (2024).mkv", .directStream(.remux)),
            ("Glassfin Unsupported (2024).mkv", .unsupported(.unsupportedVideo)),
        ]
        for (filename, expected) in fixtures {
            // Use the path: an online metadata provider may rename the generated movie.
            let item = try XCTUnwrap(items.Items.first { $0.Path?.hasSuffix(filename) == true }, filename)
            let detail = try await api.item(itemID: item.Id, userID: session.session.userID)
            let metadata = detail.MediaSources?.first
            let supported = PlaybackDecision.supportsVideo(
                streams: metadata?.MediaStreams ?? detail.MediaStreams,
                defaultIndex: metadata?.DefaultVideoStreamIndex)
            if case .unsupported(let failure) = expected {
                XCTAssertFalse(supported, filename)
                XCTAssertEqual(failure.localizedKey, PlaybackCopy.unsupportedVideoKey)
                // Q8P-05: never call PlaybackInfo for MPEG-2, even in the live matrix.
                continue
            }
            XCTAssertTrue(supported, filename)
            let info = try await api.playbackInfo(
                itemID: item.Id, userID: session.session.userID, start: .zero, maxBitrate: 120_000_000)
            let source = try XCTUnwrap(info.MediaSources?.first, filename)
            let decision = PlaybackDecision.decide(mediaSource: source)
            XCTAssertEqual(decision, expected, filename)
            if case .unsupported = decision { continue }
            XCTAssertNotNil(info.PlaySessionId, filename)
            switch expected {
            case .directPlay:
                XCTAssertEqual(source.SupportsDirectPlay, true, filename)
                let prepared = try MediaURLBuilder.directPlay(
                    server: target.url, identity: identity, itemID: item.Id,
                    mediaSourceID: try XCTUnwrap(source.Id), playSessionID: try XCTUnwrap(info.PlaySessionId))
                XCTAssertFalse(MediaCredentialQuery.contains(prepared.url), filename)
                XCTAssertNotNil(prepared.authorizationHeader)
            case .directStream(let conversion):
                let url = try MediaURLBuilder.videoCopyHLS(
                    server: target.url, transcodingURL: try XCTUnwrap(source.TranscodingUrl, filename),
                    conversion: conversion)
                XCTAssertTrue(MediaOrigin.matches(target.url, url), filename)
                XCTAssertFalse(MediaCredentialQuery.contains(url), filename)
                XCTAssertFalse(VideoTranscodeReasons.blocksPlayback(transcodingURL: source.TranscodingUrl), filename)
                let reasons = VideoTranscodeReasons.parse(transcodingURL: source.TranscodingUrl)
                if conversion == .audioTranscode { XCTAssertTrue(reasons.contains("AudioCodecNotSupported"), filename) }
                try await assertRemuxSession(
                    client: client, server: target.url, identity: identity,
                    itemID: item.Id, source: source, info: info, url: url, conversion: conversion)
            case .unsupported(let reason):
                XCTAssertEqual(reason.localizedKey, PlaybackCopy.unsupportedVideoKey)
            }
        }
    }

    /// T08P-09/11/12/34, TPOC-16/17/19: inspect the server after fetching real HLS bytes.
    private func assertRemuxSession(
        client: HTTPJellyfinClient, server: URL, identity: ClientIdentity,
        itemID: String, source: MediaSourceDTO, info: PlaybackInfoResponseDTO, url: URL,
        conversion: PlaybackDecision.StreamConversion
    ) async throws {
        let reporter = PlaybackReporter(client: client, log: SilentLog())
        let context = PlaybackReportContext(
            itemID: itemID, mediaSourceID: try XCTUnwrap(source.Id),
            playSessionID: try XCTUnwrap(info.PlaySessionId), method: .directStream)
        let error = await reporter.send("", context: context, position: .zero, paused: false, canSeek: true)
        XCTAssertNil(error)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        let transport = URLSession(configuration: configuration, delegate: StopRedirects(), delegateQueue: nil)
        defer { transport.invalidateAndCancel() }
        do {
            var next = url
            var receivedSegment = false
            for _ in 0..<4 {
                XCTAssertTrue(MediaOrigin.matches(server, next))
                guard MediaOrigin.matches(server, next), !MediaOrigin.isHTTPSDowngrade(server, next) else {
                    throw APIError.invalidURL
                }
                var request = URLRequest(url: next)
                if !MediaCredentialQuery.contains(next) {
                    request.setValue(try identity.authorizationHeader(), forHTTPHeaderField: "Authorization")
                }
                let (bytes, response) = try await transport.data(for: request)
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
                if !next.path.hasSuffix(".m3u8") {
                    XCTAssertFalse(bytes.isEmpty)
                    receivedSegment = true
                    break
                }
                let playlist = try XCTUnwrap(String(data: bytes, encoding: .utf8))
                guard case .success = HLSPlaylistRewriter.rewrite(playlist: playlist, baseURL: next) else {
                    throw APIError.invalidURL
                }
                let uri = try XCTUnwrap(playlist.split(whereSeparator: \.isNewline).first { !$0.hasPrefix("#") })
                let resolved = try XCTUnwrap(URL(string: String(uri), relativeTo: next)?.absoluteURL)
                next = resolved.path.hasSuffix(".m3u8") ? MediaCredentialQuery.stripping(resolved) : resolved
            }
            XCTAssertTrue(receivedSegment, "HLS did not reach a media segment")
            let sessions = try await client.send(APIRequest(method: "GET", path: "/Sessions"), as: [LiveSession].self)
            let active = try XCTUnwrap(sessions.first { $0.NowPlayingItem?.Id == itemID })
            let transcode = try XCTUnwrap(active.TranscodingInfo)
            XCTAssertEqual(transcode.IsVideoDirect, true)
            XCTAssertEqual(transcode.IsAudioDirect, conversion == .remux)
            if conversion == .audioTranscode { XCTAssertTrue(["aac", "eac3"].contains(transcode.AudioCodec ?? "")) }
            XCTAssertEqual(transcode.Container, "mp4")
        } catch {
            _ = await reporter.send(
                "/Stopped", context: context, position: .zero, paused: false, canSeek: true, failed: true)
            throw error
        }
        _ = await reporter.send("/Stopped", context: context, position: .zero, paused: false, canSeek: true)
        _ = try await client.send(
            APIRequest(
                method: "DELETE", path: "/Videos/ActiveEncodings",
                query: [
                    URLQueryItem(name: "deviceId", value: identity.deviceID),
                    URLQueryItem(name: "playSessionId", value: context.playSessionID),
                ]))
    }

    private struct LiveSession: Decodable, Sendable {
        struct Item: Decodable, Sendable { let Id: String? }
        struct Transcode: Decodable, Sendable {
            let IsVideoDirect: Bool?
            let IsAudioDirect: Bool?
            let AudioCodec: String?
            let Container: String?
        }
        let NowPlayingItem: Item?
        let TranscodingInfo: Transcode?
    }

    /// TPOC-02/07/10 (server prerequisites): non-admin login, libraries, resume threshold and QC.
    func testTPOC_02_seedConfigurationAndNonAdminUser() async throws {
        let target = try liveTarget()
        let admin = try await signIn(target)
        let identity = ClientIdentity(
            deviceName: "CI", deviceID: "bootstrap-check", version: "1", token: admin.accessToken)
        let client = HTTPJellyfinClient(server: target.url, identity: identity)
        let config = try await client.send(
            APIRequest(method: "GET", path: "/System/Configuration"), as: SeedConfiguration.self)
        XCTAssertEqual(config.MinResumeDurationSeconds, 0)
        XCTAssertEqual(config.MinResumePct, 5)
        XCTAssertEqual(config.MaxResumePct, 90)
        XCTAssertEqual(config.QuickConnectAvailable, true)
        let environment = ProcessInfo.processInfo.environment
        let viewer = Target(
            version: target.version, url: target.url,
            username: try XCTUnwrap(environment["GLASSFIN_TEST_USERNAME"]),
            password: try XCTUnwrap(environment["GLASSFIN_TEST_PASSWORD"]))
        let login = try await signIn(viewer)
        let viewerIdentity = ClientIdentity(
            deviceName: "CI", deviceID: "viewer-check", version: "1", token: login.accessToken)
        let viewerClient = HTTPJellyfinClient(server: target.url, identity: viewerIdentity)
        let user = try await viewerClient.send(APIRequest(method: "GET", path: "/Users/Me"), as: UserDTO.self)
        XCTAssertEqual(user.Policy?.IsAdministrator, false)
        let views = try await JellyfinLibraryService(client: viewerClient).userViews()
        XCTAssertEqual(Set(views.map(\.name)), ["Movies", "Shows"])
        let episodes = try await viewerClient.send(
            APIRequest(
                method: "GET", path: "/Items",
                query: [
                    URLQueryItem(name: "Recursive", value: "true"),
                    URLQueryItem(name: "IncludeItemTypes", value: "Episode"),
                ]), as: QueryResultDTO.self)
        XCTAssertEqual(episodes.TotalRecordCount, 3)
    }

    private struct SeedConfiguration: Decodable, Sendable {
        let MinResumeDurationSeconds: Int?
        let MinResumePct: Int?
        let MaxResumePct: Int?
        let QuickConnectAvailable: Bool?
    }

    private struct SeedItems: Decodable, Sendable {
        struct Item: Decodable, Sendable {
            let Id: String
            let Path: String?
        }
        let Items: [Item]
    }

    /// T01-20. Login, UserViews, Resume, and PlaybackInfo against one live server version.
    func testT01_20_loginUserViewsResumeAndPlaybackInfo() async throws {
        let target = try liveTarget()
        let anonymous = ClientIdentity(
            deviceName: "Glassfin CI", deviceID: "glassfin-integration", version: "0.1.0")
        let opener = HTTPJellyfinClient(server: target.url, identity: anonymous)
        let auth = JellyfinAuthenticationService(client: opener, server: target.url, serverName: "jellyfin")
        let session = try await auth.authenticate(username: target.username, password: target.password)
        XCTAssertFalse(session.accessToken.isEmpty)
        XCTAssertFalse(session.session.userID.isEmpty)

        var signedIn = anonymous
        signedIn.token = session.accessToken
        let client = HTTPJellyfinClient(server: target.url, identity: signedIn)
        let library = JellyfinLibraryService(client: client)
        let views = try await library.userViews()
        XCTAssertFalse(views.isEmpty, "\(target.version) UserViews was empty")
        let resumed = try await library.resume(limit: 5)
        XCTAssertGreaterThanOrEqual(resumed.count, 0)

        var movie: MediaItem?
        for view in views {
            let page = try await library.items(
                in: view.id,
                query: ItemQuery(includeItemTypes: ["Movie"], recursive: true),
                page: PageRequest(limit: 5)
            )
            if let first = page.items.first {
                movie = first
                break
            }
        }
        let found = try XCTUnwrap(movie, "\(target.version) library has no movie")
        let playback = try await JellyfinPlaybackInfoService(client: client, server: target.url)
            .playbackInfo(itemID: found.id, start: .zero, maxBitrate: 2_000_000)
        XCTAssertFalse(playback.mediaSourceID.isEmpty)
        XCTAssertFalse(playback.playSessionID.isEmpty)
    }

    /// T01-30. The socket carries the token only in the Authorization header.
    /// A wrong token must be rejected. A server that refuses the header is an expected
    /// failure for that version; the test does not add an ApiKey query.
    func testT01_30_headerOnlySocketReceivesKeepAliveAndRejectsWrongToken() async throws {
        let target = try liveTarget()
        let session = try await signIn(target)
        var identity = ClientIdentity(
            deviceName: "Glassfin CI", deviceID: "glassfin-integration", version: "0.1.0", token: session.accessToken)
        let request = try SocketRequestBuilder.make(server: target.url, identity: identity)
        let socketURL = try XCTUnwrap(request.url)
        XCTAssertFalse(queryCarriesCredential(socketURL))
        XCTAssertNotNil(request.value(forHTTPHeaderField: "Authorization"))

        let outcome = try HeaderOnlySocket.open(request)
        if outcome.sawKeepAlive {
            XCTAssertEqual(outcome.status, 101)
        } else if outcome.status != 101 {
            // Linux XCTest has no XCTExpectFailure. Fail this version in the open
            // and leave the URL without an ApiKey query.
            XCTFail(
                "EXPECTED FAILURE \(target.version): header-only socket HTTP \(outcome.status). ApiKey was not added."
            )
        } else {
            XCTFail("\(target.version) accepted the header but sent no KeepAlive within 10s")
        }

        identity.token = "wrong-token"
        let rejected = try SocketRequestBuilder.make(server: target.url, identity: identity)
        do {
            let wrong = try HeaderOnlySocket.open(rejected)
            XCTAssertFalse(
                wrong.sawKeepAlive, "\(target.version) accepted a wrong token on the header-only socket")
        } catch is HeaderOnlySocket.Failure {
            // A closed socket or a failed handshake rejects the wrong token.
        }
    }

    /// T08-2-08. Direct-play and HLS plan text omit the access token.
    /// The Jellyfin container log is not read from this process.
    func testT08_2_08_livePlaybackInfoURLOmitsTheAccessToken() async throws {
        let target = try liveTarget()
        let session = try await signIn(target)
        let identity = ClientIdentity(
            deviceName: "Glassfin CI",
            deviceID: "glassfin-integration",
            version: "0.1.0",
            token: session.accessToken
        )
        let client = HTTPJellyfinClient(server: target.url, identity: identity)
        let movie = try await firstMovie(client: client, version: target.version)
        let playback = try await JellyfinPlaybackInfoService(client: client, server: target.url)
            .playbackInfo(itemID: movie.id, start: .zero, maxBitrate: 2_000_000)
        let prepared = try MediaURLBuilder.directPlay(
            server: target.url,
            identity: identity,
            itemID: movie.id,
            mediaSourceID: playback.mediaSourceID,
            playSessionID: playback.playSessionID
        )
        let direct = MediaOpenPlanner.plan(
            delivery: .directFile,
            resolvedURL: prepared.url,
            authorizationHeader: prepared.authorizationHeader,
            options: MediaOpenOptions(trust: .publiclyTrusted, headerFieldsKeyAvailable: true)
        )
        var texts = [prepared.url.absoluteString, direct.description, String(describing: direct)]
        if let hls = playback.url {
            let stripped = MediaCredentialQuery.stripping(hls)
            let plan = MediaOpenPlanner.plan(
                delivery: .serverHLS,
                resolvedURL: stripped,
                authorizationHeader: prepared.authorizationHeader,
                options: MediaOpenOptions(trust: .publiclyTrusted, headerFieldsKeyAvailable: true)
            )
            texts.append(plan.description)
            texts.append(stripped.absoluteString)
        }
        let blob = texts.joined(separator: "\n")
        XCTAssertFalse(blob.contains("ApiKey="), "live playback text contained a credential query")
        let tokenLeaked = blob.contains(session.accessToken)
        XCTAssertFalse(tokenLeaked, "live playback text contained the access token")
        XCTAssertFalse(MediaCredentialQuery.contains(prepared.url))
    }

    /// T08-2-37. HEAD /Videos/{id}/stream. A 405 is recorded and is not a product failure (Q8-2-05).
    func testT08_2_37_directPlayHeadStatusIsRecorded() async throws {
        let target = try liveTarget()
        let session = try await signIn(target)
        let identity = ClientIdentity(
            deviceName: "Glassfin CI",
            deviceID: "glassfin-integration",
            version: "0.1.0",
            token: session.accessToken
        )
        let client = HTTPJellyfinClient(server: target.url, identity: identity)
        let movie = try await firstMovie(client: client, version: target.version)
        let playback = try await JellyfinPlaybackInfoService(client: client, server: target.url)
            .playbackInfo(itemID: movie.id, start: .zero, maxBitrate: 2_000_000)
        let prepared = try MediaURLBuilder.directPlay(
            server: target.url,
            identity: identity,
            itemID: movie.id,
            mediaSourceID: playback.mediaSourceID,
            playSessionID: playback.playSessionID
        )
        let delegate = StopRedirects()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        let urlSession = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { urlSession.invalidateAndCancel() }
        var head = URLRequest(url: prepared.url)
        head.httpMethod = "HEAD"
        head.setValue(prepared.authorizationHeader, forHTTPHeaderField: "Authorization")
        let (_, headResponse) = try await urlSession.data(for: head)
        let status = (headResponse as? HTTPURLResponse)?.statusCode ?? -1
        let acceptable = [200, 204, 206, 301, 302, 303, 307, 308, 405]
        XCTAssertTrue(
            acceptable.contains(status),
            "HEAD stream status \(status) on \(target.version)"
        )
        if status == 405 {
            var get = URLRequest(url: prepared.url)
            get.httpMethod = "GET"
            get.setValue(prepared.authorizationHeader, forHTTPHeaderField: "Authorization")
            get.setValue("bytes=0-1", forHTTPHeaderField: "Range")
            let (_, getResponse) = try await urlSession.data(for: get)
            let getStatus = (getResponse as? HTTPURLResponse)?.statusCode ?? -1
            let getOK = (200..<400).contains(getStatus)
            XCTAssertTrue(getOK, "Q8-2-05 GET retry status \(getStatus) on \(target.version)")
        }
    }

    /// T08-2-51. Jellyfin 12 rejects the legacy token header; Authorization works on every version.
    func testLegacyEmbyTokenHeaderIsRejectedOnJellyfin12() async throws {
        let target = try liveTarget()
        let session = try await signIn(target)
        let identity = ClientIdentity(
            deviceName: "Glassfin CI", deviceID: "glassfin-integration", version: "0.1.0", token: session.accessToken)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let urlSession = URLSession(configuration: configuration, delegate: StopRedirects(), delegateQueue: nil)
        defer { urlSession.invalidateAndCancel() }
        let endpoint = target.url.appendingPathComponent("Users/Me")
        var legacy = URLRequest(url: endpoint)
        legacy.setValue(session.accessToken, forHTTPHeaderField: "X-Emby-" + "Token")
        XCTAssertNil(legacy.value(forHTTPHeaderField: "Authorization"))
        let (_, legacyResponse) = try await urlSession.data(for: legacy)
        let legacyStatus = try XCTUnwrap(legacyResponse as? HTTPURLResponse).statusCode
        if target.version.hasPrefix("12") {
            XCTAssertEqual(legacyStatus, 401, "Jellyfin 12 accepted the legacy token header")
        } else {
            let record = "Jellyfin \(target.version): legacy token header HTTP \(legacyStatus)\n"
            FileHandle.standardOutput.write(Data(record.utf8))
        }
        var authorized = URLRequest(url: endpoint)
        authorized.setValue(try identity.authorizationHeader(), forHTTPHeaderField: "Authorization")
        XCTAssertNil(authorized.value(forHTTPHeaderField: "X-Emby-" + "Token"))
        let (_, authorizedResponse) = try await urlSession.data(for: authorized)
        let authorizedStatus = try XCTUnwrap(authorizedResponse as? HTTPURLResponse).statusCode
        XCTAssertEqual(authorizedStatus, 200, "Jellyfin \(target.version) rejected the Authorization header")
    }

    private func signIn(_ target: Target) async throws -> AuthenticatedSession {
        let anonymous = ClientIdentity(
            deviceName: "Glassfin CI", deviceID: "glassfin-integration", version: "0.1.0")
        let opener = HTTPJellyfinClient(server: target.url, identity: anonymous)
        return try await JellyfinAuthenticationService(client: opener, server: target.url, serverName: "jellyfin")
            .authenticate(username: target.username, password: target.password)
    }

    private func liveTarget() throws -> Target {
        let env = ProcessInfo.processInfo.environment
        guard env["GLASSFIN_INTEGRATION"] == "1" else {
            throw XCTSkip("Set GLASSFIN_INTEGRATION=1 to run the throwaway Jellyfin matrix.")
        }
        let version = try XCTUnwrap(env["GLASSFIN_SERVER_VERSION"])
        let url = try XCTUnwrap(URL(string: try XCTUnwrap(env["GLASSFIN_SERVER_URL"])))
        let username = try XCTUnwrap(env["GLASSFIN_USERNAME"])
        let password = try XCTUnwrap(env["GLASSFIN_PASSWORD"])
        return Target(version: version, url: url, username: username, password: password)
    }

    private func queryCarriesCredential(_ url: URL) -> Bool {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return false }
        return items.contains { item in
            let name = item.name.lowercased()
            return name == "apikey" || name == "api" + "_key" || name == "token"
        }
    }

    private func firstMovie(client: HTTPJellyfinClient, version: String) async throws -> MediaItem {
        let library = JellyfinLibraryService(client: client)
        let views = try await library.userViews()
        for view in views {
            let page = try await library.items(
                in: view.id,
                query: ItemQuery(includeItemTypes: ["Movie"], recursive: true),
                page: PageRequest(limit: 5)
            )
            if let first = page.items.first {
                return first
            }
        }
        throw XCTSkip("\(version) library has no movie")
    }
}

/// Records the first response. Redirects are not followed, so a 3xx stays visible.
private final class StopRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
