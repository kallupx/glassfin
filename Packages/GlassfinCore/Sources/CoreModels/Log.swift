import Foundation

/// Logging sink. Implementations must redact secrets before they hit a backend.
public protocol GlassfinLog: Sendable {
    func warning(_ message: String)
    func debug(_ message: String)
    func error(_ message: String)
}

public struct SilentLog: GlassfinLog {
    public init() {}
    public func warning(_ message: String) {}
    public func debug(_ message: String) {}
    public func error(_ message: String) {}
}
