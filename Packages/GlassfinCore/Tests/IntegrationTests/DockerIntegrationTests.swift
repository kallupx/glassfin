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

    /// T09-21. Alternating paired samples after two warm-ups; no query text in output.
    func testT09_21_searchBackendLatencyAndResultCounts() async throws {
        let target = try liveTarget()
        let auth = try await signIn(target)
        let identity = ClientIdentity(
            deviceName: "Glassfin CI", deviceID: "glassfin-search-benchmark", version: "0.1.0", token: auth.accessToken)
        let client = HTTPJellyfinClient(server: target.url, identity: identity)
        let backends: [any SearchBackend] = [ItemsSearchBackend(client: client), SearchHintsBackend(client: client)]
        var measurements: [[SearchBenchmarkSample]] = [[], []]
        for iteration in 0..<14 {
            for index in iteration.isMultiple(of: 2) ? [0, 1] : [1, 0] {
                let start = ContinuousClock.now
                let response = try await backends[index].results(
                    term: "Glassfin Bench", kind: nil, page: PageRequest(limit: SearchPolicy.pageSize))
                let duration = start.duration(to: .now).components
                let milliseconds = Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
                if iteration >= 2 {
                    measurements[index].append(
                        SearchBenchmarkSample(
                            milliseconds: milliseconds,
                            counts: SearchKind.allCases.map { kind in
                                response.groups.first { $0.id == kind }?.items.count ?? 0
                            },
                            withPrimaryImage: response.groups.flatMap(\.items).filter { $0.images.primaryTag != nil }
                                .count))
                }
            }
        }
        let report = SearchBenchmarkReport(
            serverVersion: target.version, seededItems: 5_000,
            items: measurements[0], hints: measurements[1])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(report)
        FileHandle.standardOutput.write(Data("T09-21 search-benchmark ".utf8) + data + Data("\n".utf8))
        let configured = ProcessInfo.processInfo.environment["GLASSFIN_SEARCH_BENCHMARK_DIR"]
        let directory =
            configured.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("glassfin-search-benchmark")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("search-\(target.version).json"), options: .atomic)
        XCTAssertEqual(measurements[0].count, 12)
        XCTAssertTrue(measurements[0].allSatisfy { $0.counts == Array(repeating: SearchPolicy.pageSize, count: 3) })
        XCTAssertTrue(measurements[1].allSatisfy { $0.counts.reduce(0, +) > 0 })
    }

    /// T09-22. A real seeded umlaut item must be found through both endpoints.
    func testT09_22_searchFindsUmlautSeedWithBothBackends() async throws {
        let target = try liveTarget()
        let auth = try await signIn(target)
        let client = HTTPJellyfinClient(
            server: target.url,
            identity: ClientIdentity(
                deviceName: "Glassfin CI", deviceID: "glassfin-search-unicode", version: "0.1.0",
                token: auth.accessToken))
        for backend: any SearchBackend in [ItemsSearchBackend(client: client), SearchHintsBackend(client: client)] {
            let response = try await backend.results(
                term: "Sääasema", kind: nil, page: PageRequest(limit: SearchPolicy.pageSize))
            XCTAssertTrue(response.groups.flatMap(\.items).contains { $0.name.contains("Sääasema") })
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

private struct SearchBenchmarkSample: Codable {
    var milliseconds: Double
    /// Movies, series, episodes, in that order.
    var counts: [Int]
    var withPrimaryImage: Int
}

private struct SearchBenchmarkReport: Encodable {
    var serverVersion: String
    var seededItems: Int
    var items: [SearchBenchmarkSample]
    var hints: [SearchBenchmarkSample]

    private enum CodingKeys: String, CodingKey {
        case serverVersion, seededItems, items, hints, itemsMedianMs, hintsMedianMs, itemsP95Ms, hintsP95Ms
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(serverVersion, forKey: .serverVersion)
        try values.encode(seededItems, forKey: .seededItems)
        try values.encode(items, forKey: .items)
        try values.encode(hints, forKey: .hints)
        try values.encode(percentile(items, fraction: 0.5), forKey: .itemsMedianMs)
        try values.encode(percentile(hints, fraction: 0.5), forKey: .hintsMedianMs)
        try values.encode(percentile(items, fraction: 0.95), forKey: .itemsP95Ms)
        try values.encode(percentile(hints, fraction: 0.95), forKey: .hintsP95Ms)
    }

    private func percentile(_ samples: [SearchBenchmarkSample], fraction: Double) -> Double {
        let sorted = samples.map(\.milliseconds).sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[max(0, Int((Double(sorted.count) * fraction).rounded(.up)) - 1)]
    }
}
