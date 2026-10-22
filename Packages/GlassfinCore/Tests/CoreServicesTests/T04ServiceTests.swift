import CoreModels
import CoreNetworking
import Foundation
import GlassfinServices
import XCTest

final class T04ServiceTests: XCTestCase {
    func testT04_35_quickConnectInitiateIsPost() async throws {
        let client = RecordingClient()
        client.payload = Data(#"{"Code":"482913","Secret":"hidden","Authenticated":false}"#.utf8)
        let service = JellyfinAuthenticationService(
            client: client, server: try XCTUnwrap(URL(string: "https://media.example/jellyfin")))
        let challenge = try await service.initiateQuickConnect()
        XCTAssertEqual(client.methods, ["POST"])
        XCTAssertEqual(client.paths, ["/QuickConnect/Initiate"])
        XCTAssertEqual(challenge.code, "482913")
        XCTAssertFalse(challenge.authenticated)
        XCTAssertFalse(String(describing: challenge).contains("hidden"))
    }

    func testT04_51_unicodeCredentialsStayInTheJSONBody() async throws {
        let client = RecordingClient()
        client.payload = Data(
            #"{"AccessToken":"token","ServerId":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","User":{"Id":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","Name":"Äijä"}}"#
                .utf8)
        let service = JellyfinAuthenticationService(
            client: client, server: try XCTUnwrap(URL(string: "https://media.example")))
        _ = try await service.authenticate(username: "Äijä", password: "pässi🔑+ \"x\"")
        let body = try XCTUnwrap(client.bodies.first)
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("Äijä"))
        XCTAssertTrue(text.contains("pässi🔑"))
        XCTAssertEqual(client.methods, ["POST"])
        XCTAssertEqual(client.paths, ["/Users/AuthenticateByName"])
    }

    func testT04_52_capabilitiesBodyOmitsDeviceProfile() async throws {
        let client = RecordingClient()
        client.payload = Data("{}".utf8)
        let service = JellyfinAuthenticationService(
            client: client, server: try XCTUnwrap(URL(string: "https://media.example")))
        try await service.postCapabilities(playableMediaTypes: ["Video", "Audio"], supportsMediaControl: true)
        let text = String(decoding: try XCTUnwrap(client.bodies.first), as: UTF8.self)
        XCTAssertTrue(text.contains("Video"))
        XCTAssertTrue(text.contains("Audio"))
        XCTAssertTrue(text.contains("SupportsMediaControl"))
        XCTAssertFalse(text.contains("DeviceProfile"))
        XCTAssertEqual(client.paths, ["/Sessions/Capabilities/Full"])
        XCTAssertEqual(client.methods, ["POST"])
    }

    func testSubpathIsKeptOnLoginAndCurrentUser() async throws {
        let server = try XCTUnwrap(URL(string: "https://media.example/jellyfin"))
        let client = RecordingClient()
        client.payload = Data(
            #"{"AccessToken":"token","User":{"Id":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","Name":"Ada"}}"#.utf8)
        let service = JellyfinAuthenticationService(client: client, server: server, knownServer: nil)
        _ = try await service.authenticate(username: "Ada", password: "secret")
        let login = ServerAddressCandidates.appendingAPIPath(server, path: "/Users/AuthenticateByName")
        XCTAssertEqual(login?.path, "/jellyfin/Users/AuthenticateByName")
        let me = ServerAddressCandidates.appendingAPIPath(server, path: "/Users/Me")
        XCTAssertEqual(me?.path, "/jellyfin/Users/Me")
    }
}

private final class RecordingClient: JellyfinAPIClient, @unchecked Sendable {
    var methods: [String] = []
    var paths: [String] = []
    var bodies: [Data] = []
    var payload = Data()

    func send(_ request: APIRequest) async throws(APIError) -> Data {
        methods.append(request.method)
        paths.append(request.path)
        if let body = request.body { bodies.append(body) }
        return payload
    }
}
