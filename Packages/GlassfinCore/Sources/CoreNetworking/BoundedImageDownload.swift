import CoreModels
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Buffers at most the image budget. The response header is only an early rejection;
/// every delivered chunk is counted before appending, including unknown or false lengths.
/// A private session gives each download its own data delegate and cancellation lifetime.
final class BoundedImageDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maximumBytes: Int
    private let redirects = RedirectSessionDelegate()
    private let trust: TrustCapture
    private let lock = NSLock()
    private var buffer = Data()
    private var response: URLResponse?
    private var continuation: CheckedContinuation<(Data, URLResponse, Int?), any Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var finished = false

    init(maximumBytes: Int, certificatePin: OriginCertificatePin?) {
        self.maximumBytes = max(0, maximumBytes)
        self.trust = TrustCapture(certificatePin: certificatePin)
    }

    func data(for request: URLRequest, configuration: URLSessionConfiguration) async throws -> (Data, URLResponse, Int?)
    {
        configuration.urlCache = nil
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                guard !finished else {
                    lock.unlock()
                    continuation.resume(throwing: APIError.cancelled)
                    return
                }
                self.continuation = continuation
                configuration.urlCache = nil
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                let task = session.dataTask(with: request)
                self.session = session
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
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        // Preserve HTTP error precedence, especially authenticated 401. Error bodies are unnecessary.
        if let http = response as? HTTPURLResponse, let failure = HTTPStatusMapper.failure(for: http.statusCode) {
            let rejection = redirects.consumeRejection(for: dataTask.taskIdentifier)
            completionHandler(.cancel)
            finish(.failure(rejection.map(APIError.redirectRejected) ?? failure))
            return
        }
        if response.expectedContentLength > Int64(maximumBytes) {
            completionHandler(.cancel)
            finish(.failure(APIError.responseTooLarge))
            return
        }
        lock.lock()
        self.response = response
        let accept = !finished
        lock.unlock()
        completionHandler(accept ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        // Subtraction avoids integer overflow and rejects before the buffer can exceed the cap.
        guard data.count <= maximumBytes - buffer.count else {
            lock.unlock()
            finish(.failure(APIError.responseTooLarge))
            return
        }
        buffer.append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        redirects.urlSession(session, task: task, didCompleteWithError: error)
        if let error {
            finish(.failure(error))
            return
        }
        lock.lock()
        let response = response
        let data = buffer
        lock.unlock()
        if let response {
            finish(.success((data, response, task.taskIdentifier)))
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
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        redirects.urlSession(
            session, task: task, willPerformHTTPRedirection: response,
            newRequest: request, completionHandler: completionHandler)
    }

    private func finish(_ result: Result<(Data, URLResponse, Int?), any Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let continuation = continuation
        let session = session
        self.continuation = nil
        self.session = nil
        task = nil
        buffer = Data()
        lock.unlock()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }
}
