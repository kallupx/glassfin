import CoreModels
import Foundation

/// S4.2 and S4.3. Public names need HTTPS. Local HTTP is allowed and stays marked as unencrypted.
public enum ServerTransportPolicy {
    public enum Verdict: Sendable, Equatable {
        case secure
        case unencryptedLocal
        case publicHTTPRejected
        case invalid
    }

    public static let unencryptedWarning = "Yhteys ei ole salattu"
    public static let publicAddressRequiresHTTPS = "Julkiset osoitteet vaativat HTTPS:n"

    public static func evaluate(_ url: URL) -> Verdict {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .invalid
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return .invalid }
        if scheme == "https" { return .secure }
        if isLocal(host) { return .unencryptedLocal }
        return .publicHTTPRejected
    }

    public static func showsUnencryptedMark(_ url: URL) -> Bool {
        evaluate(url) == .unencryptedLocal
    }

    public static func message(for verdict: Verdict) -> String? {
        switch verdict {
        case .unencryptedLocal:
            return unencryptedWarning
        case .publicHTTPRejected:
            return publicAddressRequiresHTTPS
        case .secure, .invalid:
            return nil
        }
    }

    public static func badge(for url: URL) -> ServerSecurityBadge {
        let verdict = evaluate(url)
        return ServerSecurityBadge(showsUnencryptedMark: verdict == .unencryptedLocal, message: message(for: verdict))
    }

    static func isLocal(_ host: String) -> Bool {
        var trimmed = host
        while trimmed.hasSuffix(".") { trimmed.removeLast() }
        if trimmed.isEmpty { return false }
        if trimmed == "localhost" || trimmed.hasSuffix(".local") || !trimmed.contains(".") {
            return true
        }
        return isIPv4(trimmed) || trimmed.contains(":")
    }

    private static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let value = Int(part), (0...255).contains(value) else { return false }
            return !(part.count > 1 && part.hasPrefix("0"))
        }
    }
}

public struct ServerSecurityBadge: Sendable, Equatable {
    public var showsUnencryptedMark: Bool
    public var message: String?

    public init(showsUnencryptedMark: Bool, message: String?) {
        self.showsUnencryptedMark = showsUnencryptedMark
        self.message = message
    }
}

/// S4.5. http(s) only, userinfo removed, dot segments collapsed, credential queries dropped.
public enum ServerAddress {
    public static func canonical(_ raw: URL) throws -> URL {
        let normalized = try ServerURLNormalizer.normalize(raw)
        guard var components = URLComponents(url: normalized, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.fragment = nil
        if let items = components.queryItems {
            let kept = items.filter { !RedirectPolicy.isCredentialQueryName($0.name) }
            components.queryItems = kept.isEmpty ? nil : kept
        }
        components.path = normalizePath(components.path)
        guard let url = components.url, url.host != nil else { throw APIError.invalidURL }
        return url
    }

    static func normalizePath(_ path: String) -> String {
        let trailing = path.count > 1 && path.hasSuffix("/")
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        var stack: [Substring] = []
        for part in parts {
            if part == "." { continue }
            if part == ".." {
                if !stack.isEmpty { stack.removeLast() }
                continue
            }
            stack.append(part)
        }
        if stack.isEmpty { return path.isEmpty ? "" : "/" }
        var result = "/" + stack.joined(separator: "/")
        if trailing { result.append("/") }
        return result
    }
}
