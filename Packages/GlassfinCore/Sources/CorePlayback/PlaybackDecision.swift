import CoreModels
import Foundation

/// M08a-PoC deliberately advertises only a small, static set of native codecs.
public struct PlaybackDeviceProfile: Encodable, Sendable {
    public struct DirectPlayProfile: Encodable, Sendable {
        public let Container = "mp4,mov,m4v,hls"
        public let `Type` = "Video"
        public let VideoCodec = "h264,hevc"
        public let AudioCodec = "aac,ac3,eac3"
    }

    public struct TranscodingProfile: Encodable, Sendable {
        public let Container = "mp4"
        public let `Protocol` = "hls"
        public let `Type` = "Video"
        public let VideoCodec = "h264,hevc"
        public let AudioCodec = "aac,eac3"
        public let Context = "Streaming"
        public let EnableSubtitlesInManifest = false
        public let BreakOnNonKeyFrames = false
    }

    public let Name = "Glassfin M08a-PoC"
    public let DirectPlayProfiles = [DirectPlayProfile()]
    public let TranscodingProfiles = [TranscodingProfile()]
    /// No Encode subtitle profile. PlaybackInfo also disables subtitles explicitly.
    public let SubtitleProfiles: [String] = []

    public init() {}
}

public enum PlaybackDecision: Sendable, Equatable {
    public enum StreamConversion: Sendable, Equatable {
        case remux
        case audioTranscode
    }

    case directPlay
    case directStream(StreamConversion)
    case unsupported(PlaybackFailure)

    /// Mirrors the static profile and fails closed when codec metadata is missing.
    public static func decide(mediaSource source: MediaSourceDTO) -> PlaybackDecision {
        let streams = source.MediaStreams ?? []
        let video = streams.first { $0.Type?.lowercased() == "video" }?.Codec?.lowercased()
        guard let video, ["h264", "hevc"].contains(video) else {
            return .unsupported(.unsupportedVideo)
        }
        let audio = streams.first { $0.Type?.lowercased() == "audio" }
        let supportedAudio = audio == nil || ["aac", "ac3", "eac3"].contains(audio?.Codec?.lowercased() ?? "")
        let nativeContainer = ["mp4", "mov", "m4v", "hls"].contains(source.Container?.lowercased() ?? "")
        if nativeContainer && supportedAudio && source.SupportsDirectPlay == true {
            return .directPlay
        }
        guard let url = source.TranscodingUrl, !url.isEmpty else { return .unsupported(.unsupportedVideo) }
        // Even a supported codec may require video conversion (level, bitrate, HDR, burn-in).
        if (source.TranscodeReasons ?? []).contains(where: {
            $0.lowercased().hasPrefix("video") || $0.lowercased().hasPrefix("subtitle")
        }) {
            return .unsupported(.unsupportedVideo)
        }
        return .directStream(supportedAudio ? .remux : .audioTranscode)
    }
}
