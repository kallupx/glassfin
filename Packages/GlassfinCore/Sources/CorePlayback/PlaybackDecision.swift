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
        public let BreakOnNonKeyFrames = true
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

    /// The first default video wins; an audio default and server index hints do not select video.
    public static func videoFailure(streams: [MediaStreamDTO]?) -> PlaybackFailure? {
        let videos = (streams ?? []).filter { $0.Type?.lowercased() == "video" }
        guard let video = videos.first(where: { $0.IsDefault == true }) ?? videos.first else {
            return .couldNotPlay
        }
        return ["h264", "hevc"].contains(video.Codec?.lowercased() ?? "") ? nil : .unsupportedVideo
    }

    public static func supportsVideo(streams: [MediaStreamDTO]?) -> Bool {
        videoFailure(streams: streams) == nil
    }

    /// Q8P-22: choose the first default audio stream, then the first audio stream in metadata order.
    static func defaultAudio(streams: [MediaStreamDTO]?) -> MediaStreamDTO? {
        let audio = (streams ?? []).filter { $0.Type?.lowercased() == "audio" }
        return audio.first { $0.IsDefault == true } ?? audio.first
    }

    public static func decide(mediaSource source: MediaSourceDTO, allowDirectPlay: Bool = true) -> PlaybackDecision {
        let streams = source.MediaStreams ?? []
        if let reason = videoFailure(streams: streams) { return .unsupported(reason) }
        if VideoTranscodeReasons.blocksPlayback(transcodingURL: source.TranscodingUrl) {
            return .unsupported(.unsupportedVideo)
        }
        let audio = defaultAudio(streams: streams)
        let supportedAudio = audio == nil || ["aac", "ac3", "eac3"].contains(audio?.Codec?.lowercased() ?? "")
        let nativeContainer = ["mp4", "mov", "m4v", "hls"].contains(source.Container?.lowercased() ?? "")
        if allowDirectPlay && nativeContainer && supportedAudio && source.SupportsDirectPlay == true {
            return .directPlay
        }
        guard let url = source.TranscodingUrl, !url.isEmpty else { return .unsupported(.couldNotPlay) }
        return .directStream(supportedAudio ? .remux : .audioTranscode)
    }
}
