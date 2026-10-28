import CoreModels
import Foundation

public enum PlaybackAttempt: Int, Sendable {
    case automatic, directStream, transcode
    public var next: Self? { Self(rawValue: rawValue + 1) }
}

public struct PlaybackStreamSelection: Sendable, Equatable {
    public let method: PlayMethod
    public let usesHLS: Bool

    /// Jellyfin's negotiated URL determines target codecs. Never rewrite its encoding choices.
    /// PB11 names copied video with converted audio DirectStream; video encoding is Transcode.
    public static func decide(
        source: MediaSourceDTO, attempt: PlaybackAttempt, subtitle: PlaybackTrack? = nil
    ) throws(PlaybackFailure) -> Self {
        let burn = subtitle?.delivery == .burnIn
        if attempt == .automatic, source.SupportsDirectPlay == true, !burn {
            return Self(method: .directPlay, usesHLS: source.Container?.lowercased() == "hls")
        }
        guard let url = source.TranscodingUrl, !url.isEmpty else { throw .couldNotPlay }
        let videoEncoding = attempt == .transcode || burn || VideoTranscodeReasons.blocksPlayback(transcodingURL: url)
        return Self(method: videoEncoding ? .transcode : .directStream, usesHLS: true)
    }
}

extension MediaURLBuilder {
    /// Full M08a preserves every server-negotiated codec, stream index and subtitle method.
    public static func negotiatedHLS(server: URL, transcodingURL: String) throws(PlaybackFailure) -> URL {
        guard let url = resolveTranscodingURL(server: server, transcodingURL: transcodingURL),
            MediaOrigin.matches(server, url), !MediaOrigin.isHTTPSDowngrade(server, url),
            MediaURLValidation.hasNoUserInfo(url)
        else { throw .insecureRedirect }
        return MediaCredentialQuery.stripping(url)
    }
}
