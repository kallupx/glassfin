import CoreModels
import Foundation

/// Quick Connect secret stays in memory. Logs and this description never include it (S3.2).
public struct QuickConnectSecret: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    private let value: String

    public init(_ value: String) {
        self.value = value
    }

    public var description: String { "QuickConnectSecret(redacted)" }
    public var debugDescription: String { "QuickConnectSecret(redacted)" }

    public func reveal() -> String { value }
}

public enum QuickConnectSecurity {
    public static let pollInterval: Duration = .seconds(5)
    public static let timeout: Duration = .seconds(5 * 60)

    /// What the UI may show. The secret is not a field.
    public struct Display: Sendable, Equatable, CustomStringConvertible {
        public var code: String

        public init(code: String) {
            self.code = code
        }

        public var description: String { "QuickConnect(code: \(code))" }
    }

    public static func display(code: String) -> Display {
        Display(code: code)
    }
}

public enum QuickConnectPoll: Sendable, Equatable {
    case pending
    case authenticated
    case serverStarting
}

public enum QuickConnectOutcome: Sendable, Equatable {
    case authenticated
    case serverStarting
    case expired
    case cancelled
}

public struct QuickConnectMonitor: Sendable {
    public var clock: any GlassfinClock
    public var pollInterval: Duration
    public var timeout: Duration

    public init(
        clock: any GlassfinClock,
        pollInterval: Duration = QuickConnectSecurity.pollInterval,
        timeout: Duration = QuickConnectSecurity.timeout
    ) {
        self.clock = clock
        self.pollInterval = pollInterval
        self.timeout = timeout
    }

    /// Polls every `pollInterval` until authenticated, cancelled, or `timeout` (S3.3).
    /// The secret is passed only to `poll`. The log line is the code display.
    public func run(
        secret: QuickConnectSecret,
        code: String,
        log: any GlassfinLog,
        poll: @Sendable (String) async -> QuickConnectPoll
    ) async -> QuickConnectOutcome {
        log.debug(QuickConnectSecurity.display(code: code).description)
        let start = clock.now()
        while !Task.isCancelled {
            if clock.now() - start >= timeout { return .expired }
            let state = await poll(secret.reveal())
            if Task.isCancelled { return .cancelled }
            if state == .authenticated { return .authenticated }
            if state == .serverStarting { return .serverStarting }
            let remaining = timeout - (clock.now() - start)
            if remaining <= .zero { return .expired }
            do {
                try await clock.sleep(for: min(pollInterval, remaining))
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .cancelled
            }
            if Task.isCancelled { return .cancelled }
        }
        return .cancelled
    }
}
