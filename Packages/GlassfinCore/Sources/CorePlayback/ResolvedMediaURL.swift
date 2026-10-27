import CoreNetworking
import Foundation

/// Handoff to AVPlayer (M08). This type does not import AVFoundation so it builds on Linux.
///
/// AVPlayer follows redirects on its own and does not use Glassfin's `URLSession` delegate,
/// so S4.6 cannot protect a player request. Always pass the server's already-resolved media
/// URL. Prefer the Authorization header via `AVURLAssetHTTPHeaderFieldsKey` (the constant
/// below). A credential query is only a fallback, and any URL that contains one must be
/// redacted before logging. ADR M08-2 tries the resource loader first, then this key.
public struct ResolvedMediaURL: Sendable, Equatable, CustomStringConvertible {
    #if DEBUG
        public static let httpHeaderFieldsKey = "AVURLAssetHTTPHeaderFieldsKey"
    #else
        public static let httpHeaderFieldsKey = ""
    #endif

    public var url: URL
    public var headerFields: [String: String]
    public var usesAPIKeyQueryFallback: Bool

    public init(url: URL, headerFields: [String: String], usesAPIKeyQueryFallback: Bool) {
        self.url = url
        self.headerFields = headerFields
        self.usesAPIKeyQueryFallback = usesAPIKeyQueryFallback
    }

    public var description: String {
        "ResolvedMediaURL(url: \(SensitiveRedactor.redact(url.absoluteString)), fallback: \(usesAPIKeyQueryFallback))"
    }
}

public enum PlaybackHandoff {
    public static func make(_ prepared: PreparedMediaRequest) -> ResolvedMediaURL {
        var headers: [String: String] = [:]
        if let authorization = prepared.authorizationHeader {
            headers["Authorization"] = authorization
        }
        return ResolvedMediaURL(
            url: prepared.url,
            headerFields: headers,
            usesAPIKeyQueryFallback: prepared.usesAPIKeyQuery
        )
    }
}
