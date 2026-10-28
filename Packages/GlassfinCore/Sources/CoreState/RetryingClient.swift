import CoreModels
import CoreNetworking
import Foundation

public enum IdempotentRetry {
    public static func shouldRetry(_ error: APIError) -> Bool {
        switch error {
        case .timeout, .network:
            return true
        case .server(let status):
            return status == 502 || status == 503 || status == 504
        default:
            return false
        }
    }

    public static func maximumAttempts(method: String) -> Int {
        method.uppercased() == "GET" ? NetworkThresholds.retryDelays.count + 1 : 1
    }
}

/// Retries idempotent GETs. HTTP 401 is never retried.
public struct RetryingAPIClient: JellyfinAPIClient {
    public var inner: any JellyfinAPIClient
    public var clock: any GlassfinClock

    public init(inner: any JellyfinAPIClient, clock: any GlassfinClock) {
        self.inner = inner
        self.clock = clock
    }

    public func send(_ request: APIRequest) async throws(APIError) -> Data {
        let attempts = IdempotentRetry.maximumAttempts(method: request.method)
        var last = APIError.network
        for index in 0..<attempts {
            if Task.isCancelled { throw APIError.cancelled }
            do {
                return try await inner.send(request)
            } catch let error as APIError {
                last = error
                let hasAnother = index + 1 < attempts
                guard hasAnother, IdempotentRetry.shouldRetry(error) else { throw error }
                do {
                    try await clock.sleep(for: NetworkThresholds.retryDelays[index])
                } catch {
                    throw APIError.cancelled
                }
            }
        }
        throw last
    }
}

public final class RequestScope: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [UUID: @Sendable () -> Void] = [:]

    public init() {}

    @discardableResult
    public func track<T: Sendable, E: Error>(_ task: Task<T, E>, id: UUID = UUID()) -> UUID {
        lock.lock()
        tasks[id] = { task.cancel() }
        lock.unlock()
        Task { [weak self] in
            _ = try? await task.value
            self?.untrack(id)
        }
        return id
    }

    @discardableResult
    public func trackCancellation(_ cancel: @escaping @Sendable () -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        tasks[id] = cancel
        lock.unlock()
        return id
    }

    public func untrack(_ id: UUID) {
        lock.lock()
        tasks[id] = nil
        lock.unlock()
    }

    public func cancelAll() {
        lock.lock()
        let current = Array(tasks.values)
        tasks.removeAll()
        lock.unlock()
        for task in current {
            task()
        }
    }
}
