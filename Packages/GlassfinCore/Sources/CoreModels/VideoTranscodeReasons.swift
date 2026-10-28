import Foundation

/// Q8P-05: the server ignores TranscodeReasons in JSON. Only the negotiated URL is binding.
public enum VideoTranscodeReasons {
    private static let blocking: Set<String> = [
        "VideoCodecNotSupported", "VideoProfileNotSupported", "VideoRangeTypeNotSupported",
        "VideoCodecTagNotSupported", "VideoLevelNotSupported", "VideoResolutionNotSupported",
        "VideoBitDepthNotSupported", "VideoFramerateNotSupported", "RefFramesNotSupported",
        "AnamorphicVideoNotSupported", "InterlacedVideoNotSupported", "VideoBitrateNotSupported",
        "UnknownVideoStreamInfo", "VideoRotationNotSupported",
    ]

    public static func parse(transcodingURL: String?) -> [String] {
        guard let transcodingURL,
            let components = URLComponents(string: transcodingURL)
        else { return [] }
        return (components.queryItems ?? []).filter { $0.name == "TranscodeReasons" }
            .flatMap { ($0.value ?? "").split(separator: ",").map(String.init) }
    }

    public static func blocksPlayback(transcodingURL: String?) -> Bool {
        parse(transcodingURL: transcodingURL).contains { blocking.contains($0) }
    }
}
