import Foundation

/// Scheme, host, and port. Default ports are filled in so `:443` matches an omitted HTTPS port.
public enum MediaOrigin {
    public static func matches(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let left = parts(lhs), let right = parts(rhs) else { return false }
        return left == right
    }

    public static func isHTTPSDowngrade(_ original: URL, _ next: URL) -> Bool {
        original.scheme?.lowercased() == "https" && next.scheme?.lowercased() == "http"
    }

    private struct Parts: Equatable {
        var scheme: String
        var host: String
        var port: Int
    }

    private static func parts(_ url: URL) -> Parts? {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        guard let port = url.port ?? defaultPort(scheme) else { return nil }
        return Parts(scheme: scheme, host: host, port: port)
    }

    private static func defaultPort(_ scheme: String) -> Int? {
        switch scheme {
        case "https": 443
        case "http": 80
        default: nil
        }
    }
}
