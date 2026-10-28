import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Why an HTTP redirect was not followed, or how a followed redirect was adjusted.
public enum RedirectRejection: Error, Sendable, Equatable {
    /// HTTPS target rewritten to HTTP.
    case httpsDowngrade
    /// A URL carrying `ApiKey` (or the legacy query name) redirected to another host.
    case credentialQueryCrossHost
    /// A URL carrying `ApiKey` redirected from HTTPS to HTTP.
    case credentialQueryDowngrade
    /// The session returned a redirect the client refused to follow.
    case notFollowed
}

/// Errors surfaced by the Jellyfin API layer.
///
/// Only ``unauthorized`` (HTTP 401) may end a session. Network failures, TLS
/// failures, timeouts, HTTP 403, and HTTP 5xx must never be treated as logout.
public enum APIError: Error, Sendable, Equatable {
    case unauthorized
    case forbidden
    case notFound
    case server(status: Int)
    case timeout
    case network
    case tls
    case decoding
    case cancelled
    case redirectRejected(RedirectRejection)
    case invalidURL
    case headerRejected
    /// A path segment was not a 32-hex GUID (dashes optional).
    case invalidItemID
    /// `NSURLErrorAppTransportSecurityRequiresSecureConnection` (-1022).
    /// Shown with the same copy as an explicit public `http://` address.
    case transportSecurity
}

public enum LogoutPolicy {
    /// True only for a real server 401. T01-08, S2.2.
    public static func shouldLogOut(_ error: APIError) -> Bool {
        if case .unauthorized = error {
            return true
        }
        return false
    }
}

public enum HTTPStatusMapper {
    public static func failure(for status: Int) -> APIError? {
        switch status {
        case 200..<300:
            return nil
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 404:
            return .notFound
        case 300..<400:
            return .redirectRejected(.notFollowed)
        default:
            return .server(status: status)
        }
    }
}

public enum URLErrorMapper {
    /// `NSURLErrorAppTransportSecurityRequiresSecureConnection`.
    public static let appTransportSecurityRequiresSecureConnection = -1022

    public static func map(_ error: URLError) -> APIError {
        if error.code.rawValue == appTransportSecurityRequiresSecureConnection {
            return .transportSecurity
        }
        switch error.code {
        case .timedOut:
            return .timeout
        case .cancelled:
            return .cancelled
        case .serverCertificateUntrusted,
            .serverCertificateHasBadDate,
            .serverCertificateHasUnknownRoot,
            .serverCertificateNotYetValid,
            .secureConnectionFailed,
            .clientCertificateRejected,
            .clientCertificateRequired:
            return .tls
        default:
            return .network
        }
    }
}
