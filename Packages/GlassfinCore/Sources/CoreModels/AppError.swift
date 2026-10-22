import Foundation

/// Certificate shown when a server certificate is untrusted or has changed.
///
/// ``unavailable`` is used when the transport reports TLS failure without a
/// certificate the app can fingerprint yet. The certificate screen fills this in.
public struct CertificateInfo: Sendable, Hashable, Equatable {
    public var fingerprintSHA256: String
    public var subject: String
    public var validFrom: Date?
    public var validUntil: Date?

    public init(fingerprintSHA256: String, subject: String, validFrom: Date? = nil, validUntil: Date? = nil) {
        self.fingerprintSHA256 = fingerprintSHA256
        self.subject = subject
        self.validFrom = validFrom
        self.validUntil = validUntil
    }

    public static let unavailable = CertificateInfo(fingerprintSHA256: "", subject: "")
}

/// Playback failures surfaced after the player has a concrete error.
/// The direct-play → direct-stream → transcode fallback itself belongs to playback.
public enum PlaybackError: Error, Sendable, Equatable {
    case itemFailed(code: String?)
    case stalled
    case fallbackExhausted
}

/// Unified error model for the app.
///
/// Only ``unauthorized`` ends a signed-in session, and only an authenticated
/// request's HTTP 401 maps to it. Network, TLS, timeout, HTTP 403, and HTTP 5xx
/// never do.
public enum AppError: Error, Sendable, Equatable {
    /// The device has no network path.
    case offline
    /// DNS failure, connection refused, timeout, or a gateway 502/503/504.
    case serverUnreachable
    /// Self-signed or changed certificate.
    case tlsUntrusted(CertificateInfo)
    /// HTTP 401 on an authenticated request. Ends the session once.
    case unauthorized
    /// HTTP 401 on a login request. Does not end an existing session.
    case invalidCredentials
    /// HTTPS→HTTP or an `ApiKey` URL redirected across hosts was rejected.
    case insecureRedirect
    /// HTTP 403. The session stays signed in.
    case forbidden
    case notFound
    case serverError(status: Int)
    /// `/System/Info/Public` version is below the client minimum.
    case unsupportedServer(version: String)
    case playback(PlaybackError)
    /// Unexpected JSON. List decoding skips the bad element instead of failing the screen.
    case decoding
    /// The task was cancelled. Not shown to the user.
    case cancelled
    /// A local invariant failed (for example a header value containing CR/LF). Logged, not fatal.
    case internalInvariant
}

public enum RequestAuthentication: Sendable, Equatable {
    /// Public endpoints such as `/System/Ping`. A 401 here is not session expiry.
    case anonymous
    case login
    case authenticated
}

public enum SessionTermination {
    /// True only for ``AppError/unauthorized``. T02-07, T02-08, S2.2.
    public static func shouldEndSession(_ error: AppError) -> Bool {
        if case .unauthorized = error {
            return true
        }
        return false
    }
}

public enum ServerVersionGate {
    public static func failure(for version: SemVer) -> AppError? {
        guard !version.meetsMinimumServer else { return nil }
        return .unsupportedServer(version: dotted(version))
    }

    public static func dotted(_ version: SemVer) -> String {
        "\(version.major).\(version.minor).\(version.patch)"
    }
}

/// Maps transport errors into ``AppError`` without ever turning a non-401 into logout.
public enum AppErrorMapping {
    public static func map(_ error: APIError, context: RequestAuthentication, deviceOffline: Bool) -> AppError {
        switch error {
        case .unauthorized:
            switch context {
            case .authenticated:
                return .unauthorized
            case .login:
                return .invalidCredentials
            case .anonymous:
                // The spec defines 401 for login and for authenticated calls.
                // A public endpoint that returns 401 must not look like session expiry.
                return .serverError(status: 401)
            }
        case .forbidden:
            return .forbidden
        case .notFound:
            return .notFound
        case .server(let status):
            // The behavior table treats 502/503/504 as "server down", not as a generic 5xx row.
            if status == 502 || status == 503 || status == 504 {
                return deviceOffline ? .offline : .serverUnreachable
            }
            return .serverError(status: status)
        case .timeout, .network:
            return deviceOffline ? .offline : .serverUnreachable
        case .tls:
            return .tlsUntrusted(.unavailable)
        case .decoding:
            return .decoding
        case .cancelled:
            return .cancelled
        case .redirectRejected(let reason):
            switch reason {
            case .httpsDowngrade, .credentialQueryCrossHost, .credentialQueryDowngrade:
                return .insecureRedirect
            case .notFollowed:
                return deviceOffline ? .offline : .serverUnreachable
            }
        case .invalidURL, .headerRejected, .invalidItemID:
            return .internalInvariant
        }
    }

    public static func isConnectivity(_ error: AppError) -> Bool {
        switch error {
        case .offline, .serverUnreachable:
            return true
        default:
            return false
        }
    }
}

/// Plain-language copy. Technical detail stays in ``diagnostic(_:)``.
public enum AppErrorMessage {
    public static let offline = "Ei verkkoyhteyttä"
    public static let serverDown = "Palvelimeen ei saada yhteyttä"
    public static let retry = "Yritä uudelleen"
    public static let switchServer = "Vaihda palvelinta"
    public static let sessionEnded = "Istunto päättyi, kirjaudu uudelleen"
    public static let forbidden = "Ei oikeuksia tähän toimintoon"
    public static let playbackFailed = "Tätä tiedostoa ei voitu toistaa"
    public static let buffering = "Puskurointi kestää tavallista pidempään"
    public static let playbackOffline = "Toisto ei ole käytettävissä ilman verkkoyhteyttä"
    public static let playbackUnreachable = "Toisto ei ole käytettävissä, koska palvelimeen ei saada yhteyttä"

    /// Nil when the error must not be shown (cancellation, skipped JSON, local invariant).
    public static func userFacing(_ error: AppError) -> String? {
        switch error {
        case .offline:
            return offline
        case .serverUnreachable:
            return serverDown
        case .tlsUntrusted:
            return "Palvelimen sertifikaatti ei ole luotettu"
        case .unauthorized:
            return sessionEnded
        case .invalidCredentials:
            return "Virheellinen käyttäjätunnus tai salasana"
        case .insecureRedirect:
            return "Yhteys ohjattiin turvattomaan osoitteeseen"
        case .forbidden:
            return forbidden
        case .notFound:
            return "Kohdetta ei löydy"
        case .serverError:
            return "Palvelin palautti virheen"
        case .unsupportedServer(let version):
            return
                "Palvelinversio \(version) ei ole tuettu. Vaaditaan vähintään \(ServerVersionGate.dotted(.minimumJellyfin))."
        case .playback:
            return playbackFailed
        case .decoding, .cancelled, .internalInvariant:
            return nil
        }
    }

    /// Settings → Diagnostics. Must not include secrets; ``AppError`` has no token payload.
    public static func diagnostic(_ error: AppError) -> String {
        switch error {
        case .offline:
            return "offline"
        case .serverUnreachable:
            return "serverUnreachable"
        case .tlsUntrusted(let info):
            return "tlsUntrusted fingerprint=\(info.fingerprintSHA256) subject=\(info.subject)"
        case .unauthorized:
            return "unauthorized"
        case .invalidCredentials:
            return "invalidCredentials"
        case .insecureRedirect:
            return "insecureRedirect"
        case .forbidden:
            return "forbidden"
        case .notFound:
            return "notFound"
        case .serverError(let status):
            return "serverError status=\(status)"
        case .unsupportedServer(let version):
            return "unsupportedServer version=\(version)"
        case .playback(let playback):
            return "playback \(playback)"
        case .decoding:
            return "decoding"
        case .cancelled:
            return "cancelled"
        case .internalInvariant:
            return "internalInvariant"
        }
    }

    public static func report(_ error: AppError, log: any GlassfinLog) {
        switch error {
        case .internalInvariant:
            log.warning("Non-fatal invariant failure")
        case .decoding:
            log.warning("Skipped undecodable content")
        case .cancelled:
            break
        default:
            log.error(diagnostic(error))
        }
    }
}
