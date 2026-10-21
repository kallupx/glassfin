import Foundation

/// Spec "Clock". Named to avoid clashing with `Swift.Clock`.
public protocol GlassfinClock: Sendable {
    func now() -> Duration
    func sleep(for duration: Duration) async throws
}

public struct SystemGlassfinClock: GlassfinClock {
    private let origin: ContinuousClock.Instant

    public init() {
        origin = ContinuousClock.now
    }

    public func now() -> Duration {
        origin.duration(to: .now)
    }

    public func sleep(for duration: Duration) async throws {
        try await ContinuousClock().sleep(for: duration)
    }
}

public protocol JitterSource: Sendable {
    /// Full jitter sample in `0...1`.
    func nextUnitInterval() -> Double
}

public struct SystemJitter: JitterSource {
    public init() {}
    public func nextUnitInterval() -> Double {
        Double.random(in: 0...1)
    }
}

public struct ConstantJitter: JitterSource {
    public var unit: Double
    public init(unit: Double) { self.unit = unit }
    public func nextUnitInterval() -> Double { unit }
}

/// Full jitter: `random(0, min(30s, 1s * 2^attempt))`.
public enum ExponentialBackoff {
    public static let baseMilliseconds = 1_000
    public static let capMilliseconds = 30_000

    public static func delay(attempt: Int, jitterUnit: Double) -> Duration {
        let unit = min(1, max(0, jitterUnit))
        let shifted = attempt >= 16 ? capMilliseconds : baseMilliseconds * (1 << max(0, attempt))
        let cap = min(capMilliseconds, shifted)
        let milliseconds = Int((Double(cap) * unit).rounded(.toNearestOrAwayFromZero))
        return .milliseconds(milliseconds)
    }
}

public struct ReconnectController: Sendable {
    public private(set) var attempt: Int
    public private(set) var connectedAt: Duration?
    public var stableAfter: Duration

    public init(attempt: Int = 0, stableAfter: Duration = .seconds(10)) {
        self.attempt = attempt
        self.connectedAt = nil
        self.stableAfter = stableAfter
    }

    public mutating func didConnect(now: Duration) {
        connectedAt = now
    }

    /// Resets the attempt counter only after the socket has stayed up for `stableAfter`.
    public mutating func markStableIfNeeded(now: Duration) {
        guard let start = connectedAt, now - start >= stableAfter else { return }
        attempt = 0
    }

    public mutating func delayAfterFailure(now: Duration, jitterUnit: Double) -> Duration {
        if let start = connectedAt, now - start >= stableAfter {
            attempt = 0
        }
        let delay = ExponentialBackoff.delay(attempt: attempt, jitterUnit: jitterUnit)
        attempt += 1
        connectedAt = nil
        return delay
    }
}
