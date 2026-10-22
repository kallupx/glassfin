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
    public init() {}

    public func fetchPublicInfo(url: URL, timeout: Duration) async -> ServerCandidateResult {
        guard let target = ServerAddressCandidates.appendingAPIPath(url, path: "/System/Info/Public") else {
            return .notJellyfin
        }
        var request = URLRequest(url: target)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.seconds(timeout)
        let capture = TrustCapture()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: capture, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (data, response) = try await session.data(for: request, delegate: capture)
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

    var leaf: CertificatePresentation? {
        lock.lock()
        defer { lock.unlock() }
        return stored
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
            if let presentation = Self.leaf(from: trust) {
                lock.lock()
                stored = presentation
                lock.unlock()
            }
            var error: CFError?
            if SecTrustEvaluateWithError(trust, &error) {
                return (.performDefaultHandling, nil)
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
