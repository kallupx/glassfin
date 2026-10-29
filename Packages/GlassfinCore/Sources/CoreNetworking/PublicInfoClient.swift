import CoreModels
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

#if canImport(Security)
    import Security
#endif

/// Fetches `/System/Info/Public` for one candidate. The leaf is recorded for the
/// certificate screen. This type does not write a pin.
public struct URLSessionPublicInfoClient: ServerCandidateClient {
    private var transport: (any RequestTransport)?

    public init() { transport = nil }

    init(transport: any RequestTransport) { self.transport = transport }

    public func fetchPublicInfo(url: URL, timeout: Duration, certificatePin: OriginCertificatePin? = nil) async
        -> ServerCandidateResult
    {
        guard let target = ServerAddressCandidates.appendingAPIPath(url, path: "/System/Info/Public") else {
            return .notJellyfin
        }
        var request = URLRequest(url: target)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.seconds(timeout)
        let capture = TrustCapture(certificatePin: certificatePin)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: capture, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            let data: Data
            let response: URLResponse
            if let transport {
                (data, response, _) = try await transport.data(for: request, maximumBytes: nil)
            } else {
                (data, response) = try await session.data(for: request, delegate: capture)
            }
            // A startup response may be HTML. Neither its body nor its headers supply UI copy.
            if (response as? HTTPURLResponse)?.statusCode == 503 { return .serverStarting }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return .notJellyfin
            }
            return PublicInfoInterpreter.interpret(data, url: url)
        } catch let error as URLError {
            return ProbeTransportError.classify(error, leaf: capture.leaf)
        } catch is CancellationError {
            return .cancelled
        } catch {
            if Task.isCancelled { return .cancelled }
            return .refused
        }
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}

/// Records the leaf certificate. A system-trusted chain uses default handling.
/// An untrusted chain is cancelled so the probe can open the certificate screen.
final class TrustCapture: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: CertificatePresentation?
    private let certificatePin: OriginCertificatePin?
    private let connectionURL: URL?

    init(certificatePin: OriginCertificatePin? = nil, connectionURL: URL? = nil) {
        self.connectionURL = connectionURL
        self.certificatePin = certificatePin
    }

    /// Trusted chains never supply an error leaf, including when the task is cancelled.
    func record(_ presentation: CertificatePresentation?, isSystemTrusted: Bool) {
        lock.withLock { stored = isSystemTrusted ? nil : presentation }
    }

    /// Probing must not let a response move the connection to another origin.
    static func redirectRequest(_ proposed: URLRequest) -> URLRequest? { nil }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(Self.redirectRequest(request))
    }

    var leaf: CertificatePresentation? {
        lock.withLock { stored }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        #if canImport(Security)
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                let trust = challenge.protectionSpace.serverTrust
            else {
                return (.performDefaultHandling, nil)
            }
            var error: CFError?
            if SecTrustEvaluateWithError(trust, &error) {
                record(nil, isSystemTrusted: true)
                return (.performDefaultHandling, nil)
            }
            let presentation = Self.leaf(from: trust)
            record(presentation, isSystemTrusted: false)
            if let presentation, let target = connectionURL ?? task.currentRequest?.url,
                let fingerprint = certificatePin?.fingerprint(for: target),
                challenge.protectionSpace.host.lowercased() == target.host?.lowercased(),
                challenge.protectionSpace.port == (target.port ?? 443),
                case .usePinnedCredential = SelfSignedTrustFlow.handle(
                    isSystemTrusted: false, leaf: presentation, pinnedSHA256: fingerprint,
                    userAcceptedFingerprint: nil
                ).decision
            {
                return (.useCredential, URLCredential(trust: trust))
            }
            return (.cancelAuthenticationChallenge, nil)
        #else
            _ = session
            _ = task
            _ = challenge
            return (.performDefaultHandling, nil)
        #endif
    }

    #if canImport(Security)
        private static func leaf(from trust: SecTrust) -> CertificatePresentation? {
            guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let certificate = chain.first
            else { return nil }
            let data = SecCertificateCopyData(certificate) as Data
            let subject = (SecCertificateCopySubjectSummary(certificate) as String?) ?? ""
            return CertificatePresentation(
                sha256: CertificateFingerprint.sha256Hex(data),
                subject: subject,
                notBefore: Date(timeIntervalSince1970: 0),
                notAfter: Date(timeIntervalSince1970: 0)
            )
        }
    #endif
}
