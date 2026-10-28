import Foundation

#if canImport(AVFoundation) && canImport(VideoToolbox)
    import AVFoundation
    import VideoToolbox
#endif

/// A snapshot is injected in portable tests and refreshed for each playback on Apple platforms.
public struct PlaybackCapabilities: Sendable, Equatable {
    public var hevc: Bool
    public var av1: Bool
    public var verifiedOpus: Bool
    public var hdr10: Bool
    public var hlg: Bool
    public var dolbyVision: Bool
    public var h264Level: Int
    public var hevcLevel: Int

    public init(
        hevc: Bool = true, av1: Bool = false, verifiedOpus: Bool = false,
        hdr10: Bool = false, hlg: Bool = false, dolbyVision: Bool = false,
        h264Level: Int = 52, hevcLevel: Int = 153
    ) {
        self.hevc = hevc
        self.av1 = av1
        self.verifiedOpus = verifiedOpus
        self.hdr10 = hdr10
        self.hlg = hlg
        self.dolbyVision = dolbyVision
        self.h264Level = h264Level
        self.hevcLevel = hevcLevel
    }

    @MainActor
    public static func current() -> Self {
        #if canImport(AVFoundation) && canImport(VideoToolbox)
            let hevc = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
            let av1 = VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
            #if os(iOS) || os(tvOS)
                let modes = AVPlayer.availableHDRModes
                let hdr = AVPlayer.eligibleForHDRPlayback
                return Self(
                    hevc: hevc, av1: av1,
                    hdr10: hdr && modes.contains(.hdr10), hlg: hdr && modes.contains(.hlg),
                    dolbyVision: hdr && modes.contains(.dolbyVision)
                )
            #else
                // availableHDRModes is unavailable on macOS; keep the conservative SDR defaults.
                return Self(hevc: hevc, av1: av1)
            #endif
        #else
            return Self(hevc: false)
        #endif
    }

    public var videoCodecs: String { (["h264"] + (hevc ? ["hevc"] : []) + (av1 ? ["av1"] : [])).joined(separator: ",") }
    public var audioCodecs: String { "aac,ac3,eac3,alac,flac,mp3" + (verifiedOpus ? ",opus" : "") }
    public var videoRanges: String {
        var ranges = ["SDR"]
        if hdr10 { ranges.append("HDR10") }
        if hlg { ranges.append("HLG") }
        if dolbyVision {
            ranges += ["DOVI", "DOVIWithSDR"]
            if hdr10 { ranges.append("DOVIWithHDR10") }
        }
        return ranges.joined(separator: "|")
    }
}

/// Wire names mirror jellyfin-sdk-swift DeviceProfile, CodecProfile and TranscodingProfile.
/// Like the existing PlaybackAPI DTOs this remains usable on Linux without Network.framework.
public struct RuntimeDeviceProfile: Encodable, Sendable {
    public struct DirectPlayProfile: Encodable, Sendable {
        let Container = "mp4,m4v,mov"
        let `Type` = "Video"
        let VideoCodec: String
        let AudioCodec: String
    }
    public struct Condition: Encodable, Sendable {
        let Condition: String
        let Property: String
        let Value: String
        let IsRequired = false
    }
    public struct CodecProfile: Encodable, Sendable {
        let `Type` = "Video"
        let Codec: String
        let Conditions: [Condition]
    }
    public struct TranscodingProfile: Encodable, Sendable {
        let `Type` = "Video"
        let `Protocol` = "hls"
        let Container = "mp4"
        let VideoCodec: String
        let AudioCodec = "eac3,ac3,aac"
        let MaxAudioChannels = "8"
        let BreakOnNonKeyFrames = true
        let EnableSubtitlesInManifest = false
        let Context = "Streaming"
    }
    public struct SubtitleProfile: Encodable, Sendable {
        let Format: String
        let Method: String
    }
    let Name = "Glassfin AVPlayer"
    public let DirectPlayProfiles: [DirectPlayProfile]
    public let CodecProfiles: [CodecProfile]
    public let TranscodingProfiles: [TranscodingProfile]
    public let SubtitleProfiles: [SubtitleProfile]
    public let MaxStreamingBitrate: Int

    public init(capabilities: PlaybackCapabilities, maxBitrate: Int, convertASS: Bool = true) {
        DirectPlayProfiles = [.init(VideoCodec: capabilities.videoCodecs, AudioCodec: capabilities.audioCodecs)]
        var codecs: [CodecProfile] = [
            .init(
                Codec: "h264",
                Conditions: [
                    .init(Condition: "LessThanEqual", Property: "VideoLevel", Value: String(capabilities.h264Level)),
                    .init(Condition: "LessThanEqual", Property: "VideoBitDepth", Value: "8"),
                    .init(
                        Condition: "EqualsAny", Property: "VideoProfile",
                        Value: "baseline|constrained baseline|main|high"),
                    .init(Condition: "EqualsAny", Property: "VideoRangeType", Value: "SDR"),
                ])
        ]
        if capabilities.hevc {
            codecs.append(
                .init(
                    Codec: "hevc",
                    Conditions: [
                        .init(
                            Condition: "LessThanEqual", Property: "VideoLevel", Value: String(capabilities.hevcLevel)),
                        .init(Condition: "LessThanEqual", Property: "VideoBitDepth", Value: "10"),
                        .init(Condition: "EqualsAny", Property: "VideoProfile", Value: "main|main 10"),
                        .init(Condition: "EqualsAny", Property: "VideoRangeType", Value: capabilities.videoRanges),
                    ]))
        }
        if capabilities.av1 {
            codecs.append(
                .init(
                    Codec: "av1",
                    Conditions: [
                        .init(Condition: "LessThanEqual", Property: "VideoBitDepth", Value: "10"),
                        .init(Condition: "EqualsAny", Property: "VideoRangeType", Value: capabilities.videoRanges),
                    ]))
        }
        CodecProfiles = codecs
        TranscodingProfiles = [.init(VideoCodec: capabilities.hevc ? "hevc,h264" : "h264")]
        // Text formats request conversion to VTT. Image subtitles always require server burn-in.
        SubtitleProfiles =
            ["vtt", "subrip", "srt"].map { .init(Format: $0, Method: "External") }
            + [.init(Format: "vtt", Method: "Hls"), .init(Format: "mov_text", Method: "Embed")]
            + ["pgssub", "dvdsub"].map { .init(Format: $0, Method: "Encode") }
            + ["ass", "ssa"].map { .init(Format: $0, Method: convertASS ? "External" : "Encode") }
        MaxStreamingBitrate = max(1, maxBitrate)
    }
}

public struct PlaybackConfiguration: Sendable {
    public var isPoC: Bool
    public var convertASS: Bool
    public var remoteBitrate: Int
    public var capabilities: PlaybackCapabilities?

    public init(convertASS: Bool = true, remoteBitrate: Int = 20_000_000, capabilities: PlaybackCapabilities? = nil) {
        self.isPoC = false
        self.convertASS = convertASS
        self.remoteBitrate = max(1, remoteBitrate)
        self.capabilities = capabilities
    }

    public static var poc: Self {
        var value = Self()
        value.isPoC = true
        return value
    }
}
