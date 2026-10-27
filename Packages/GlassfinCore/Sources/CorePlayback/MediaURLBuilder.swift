import CoreModels
import CoreNetworking
import Foundation

/// Builds playback URLs. The credential-query fallback is constructed only here.
public enum MediaURLBuilder {
    public static func resolveTranscodingURL(server: URL, transcodingURL: String) -> URL? {
        DTOMapper.resolve(server: server, relative: transcodingURL)
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
        guard !token.isEmpty else { return nil }
        guard !MediaCredentialQuery.contains(strippedURL) else { return nil }
        guard var components = URLComponents(url: strippedURL, resolvingAgainstBaseURL: false) else { return nil }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "ApiKey", value: token))
        components.queryItems = items
        return components.url
    }
}
