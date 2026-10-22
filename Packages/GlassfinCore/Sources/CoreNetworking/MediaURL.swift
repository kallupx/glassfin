import CoreModels
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public enum MediaAuthorizationMode: Sendable, Equatable {
    /// Preferred. Token travels in the Authorization header (and later in AVURLAsset options).
    case header
    /// Fallback only, for a media URL handed to a player that cannot set headers.
    case apiKeyQuery
}

public struct PreparedMediaRequest: Sendable, Equatable, CustomStringConvertible {
    public var url: URL
    public var authorizationHeader: String?
    public var usesAPIKeyQuery: Bool

    public init(url: URL, authorizationHeader: String?, usesAPIKeyQuery: Bool) {
        self.url = url
        self.authorizationHeader = authorizationHeader
        self.usesAPIKeyQuery = usesAPIKeyQuery
    }

    public var description: String {
        "PreparedMediaRequest(url: \(SensitiveRedactor.redact(url.absoluteString)), apiKey: \(usesAPIKeyQuery))"
    }
}

public enum MediaRequestBuilder {
    /// Builds a media or image request. Header mode and `ApiKey` query mode are mutually exclusive.
    public static func prepare(
        server: URL,
        path: String,
        query: [URLQueryItem] = [],
        identity: ClientIdentity,
        mode: MediaAuthorizationMode
    ) throws -> PreparedMediaRequest {
        switch mode {
        case .header:
            let url = try HTTPJellyfinClient.url(server: server, path: path, query: query)
            if RedirectPolicy.containsCredentialQuery(url) {
                throw APIError.invalidURL
            }
            return PreparedMediaRequest(
                url: url,
                authorizationHeader: try identity.authorizationHeader(),
                usesAPIKeyQuery: false
            )
        case .apiKeyQuery:
            guard let token = identity.token, !token.isEmpty else { throw APIError.unauthorized }
            var items = query
            items.append(URLQueryItem(name: "ApiKey", value: token))
            let url = try HTTPJellyfinClient.url(server: server, path: path, query: items)
            return PreparedMediaRequest(url: url, authorizationHeader: nil, usesAPIKeyQuery: true)
        }
    }
}

/// WebSocket endpoint.
///
/// Verified against jellyfin-sdk-swift 3.3.0 `JellyfinClient.socketURL`: the path is
/// `{server path}/socket`, the scheme is `ws`/`wss`, and the SDK puts the token in an
/// `ApiKey` query item plus `deviceId`. URLSession's web socket task can send headers,
/// so Glassfin sends the MediaBrowser header and only `deviceId` in the query.
/// `ApiKey` stays off the socket URL because proxy logs would capture it (S5.1).
public enum SocketRequestBuilder {
    public static func make(server: URL, identity: ClientIdentity) throws -> URLRequest {
        guard var components = URLComponents(url: server, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        switch components.scheme?.lowercased() {
        case "https": components.scheme = "wss"
        case "http": components.scheme = "ws"
        default: throw APIError.invalidURL
        }
        var base = components.path
        while base.hasSuffix("/") { base.removeLast() }
        components.path = base + "/socket"
        components.queryItems = [URLQueryItem(name: "deviceId", value: identity.deviceID)]
        guard let url = components.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(try identity.authorizationHeader(), forHTTPHeaderField: "Authorization")
        return request
    }
}
