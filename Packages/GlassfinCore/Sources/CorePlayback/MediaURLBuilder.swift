import CoreModels
import CoreNetworking
import Foundation

/// Builds playback URLs. The credential-query fallback is constructed only here.
public enum MediaURLBuilder {
    public static func resolveTranscodingURL(server: URL, transcodingURL: String) -> URL? {
        // The mapper's slash-relative path preserves both proxy subpaths and query parameters.
        let relative =
            URL(string: transcodingURL)?.scheme == nil && !transcodingURL.hasPrefix("/")
            ? "/" + transcodingURL : transcodingURL
        return DTOMapper.resolve(server: server, relative: relative)
    }

    /// M08a-PoC: keep the negotiated URL but prohibit video encoding and subtitle burn-in.
    /// `Container=mp4` in the DeviceProfile negotiates fMP4; the URL enforces the segment format too.
    public static func videoCopyHLS(
        server: URL, transcodingURL: String, conversion: PlaybackDecision.StreamConversion
    ) throws(PlaybackFailure) -> URL {
        guard let url = resolveTranscodingURL(server: server, transcodingURL: transcodingURL),
            MediaOrigin.matches(server, url), !MediaOrigin.isHTTPSDowngrade(server, url),
            url.user == nil, url.password == nil,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { throw .insecureRedirect }
        let enforced = [
            "VideoCodec": "copy", "AudioCodec": conversion == .remux ? "copy" : "aac",
            "SegmentContainer": "mp4", "SubtitleStreamIndex": "-1",
            "AllowVideoStreamCopy": "true", "AllowAudioStreamCopy": "true",
        ]
        let names = Set(enforced.keys.map { $0.lowercased() })
        var query = (components.queryItems ?? []).filter { !names.contains($0.name.lowercased()) }
        query.append(
            contentsOf: enforced.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) })
        components.queryItems = query
        guard let result = components.url else { throw .couldNotPlay }
        return MediaCredentialQuery.stripping(result)
    }

    public static func directPlay(
        server: URL,
        identity: ClientIdentity,
        itemID: String,
        mediaSourceID: String,
        playSessionID: String
    ) throws(APIError) -> PreparedMediaRequest {
        try DirectPlayURL.make(
            server: server,
            identity: identity,
            itemID: itemID,
            mediaSourceID: mediaSourceID,
            playSessionID: playSessionID
        )
    }

    /// Opt-in fallback. The result has a credential query and no Authorization header.
    public static func queryCredentialFallback(strippedURL: URL, token: String) -> URL? {
        #if DEBUG
            guard !token.isEmpty else { return nil }
            guard !MediaCredentialQuery.contains(strippedURL) else { return nil }
            guard var components = URLComponents(url: strippedURL, resolvingAgainstBaseURL: false) else { return nil }
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "ApiKey", value: token))
            components.queryItems = items
            return components.url
        #else
            return nil
        #endif
    }
}
