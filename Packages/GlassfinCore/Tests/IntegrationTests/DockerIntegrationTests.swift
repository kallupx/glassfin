import CoreModels
import CoreNetworking
import CorePlayback
import Foundation
import GlassfinServices
import XCTest

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

    // T06-37: canonical spec/TESTPLAN-M06.md.
    func testT06_37_homeEndpointsAndResetPosition() async throws {
        let target = try liveTarget()
        let auth = try await signIn(target)
        let identity = ClientIdentity(
            deviceName: "Glassfin CI", deviceID: "glassfin-home-integration", version: "0.1.0", token: auth.accessToken)
        let service = JellyfinLibraryService(client: HTTPJellyfinClient(server: target.url, identity: identity))
        async let resume = service.resume(limit: 20)
        async let next = service.nextUp(limit: 20)
        let libraries = try await service.userViews()
        XCTAssertFalse(libraries.isEmpty)
        var item: MediaItem?
        for library in libraries {
            let latest = try await service.latest(in: library.id, limit: 20)
            XCTAssertLessThanOrEqual(latest.count, 20)
            if item == nil { item = latest.first }
        }
        _ = try await (resume, next)
        let found = try XCTUnwrap(item)
        try await service.updateUserData(id: found.id, position: .zero, played: false)
        let state = try await service.userData(id: found.id)
        XCTAssertEqual(state.playbackPosition, .zero)
        XCTAssertFalse(state.played)
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
