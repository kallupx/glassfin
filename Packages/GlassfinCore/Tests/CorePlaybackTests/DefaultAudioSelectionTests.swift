import CoreModels
import CoreNetworking
import CorePlayback
import Foundation
import XCTest

@MainActor
final class DefaultAudioSelectionTests: XCTestCase {
    /// Q8P-22: the first default audio stream determines both the wire index and codec decision.
    func testQ8P_22_defaultAudioOverridesFirstAudio() async throws {
        for (first, chosen, expected) in [
            ("dts", "aac", PlaybackDecision.directPlay),
            ("aac", "dts", .directStream(.audioTranscode)),
        ] {
            try await assertPlayback(
                audio: [
                    ["Type": "Audio", "Index": 9, "Codec": first],
                    ["Type": "Subtitle", "Index": 1, "Codec": "srt", "IsDefault": true],
                    ["Type": "Audio", "Index": 4, "Codec": chosen, "IsDefault": true],
                    ["Type": "Audio", "Index": 2, "Codec": first, "IsDefault": true],
                ], expectedIndex: 4, expectedDecision: expected)
        }
    }

    /// Q8P-22: missing/false default flags preserve audio order rather than sorting stream indexes.
    func testQ8P_22_firstAudioUsedWhenNoneIsDefault() async throws {
        for (first, other, expected) in [
            ("aac", "dts", PlaybackDecision.directPlay),
            ("dts", "aac", .directStream(.audioTranscode)),
        ] {
            try await assertPlayback(
                audio: [
                    ["Type": "Audio", "Index": 9, "Codec": first],
                    ["Type": "Audio", "Index": 2, "Codec": other, "IsDefault": false],
                ], expectedIndex: 9, expectedDecision: expected)
        }
    }

    /// Q8P-22: all supported audio codecs accept mixed case; unsupported codecs still convert.
    func testQ8P_22_audioCodecComparisonIsCaseInsensitive() async throws {
        for codec in ["AAC", "AaC", "AC3", "Ac3", "EAC3", "EaC3", "DTS", "TrueHD"] {
            let expected: PlaybackDecision =
                ["DTS", "TrueHD"].contains(codec) ? .directStream(.audioTranscode) : .directPlay
            try await assertPlayback(
                audio: [["Type": "Audio", "Index": 7, "Codec": codec, "IsDefault": true]],
                expectedIndex: 7, expectedDecision: expected)
        }
    }

    /// Q8P-22: video without audio can DirectPlay or remux and omits AudioStreamIndex.
    func testQ8P_22_missingAudioDoesNotBlockPlayback() async throws {
        for container in ["mp4", "mkv"] {
            try await assertPlayback(
                audio: [["Type": "Subtitle", "Index": 3, "Codec": "srt", "IsDefault": true]],
                expectedIndex: nil,
                expectedDecision: container == "mp4" ? .directPlay : .directStream(.remux),
                container: container)
        }
    }

    /// Q8P-22: the one video-copy retry retains the selected default audio index.
    func testQ8P_22_retryRetainsDefaultAudioIndex() async throws {
        try await assertPlayback(
            audio: [
                ["Type": "Audio", "Index": 9, "Codec": "dts"],
                ["Type": "Audio", "Index": 4, "Codec": "aac", "IsDefault": true],
            ], expectedIndex: 4, expectedDecision: .directPlay, retry: true)
    }

    private func assertPlayback(
        audio: [[String: Any]], expectedIndex: Int?, expectedDecision: PlaybackDecision,
        container: String = "mp4", retry: Bool = false,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let streams = [["Type": "Video", "Index": 0, "Codec": "h264", "IsDefault": true]] + audio
        var fixture = try jsonBody(
            playbackFixture(
                container: container, transcodingURL: "/master.m3u8?ApiKey=fake-server-query"))
        var source = try XCTUnwrap((fixture["MediaSources"] as? [[String: Any]])?.first)
        source["MediaStreams"] = streams
        // Server hints must not override the item metadata's default or first audio stream.
        source["DefaultAudioStreamIndex"] = 99
        fixture["MediaSources"] = [source]
        let response = try JSONSerialization.data(withJSONObject: fixture)
        let decoded = try JSONDecoder().decode(PlaybackInfoResponseDTO.self, from: response)
        XCTAssertEqual(
            PlaybackDecision.decide(mediaSource: try XCTUnwrap(decoded.MediaSources?.first)),
            expectedDecision, file: file, line: line)
        source["SupportsDirectPlay"] = false
        fixture["MediaSources"] = [source]
        fixture["PlaySessionId"] = "retry-session"
        let retryResponse = try JSONSerialization.data(withJSONObject: fixture)

        // Exercise both supported locations for the item's preflight stream metadata.
        for nestedMetadata in [false, true] {
            let item: [String: Any] =
                nestedMetadata ? ["MediaSources": [["MediaStreams": streams]]] : ["MediaStreams": streams]
            let metadata = try JSONSerialization.data(withJSONObject: item)
            let client = PoCAPIClient { request throws(APIError) in
                if request.method == "GET" { return metadata }
                if request.path.hasSuffix("/PlaybackInfo") {
                    let direct = (try? jsonBody(request.body)["EnableDirectPlay"] as? Bool) ?? true
                    return direct ? response : retryResponse
                }
                return Data()
            }
            let session = MockPlaybackSession(
                serverURL: try XCTUnwrap(URL(string: "https://server.example/jellyfin")), userID: pocUserID,
                identity: ClientIdentity(deviceName: "TV", deviceID: "device", version: "1", token: "secret"),
                apiClient: client)
            let engine = MockPlaybackEngine()
            if retry { engine.loadErrors = [.network, nil] }
            let coordinator = PlaybackCoordinator(
                session: session, engine: engine, origin: MockPlaybackOrigin(),
                timer: ManualPlaybackTimer(), configuration: .poc)
            await coordinator.play(itemID: pocItemID, choice: .startOver)
            for _ in 0..<2_000 {
                if coordinator.state == .playing { break }
                await Task.yield()
            }
            XCTAssertEqual(coordinator.state, .playing, file: file, line: line)
            XCTAssertNil(coordinator.failure, file: file, line: line)
            XCTAssertEqual(engine.loads.count, 1, file: file, line: line)
            let calls = await client.calls
            let requests = calls.filter { $0.path.hasSuffix("/PlaybackInfo") }
            XCTAssertEqual(requests.count, retry ? 2 : 1, file: file, line: line)
            for request in requests {
                let body = try jsonBody(request.body)
                XCTAssertEqual(body["AudioStreamIndex"] as? Int, expectedIndex, file: file, line: line)
                XCTAssertEqual(body["SubtitleStreamIndex"] as? Int, -1, file: file, line: line)
                XCTAssertEqual(body["AllowVideoStreamCopy"] as? Bool, true, file: file, line: line)
            }
            let url = try XCTUnwrap(engine.loads.first?.carrier.originURL, file: file, line: line)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            if retry || expectedDecision != .directPlay {
                XCTAssertEqual(query?.first { $0.name == "VideoCodec" }?.value, "copy", file: file, line: line)
                XCTAssertEqual(
                    query?.first { $0.name == "AudioCodec" }?.value,
                    expectedDecision == .directStream(.audioTranscode) ? "aac" : "copy", file: file, line: line)
            }
            await coordinator.stop()
        }
    }
}
