import CoreModels
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public enum RedirectFollow: Sendable, Equatable {
    case follow(stripAuthorization: Bool)
    case reject(RedirectRejection)
}

public enum RedirectApplication: Sendable, Equatable {
    case follow(URLRequest)
    case reject(RedirectRejection)
}

/// S4.6 for Glassfin's own `URLSession`.
///
/// Authorization stays on the same origin (scheme, host, and port). Any HTTPS→HTTP
/// redirect is rejected. A request URL that contains an API key query is rejected,
/// not merely stripped, when the target is a different origin or HTTP.
///
/// AVPlayer follows redirects itself and does not use this delegate. Callers must
/// hand AVPlayer the server's already-resolved media URL (see `ResolvedMediaURL`).
public enum RedirectPolicy {
    public static func decide(originalURL: URL, redirectURL: URL) -> RedirectFollow {
        let downgrade = isHTTPSDowngrade(originalURL, redirectURL)
        let sameOrigin = originsMatch(originalURL, redirectURL)
        let credential = containsCredentialQuery(originalURL)
        if credential && downgrade {
            return .reject(.credentialQueryDowngrade)
        }
        if downgrade {
            return .reject(.httpsDowngrade)
        }
        if credential && !sameOrigin {
            return .reject(.credentialQueryCrossHost)
        }
        if !sameOrigin {
            return .follow(stripAuthorization: true)
        }
        return .follow(stripAuthorization: false)
    }

    public static func apply(original: URLRequest, proposed: URLRequest) -> RedirectApplication {
        guard let originalURL = original.url, let redirectURL = proposed.url else {
            return .reject(.notFollowed)
        }
        switch decide(originalURL: originalURL, redirectURL: redirectURL) {
        case .reject(let reason):
            return .reject(reason)
        case .follow(let strip):
            var copy = proposed
            if strip {
                copy.setValue(nil, forHTTPHeaderField: "Authorization")
            }
            return .follow(copy)
        }
    }

    static func containsCredentialQuery(_ url: URL) -> Bool {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.contains { isCredentialQueryName($0.name) }
    }

    static func isCredentialQueryName(_ name: String) -> Bool {
        let folded = name.lowercased()
        return folded == "apikey" || folded == "api" + "_key"
    }

    private struct Origin: Equatable {
        var scheme: String
        var host: String
        var port: Int
    }

    /// Scheme, host, and port. Default ports are filled in so `:443` matches an omitted HTTPS port.
    private static func originsMatch(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let left = origin(lhs), let right = origin(rhs) else { return false }
        return left == right
    }

    private static func origin(_ url: URL) -> Origin? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        guard let port = url.port ?? defaultPort(scheme) else { return nil }
        return Origin(scheme: scheme, host: host, port: port)
    }

    private static func defaultPort(_ scheme: String) -> Int? {
        switch scheme {
        case "https":
            443
        case "http":
            80
        default:
            nil
        }
    }

    private static func isHTTPSDowngrade(_ original: URL, _ redirect: URL) -> Bool {
        original.scheme?.lowercased() == "https" && redirect.scheme?.lowercased() == "http"
    }
}

public final class RedirectSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var rejection: RedirectRejection?

    public func consumeRejection() -> RedirectRejection? {
        lock.lock()
        defer { lock.unlock() }
        let value = rejection
        rejection = nil
        return value
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let original = task.originalRequest ?? task.currentRequest ?? request
        switch RedirectPolicy.apply(original: original, proposed: request) {
        case .follow(let next):
            completionHandler(next)
        case .reject(let reason):
            lock.lock()
            rejection = reason
            lock.unlock()
            completionHandler(nil)
        }
    }
}
