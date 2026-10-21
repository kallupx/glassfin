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
/// Authorization never crosses hosts. Any HTTPS→HTTP redirect is rejected.
/// A request URL that contains `ApiKey` (or the legacy query name) is rejected,
/// not merely stripped, when the target is a different host or HTTP.
/// Same-host HTTPS redirects are allowed.
///
/// AVPlayer follows redirects itself and does not use this delegate. Callers must
/// hand AVPlayer the server's already-resolved media URL (see `ResolvedMediaURL`).
public enum RedirectPolicy {
    public static func decide(originalURL: URL, redirectURL: URL) -> RedirectFollow {
        let downgrade = isHTTPSDowngrade(originalURL, redirectURL)
        let sameHost = hostsMatch(originalURL, redirectURL)
        let credential = containsCredentialQuery(originalURL)
        if credential && !sameHost {
            return .reject(.credentialQueryCrossHost)
        }
        if credential && downgrade {
            return .reject(.credentialQueryDowngrade)
        }
        if downgrade {
            return .reject(.httpsDowngrade)
        }
        if !sameHost {
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
        let legacy = "api" + "_key"
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.contains { $0.name == "ApiKey" || $0.name == legacy }
    }

    private static func hostsMatch(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let left = lhs.host, let right = rhs.host else { return false }
        return left.caseInsensitiveCompare(right) == .orderedSame
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
