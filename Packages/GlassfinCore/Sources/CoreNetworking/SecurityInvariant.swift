import Foundation

/// Broken security invariant. M02's `AppError` does not exist yet; this is the stand-in
/// for the spec's `AppError.internalInvariant`.
public enum SecurityInvariantError: Error, Sendable, Equatable {
    case internalInvariant
}
