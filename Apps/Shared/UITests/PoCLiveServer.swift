import Foundation

/// Test-only access to the live Jellyfin server used by the PoC acceptance journeys
/// (spec/TESTPLAN-PoC-ACCEPTANCE.md). It never runs against the in-app mock server.
///
/// Configuration comes from the test runner environment. With `xcodebuild test`, export each
/// variable with the `TEST_RUNNER_` prefix (for example `TEST_RUNNER_GLASSFIN_POC_SERVER_URL`).
/// Credentials are read only from the environment, are never hardcoded, and are never written
/// to failure messages, attachments or logs (TPOC-79, TPOC-80).
struct PoCLiveServerConfiguration: Sendable {
    static let serverURLKey = "GLASSFIN_POC_SERVER_URL"
    static let usernameKey = "GLASSFIN_POC_USERNAME"
    static let passwordKey = "GLASSFIN_POC_PASSWORD"
    static let adminUsernameKey = "GLASSFIN_POC_ADMIN_USERNAME"
    static let adminPasswordKey = "GLASSFIN_POC_ADMIN_PASSWORD"
    static let allKeys = [serverURLKey, usernameKey, passwordKey, adminUsernameKey, adminPasswordKey]

    let serverURL: URL
    let username: String
    let password: String
    let adminUsername: String
    let adminPassword: String

    /// Returns nil when any variable is missing, so the journey can be skipped rather than failed.
    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Self? {
        let values = allKeys.map { (environment[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !values.contains(where: \.isEmpty), let url = URL(string: values[0]), url.scheme != nil else {
            return nil
        }
        return Self(
            serverURL: url, username: values[1], password: values[2], adminUsername: values[3],
            adminPassword: values[4])
    }

    static var skipReason: String {
        "Live PoC journey: set \(allKeys.joined(separator: ", ")) (prefix TEST_RUNNER_ for xcodebuild) "
            + "against a seeded native macOS Jellyfin server (TPOC-02) and a clean simulator (TPOC-04)."
    }
}

/// One movie from the seeded "Movies" library (TESTPLAN-M08a-PoC Appendix A).
struct PoCSeedMovie: Sendable, Equatable {
    let id: String
    let name: String
    let libraryID: String
}

/// The fields of `GET /Sessions` the acceptance rows assert on.
struct PoCPlaybackSession: Sendable, Equatable {
    var playMethod: String?
    var positionTicks: Int64
    var isPaused: Bool
    var hasTranscodingInfo: Bool
    var isVideoDirect: Bool?
    var isAudioDirect: Bool?
    var audioCodec: String?
    var transcodeReasons: [String]

    /// Video reasons from SPEC.md Q8P-05; any of these means the server re-encodes video.
    static let videoReasons: Set<String> = [
        "VideoCodecNotSupported", "VideoProfileNotSupported", "VideoRangeTypeNotSupported",
        "VideoCodecTagNotSupported", "VideoLevelNotSupported", "VideoResolutionNotSupported",
        "VideoBitDepthNotSupported", "VideoFramerateNotSupported", "RefFramesNotSupported",
        "AnamorphicVideoNotSupported", "InterlacedVideoNotSupported", "VideoBitrateNotSupported",
        "UnknownVideoStreamInfo", "VideoRotationNotSupported",
    ]

    var videoTranscodeReasons: [String] { transcodeReasons.filter(Self.videoReasons.contains) }

    init(json: [String: Any]) {
        let playState = json["PlayState"] as? [String: Any] ?? [:]
        playMethod = playState["PlayMethod"] as? String
        positionTicks = (playState["PositionTicks"] as? NSNumber)?.int64Value ?? 0
        isPaused = (playState["IsPaused"] as? Bool) ?? false
        let transcoding = json["TranscodingInfo"] as? [String: Any]
        hasTranscodingInfo = transcoding != nil
        isVideoDirect = transcoding?["IsVideoDirect"] as? Bool
        isAudioDirect = transcoding?["IsAudioDirect"] as? Bool
        audioCodec = (transcoding?["AudioCodec"] as? String)?.lowercased()
        // Older servers serialize the flags as one comma-separated string, newer ones as an array.
        switch transcoding?["TranscodeReasons"] {
        case let list as [String]: transcodeReasons = list
        case let text as String: transcodeReasons = text.split(separator: ",").map { String($0) }
        default: transcodeReasons = []
        }
    }
}

enum PoCLiveServerError: Error, CustomStringConvertible {
    case http(path: String, status: Int)
    case decoding(path: String)
    case missingSeed(String)
    case noPlaybackSession(String)

    var description: String {
        switch self {
        case .http(let path, let status): "Live server \(path) returned HTTP \(status)"
        case .decoding(let path): "Live server \(path) returned an unexpected body"
        case .missingSeed(let what): "Seed is missing \(what) (TPOC-02 / QPOC-03)"
        case .noPlaybackSession(let state): "The server never reported a transcoding session (\(state))"
        }
    }
}

/// Minimal admin API client for server-side assertions (`/Sessions`, `/Items`, UserData).
/// It uses its own device identity, so its session never matches the app under test.
final class PoCLiveServer: Sendable {
    let configuration: PoCLiveServerConfiguration
    private let adminToken: String
    let testUserID: String

    private static let clientFields =
        #"Client="Glassfin PoC UITests", Device="uitest-runner", DeviceId="glassfin-poc-uitest-runner", "#
        + #"Version="0.1.0""#

    private init(configuration: PoCLiveServerConfiguration, adminToken: String, testUserID: String) {
        self.configuration = configuration
        self.adminToken = adminToken
        self.testUserID = testUserID
    }

    static func connect(_ configuration: PoCLiveServerConfiguration) async throws -> PoCLiveServer {
        let body = try JSONSerialization.data(withJSONObject: [
            "Username": configuration.adminUsername, "Pw": configuration.adminPassword,
        ])
        let auth = try await rawRequest(
            configuration.serverURL, "POST", "/Users/AuthenticateByName", token: nil, body: body)
        guard let token = auth["AccessToken"] as? String, !token.isEmpty else {
            throw PoCLiveServerError.decoding(path: "/Users/AuthenticateByName")
        }
        let users = try await rawList(configuration.serverURL, "/Users", token: token)
        guard let user = users.first(where: { ($0["Name"] as? String) == configuration.username }),
            let userID = user["Id"] as? String
        else { throw PoCLiveServerError.missingSeed("the non-admin test user") }
        return PoCLiveServer(configuration: configuration, adminToken: token, testUserID: userID)
    }

    /// Finds the seeded movie by its media, not by its title, so title changes in the seed do not matter.
    /// F3: MKV, H.264 + AAC. F4: MKV, H.264 + DTS.
    func movie(container: String, videoCodec: String, audioCodec: String) async throws -> PoCSeedMovie {
        let views = try await object("/UserViews?userId=\(testUserID)")
        let libraries = views["Items"] as? [[String: Any]] ?? []
        guard let movies = libraries.first(where: { ($0["CollectionType"] as? String) == "movies" }),
            let libraryID = movies["Id"] as? String
        else { throw PoCLiveServerError.missingSeed("a Movies library") }
        let page = try await object(
            "/Items?userId=\(testUserID)&parentId=\(libraryID)&recursive=true&includeItemTypes=Movie"
                + "&fields=MediaStreams,MediaSources")
        for item in page["Items"] as? [[String: Any]] ?? [] {
            guard let id = item["Id"] as? String, let name = item["Name"] as? String else { continue }
            let sources = item["MediaSources"] as? [[String: Any]] ?? []
            let source = sources.first ?? [:]
            let streams = (source["MediaStreams"] as? [[String: Any]]) ?? (item["MediaStreams"] as? [[String: Any]])
            let codecs = (streams ?? []).map {
                (($0["Type"] as? String) ?? "", (($0["Codec"] as? String) ?? "").lowercased())
            }
            let containers = ((source["Container"] as? String) ?? (item["Container"] as? String) ?? "")
                .lowercased().split(separator: ",").map { String($0) }
            if containers.contains(container) && codecs.contains(where: { $0 == ("Video", videoCodec) })
                && codecs.contains(where: { $0 == ("Audio", audioCodec) })
            {
                return PoCSeedMovie(id: id, name: name, libraryID: libraryID)
            }
        }
        throw PoCLiveServerError.missingSeed("a \(container) \(videoCodec) + \(audioCodec) movie")
    }

    /// The test user's session that is playing `itemID`, if any.
    func playbackSession(itemID: String) async throws -> PoCPlaybackSession? {
        let sessions = try await list("/Sessions")
        let match = sessions.first {
            ($0["UserId"] as? String) == testUserID
                && (($0["NowPlayingItem"] as? [String: Any])?["Id"] as? String) == itemID
        }
        return match.map(PoCPlaybackSession.init(json:))
    }

    func isPlayed(itemID: String) async throws -> Bool {
        let item = try await object("/Items/\(itemID)?userId=\(testUserID)")
        return ((item["UserData"] as? [String: Any])?["Played"] as? Bool) ?? false
    }

    /// Resets watched state and position so every journey starts from "Play" (journey isolation).
    func resetUserData(itemID: String) async throws {
        _ = try await Self.rawRequest(
            configuration.serverURL, "DELETE", "/UserPlayedItems/\(itemID)?userId=\(testUserID)",
            token: adminToken, body: nil, allowEmpty: true)
    }

    private func object(_ path: String) async throws -> [String: Any] {
        try await Self.rawRequest(configuration.serverURL, "GET", path, token: adminToken, body: nil)
    }

    private func list(_ path: String) async throws -> [[String: Any]] {
        try await Self.rawList(configuration.serverURL, path, token: adminToken)
    }

    private static func rawList(_ base: URL, _ path: String, token: String) async throws -> [[String: Any]] {
        let data = try await data(base, "GET", path, token: token, body: nil)
        guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw PoCLiveServerError.decoding(path: redacted(path))
        }
        return list
    }

    private static func rawRequest(
        _ base: URL, _ method: String, _ path: String, token: String?, body: Data?, allowEmpty: Bool = false
    ) async throws -> [String: Any] {
        let data = try await data(base, method, path, token: token, body: body)
        if allowEmpty && data.isEmpty { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PoCLiveServerError.decoding(path: redacted(path))
        }
        return object
    }

    private static func data(_ base: URL, _ method: String, _ path: String, token: String?, body: Data?)
        async throws -> Data
    {
        let trimmed = base.absoluteString.hasSuffix("/") ? String(base.absoluteString.dropLast()) : base.absoluteString
        guard let url = URL(string: trimmed + path) else { throw PoCLiveServerError.decoding(path: redacted(path)) }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The token travels only in the Authorization header, never in a query (03-security S5).
        let tokenField = token.map { #", Token="\#($0)""# } ?? ""
        request.setValue("MediaBrowser \(clientFields)\(tokenField)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw PoCLiveServerError.http(path: redacted(path), status: status) }
        return data
    }

    /// Paths never contain credentials; the query is dropped anyway so IDs do not clutter reports.
    private static func redacted(_ path: String) -> String {
        String(path.split(separator: "?", maxSplits: 1).first ?? "")
    }
}
