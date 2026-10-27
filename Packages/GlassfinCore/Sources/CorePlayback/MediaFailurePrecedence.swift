import CoreModels

/// Cancellation is a fallback diagnostic: it must never erase an already recorded failure.
enum MediaFailurePrecedence {
    static func recording(_ incoming: APIError, after current: APIError?) -> APIError {
        incoming == .cancelled ? (current ?? incoming) : incoming
    }
}
