import CoreModels
import CoreNetworking
import CorePlayback
import CoreTestSupport
import Foundation
import GlassfinServices
import XCTest

final class ServiceEndpointTests: XCTestCase {
    private let server = URL(string: "http://127.0.0.1:8096")!
    private let itemGUID = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    private let seriesGUID = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    private let seasonGUID = "cccccccccccccccccccccccccccccccc"
    private let movieGUID = "dddddddddddddddddddddddddddddddd"
    private let sourceGUID = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

    func testP0EndpointMatrix() async {
        let names = [
            "publicInfo", "ping", "authenticate", "quickConnectEnabled", "initiateQuickConnect",
            "quickConnectState", "authenticateQuickConnect", "logout", "currentUser", "publicUsers",
            "postCapabilities", "userViews", "items", "resume", "nextUp", "latest", "seasons",
            "episodes", "item", "similar", "filters", "setPlayed", "setFavorite", "userData",
            "updateUserData", "hints", "playbackInfo", "mediaSegments", "bitrateTest",
            "started", "progress", "stopped", "pingSession",
        ]
        for name in names {
            await expect(name, scenario: .ok)
            await expect(name, scenario: .unauthorized)
            await expect(name, scenario: .notFound)
            await expect(name, scenario: .server)
            await expect(name, scenario: .timeout)
            await expect(name, scenario: .badJSON)
        }
    }

    func testQuickConnectInitiateIsPost() async throws {
        let client = MockAPIClient { _ in
            Data("{\"Code\":\"123456\",\"Secret\":\"secret-value\"}".utf8)
        }
        let auth = JellyfinAuthenticationService(client: client, server: server)
        let challenge = try await auth.initiateQuickConnect()
        XCTAssertEqual(challenge.code, "123456")
        let calls = await client.calls
        XCTAssertEqual(calls.first?.method, "POST")
        XCTAssertEqual(calls.first?.path, "/QuickConnect/Initiate")
    }

    func testLogoutUsesSessionsLogout() async throws {
        let client = MockAPIClient { _ in Data() }
        let auth = JellyfinAuthenticationService(client: client, server: server)
        try await auth.logout()
        let calls = await client.calls
        XCTAssertEqual(calls.first?.method, "POST")
        XCTAssertEqual(calls.first?.path, "/Sessions/Logout")
    }

    func testOutboundPositionTicksAreNeverNegative() async throws {
        let client = MockAPIClient { _ in Data() }
        let reporting = JellyfinReportingService(client: client)
        try await reporting.started(itemID: "item", position: .seconds(-3), playSessionID: "play")
        try await reporting.progress(itemID: "item", position: .seconds(-3), playSessionID: "play", paused: true)
        try await reporting.stopped(itemID: "item", position: .seconds(-3), playSessionID: "play", failed: false)
        let library = JellyfinLibraryService(client: client)
        try await library.updateUserData(id: itemGUID, position: .seconds(-9), played: false)
        let playback = JellyfinPlaybackInfoService(client: client, server: server)
        let playbackBody = Data(
            "{\"MediaSources\":[{\"Id\":\"source\",\"SupportsDirectPlay\":true}],\"PlaySessionId\":\"play\"}".utf8
        )
        await client.setHandler { request in
            request.path.contains("PlaybackInfo") ? playbackBody : Data()
        }
        _ = try await playback.playbackInfo(itemID: itemGUID, start: .seconds(-2), maxBitrate: 20_000_000)
        let calls = await client.calls
        for call in calls {
            let body = call.body ?? Data()
            let text = String(decoding: body, as: UTF8.self)
            XCTAssertFalse(text.contains("-"), "\(call.path) sent a negative number: \(text)")
            if text.contains("PositionTicks") || text.contains("PlaybackPositionTicks")
                || text.contains("StartTimeTicks")
            {
                XCTAssertTrue(text.contains(":0"))
            }
        }
    }

    /// T01-24. Image and stream requests never send the header and an ApiKey query together.
    func testT01_24_imageAndStreamNeverCombineHeaderAndApiKey() throws {
        let identity = ClientIdentity(
            deviceName: "Living Room", deviceID: "device-1", version: "0.1.0", token: "token-secret")
        let media = JellyfinMediaURLService(server: server, identity: identity)
        let header = try media.stream(
            itemID: movieGUID, mediaSourceID: sourceGUID, playSessionID: "play", mode: .header)
        XCTAssertNotNil(header.authorizationHeader)
        XCTAssertFalse(header.url.absoluteString.contains("ApiKey"))
        let query = try media.stream(
            itemID: movieGUID, mediaSourceID: sourceGUID, playSessionID: "play", mode: .apiKeyQuery)
        XCTAssertNil(query.authorizationHeader)
        XCTAssertTrue(query.usesAPIKeyQuery)
        let image = try JellyfinImageService(server: server, identity: identity).imageRequest(
            itemID: movieGUID,
            imageType: "Primary",
            maxWidth: 400
        )
        XCTAssertFalse(image.url.absoluteString.contains("ApiKey"))
        let handoff = PlaybackHandoff.make(query)
        XCTAssertTrue(handoff.headerFields.isEmpty)
        XCTAssertEqual(ResolvedMediaURL.httpHeaderFieldsKey, "AVURLAssetHTTPHeaderFieldsKey")
        XCTAssertFalse(String(describing: handoff).contains("token-secret"))
        _ = try media.trickplay(itemID: movieGUID, width: 320, index: 0, mediaSourceID: sourceGUID)
        _ = try media.subtitles(itemID: movieGUID, mediaSourceID: sourceGUID, index: 1)
        XCTAssertTrue(header.url.path.contains(movieGUID))
        XCTAssertThrowsError(
            try media.stream(itemID: "../Admin", mediaSourceID: sourceGUID, playSessionID: "play", mode: .header)
        ) {
            XCTAssertEqual($0 as? APIError, .invalidItemID)
        }
    }

    func testInvalidItemIDIsNotSent() async {
        let client = MockAPIClient { _ in Data() }
        let library = JellyfinLibraryService(client: client)
        do {
            _ = try await library.item(id: "item/../../Users")
            XCTFail("Expected invalidItemID")
        } catch {
            XCTAssertEqual(error, .invalidItemID)
        }
        let calls = await client.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testCancellationIsNotUnauthorized() async {
        let client = MockAPIClient { _ throws(APIError) in
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                throw APIError.cancelled
            }
            return Data()
        }
        let task = Task {
            try await client.send(APIRequest(method: "GET", path: "/System/Ping"))
        }
        try? await Task.sleep(for: .milliseconds(30))
        task.cancel()
        let result = await task.result
        switch result {
        case .success:
            XCTFail("Cancelled request succeeded")
        case .failure(let error):
            let api = error as? APIError
            XCTAssertTrue(api == .cancelled || error is CancellationError)
            XCTAssertNotEqual(api, APIError.unauthorized)
        }
    }

    private enum Scenario {
        case ok
        case unauthorized
        case notFound
        case server
        case timeout
        case badJSON
    }

    private func expect(_ name: String, scenario: Scenario) async {
        let client = MockAPIClient { request throws(APIError) in
            switch scenario {
            case .ok:
                return Self.payload(for: request)
            case .badJSON:
                return Data("not-json".utf8)
            case .unauthorized:
                throw APIError.unauthorized
            case .notFound:
                throw APIError.notFound
            case .server:
                throw APIError.server(status: 500)
            case .timeout:
                throw APIError.timeout
            }
        }
        do {
            try await invoke(name, client: client)
            switch scenario {
            case .ok:
                break
            case .badJSON where name == "ping" || name == "bitrateTest":
                break
            default:
                XCTFail("\(name) \(scenario) succeeded")
            }
        } catch let error as APIError {
            switch scenario {
            case .ok:
                XCTFail("\(name) failed with \(error)")
            case .unauthorized:
                XCTAssertEqual(error, .unauthorized, name)
            case .notFound:
                XCTAssertEqual(error, .notFound, name)
            case .server:
                XCTAssertEqual(error, .server(status: 500), name)
            case .timeout:
                XCTAssertEqual(error, .timeout, name)
            case .badJSON:
                XCTAssertEqual(error, .decoding, name)
            }
        } catch {
            XCTFail("\(name) threw \(error)")
        }
    }

    private func invoke(_ name: String, client: MockAPIClient) async throws {
        let system = JellyfinSystemService(client: client, server: server)
        let auth = JellyfinAuthenticationService(client: client, server: server, serverName: "Home")
        let library = JellyfinLibraryService(client: client)
        let search = JellyfinSearchService(client: client)
        let playback = JellyfinPlaybackInfoService(client: client, server: server)
        let reporting = JellyfinReportingService(client: client)
        switch name {
        case "publicInfo": _ = try await system.publicInfo()
        case "ping": _ = try await system.ping()
        case "authenticate": _ = try await auth.authenticate(username: "ada", password: "secret")
        case "quickConnectEnabled": _ = try await auth.quickConnectEnabled()
        case "initiateQuickConnect": _ = try await auth.initiateQuickConnect()
        case "quickConnectState": _ = try await auth.quickConnectState(secret: "secret-value")
        case "authenticateQuickConnect": _ = try await auth.authenticate(quickConnectSecret: "secret-value")
        case "logout": try await auth.logout()
        case "currentUser": _ = try await auth.currentUser()
        case "publicUsers": _ = try await auth.publicUsers()
        case "postCapabilities":
            try await auth.postCapabilities(playableMediaTypes: ["Video"], supportsMediaControl: true)
        case "userViews": _ = try await library.userViews()
        case "items": _ = try await library.items(in: "lib", query: ItemQuery(), page: PageRequest())
        case "resume": _ = try await library.resume(limit: 10)
        case "nextUp": _ = try await library.nextUp(limit: 10)
        case "latest": _ = try await library.latest(in: "lib", limit: 10)
        case "seasons": _ = try await library.seasons(series: seriesGUID)
        case "episodes": _ = try await library.episodes(series: seriesGUID, season: seasonGUID)
        case "item": _ = try await library.item(id: itemGUID)
        case "similar": _ = try await library.similar(id: itemGUID, limit: 5)
        case "filters": _ = try await library.filters(in: "lib")
        case "setPlayed": try await library.setPlayed(itemGUID, true)
        case "setFavorite": try await library.setFavorite(itemGUID, false)
        case "userData": _ = try await library.userData(id: itemGUID)
        case "updateUserData": try await library.updateUserData(id: itemGUID, position: .seconds(2), played: false)
        case "hints": _ = try await search.hints(term: "north", limit: 5)
        case "playbackInfo":
            _ = try await playback.playbackInfo(itemID: itemGUID, start: .zero, maxBitrate: 8_000_000)
        case "mediaSegments": _ = try await playback.mediaSegments(itemID: itemGUID)
        case "bitrateTest": _ = try await playback.bitrateTest(size: 1_000_000)
        case "started": try await reporting.started(itemID: "item", position: .seconds(1), playSessionID: "play")
        case "progress":
            try await reporting.progress(itemID: "item", position: .seconds(1), playSessionID: "play", paused: false)
        case "stopped":
            try await reporting.stopped(itemID: "item", position: .seconds(1), playSessionID: "play", failed: false)
        case "pingSession": try await reporting.ping(playSessionID: "play")
        default: XCTFail("Unknown endpoint \(name)")
        }
    }

    private static func payload(for request: APIRequest) -> Data {
        let path = request.path
        if path == "/System/Ping" { return Data("Jellyfin Server".utf8) }
        if path == "/QuickConnect/Enabled" { return Data("true".utf8) }
        if path == "/Playback/BitrateTest" { return Data(repeating: 1, count: 4) }
        if path == "/System/Info/Public" {
            return Data("{\"ServerName\":\"Home\",\"Version\":\"12.2.0\",\"Id\":\"srv\"}".utf8)
        }
        if path == "/Users/AuthenticateByName" || path == "/Users/AuthenticateWithQuickConnect" {
            return Data(
                "{\"AccessToken\":\"token-value\",\"ServerId\":\"srv\",\"User\":{\"Id\":\"user\",\"Name\":\"Ada\",\"Policy\":{\"IsAdministrator\":false}}}"
                    .utf8
            )
        }
        if path == "/QuickConnect/Initiate" || path == "/QuickConnect/Connect" {
            return Data("{\"Code\":\"123456\",\"Secret\":\"secret-value\"}".utf8)
        }
        if path == "/Users/Me" {
            return Data("{\"Id\":\"user\",\"Name\":\"Ada\",\"Policy\":{\"IsAdministrator\":true}}".utf8)
        }
        if path == "/Users/Public" {
            return Data("[{\"Id\":\"user\",\"Name\":\"Ada\"}]".utf8)
        }
        if path == "/Items/Latest" {
            return Data("[{\"Id\":\"movie\",\"Name\":\"North\",\"Type\":\"Movie\"}]".utf8)
        }
        if path == "/Items/Filters2" {
            return Data("{\"Genres\":[\"Drama\"],\"Years\":[2024]}".utf8)
        }
        if path == "/Search/Hints" {
            return Data("{\"SearchHints\":[{\"ItemId\":\"movie\",\"Name\":\"North\",\"Type\":\"Movie\"}]}".utf8)
        }
        if path.contains("/PlaybackInfo") {
            return Data(
                "{\"MediaSources\":[{\"Id\":\"source\",\"SupportsDirectPlay\":true}],\"PlaySessionId\":\"play\"}".utf8)
        }
        if path.hasPrefix("/MediaSegments/") {
            return Data("[{\"Type\":\"Intro\",\"StartTicks\":0,\"EndTicks\":10000000}]".utf8)
        }
        if path.hasSuffix("/UserData") && request.method == "GET" {
            return Data("{\"Played\":false,\"PlaybackPositionTicks\":0,\"IsFavorite\":false}".utf8)
        }
        if path == "/UserViews" || path == "/Items" || path == "/UserItems/Resume" || path == "/Shows/NextUp"
            || path.hasPrefix("/Shows/") || path.hasSuffix("/Similar")
        {
            return Data(
                "{\"Items\":[{\"Id\":\"item\",\"Name\":\"North\",\"Type\":\"Movie\"}],\"TotalRecordCount\":1}".utf8)
        }
        if path.hasPrefix("/Items/") {
            return Data("{\"Id\":\"item\",\"Name\":\"North\",\"Type\":\"Movie\"}".utf8)
        }
        return Data()
    }
}
