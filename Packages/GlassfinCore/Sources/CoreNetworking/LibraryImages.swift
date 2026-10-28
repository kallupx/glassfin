import CoreModels
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public enum LibraryImageType: String, Sendable, Codable {
    case primary = "Primary"
    case backdrop = "Backdrop"
    case logo = "Logo"
    case thumb = "Thumb"
}

public struct LibraryImageRequest: Sendable, Hashable {
    public let serverID: String
    public let itemID: ItemID
    public let type: LibraryImageType
    public let tag: String
    public let width: Int
    public let height: Int

    public init(serverID: String, itemID: ItemID, type: LibraryImageType, tag: String, width: Int, height: Int) {
        self.serverID = serverID
        self.itemID = itemID
        self.type = type
        self.tag = tag
        self.width = max(1, width)
        self.height = max(1, height)
    }

    public var cacheKey: String {
        // Length framing prevents ambiguous tuples, including tags containing separators.
        let fields = [serverID, itemID.value, type.rawValue, tag, String(width), String(height)]
        let framed = fields.map { "\($0.utf8.count):\($0)" }.joined()
        return CertificateFingerprint.sha256Hex(Data(framed.utf8))
    }

    public var apiRequest: APIRequest {
        APIRequest(
            method: "GET", path: "/Items/\(itemID.value)/Images/\(type.rawValue)",
            query: [
                URLQueryItem(name: "tag", value: tag),
                URLQueryItem(name: "maxWidth", value: String(width)),
                URLQueryItem(name: "maxHeight", value: String(height)),
            ], maximumResponseBytes: MetadataPolicy.imageMaxBytes)
    }
}

/// A bounded, ephemeral download: no URLCache, cookies, or persistent URL-based filenames.
/// Enforces the byte cap while receiving, even for chunked responses without Content-Length.
final class BoundedResponseDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let limit: Int
    private let redirects: RedirectSessionDelegate
    private let trust: TrustCapture
    private let lock = NSLock()
    private var data = Data()
    private var continuation: CheckedContinuation<(Data, URLResponse, Int?), any Error>?
    private var task: URLSessionDataTask?
    private var stopped = false
    private var receivedBytes = 0

    /// Test observation: includes the rejecting chunk, excludes callbacks discarded after stopping.
    var receivedByteCount: Int { lock.withLock { receivedBytes } }

    init(limit: Int, redirects: RedirectSessionDelegate, certificatePin: OriginCertificatePin?) {
        self.limit = limit
        self.redirects = redirects
        self.trust = TrustCapture(certificatePin: certificatePin)
    }

    func run(_ request: URLRequest, protocolClasses: [AnyClass]? = nil) async throws -> (Data, URLResponse, Int?) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                guard !stopped else {
                    lock.unlock()
                    continuation.resume(throwing: APIError.cancelled)
                    return
                }
                self.continuation = continuation
                let configuration = URLSessionConfiguration.ephemeral
                if let protocolClasses { configuration.protocolClasses = protocolClasses }
                configuration.urlCache = nil
                configuration.httpCookieStorage = nil
                configuration.httpShouldSetCookies = false
                configuration.timeoutIntervalForRequest = 15
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                let task = session.dataTask(with: request)
                self.task = task
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            self.finish(.failure(APIError.cancelled))
        }
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse, http.statusCode >= 400,
            let failure = HTTPStatusMapper.failure(for: http.statusCode)
        {
            completionHandler(.cancel)
            finish(.failure(failure))
        } else if response.expectedContentLength > Int64(limit) {
            completionHandler(.cancel)
            finish(.failure(APIError.decoding))
        } else {
            completionHandler(.allow)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        lock.lock()
        if !stopped { receivedBytes += chunk.count }
        // Content-Length is only an early rejection hint. This count is the guarantee,
        // including chunked, compressed, missing-length and dishonest responses.
        let tooLarge = chunk.count > limit - data.count
        if !tooLarge, !stopped { data.append(chunk) }
        lock.unlock()
        if tooLarge { finish(.failure(APIError.decoding)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        defer { session.finishTasksAndInvalidate() }
        if let error {
            finish(.failure(error))
        } else if let response = task.response {
            lock.lock()
            let received = data
            lock.unlock()
            finish(.success((received, response, task.taskIdentifier)))
        } else {
            finish(.failure(APIError.network))
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        await trust.urlSession(session, task: task, didReceive: challenge)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        if let url = request.url, Self.hasCredentialQuery(url) {
            completionHandler(nil)
            finish(.failure(APIError.invalidURL))
            return
        }
        redirects.urlSession(
            session, task: task, willPerformHTTPRedirection: response, newRequest: request,
            completionHandler: completionHandler)
    }

    static func hasCredentialQuery(_ url: URL) -> Bool {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return query.contains { RedirectPolicy.isCredentialQueryName($0.name) || $0.name.lowercased() == "token" }
    }

    private func finish(_ result: Result<(Data, URLResponse, Int?), any Error>) {
        lock.lock()
        guard !stopped else {
            lock.unlock()
            return
        }
        stopped = true
        let continuation = continuation
        self.continuation = nil
        let task = task
        self.task = nil
        data = Data()
        lock.unlock()
        if case .failure = result { task?.cancel() }
        continuation?.resume(with: result)
    }
}
