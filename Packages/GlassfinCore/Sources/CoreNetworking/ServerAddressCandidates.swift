import CoreModels
import Foundation

/// One URL the probe may try. HTTP to a public host is listed so the caller can
/// explain the skip, and ``mayConnect`` is false so it is never requested.
public struct ServerEndpointCandidate: Sendable, Equatable {
    public var url: URL
    public var verdict: ServerTransportPolicy.Verdict
    public var mayConnect: Bool

    public init(url: URL, verdict: ServerTransportPolicy.Verdict, mayConnect: Bool) {
        self.url = url
        self.verdict = verdict
        self.mayConnect = mayConnect
    }
}

/// How ``ServerAddressCandidates/expand(_:)`` classified the text the user typed.
public struct ServerAddressPlan: Sendable, Equatable {
    public var candidates: [ServerEndpointCandidate]
    /// True only when the user typed `http://` and the host is public.
    public var explicitPublicHTTP: Bool
    public var invalid: Bool

    public init(candidates: [ServerEndpointCandidate], explicitPublicHTTP: Bool, invalid: Bool) {
        self.candidates = candidates
        self.explicitPublicHTTP = explicitPublicHTTP
        self.invalid = invalid
    }

    public static let invalid = ServerAddressPlan(candidates: [], explicitPublicHTTP: false, invalid: true)

    /// HTTP candidates that S4.3 refuses. The probe does not open them.
    public var httpSkippedByPolicy: Bool {
        candidates.contains { $0.verdict == .publicHTTPRejected }
    }
}

/// Q4-02 attempt list. Subpaths stay on every candidate. HTTP is emitted only as a
/// non-connectable record when S4.3 rejects the host.
public enum ServerAddressCandidates {
    public static let attemptTimeout: Duration = .seconds(5)
    public static let overallTimeout: Duration = .seconds(20)

    private static let forbiddenSchemes: Set<String> = ["ftp", "file", "javascript", "glassfin-media"]

    public static func expand(_ raw: String) -> ServerAddressPlan {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalid }
        if let scheme = scheme(in: trimmed) {
            if forbiddenSchemes.contains(scheme) || (scheme != "http" && scheme != "https") {
                return .invalid
            }
            return expandSchemed(trimmed, scheme: scheme)
        }
        return expandSchemeless(trimmed)
    }

    /// Joins an API path onto a server URL, keeping a reverse-proxy subpath.
    public static func appendingAPIPath(_ server: URL, path: String) -> URL? {
        guard var components = URLComponents(url: server, resolvingAgainstBaseURL: false) else { return nil }
        let base = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        let relative = path.hasPrefix("/") ? path : "/" + path
        components.path = base + relative
        return components.url
    }

    private static func expandSchemed(_ raw: String, scheme: String) -> ServerAddressPlan {
        guard let parsed = URL(string: raw), let canonical = try? ServerAddress.canonical(parsed),
            let host = canonical.host?.lowercased(), !host.isEmpty
        else { return .invalid }
        let path = canonical.path.isEmpty ? "/" : canonical.path
        let explicitPort = URLComponents(string: raw)?.port
        if let explicitPort {
            guard let candidate = endpoint(scheme: scheme, host: host, port: explicitPort, path: path) else {
                return .invalid
            }
            return plan(candidates: [candidate], scheme: scheme)
        }
        let ports = scheme == "https" ? [443, 8920] : [8096, 80]
        let candidates = ports.compactMap { endpoint(scheme: scheme, host: host, port: $0, path: path) }
        guard !candidates.isEmpty else { return .invalid }
        return plan(candidates: candidates, scheme: scheme)
    }

    private static func expandSchemeless(_ raw: String) -> ServerAddressPlan {
        guard let parts = schemelessParts(raw), !parts.host.isEmpty else { return .invalid }
        let pairs: [(String, Int)]
        if let port = parts.port {
            pairs = [("https", port), ("http", port)]
        } else {
            pairs = [("https", 443), ("https", 8920), ("http", 8096), ("http", 80)]
        }
        let candidates = pairs.compactMap { endpoint(scheme: $0.0, host: parts.host, port: $0.1, path: parts.path) }
        guard !candidates.isEmpty else { return .invalid }
        return ServerAddressPlan(candidates: candidates, explicitPublicHTTP: false, invalid: false)
    }

    private static func plan(candidates: [ServerEndpointCandidate], scheme: String) -> ServerAddressPlan {
        let explicitPublic = scheme == "http" && candidates.contains { $0.verdict == .publicHTTPRejected }
        return ServerAddressPlan(candidates: candidates, explicitPublicHTTP: explicitPublic, invalid: false)
    }

    private static func endpoint(scheme: String, host: String, port: Int, path: String) -> ServerEndpointCandidate? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        components.path = path.hasPrefix("/") ? path : "/" + path
        guard let url = components.url, let canonical = try? ServerAddress.canonical(url) else { return nil }
        let verdict = ServerTransportPolicy.evaluate(canonical)
        let mayConnect = verdict == .secure || verdict == .unencryptedLocal
        return ServerEndpointCandidate(url: canonical, verdict: verdict, mayConnect: mayConnect)
    }

    private static func scheme(in raw: String) -> String? {
        guard let range = raw.range(of: "://") else { return nil }
        let scheme = raw[..<range.lowerBound].lowercased()
        guard !scheme.isEmpty, scheme.allSatisfy({ $0.isLetter || $0 == "+" || $0 == "-" || $0 == "." }) else {
            return nil
        }
        return scheme
    }

    private static func schemelessParts(_ raw: String) -> (host: String, port: Int?, path: String)? {
        if raw.hasPrefix("[") {
            guard let end = raw.firstIndex(of: "]") else { return nil }
            let host = String(raw[raw.index(after: raw.startIndex)..<end])
            let rest = String(raw[raw.index(after: end)...])
            return hostPortPath(host: host, rest: rest, allowColonInHost: true)
        }
        let path: String
        let hostPort: String
        if let slash = raw.firstIndex(of: "/") {
            hostPort = String(raw[..<slash])
            path = String(raw[slash...])
        } else {
            hostPort = raw
            path = "/"
        }
        guard !hostPort.isEmpty else { return nil }
        if let colon = hostPort.lastIndex(of: ":"), hostPort.filter({ $0 == ":" }).count == 1 {
            let portText = hostPort[hostPort.index(after: colon)...]
            if portText.isEmpty || !portText.allSatisfy({ $0.isASCII && $0.isNumber }) {
                return nil
            }
            guard let port = Int(portText), (1...65_535).contains(port) else { return nil }
            let host = String(hostPort[..<colon])
            guard !host.isEmpty else { return nil }
            return (host, port, path.isEmpty ? "/" : path)
        }
        if hostPort.contains(":") { return nil }
        return (hostPort, nil, path.isEmpty ? "/" : path)
    }

    private static func hostPortPath(host: String, rest: String, allowColonInHost: Bool) -> (
        host: String, port: Int?, path: String
    )? {
        guard !host.isEmpty else { return nil }
        _ = allowColonInHost
        if rest.isEmpty { return (host, nil, "/") }
        if rest.hasPrefix("/") { return (host, nil, rest) }
        guard rest.hasPrefix(":") else { return nil }
        let after = rest.dropFirst()
        let portText: Substring
        let path: String
        if let slash = after.firstIndex(of: "/") {
            portText = after[..<slash]
            path = String(after[slash...])
        } else {
            portText = after
            path = "/"
        }
        guard let port = Int(portText), (1...65_535).contains(port) else { return nil }
        return (host, port, path)
    }
}
