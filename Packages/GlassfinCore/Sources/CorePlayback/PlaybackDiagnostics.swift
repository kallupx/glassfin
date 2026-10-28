import CoreModels
import Foundation

public struct PlaybackDiagnostics: Sendable, Equatable {
    public let method: PlayMethod
    public let sourceVideo: String
    public let sourceAudio: String
    public let targetVideo: String
    public let targetAudio: String
    public let bitrate: Int?

    public init(source: MediaSourceDTO, method: PlayMethod, selection: PlaybackTrackSelection) {
        self.method = method
        let streams = source.MediaStreams ?? []
        func codec(_ kind: String, index: Int? = nil) -> String {
            let candidates = streams.filter { $0.Type?.lowercased() == kind }
            let stream =
                index.flatMap { id in candidates.first { $0.Index == id } }
                ?? candidates.first { $0.IsDefault == true } ?? candidates.first
            return MetadataSanitizer.displayText(MediaLogRedactor.redact(stream?.Codec ?? ""), limit: 40)
        }
        sourceVideo = codec("video")
        sourceAudio = codec("audio", index: selection.audio)
        let query = method == .directPlay ? [] : URLComponents(string: source.TranscodingUrl ?? "")?.queryItems ?? []
        func target(_ name: String, fallback: String) -> String {
            let value = query.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value ?? fallback
            return MetadataSanitizer.displayText(MediaLogRedactor.redact(value), limit: 40)
        }
        targetVideo = target("VideoCodec", fallback: sourceVideo)
        targetAudio = target("AudioCodec", fallback: sourceAudio)
        let videoRate = Int(query.first { $0.name.lowercased() == "videobitrate" }?.value ?? "")
        let audioRate = Int(query.first { $0.name.lowercased() == "audiobitrate" }?.value ?? "")
        if let videoRate, let audioRate, videoRate >= 0, audioRate >= 0, videoRate <= Int.max - audioRate {
            bitrate = videoRate + audioRate
        } else {
            bitrate = source.Bitrate
        }
    }
}

@MainActor
public protocol PlaybackBufferReporting: AnyObject {
    var bufferedDuration: Duration { get }
}
