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
/// redirect is rejected. A redirect from local HTTP onto public HTTP is not followed,
/// so Authorization is not sent there. A request URL that contains an API key query is rejected,
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
        if leavesLocalHTTP(originalURL, for: redirectURL) {
            return .reject(.notFollowed)
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
    public static func originsMatch(_ lhs: URL, _ rhs: URL) -> Bool {
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

    /// Private or local HTTP must not be sent on to a public HTTP host. Authorization stays behind.
    private static func leavesLocalHTTP(_ original: URL, for redirect: URL) -> Bool {
        ServerTransportPolicy.evaluate(original) == .unencryptedLocal
            && ServerTransportPolicy.evaluate(redirect) == .publicHTTPRejected
    }
}

/// Same-origin redirects stop after 5 follows. A repeated URL is a loop and is not followed.
public enum RedirectFollowLimit {
    public static let maximum = 5

    public static func decide(
        followed: Int,
        seen: [URL],
        original: URLRequest,
        proposed: URLRequest
    ) -> RedirectApplication {
        if followed >= maximum {
            return .reject(.notFollowed)
        }
        guard let next = proposed.url else { return .reject(.notFollowed) }
        if seen.contains(where: { same($0, next) }) {
            return .reject(.notFollowed)
        }
        return RedirectPolicy.apply(original: original, proposed: proposed)
    }

    static func same(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.absoluteString == rhs.absoluteString
    }
}

public final class RedirectSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private struct HopState {
        var followed: Int
        var seen: [URL]
    }

    private let lock = NSLock()
    private var rejections: [Int: RedirectRejection] = [:]
    private var hops: [Int: HopState] = [:]

    public func consumeRejection(for taskIdentifier: Int) -> RedirectRejection? {
        lock.lock()
        defer { lock.unlock() }
        return rejections.removeValue(forKey: taskIdentifier)
    }

    /// One in-flight task. Returns nil when two tasks have a rejection waiting, so they cannot be swapped.
    public func consumeRejection() -> RedirectRejection? {
        lock.lock()
        defer { lock.unlock() }
        guard rejections.count == 1, let key = rejections.keys.first else { return nil }
        return rejections.removeValue(forKey: key)
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let original = task.originalRequest ?? task.currentRequest ?? request
        let decision: RedirectApplication = {
            lock.lock()
            defer { lock.unlock() }
            var state = hops[task.taskIdentifier] ?? HopState(followed: 0, seen: [])
            if state.seen.isEmpty, let originalURL = original.url {
                state.seen.append(originalURL)
            }
            let decision = RedirectFollowLimit.decide(
                followed: state.followed,
                seen: state.seen,
                original: original,
                proposed: request
            )
            switch decision {
            case .follow:
                state.followed += 1
                if let url = request.url {
                    state.seen.append(url)
                }
            case .reject(let reason):
                rejections[task.taskIdentifier] = reason
            }
            hops[task.taskIdentifier] = state
            return decision
        }()
        switch decision {
        case .follow(let next):
            completionHandler(next)
        case .reject:
            completionHandler(nil)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.lock()
        hops[task.taskIdentifier] = nil
        lock.unlock()
    }
}
