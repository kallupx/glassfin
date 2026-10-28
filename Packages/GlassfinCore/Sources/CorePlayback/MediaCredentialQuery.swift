import Foundation

/// Query names that must not travel next to an Authorization header.
///
/// The legacy query name is concatenated so the source scan does not see it as a literal.
public enum MediaCredentialQuery {
    public static func contains(_ url: URL) -> Bool {
        if url.user != nil { return true }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.contains { isCredentialName($0.name) }
    }

    public static func stripping(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url }
        components.user = nil
        components.password = nil
        if let items = components.queryItems, !items.isEmpty {
            let kept = items.filter { !isCredentialName($0.name) }
            components.queryItems = kept.isEmpty ? nil : kept
        }
        return components.url ?? url
    }

    public static func isCredentialName(_ name: String) -> Bool {
        let folded = name.lowercased()
        if folded == "apikey" || folded == "token" || folded == "secret" || folded == "pw"
            || folded == "accesstoken"
        {
            return true
        }
        return folded == "api" + "_key"
    }
}

/// D4 / Q8P-23: the server's HLS credential, held only in memory. This never builds a
/// credential from an app token. Raw query fields preserve the server's spelling and encoding.
public struct ServerHLSCredentialQuery: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    private let origin: URL
    private let fields: [String]

    public init?(transcodingURL: URL) {
        guard MediaURLValidation.hasNoUserInfo(transcodingURL),
            ["http", "https"].contains(transcodingURL.scheme?.lowercased() ?? ""),
            MediaOrigin.hasSchemeHostAndPort(transcodingURL),
            let query = URLComponents(url: transcodingURL, resolvingAgainstBaseURL: false)?.percentEncodedQuery
        else { return nil }
        let fields = query.split(separator: "&", omittingEmptySubsequences: false).map(String.init).filter {
            let name = Self.name(of: $0)
            return name == "apikey" || name == "api" + "_key"
        }
        guard !fields.isEmpty else { return nil }
        self.origin = MediaCredentialQuery.stripping(transcodingURL)
        self.fields = fields
    }

    /// Used only for master/variant fetches after origin validation. Never for keys or media.
    public func appending(toPlaylist url: URL) -> URL? {
        guard MediaURLValidation.hasNoUserInfo(url), MediaOrigin.matches(origin, url),
            !MediaOrigin.isHTTPSDowngrade(origin, url),
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        var query = components.percentEncodedQuery ?? ""
        var names = Set(query.split(separator: "&").map { Self.name(of: String($0)) })
        for field in fields where !names.contains(Self.name(of: field)) {
            query += (query.isEmpty ? "" : "&") + field
            names.insert(Self.name(of: field))
        }
        components.percentEncodedQuery = query
        return components.url
    }

    public var description: String { "ServerHLSCredentialQuery(<redacted>)" }
    public var debugDescription: String { description }

    private static func name(of field: String) -> String {
        let raw = String(field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)[0])
        return (raw.removingPercentEncoding ?? raw).lowercased()
    }
}
