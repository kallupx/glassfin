import CoreModels
import CoreNetworking
import CorePlayback
import Foundation
import XCTest

@testable import CoreNetworking

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

let pocItemID = "00112233445566778899aabbccddeeff"
let pocUserID = "11112233445566778899aabbccddeeff"
let pocSourceID = "22112233445566778899aabbccddeeff"

func playbackFixture(
    container: String = "mp4", video: String = "h264", audio: String = "aac",
    direct: Bool = true, transcodingURL: String? = nil
) throws -> Data {
    var source: [String: Any] = [
        "Id": pocSourceID, "Container": container, "SupportsDirectPlay": direct,
        "SupportsDirectStream": true, "SupportsTranscoding": true,
        "MediaStreams": [["Type": "Video", "Codec": video], ["Type": "Audio", "Codec": audio]],
    ]
    source["TranscodingUrl"] = transcodingURL
    return try JSONSerialization.data(withJSONObject: ["PlaySessionId": "play-session", "MediaSources": [source]])
}

func jsonBody(_ data: Data?) throws -> [String: Any] {
    let bytes = try XCTUnwrap(data)
    return try XCTUnwrap(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
}

final class PlaybackPoCDecisionTests: XCTestCase {
    /// T08a-PoC-02: client and server must agree, including a video-copy-only fallback.
    func testT08a_PoC_02_profileDecisionMatrix() throws {
        let cases: [(String, String, String, Bool, String?, PlaybackDecision)] = [
            ("mp4", "h264", "aac", true, nil, .directPlay),
            ("mov", "hevc", "eac3", true, nil, .directPlay),
            ("m4v", "hevc", "ac3", true, nil, .directPlay),
            ("hls", "h264", "aac", true, nil, .directPlay),
            ("mkv", "h264", "aac", false, "/master.m3u8", .directStream(.remux)),
            ("mkv", "h264", "dts", false, "/master.m3u8", .directStream(.audioTranscode)),
            ("mp4", "hevc", "truehd", true, "/master.m3u8", .directStream(.audioTranscode)),
            ("mp4", "h264", "aac", false, nil, .unsupported(.unsupportedVideo)),
            ("mkv", "h264", "aac", false, "", .unsupported(.unsupportedVideo)),
        ]
        for (container, video, audio, direct, url, expected) in cases {
            let data = try playbackFixture(
                container: container, video: video, audio: audio, direct: direct, transcodingURL: url)
            let dto = try JSONDecoder().decode(PlaybackInfoResponseDTO.self, from: data)
            let source = try XCTUnwrap(dto.MediaSources?.first)
            XCTAssertEqual(PlaybackDecision.decide(mediaSource: source), expected)
        }
        for codec in ["vp9", "mpeg2video", "vc1", "av1", "mpeg4", ""] {
            let data = try playbackFixture(video: codec, transcodingURL: "/master.m3u8")
            let dto = try JSONDecoder().decode(PlaybackInfoResponseDTO.self, from: data)
            XCTAssertEqual(
                PlaybackDecision.decide(mediaSource: try XCTUnwrap(dto.MediaSources?.first)),
                .unsupported(.unsupportedVideo)
            )
        }
        for reason in ["VideoBitrateNotSupported", "SubtitleCodecNotSupported"] {
            let dto = try JSONDecoder().decode(
                MediaSourceDTO.self,
                from: Data(
                    """
                    {"Container":"mkv","TranscodingUrl":"/master.m3u8","TranscodeReasons":["\(reason)"],
                    "MediaStreams":[{"Type":"Video","Codec":"h264"}]}
                    """.utf8))
            XCTAssertEqual(PlaybackDecision.decide(mediaSource: dto), .unsupported(.unsupportedVideo))
        }
    }

    /// T08a-PoC-03: only supported codecs; HLS uses fMP4, never a subtitle Encode profile.
    func testT08a_PoC_03_deviceProfileShapeAndVideoCopyURL() throws {
        let profile = try jsonBody(JSONEncoder().encode(PlaybackDeviceProfile()))
        let direct = try XCTUnwrap((profile["DirectPlayProfiles"] as? [[String: Any]])?.first)
        XCTAssertEqual(direct["Container"] as? String, "mp4,mov,m4v,hls")
        XCTAssertEqual(direct["VideoCodec"] as? String, "h264,hevc")
        XCTAssertEqual(direct["AudioCodec"] as? String, "aac,ac3,eac3")
        let transcode = try XCTUnwrap((profile["TranscodingProfiles"] as? [[String: Any]])?.first)
        XCTAssertEqual(transcode["Protocol"] as? String, "hls")
        XCTAssertEqual(transcode["Container"] as? String, "mp4")
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

    /// T08a-PoC-05: ticks are exact and saturate safely beyond Int64's tick range.
    func testT08a_PoC_05_resumeTicksAndSaturation() {
        for ticks: Int64 in [0, 1, 10_000_000, 937_000_001_234, Int64.max] {
            XCTAssertEqual(Ticks.ticks(from: Ticks.positionDuration(from: ticks, log: SilentLog())), ticks)
        }
        XCTAssertEqual(Ticks.ticks(from: .seconds(Int64.max)), Int64.max)
        XCTAssertEqual(Ticks.ticks(from: .seconds(-1)), 0)
        let justAboveLimit = Duration(
            secondsComponent: Int64.max / Ticks.perSecond, attosecondsComponent: 999_999_999_999_999_999)
        XCTAssertEqual(Ticks.ticks(from: justAboveLimit), Int64.max)
    }

    /// T08a-PoC-09: the PoC handoff is a header resource loader in both Debug and Release.
    func testT08a_PoC_09_directURLHasNoCredentialOrFallback() throws {
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

    /// T08a-PoC-10: compare catalog keys and translation presence, never literal UI copy.
    func testT08a_PoC_10_catalogKeysHaveBothTranslations() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("Sources/CoreNetworking/Localizable.xcstrings")
        let catalog = try jsonBody(Data(contentsOf: url))
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        for reason in [PlaybackFailure.unsupportedVideo, .couldNotPlay, .insecureRedirect] {
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

    /// T08a-PoC-01: request and response pass through the real HTTPClient and its auth writer.
    func testT08a_PoC_01_playbackInfoRequestAndParsing() async throws {
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
    init(data: Data) { self.data = data }
    func data(for request: URLRequest) async throws -> (Data, URLResponse, Int?) {
        requests.append(request)
        let url = try XCTUnwrap(request.url)
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        return (data, response, nil)
    }
}
