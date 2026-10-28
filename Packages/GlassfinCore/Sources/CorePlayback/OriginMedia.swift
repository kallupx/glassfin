import CoreModels
import Foundation

public struct HTTPByteRange: Sendable, Equatable {
    public var start: Int64
    public var end: Int64?

    public init(start: Int64, end: Int64?) {
        self.start = start
        self.end = end
    }

    public var headerValue: String {
        if let end {
            return "bytes=\(start)-\(end)"
        }
        return "bytes=\(start)-"
    }
}

public enum ContentRangeHeader {
    /// `bytes 0-1/123` → 123. An unknown total (`*`) is `nil`.
    public static func totalLength(of header: String?) -> Int64? {
        guard let header, let slash = header.lastIndex(of: "/") else { return nil }
        let total = header[header.index(after: slash)...].trimmingCharacters(in: .whitespaces)
        if total == "*" { return nil }
        return Int64(total)
    }
}

public struct OriginMediaResponse: Sendable, Equatable {
    public var status: Int
    public var location: URL?
    public var contentType: String?
    public var body: Data
    public var totalLength: Int64?

    public init(
        status: Int,
        location: URL? = nil,
        contentType: String? = nil,
        body: Data = Data(),
        totalLength: Int64? = nil
    ) {
        self.status = status
        self.location = location
        self.contentType = contentType
        self.body = body
        self.totalLength = totalLength
    }
}

/// A fetch the resource loader performs with Glassfin's session.
///
/// A credential query together with an Authorization header is refused, so the two cannot be combined.
public struct OriginMediaRequest: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public var method: String
    public var url: URL
    public var authorizationHeader: String?
    public var range: HTTPByteRange?
    public var trust: ServerTrustClass

    public init?(
        method: String,
        url: URL,
        authorizationHeader: String?,
        range: HTTPByteRange? = nil,
        trust: ServerTrustClass
    ) {
        guard MediaURLValidation.hasNoUserInfo(url) else { return nil }
        let credential = MediaCredentialQuery.contains(url)
        if credential && authorizationHeader != nil { return nil }
        if let authorizationHeader, authorizationHeader.isEmpty { return nil }
        self.method = method
        self.url = url
        self.authorizationHeader = authorizationHeader
        self.range = range
        self.trust = trust
    }

    public var description: String {
        let authorization = authorizationHeader == nil ? "none" : "header"
        let host = url.host ?? ""
        return "OriginMediaRequest(method: \(method), host: \(host), "
            + "authorization: \(authorization), trust: \(trust))"
    }

    public var debugDescription: String { description }
}

public protocol MediaOriginClient: Sendable {
    func fetch(_ request: OriginMediaRequest) async throws(APIError) -> OriginMediaResponse
}

public enum ResourceLoadPlanner {
    /// D4: only same-origin playlists receive the verbatim server credential query, without
    /// Authorization. Keys and other resources use the header and credential-free URLs.
    public static func originRequest(
        assetURL: URL,
        authorizationHeader: String,
        trust: ServerTrustClass,
        range: HTTPByteRange?,
        allowedOrigin: URL,
        playlistCredentials: ServerHLSCredentialQuery? = nil
    ) -> OriginMediaRequest? {
        guard MediaURLValidation.hasNoUserInfo(assetURL), MediaURLValidation.hasNoUserInfo(allowedOrigin) else {
            return nil
        }
        guard let origin = MediaAssetScheme.unwrap(assetURL) else { return nil }
        guard MediaOrigin.matches(origin, allowedOrigin), !MediaOrigin.isHTTPSDowngrade(allowedOrigin, origin) else {
            return nil
        }
        let scheme = origin.scheme?.lowercased()
        guard scheme == "https" || scheme == "http" else { return nil }
        let isPlaylist = PlaylistSniffer.isPlaylistURL(origin) && !MediaAssetScheme.isKey(assetURL)
        let requestURL: URL
        if isPlaylist, let playlistCredentials {
            guard let authenticated = playlistCredentials.appending(toPlaylist: origin) else { return nil }
            requestURL = authenticated
        } else {
            requestURL = origin
        }
        return OriginMediaRequest(
            method: "GET",
            url: requestURL,
            authorizationHeader: MediaCredentialQuery.contains(requestURL) ? nil : authorizationHeader,
            range: PlaylistSniffer.isPlaylistURL(origin)
                ? nil : ChunkedRangePlanner.next(range: range, received: 0, totalLength: nil),
            trust: trust
        )
    }
}

public struct PlayerByteReply: Sendable, Equatable {
    public var data: Data
    public var contentTypeUTI: String
    public var contentLength: Int64
    public var isByteRangeAccessSupported: Bool

    public init(data: Data, contentTypeUTI: String, contentLength: Int64, isByteRangeAccessSupported: Bool) {
        self.data = data
        self.contentTypeUTI = contentTypeUTI
        self.contentLength = contentLength
        self.isByteRangeAccessSupported = isByteRangeAccessSupported
    }
}

public enum PlaylistSniffer {
    public static func isPlaylistURL(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "m3u8"
    }

    public static func isPlaylist(contentType: String?, body: Data) -> Bool {
        if let contentType {
            let lower = contentType.lowercased()
            if lower.hasPrefix("video/") || lower.hasPrefix("audio/") { return false }
            if lower.contains("mpegurl") { return true }
        }
        return bodyLooksLikePlaylist(body)
    }

    private static func bodyLooksLikePlaylist(_ body: Data) -> Bool {
        let prefix = body.prefix(64)
        guard let text = String(data: prefix, encoding: .utf8) else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutBOM = trimmed.hasPrefix("\u{feff}") ? String(trimmed.dropFirst()) : trimmed
        return withoutBOM.hasPrefix("#EXTM3U")
    }
}

public enum PlayerResponseBuilder {
    /// Playlist bodies are rewritten before they are handed to AVPlayer. Other bodies pass through.
    public static func build(origin: OriginMediaResponse, requestURL: URL) -> PlayerByteReply? {
        guard (200..<300).contains(origin.status) else { return nil }
        if PlaylistSniffer.isPlaylist(contentType: origin.contentType, body: origin.body) {
            guard origin.body.count <= MediaLoaderLimits.playlistBytes,
                let text = String(data: origin.body, encoding: .utf8)
            else { return nil }
            guard case .success(let rewrite) = HLSPlaylistRewriter.rewrite(playlist: text, baseURL: requestURL) else {
                return nil
            }
            let data = Data(rewrite.playlist.utf8)
            return PlayerByteReply(
                data: data,
                contentTypeUTI: "public.m3u-playlist",
                contentLength: Int64(data.count),
                isByteRangeAccessSupported: false
            )
        }
        let length = origin.totalLength ?? Int64(origin.body.count)
        return PlayerByteReply(
            data: origin.body,
            contentTypeUTI: progressiveUTI(contentType: origin.contentType, url: requestURL),
            contentLength: length,
            isByteRangeAccessSupported: true
        )
    }

    private static func progressiveUTI(contentType: String?, url: URL) -> String {
        let type = contentType?.lowercased() ?? ""
        let path = url.path.lowercased()
        if type.contains("mp4") || path.hasSuffix(".mp4") || path.hasSuffix(".m4v") {
            return "public.mpeg-4"
        }
        if type.contains("quicktime") || path.hasSuffix(".mov") {
            return "com.apple.quicktime-movie"
        }
        return "public.data"
    }
}
