import CoreModels
import CoreNetworking
import Foundation
import XCTest

@testable import CoreNetworking
@testable import CorePlayback

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

let pocItemID = "00112233445566778899aabbccddeeff"
let pocUserID = "11112233445566778899aabbccddeeff"
let pocSourceID = "22112233445566778899aabbccddeeff"

func playbackFixture(
    container: String = "mp4", video: String = "h264", audio: String = "aac",
    direct: Bool = true, transcodingURL: String? = nil, playSessionID: String = "play-session"
) throws -> Data {
    var source: [String: Any] = [
        "Id": pocSourceID, "Container": container, "SupportsDirectPlay": direct,
        "SupportsDirectStream": true, "SupportsTranscoding": true,
        "MediaStreams": [["Type": "Video", "Codec": video], ["Type": "Audio", "Codec": audio]],
    ]
    source["TranscodingUrl"] = transcodingURL
    return try JSONSerialization.data(withJSONObject: ["PlaySessionId": playSessionID, "MediaSources": [source]])
}

func playbackItemFixture(from info: Data) throws -> Data {
    var item = try JSONSerialization.jsonObject(with: info) as? [String: Any] ?? [:]
    item["MediaStreams"] = (item["MediaSources"] as? [[String: Any]])?.first?["MediaStreams"]
    item["UserData"] = ["PlaybackPositionTicks": 125_000_000]
    return try JSONSerialization.data(withJSONObject: item)
}

func jsonBody(_ data: Data?) throws -> [String: Any] {
    let bytes = try XCTUnwrap(data)
    return try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
}

final class PlaybackPoCDecisionTests: XCTestCase {
    /// T08P-06/T08P-07/T08P-08/T08P-10/T08P-12/T08P-14/T08P-16: client and server must agree, including a video-copy-only fallback.
    func testT08P_06_07_08_10_12_14_16_profileDecisionMatrix() throws {
        let cases: [(String, String, String, Bool, String?, PlaybackDecision)] = [
            ("mp4", "h264", "aac", true, nil, .directPlay),
            ("mov", "hevc", "eac3", true, nil, .directPlay),
            ("m4v", "hevc", "ac3", true, nil, .directPlay),
            ("hls", "h264", "aac", true, nil, .directPlay),
            ("mkv", "h264", "aac", false, "/master.m3u8", .directStream(.remux)),
            ("mkv", "h264", "dts", false, "/master.m3u8", .directStream(.audioTranscode)),
            ("mkv", "hevc", "ac3", false, "/master.m3u8", .directStream(.remux)),
            ("mp4", "hevc", "truehd", true, "/master.m3u8", .directStream(.audioTranscode)),
            ("mp4", "h264", "aac", false, nil, .unsupported(.couldNotPlay)),
            ("mkv", "h264", "aac", false, "", .unsupported(.couldNotPlay)),
        ]
        for (container, video, audio, direct, url, expected) in cases {
            let data = try playbackFixture(
                container: container, video: video, audio: audio, direct: direct, transcodingURL: url)
            let dto = try JSONDecoder().decode(PlaybackInfoResponseDTO.self, from: data)
            let source = try XCTUnwrap(dto.MediaSources?.first)
            XCTAssertEqual(PlaybackDecision.decide(mediaSource: source), expected)
        }
        for codec in ["mpeg2video", "vc1", "av1", "mpeg4", "h265", "H265", ""] {
            let data = try playbackFixture(video: codec, transcodingURL: "/master.m3u8")
            let dto = try JSONDecoder().decode(PlaybackInfoResponseDTO.self, from: data)
            XCTAssertEqual(
                PlaybackDecision.decide(mediaSource: try XCTUnwrap(dto.MediaSources?.first)),
                .unsupported(.unsupportedVideo)
            )
        }

    }

    /// T08P-01/T08P-70: only supported codecs; HLS uses fMP4, never a subtitle Encode profile.
    func testT08P_01_70_deviceProfileShapeAndVideoCopyURL() throws {
        let profile = try jsonBody(JSONEncoder().encode(PlaybackDeviceProfile()))
        let direct = try XCTUnwrap((profile["DirectPlayProfiles"] as? [[String: Any]])?.first)
        XCTAssertEqual(direct["Container"] as? String, "mp4,mov,m4v,hls")
        XCTAssertEqual(direct["VideoCodec"] as? String, "h264,hevc")
        XCTAssertEqual(direct["AudioCodec"] as? String, "aac,ac3,eac3")
        let transcode = try XCTUnwrap((profile["TranscodingProfiles"] as? [[String: Any]])?.first)
        XCTAssertEqual(transcode["Protocol"] as? String, "hls")
        XCTAssertEqual(transcode["Container"] as? String, "mp4")
        XCTAssertEqual(transcode["BreakOnNonKeyFrames"] as? Bool, true)
        XCTAssertEqual(transcode["AudioCodec"] as? String, "aac,eac3")
        XCTAssertEqual(transcode["VideoCodec"] as? String, "h264,hevc")
        XCTAssertEqual(transcode["EnableSubtitlesInManifest"] as? Bool, false)
        XCTAssertEqual((profile["SubtitleProfiles"] as? [String])?.count, 0)
        let server = try XCTUnwrap(URL(string: "https://server.example/jellyfin"))
        let relative = try XCTUnwrap(
            MediaURLBuilder.resolveTranscodingURL(
                server: server, transcodingURL: "Videos/abc/master.m3u8?PlaySessionId=keep"))
        XCTAssertEqual(relative.path, "/jellyfin/Videos/abc/master.m3u8")
        XCTAssertEqual(URLComponents(url: relative, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "keep")
        for conversion in [PlaybackDecision.StreamConversion.remux, .audioTranscode] {
            let url = try MediaURLBuilder.videoCopyHLS(
                server: server, transcodingURL: "/Videos/abc/master.m3u8?VideoCodec=h264&ApiKey=secret",
                conversion: conversion)
            XCTAssertEqual(url.path, "/jellyfin/Videos/abc/master.m3u8")
            XCTAssertFalse(MediaCredentialQuery.contains(url))
            let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(query.first { $0.name == "VideoCodec" }?.value, "copy")
            XCTAssertEqual(query.first { $0.name == "AudioCodec" }?.value, conversion == .remux ? "copy" : "aac")
            XCTAssertEqual(query.first { $0.name == "SegmentContainer" }?.value, "mp4")
            XCTAssertEqual(query.first { $0.name == "SubtitleStreamIndex" }?.value, "-1")
        }
        for target in ["https://other.example/master.m3u8", "http://server.example/master.m3u8"] {
            XCTAssertThrowsError(
                try MediaURLBuilder.videoCopyHLS(
                    server: server, transcodingURL: target, conversion: .remux
                )
            ) { XCTAssertEqual($0 as? PlaybackFailure, .insecureRedirect) }
        }
    }

    /// T08P-36: ticks are exact and saturate safely beyond Int64's tick range.
    func testT08P_36_resumeTicksAndSaturation() {
        for ticks: Int64 in [0, 1, 10_000_000, 937_000_001_234, Int64.max] {
            XCTAssertEqual(Ticks.ticks(from: Ticks.positionDuration(from: ticks, log: SilentLog())), ticks)
        }
        XCTAssertEqual(Ticks.ticks(from: .seconds(Int64.max)), Int64.max)
        XCTAssertEqual(Ticks.ticks(from: .seconds(-1)), 0)
        let justAboveLimit = Duration(
            secondsComponent: Int64.max / Ticks.perSecond, attosecondsComponent: 999_999_999_999_999_999)
        XCTAssertEqual(Ticks.ticks(from: justAboveLimit), Int64.max)
    }

    /// T08P-69/T08P-71: the PoC handoff is a header resource loader in both Debug and Release.
    func testT08P_69_71_directURLHasNoCredentialOrFallback() throws {
        let server = try XCTUnwrap(URL(string: "https://server.example/jellyfin"))
        let identity = ClientIdentity(deviceName: "TV", deviceID: "device", version: "1", token: "secret")
        let request = try MediaURLBuilder.directPlay(
            server: server, identity: identity, itemID: pocItemID, mediaSourceID: pocSourceID,
            playSessionID: "play-session")
        XCTAssertEqual(request.url.path, "/jellyfin/Videos/\(pocItemID)/stream")
        XCTAssertFalse(MediaCredentialQuery.contains(request.url))
        let query = try XCTUnwrap(URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first { $0.name == "static" }?.value, "true")
        XCTAssertEqual(query.first { $0.name == "deviceId" }?.value, "device")
        XCTAssertEqual(query.first { $0.name == "mediaSourceId" }?.value, pocSourceID)
        XCTAssertEqual(query.first { $0.name == "playSessionId" }?.value, "play-session")
        let plan = MediaOpenPlanner.plan(
            delivery: .directFile, resolvedURL: request.url, authorizationHeader: request.authorizationHeader,
            options: MediaOpenOptions(trust: .publiclyTrusted, headerFieldsKeyAvailable: false))
        guard case .resourceLoader(let carrier) = plan.primary else { return XCTFail("Expected resource loader") }
        XCTAssertEqual(carrier.assetURL.scheme, "glassfin-media")
        XCTAssertEqual(carrier.authorizationHeader, try identity.authorizationHeader())
        XCTAssertTrue(plan.measuredFallbacks.isEmpty)
        XCTAssertFalse(MediaCredentialQuery.contains(carrier.assetURL))
        XCTAssertFalse(HeaderFieldsKeyPolicy.isAllowed(buildIsDebug: false))
    }

    /// T08P-62: compare catalog keys and translation presence, never literal UI copy.
    func testT08P_62_catalogKeysHaveBothTranslations() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("Sources/CoreNetworking/Localizable.xcstrings")
        let catalog = try jsonBody(Data(contentsOf: url))
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        XCTAssertEqual(PlaybackCopy.unsupportedVideoKey, "playback.unsupportedVideoFormat")
        XCTAssertEqual(PlaybackCopy.pinnedHLSKey, "playback.selfSignedRemuxBlocked")
        XCTAssertNil(strings["playback.error.unsupportedVideo"])
        XCTAssertNil(strings["playback.error.pinnedHLS"])
        let exactTranslations = [
            PlaybackCopy.unsupportedVideoKey: [
                "en": "This video format isn't supported yet", "fi": "Tätä videomuotoa ei vielä tueta",
            ],
            PlaybackCopy.pinnedHLSKey: [
                "en": "This video can't be played yet from a server with a self-signed certificate.",
                "fi": "Tätä videota ei voi vielä toistaa palvelimelta, jolla on itse allekirjoitettu varmenne.",
            ],
        ]
        for (key, expected) in exactTranslations {
            let entry = try XCTUnwrap(strings[key] as? [String: Any])
            let languages = try XCTUnwrap(entry["localizations"] as? [String: Any])
            for (language, value) in expected {
                let localization = try XCTUnwrap(languages[language] as? [String: Any])
                let unit = try XCTUnwrap(localization["stringUnit"] as? [String: String])
                XCTAssertEqual(unit["value"], value)
            }
        }
        for reason in [
            PlaybackFailure.unsupportedVideo, .couldNotPlay, .insecureRedirect, .hlsSegmentsBypassPinnedTrust,
        ] {
            let entry = try XCTUnwrap(strings[reason.localizedKey] as? [String: Any])
            let languages = try XCTUnwrap(entry["localizations"] as? [String: Any])
            for language in ["en", "fi"] {
                let localization = try XCTUnwrap(languages[language] as? [String: Any])
                let unit = try XCTUnwrap(localization["stringUnit"] as? [String: String])
                XCTAssertEqual(unit["state"], "translated")
                XCTAssertFalse(try XCTUnwrap(unit["value"]).isEmpty)
            }
            #if os(Linux)
                XCTAssertEqual(PlaybackCopy.message(for: reason.localizedKey), reason.localizedKey)
            #endif
        }
    }

    /// TPOC-65: all catalog entries, including the OK action, have both languages.
    func testTPOC_65_catalogCompleteness() throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let repository = package.deletingLastPathComponent().deletingLastPathComponent()
        for url in [
            package.appendingPathComponent("Sources/CoreNetworking/Localizable.xcstrings"),
            repository.appendingPathComponent("Apps/Shared/Resources/Localizable.xcstrings"),
        ] {
            let strings = try XCTUnwrap(jsonBody(Data(contentsOf: url))["strings"] as? [String: Any])
            for (key, value) in strings {
                let entry = try XCTUnwrap(value as? [String: Any])
                let languages = try XCTUnwrap(entry["localizations"] as? [String: Any])
                for language in ["en", "fi"] {
                    let localization = try XCTUnwrap(languages[language] as? [String: Any], key)
                    let unit = try XCTUnwrap(localization["stringUnit"] as? [String: String], key)
                    XCTAssertFalse(try XCTUnwrap(unit["value"], key).isEmpty)
                }
            }
        }
    }

    /// T08P-32/73: real CoreNetworking auth and error mapping for all three report endpoints.
    func testT08P_32_73_reportHTTPFailuresRedactAndKeepHeaderOnlyAuth() async throws {
        let token = "report-token-secret"
        let transport = PoCTransport(data: Data("Authorization: \(token) ApiKey=\(token)".utf8), status: 500)
        let server = try XCTUnwrap(URL(string: "https://server.example/jellyfin"))
        let identity = ClientIdentity(deviceName: "TV", deviceID: "device", version: "1", token: token)
        let client = HTTPJellyfinClient(server: server, identity: identity, transport: transport)
        let sink = ReportLogCapture()
        let reporter = PlaybackReporter(client: client, log: sink)
        let context = PlaybackReportContext(
            itemID: pocItemID, mediaSourceID: pocSourceID,
            playSessionID: "session", method: .directStream)
        for event in ["", "/Progress", "/Stopped"] {
            let error = await reporter.send(
                event, context: context, position: .seconds(10), paused: false, canSeek: true)
            XCTAssertEqual(error, .server(status: 500))
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 6)
        for request in requests {
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), try identity.authorizationHeader())
            XCTAssertFalse(MediaCredentialQuery.contains(try XCTUnwrap(request.url)))
            XCTAssertFalse(String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self).contains(token))
        }
        XCTAssertEqual(sink.messages.count, 6)
        XCTAssertFalse(sink.messages.joined().contains(token))
    }

    /// T08P-02: request and response pass through the real HTTPClient and its auth writer.
    func testT08P_02_playbackInfoRequestAndParsing() async throws {
        let transport = PoCTransport(data: try playbackFixture(container: "mov", video: "hevc", audio: "eac3"))
        let server = try XCTUnwrap(URL(string: "https://server.example/jellyfin"))
        let identity = ClientIdentity(deviceName: "TV", deviceID: "device", version: "1", token: "secret")
        let api = PlaybackAPI(client: HTTPJellyfinClient(server: server, identity: identity, transport: transport))
        let info = try await api.playbackInfo(
            itemID: pocItemID, userID: pocUserID, start: .seconds(12), maxBitrate: 120_000_000)
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/jellyfin/Items/\(pocItemID)/PlaybackInfo")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), try identity.authorizationHeader())
        XCTAssertFalse(MediaCredentialQuery.contains(try XCTUnwrap(request.url)))
        let body = try jsonBody(request.httpBody)
        XCTAssertEqual(body["UserId"] as? String, pocUserID)
        XCTAssertEqual(body["StartTimeTicks"] as? Int64, 120_000_000)
        XCTAssertEqual(body["MaxStreamingBitrate"] as? Int, 120_000_000)
        for key in [
            "EnableDirectPlay", "EnableDirectStream", "EnableTranscoding", "AllowVideoStreamCopy",
            "AllowAudioStreamCopy",
        ] {
            XCTAssertEqual(body[key] as? Bool, true)
        }
        XCTAssertNotNil(body["DeviceProfile"])
        XCTAssertNil(body["AudioStreamIndex"])
        XCTAssertEqual(body["SubtitleStreamIndex"] as? Int, -1)
        let source = try XCTUnwrap(info.MediaSources?.first)
        XCTAssertEqual(source.Id, pocSourceID)
        XCTAssertEqual(source.Container, "mov")
        XCTAssertEqual(source.SupportsDirectPlay, true)
        XCTAssertEqual(source.SupportsDirectStream, true)
        XCTAssertEqual(source.SupportsTranscoding, true)
        XCTAssertEqual(source.MediaStreams?.map(\.Codec), ["hevc", "eac3"])
        XCTAssertEqual(info.PlaySessionId, "play-session")
        _ = try await api.playbackInfo(itemID: pocItemID, userID: pocUserID, start: .seconds(-1), maxBitrate: 1)
        let negative = await transport.requests.last
        XCTAssertEqual(try jsonBody(negative?.httpBody)["StartTimeTicks"] as? Int64, 0)
    }
}

private actor PoCTransport: RequestTransport {
    let data: Data
    private(set) var requests: [URLRequest] = []
    let status: Int
    init(data: Data, status: Int = 200) {
        self.data = data
        self.status = status
    }
    func data(for request: URLRequest) async throws -> (Data, URLResponse, Int?) {
        requests.append(request)
        let url = try XCTUnwrap(request.url)
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
        return (data, response, nil)
    }
}

private final class ReportLogCapture: GlassfinLog, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    var messages: [String] { lock.withLock { entries } }
    func warning(_ message: String) { lock.withLock { entries.append(message) } }
    func debug(_ message: String) { lock.withLock { entries.append(message) } }
    func error(_ message: String) { lock.withLock { entries.append(message) } }
}
