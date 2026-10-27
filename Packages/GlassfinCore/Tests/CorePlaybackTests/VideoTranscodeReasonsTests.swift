import CoreModels
import CoreNetworking
import CorePlayback
import Foundation
import XCTest

/// T08P-14: locked Q8P-05 query-only rule; each blocking reason has a separate test.
final class VideoTranscodeReasonsTests: XCTestCase {
    private func assertBlocked(_ reason: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let url = "/master.m3u8?TranscodeReasons=ContainerNotSupported," + reason
        XCTAssertTrue(VideoTranscodeReasons.blocksPlayback(transcodingURL: url), file: file, line: line)
        let dto = try JSONDecoder().decode(
            PlaybackInfoResponseDTO.self,
            from: playbackFixture(container: "mkv", direct: false, transcodingURL: url))
        XCTAssertEqual(
            PlaybackDecision.decide(mediaSource: try XCTUnwrap(dto.MediaSources?.first)),
            .unsupported(.unsupportedVideo), file: file, line: line)
    }
    func testT08P_14_VideoCodecNotSupported() throws { try assertBlocked("VideoCodecNotSupported") }
    func testT08P_14_VideoProfileNotSupported() throws { try assertBlocked("VideoProfileNotSupported") }
    func testT08P_14_VideoRangeTypeNotSupported() throws { try assertBlocked("VideoRangeTypeNotSupported") }
    func testT08P_14_VideoCodecTagNotSupported() throws { try assertBlocked("VideoCodecTagNotSupported") }
    func testT08P_14_VideoLevelNotSupported() throws { try assertBlocked("VideoLevelNotSupported") }
    func testT08P_14_VideoResolutionNotSupported() throws { try assertBlocked("VideoResolutionNotSupported") }
    func testT08P_14_VideoBitDepthNotSupported() throws { try assertBlocked("VideoBitDepthNotSupported") }
    func testT08P_14_VideoFramerateNotSupported() throws { try assertBlocked("VideoFramerateNotSupported") }
    func testT08P_14_RefFramesNotSupported() throws { try assertBlocked("RefFramesNotSupported") }
    func testT08P_14_AnamorphicVideoNotSupported() throws { try assertBlocked("AnamorphicVideoNotSupported") }
    func testT08P_14_InterlacedVideoNotSupported() throws { try assertBlocked("InterlacedVideoNotSupported") }
    func testT08P_14_VideoBitrateNotSupported() throws { try assertBlocked("VideoBitrateNotSupported") }
    func testT08P_14_UnknownVideoStreamInfo() throws { try assertBlocked("UnknownVideoStreamInfo") }
    func testT08P_14_VideoRotationNotSupported() throws { try assertBlocked("VideoRotationNotSupported") }

    func testT08P_14_ignoredReasons() {
        for reason in [
            "ContainerNotSupported", "ContainerBitrateExceedsLimit", "AudioCodecNotSupported",
            "AudioChannelsNotSupported", "AudioBitrateNotSupported", "SubtitleCodecNotSupported",
            "SubtitleNotSupported", "SecondaryAudioNotSupported", "DirectPlayError", "StreamCountExceedsLimit",
            "FutureReason", "VideoFutureUnknownReason",
        ] {
            XCTAssertFalse(
                VideoTranscodeReasons.blocksPlayback(transcodingURL: "/master.m3u8?TranscodeReasons=" + reason), reason)
        }
    }

    func testT08P_14_emptyMissingAndEncodedCommas() {
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

    func testT08P_14_jsonBodyReasonsAreIgnored() throws {
        let data = Data(
            """
            {"Container":"mkv","TranscodingUrl":"/master.m3u8?TranscodeReasons=AudioCodecNotSupported",
             "TranscodeReasons":["VideoCodecNotSupported"],
             "MediaStreams":[{"Type":"Video","Codec":"h264"},{"Type":"Audio","Codec":"dts"}]}
            """.utf8)
        let source = try JSONDecoder().decode(MediaSourceDTO.self, from: data)
        XCTAssertEqual(PlaybackDecision.decide(mediaSource: source), .directStream(.audioTranscode))
    }

    func testT08P_14_defaultVideoSelection() throws {
        for (index, supported) in [(3, true), (1, false)] {
            let source = try JSONDecoder().decode(
                MediaSourceDTO.self,
                from: Data(
                    """
                    {"DefaultVideoStreamIndex":\(index),"MediaStreams":[
                        {"Type":"Video","Codec":"mpeg2video","Index":1},
                        {"Type":"Video","Codec":"hevc","Index":3,"IsDefault":true}]}
                    """.utf8))
            XCTAssertEqual(
                PlaybackDecision.supportsVideo(
                    streams: source.MediaStreams,
                    defaultIndex: source.DefaultVideoStreamIndex), supported)
            XCTAssertTrue(PlaybackDecision.supportsVideo(streams: source.MediaStreams))
        }
    }
}
