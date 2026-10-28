import CoreModels
import Foundation

public enum CoreStateModule {
    public static let name = "CoreState"
}

/// Screen state. `previous` keeps the last good value on screen during a refresh or a failure.
public enum LoadState<T: Sendable>: Sendable {
    case idle
    case loading(previous: T?)
    case loaded(T)
    case failed(AppError, previous: T?)

    public var value: T? {
        switch self {
        case .idle:
            return nil
        case .loading(let previous):
            return previous
        case .loaded(let value):
            return value
        case .failed(_, let previous):
            return previous
        }
    }

    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    public var showsSkeleton: Bool {
        if case .loading(nil) = self { return true }
        return false
    }

    /// Errors the UI may show. Cancellation, skipped JSON, and local invariants stay hidden.
    public var presentedError: AppError? {
        guard case .failed(let error, _) = self else { return nil }
        guard AppErrorMessage.userFacing(error) != nil else { return nil }
        return error
    }
}

extension LoadState: Equatable where T: Equatable {}

public enum NetworkThresholds {
    /// A request slower than this marks connectivity degraded.
    public static let degradedAfter: Duration = .seconds(3)
    public static let requestTimeout: Duration = .seconds(15)
    public static let retryDelays: [Duration] = [.milliseconds(500), .milliseconds(1_500)]
    public static let serverPingInterval: Duration = .seconds(10)
    public static let stallMessageAfter: Duration = .seconds(5)
    public static let homeTTL: Duration = .seconds(60)
    public static let libraryListTTL: Duration = .seconds(5 * 60)
    public static let searchDebounce: Duration = .milliseconds(300)
}
