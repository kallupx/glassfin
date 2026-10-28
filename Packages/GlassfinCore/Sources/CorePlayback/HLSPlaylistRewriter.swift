import Foundation

public struct HLSRewrite: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public var playlist: String
    public var rewritten: Int
    public var untouchedSegments: Int

    public init(playlist: String, rewritten: Int, untouchedSegments: Int) {
        self.playlist = playlist
        self.rewritten = rewritten
        self.untouchedSegments = untouchedSegments
    }

    /// Counts only. The playlist text can contain a server-written segment credential.
    public var description: String {
        "HLSRewrite(rewritten: \(rewritten), untouchedSegments: \(untouchedSegments))"
    }

    public var debugDescription: String { description }
}

public enum PlaylistURIRejection: Error, Sendable, Equatable {
    case userInfo
    case crossOrigin
    case httpsDowngrade
    case unresolvable
}

/// Rewrites an HLS playlist for the resource loader.
///
/// Q8-2-06: every URI is resolved against this playlist's origin. An absolute URI on
/// another origin, or any HTTPS→HTTP change, rejects the whole playlist. Playlist and key
/// URIs stay on that origin and move to `glassfin-media` with credential queries removed.
/// D4 / Q8P-23: the loader carries the server query separately and appends it only on
/// same-origin master/variant requests, without Authorization. Keys use the header only.
/// Same-origin segment and EXT-X-MAP URIs stay server-written `http`/`https` because
/// AVFoundation fetches them itself. Their server-written credentials stay untouched
/// (accepted risk); the app never adds a token to these URIs. Logs must redact them.
public enum HLSPlaylistRewriter {
    public static func rewrite(playlist: String, baseURL: URL) -> Result<HLSRewrite, PlaylistURIRejection> {
        guard MediaURLValidation.hasNoUserInfo(baseURL) else { return .failure(.userInfo) }
        let text = stripBOM(playlist)
        let base = MediaCredentialQuery.stripping(baseURL)
        var rewritten = 0
        var untouched = 0
        var lines: [String] = []
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            switch rewriteLine(String(raw), base: base, rewritten: &rewritten, untouched: &untouched) {
            case .success(let line):
                lines.append(line)
            case .failure(let rejection):
                return .failure(rejection)
            }
        }
        let result = HLSRewrite(
            playlist: lines.joined(separator: "\n"),
            rewritten: rewritten,
            untouchedSegments: untouched
        )
        return .success(result)
    }

    private static func rewriteLine(
        _ line: String,
        base: URL,
        rewritten: inout Int,
        untouched: inout Int
    ) -> Result<String, PlaylistURIRejection> {
        let trimmed = line.hasSuffix("\r") ? String(line.dropLast()) : line
        if trimmed.hasPrefix("#") {
            guard trimmed.contains("URI=\"") else { return .success(trimmed) }
            var failure: PlaylistURIRejection?
            let updated = replacingURIs(in: trimmed) { uri in
                if failure != nil { return uri }
                switch apply(
                    uri,
                    kind: kind(tagLine: trimmed, uri: uri),
                    base: base,
                    rewritten: &rewritten,
                    untouched: &untouched
                ) {
                case .success(let value):
                    return value
                case .failure(let rejection):
                    failure = rejection
                    return uri
                }
            }
            if let failure { return .failure(failure) }
            return .success(updated)
        }
        let payload = trimmed.trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { return .success(trimmed) }
        return apply(payload, kind: kind(uri: payload), base: base, rewritten: &rewritten, untouched: &untouched)
    }

    private static func apply(
        _ uri: String,
        kind: HLSURIKind,
        base: URL,
        rewritten: inout Int,
        untouched: inout Int
    ) -> Result<String, PlaylistURIRejection> {
        guard let resolved = URL(string: uri, relativeTo: base)?.absoluteURL else {
            return .failure(.unresolvable)
        }
        guard MediaURLValidation.hasNoUserInfo(resolved) else { return .failure(.userInfo) }
        if MediaOrigin.isHTTPSDowngrade(base, resolved) {
            return .failure(.httpsDowngrade)
        }
        if !MediaOrigin.matches(base, resolved) {
            return .failure(.crossOrigin)
        }
        switch kind {
        case .playlist, .key:
            let stripped = MediaCredentialQuery.stripping(resolved)
            guard let wrapped = MediaAssetScheme.wrap(stripped, isKey: kind == .key) else {
                return .failure(.unresolvable)
            }
            rewritten += 1
            return .success(wrapped.absoluteString)
        case .segment:
            untouched += 1
            return .success(resolved.absoluteString)
        }
    }

    private static func kind(tagLine: String, uri: String) -> HLSURIKind {
        switch tagName(tagLine) {
        case "EXT-X-KEY", "EXT-X-SESSION-KEY":
            return .key
        case "EXT-X-MAP", "EXT-X-PART", "EXT-X-PRELOAD-HINT":
            return .segment
        case "EXT-X-MEDIA", "EXT-X-I-FRAME-STREAM-INF":
            return .playlist
        default:
            return kind(uri: uri)
        }
    }

    private static func kind(uri: String) -> HLSURIKind {
        let path = uri.split(separator: "?", maxSplits: 1).first.map(String.init) ?? uri
        if path.lowercased().contains(".m3u8") { return .playlist }
        return .segment
    }

    private static func tagName(_ line: String) -> String? {
        guard line.hasPrefix("#EXT") else { return nil }
        let head = line.split(separator: ":", maxSplits: 1).first ?? Substring(line)
        return String(head.dropFirst())
    }

    private static func replacingURIs(in line: String, transform: (String) -> String) -> String {
        var result = ""
        var rest = Substring(line)
        let marker = "URI=\""
        while let range = rest.range(of: marker) {
            result += rest[..<range.upperBound]
            rest = rest[range.upperBound...]
            guard let end = rest.firstIndex(of: "\"") else {
                result += rest
                return result
            }
            result += transform(String(rest[..<end]))
            result.append("\"")
            rest = rest[rest.index(after: end)...]
        }
        result += rest
        return result
    }

    private static func stripBOM(_ text: String) -> String {
        text.hasPrefix("\u{feff}") ? String(text.dropFirst()) : text
    }
}

private enum HLSURIKind {
    case playlist
    case key
    case segment
}
