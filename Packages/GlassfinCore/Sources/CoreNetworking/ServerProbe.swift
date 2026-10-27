import CoreModels
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Why a probe stopped without a usable server. ``httpSkippedByPolicy`` is the extra
/// line under "Server not found" or "Not a Jellyfin server" when S4.3 skipped HTTP.
public struct ProbeFailureDetail: Sendable, Equatable {
    public var httpSkippedByPolicy: Bool

    public init(httpSkippedByPolicy: Bool) {
        self.httpSkippedByPolicy = httpSkippedByPolicy
    }
}

public enum ServerProbeOutcome: Sendable, Equatable {
    case ready(ServerInfo)
    case needsCleartext(ServerInfo)
    case needsCertificate(CertificatePresentation, url: URL)
    /// The user explicitly typed `http://` for a public host or IP. No request is made.
    case publicHTTPRejected
    case notFound(ProbeFailureDetail)
    case notJellyfin(ProbeFailureDetail)
    case unsupported(version: String, server: ServerInfo)
    case setupIncomplete(address: URL)
    case invalidAddress
    case userinfoRejected
    case cancelled
}

public enum ServerCandidateResult: Sendable, Equatable {
    case jellyfin(ServerInfo, startupComplete: Bool)
    case notJellyfin
    case dnsFailure
    case refused
    case timedOut
    case tls(CertificatePresentation)
    case transportSecurity
    case cancelled
}

public protocol ServerCandidateClient: Sendable {
    func fetchPublicInfo(url: URL, timeout: Duration) async -> ServerCandidateResult
}

public enum PublicInfoInterpreter {
    public static let jellyfinProductName = "Jellyfin Server"

    public static func interpret(_ data: Data, url: URL) -> ServerCandidateResult {
        guard let dto = try? JSONDecoder().decode(PublicSystemInfoDTO.self, from: data) else {
            return .notJellyfin
        }
        guard dto.ProductName == jellyfinProductName else { return .notJellyfin }
        guard let info = DTOMapper.serverInfo(dto, url: url) else { return .notJellyfin }
        let startupComplete = dto.StartupWizardCompleted != false
        return .jellyfin(info, startupComplete: startupComplete)
    }
}

public enum ProbeErrorCopy {
    public static func key(for outcome: ServerProbeOutcome) -> AuthCopy.Key? {
        switch outcome {
        case .notFound:
            return .serverNotFound
        case .notJellyfin:
            return .notJellyfin
        case .publicHTTPRejected:
            return .publicAddressRequiresHTTPS
        case .invalidAddress:
            return .invalidAddress
        case .userinfoRejected:
            return .userinfoRejected
        case .unsupported:
            return .unsupportedServer
        case .setupIncomplete:
            return .setupIncomplete
        case .needsCleartext:
            return .connectionNotEncrypted
        case .ready, .needsCertificate, .cancelled:
            return nil
        }
    }

    public static func httpSkippedByPolicy(_ outcome: ServerProbeOutcome) -> Bool {
        switch outcome {
        case .notFound(let detail), .notJellyfin(let detail):
            return detail.httpSkippedByPolicy
        case .ready, .needsCleartext, .needsCertificate, .publicHTTPRejected, .unsupported, .setupIncomplete,
            .invalidAddress, .userinfoRejected, .cancelled:
            return false
        }
    }
}

/// Walks ``ServerAddressCandidates`` with a 5 second attempt cap and a 20 second overall cap.
/// DNS and TLS stop the walk. Connection refusal, timeout, and non-Jellyfin responses try the next candidate.
/// HTTP to a public host is never requested.
public struct ServerProbe: Sendable {
    public var client: any ServerCandidateClient
    public var clock: any GlassfinClock

    public init(client: any ServerCandidateClient, clock: any GlassfinClock = SystemGlassfinClock()) {
        self.client = client
        self.clock = clock
    }

    public func run(address: String) async -> ServerProbeOutcome {
        if ServerAddressCandidates.containsUserinfo(address) { return .userinfoRejected }
        let plan = ServerAddressCandidates.expand(address)
        if plan.invalid { return .invalidAddress }
        if plan.explicitPublicHTTP { return .publicHTTPRejected }
        let connectable = plan.candidates.filter(\.mayConnect)
        guard !connectable.isEmpty else { return .invalidAddress }
        let detail = ProbeFailureDetail(httpSkippedByPolicy: plan.httpSkippedByPolicy)
        let started = clock.now()
        var sawNotJellyfin = false
        for candidate in connectable {
            if Task.isCancelled { return .cancelled }
            let elapsed = clock.now() - started
            if elapsed >= ServerAddressCandidates.overallTimeout { break }
            let remaining = ServerAddressCandidates.overallTimeout - elapsed
            let budget = min(ServerAddressCandidates.attemptTimeout, remaining)
            let result = await client.fetchPublicInfo(url: candidate.url, timeout: budget)
            if Task.isCancelled { return .cancelled }
            switch result {
            case .jellyfin(let info, let startupComplete):
                if !startupComplete { return .setupIncomplete(address: candidate.url) }
                if let failure = ServerVersionGate.failure(for: info.version),
                    case .unsupportedServer(let version) = failure
                {
                    return .unsupported(version: version, server: info)
                }
                switch candidate.verdict {
                case .unencryptedLocal:
                    return .needsCleartext(info)
                case .secure:
                    return .ready(info)
                case .publicHTTPRejected, .invalid:
                    return .publicHTTPRejected
                }
            case .notJellyfin:
                sawNotJellyfin = true
            case .dnsFailure:
                return .notFound(detail)
            case .refused, .timedOut:
                continue
            case .tls(let presentation):
                return .needsCertificate(presentation, url: candidate.url)
            case .transportSecurity:
                return .notFound(detail)
            case .cancelled:
                return .cancelled
            }
        }
        if Task.isCancelled { return .cancelled }
        return sawNotJellyfin ? .notJellyfin(detail) : .notFound(detail)
    }
}

public enum ProbeTransportError {
    public static let cannotFindHost = -1003
    public static let cannotConnectToHost = -1004
    public static let dnsLookupFailed = -1006

    public static func classify(_ error: URLError, leaf: CertificatePresentation?) -> ServerCandidateResult {
        if error.code.rawValue == URLErrorMapper.appTransportSecurityRequiresSecureConnection {
            return .transportSecurity
        }
        switch error.code.rawValue {
        case cannotFindHost, dnsLookupFailed:
            return .dnsFailure
        case cannotConnectToHost:
            return .refused
        default:
            break
        }
        switch URLErrorMapper.map(error) {
        case .timeout:
            return .timedOut
        case .cancelled:
            if let leaf { return .tls(leaf) }
            return .cancelled
        case .tls:
            return .tls(leaf ?? Self.unknownLeaf)
        case .transportSecurity:
            return .transportSecurity
        default:
            return .refused
        }
    }

    public static let unknownLeaf = CertificatePresentation(
        sha256: "",
        subject: "",
        notBefore: Date(timeIntervalSince1970: 0),
        notAfter: Date(timeIntervalSince1970: 0)
    )
}
