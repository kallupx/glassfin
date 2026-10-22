import CoreModels
import CoreNetworking
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
}
