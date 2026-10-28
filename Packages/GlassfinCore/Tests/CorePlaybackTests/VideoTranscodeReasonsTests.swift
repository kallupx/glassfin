import CoreModels
import CoreNetworking
import CorePlayback
import Foundation
import XCTest

/// T08P-82: locked Q8P-05 query-only rule; each blocking reason has a separate test.
final class VideoTranscodeReasonsTests: XCTestCase {
    private func assertBlocked(_ reason: String, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(
            VideoTranscodeReasons.blocksPlayback(transcodingURL: "/master.m3u8?TranscodeReasons=" + reason), file: file,
            line: line)
        let url = "/master.m3u8?TranscodeReasons=ContainerNotSupported," + reason
        XCTAssertTrue(VideoTranscodeReasons.blocksPlayback(transcodingURL: url), file: file, line: line)
        let dto = try JSONDecoder().decode(
            PlaybackInfoResponseDTO.self,
            from: playbackFixture(container: "mkv", direct: false, transcodingURL: url))
        XCTAssertEqual(
            PlaybackDecision.decide(mediaSource: try XCTUnwrap(dto.MediaSources?.first)),
            .unsupported(.unsupportedVideo), file: file, line: line)
    }
    func testT08P_82_VideoCodecNotSupported() throws { try assertBlocked("VideoCodecNotSupported") }
    func testT08P_82_VideoProfileNotSupported() throws { try assertBlocked("VideoProfileNotSupported") }
    func testT08P_82_VideoRangeTypeNotSupported() throws { try assertBlocked("VideoRangeTypeNotSupported") }
    func testT08P_82_VideoCodecTagNotSupported() throws { try assertBlocked("VideoCodecTagNotSupported") }
    func testT08P_82_VideoLevelNotSupported() throws { try assertBlocked("VideoLevelNotSupported") }
    func testT08P_82_VideoResolutionNotSupported() throws { try assertBlocked("VideoResolutionNotSupported") }
    func testT08P_82_VideoBitDepthNotSupported() throws { try assertBlocked("VideoBitDepthNotSupported") }
    func testT08P_82_VideoFramerateNotSupported() throws { try assertBlocked("VideoFramerateNotSupported") }
    func testT08P_82_RefFramesNotSupported() throws { try assertBlocked("RefFramesNotSupported") }
    func testT08P_82_AnamorphicVideoNotSupported() throws { try assertBlocked("AnamorphicVideoNotSupported") }
    func testT08P_82_InterlacedVideoNotSupported() throws { try assertBlocked("InterlacedVideoNotSupported") }
    func testT08P_82_VideoBitrateNotSupported() throws { try assertBlocked("VideoBitrateNotSupported") }
    func testT08P_82_UnknownVideoStreamInfo() throws { try assertBlocked("UnknownVideoStreamInfo") }
    func testT08P_82_VideoRotationNotSupported() throws { try assertBlocked("VideoRotationNotSupported") }

    func testT08P_83_ignoredReasons() {
        for reason in [
            "ContainerNotSupported", "ContainerBitrateExceedsLimit", "AudioCodecNotSupported",
            "AudioChannelsNotSupported", "AudioProfileNotSupported", "AudioSampleRateNotSupported",
            "AudioBitDepthNotSupported", "AudioBitrateNotSupported", "AudioIsExternal", "SubtitleCodecNotSupported",
            "SubtitleNotSupported", "SecondaryAudioNotSupported", "DirectPlayError", "StreamCountExceedsLimit",
            "FutureReason", "VideoFutureUnknownReason",
        ] {
            XCTAssertFalse(
                VideoTranscodeReasons.blocksPlayback(transcodingURL: "/master.m3u8?TranscodeReasons=" + reason), reason)
        }
    }

    func testT08P_84_emptyMissingAndEncodedCommas() {
        for url in [nil, "", "/master.m3u8", "/master.m3u8?TranscodeReasons", "/master.m3u8?TranscodeReasons="] {
            XCTAssertEqual(VideoTranscodeReasons.parse(transcodingURL: url), [])
            XCTAssertFalse(VideoTranscodeReasons.blocksPlayback(transcodingURL: url))
        }
        let url = "/master.m3u8?TranscodeReasons=AudioCodecNotSupported%2CVideoCodecNotSupported"
        XCTAssertEqual(
            VideoTranscodeReasons.parse(transcodingURL: url), ["AudioCodecNotSupported", "VideoCodecNotSupported"])
        XCTAssertTrue(VideoTranscodeReasons.blocksPlayback(transcodingURL: url))
        XCTAssertTrue(
            VideoTranscodeReasons.blocksPlayback(
                transcodingURL:
                    "/master.m3u8?TranscodeReasons=AudioCodecNotSupported&TranscodeReasons=RefFramesNotSupported"))
    }

    func testT08P_90_jsonBodyReasonsAreIgnored() throws {
        let data = Data(
            """
            {"Container":"mkv","TranscodingUrl":"/master.m3u8?TranscodeReasons=AudioCodecNotSupported",
             "TranscodeReasons":["VideoCodecNotSupported"],
             "MediaStreams":[{"Type":"Video","Codec":"h264"},{"Type":"Audio","Codec":"dts"}]}
            """.utf8)
        let source = try JSONDecoder().decode(MediaSourceDTO.self, from: data)
        XCTAssertEqual(PlaybackDecision.decide(mediaSource: source), .directStream(.audioTranscode))
    }

    func testT08P_85_malformedInputsAreDeterministic() {
        let inputs = [
            "%", "%GG", "%FF%FE", "not a URL", "/no-query", "//[]", ";;", "%%", " ",
            String(repeating: "z", count: 10_000),
        ]
        for value in inputs {
            for url in [value, "/master.m3u8?TranscodeReasons=" + value] {
                XCTAssertFalse(VideoTranscodeReasons.blocksPlayback(transcodingURL: url))
            }
        }
        let duplicate = String(repeating: "TranscodeReasons=ContainerNotSupported&", count: 1_000)
        XCTAssertFalse(VideoTranscodeReasons.blocksPlayback(transcodingURL: "/master.m3u8?" + duplicate))
        XCTAssertTrue(
            VideoTranscodeReasons.blocksPlayback(
                transcodingURL: "/master.m3u8?" + duplicate + "TranscodeReasons=VideoLevelNotSupported"))
    }

    func testT08P_86_reasonAndParameterCaseAreSignificant() {
        for query in [
            "TranscodeReasons=videocodecnotsupported", "TranscodeReasons=VIDEOCODECNOTSUPPORTED",
            "transcodereasons=VideoCodecNotSupported",
        ] {
            XCTAssertFalse(VideoTranscodeReasons.blocksPlayback(transcodingURL: "/master.m3u8?" + query))
        }
    }

    func testT08P_90_nonQueryReasonTextAndOtherQueryValuesAreIgnored() {
        for url in [
            "/VideoLevelNotSupported/master.m3u8", "/master.m3u8?VideoCodec=VideoCodecNotSupported",
            "/master.m3u8#TranscodeReasons=VideoCodecNotSupported",
            "/master.m3u8?ApiKey=canary&PlaySessionId=session&DeviceId=device",
        ] {
            XCTAssertTrue(VideoTranscodeReasons.parse(transcodingURL: url).isEmpty)
        }
    }

    func testT08P_94_defaultVideoSelectionIgnoresIndexHints() throws {
        for codec in ["h264", "mpeg2video"] {
            let other = codec == "h264" ? "mpeg2video" : "h264"
            let source = try JSONDecoder().decode(
                MediaSourceDTO.self,
                from: Data(
                    """
                    {"DefaultVideoStreamIndex":1,"MediaStreams":[
                        {"Type":"Video","Codec":"\(other)","Index":1},
                        {"Type":"Video","Codec":"\(codec)","Index":3,"IsDefault":true},
                        {"Type":"Video","Codec":"\(other)","Index":4,"IsDefault":true}]}
                    """.utf8))
            XCTAssertEqual(PlaybackDecision.supportsVideo(streams: source.MediaStreams), codec == "h264")
        }
    }
}
