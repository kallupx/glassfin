import CoreModels
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A data delegate receives chunks without URLSession's completion-handler body buffer.
/// Only bytes within the budget are retained. A missing or understated length is harmless.
final class BoundedRequestDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    typealias Result = (Data, URLResponse, Int?)
    private let maximumBytes: Int
    private let redirects: RedirectTaskProxy
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Result, any Error>?
    private var task: URLSessionDataTask?
    private var response: URLResponse?
    private var buffer = Data()
    private var cancelled = false

    init(maximumBytes: Int, redirects: RedirectTaskProxy) {
        self.maximumBytes = max(0, maximumBytes)
        self.redirects = redirects
    }

    func data(for request: URLRequest, configuration: URLSessionConfiguration) async throws -> Result {
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        // Let successful completion callbacks finish; failure and cancellation paths cancel the task explicitly.
        defer { session.finishTasksAndInvalidate() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    guard !cancelled else {
                        continuation.resume(throwing: APIError.cancelled)
                        return
                    }
                    self.continuation = continuation
                    let task = session.dataTask(with: request)
                    self.task = task
                    task.resume()
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    private func cancel() {
        let pending = lock.withLock {
            cancelled = true
            let pending = (continuation, task)
            continuation = nil
            buffer = Data()
            return pending
        }
        pending.1?.cancel()
        pending.0?.resume(throwing: APIError.cancelled)
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let failureResponse = lock.withLock { () -> CheckedContinuation<Result, any Error>? in
            self.response = response
            guard let http = response as? HTTPURLResponse,
                HTTPStatusMapper.failure(for: http.statusCode) != nil
            else { return nil }
            let pending = continuation
            continuation = nil
            return pending
        }
        if let failureResponse {
            // Authentication and redirect errors take precedence over an untrusted error body.
            completionHandler(.cancel)
            failureResponse.resume(returning: (Data(), response, dataTask.taskIdentifier))
            return
        }
        // Content-Length is deliberately ignored. The data callback enforces the budget.
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let rejected = lock.withLock { () -> CheckedContinuation<Result, any Error>? in
            guard continuation != nil else { return nil }
            guard data.count <= maximumBytes - buffer.count else {
                let pending = continuation
                continuation = nil
                buffer = Data()
                return pending
            }
            buffer.append(data)
            return nil
        }
        if let rejected {
            dataTask.cancel()
            rejected.resume(throwing: APIError.responseTooLarge)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        redirects.urlSession(session, task: task, didCompleteWithError: error)
        let pending = lock.withLock {
            let pending = (continuation, buffer, response)
            continuation = nil
            self.task = nil
            buffer = Data()
            return pending
        }
        guard let continuation = pending.0 else { return }
        if let error {
            continuation.resume(throwing: error)
        } else if let response = pending.2 {
            continuation.resume(returning: (pending.1, response, task.taskIdentifier))
        } else {
            continuation.resume(throwing: APIError.network)
        }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        await redirects.urlSession(session, task: task, didReceive: challenge)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        redirects.urlSession(
            session, task: task, willPerformHTTPRedirection: response, newRequest: request,
            completionHandler: completionHandler)
    }
}
