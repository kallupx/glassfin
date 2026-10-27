import Foundation

/// Jellyfin timebase: 1 tick = 100 nanoseconds.
///
/// Position ticks and runtime ticks are different inputs. Negative positions
/// clamp to zero with one warning. `RunTimeTicks` of zero or less means the
/// duration is unknown (`nil`). Outbound position ticks are never negative.
public enum Ticks {
    public static let perSecond: Int64 = 10_000_000
    private static let attosecondsPerTick: Int64 = 100_000_000_000

    public static func positionDuration(from ticks: Int64, log: any GlassfinLog) -> Duration {
        if ticks < 0 {
            log.warning("Negative position ticks were clamped to zero.")
            return .zero
        }
        return duration(fromNonNegative: ticks)
    }

    /// `nil` when the server omitted the runtime or sent a non-positive value.
    public static func runtimeDuration(from ticks: Int64?) -> Duration? {
        guard let ticks, ticks > 0 else { return nil }
        return duration(fromNonNegative: ticks)
    }

    public static func ticks(from duration: Duration) -> Int64 {
        let components = duration.components
        if components.seconds < 0 || components.attoseconds < 0 {
            return 0
        }
        let (whole, overflow) = components.seconds.multipliedReportingOverflow(by: perSecond)
        if overflow { return Int64.max }
        let fraction = components.attoseconds / attosecondsPerTick
        let (sum, additionOverflow) = whole.addingReportingOverflow(fraction)
        if additionOverflow { return Int64.max }
        return max(0, sum)
    }

    /// Value safe to send as `PositionTicks`. Never negative.
    public static func outboundPositionTicks(from duration: Duration) -> Int64 {
        max(0, ticks(from: duration))
    }

    private static func duration(fromNonNegative ticks: Int64) -> Duration {
        let seconds = ticks / perSecond
        let remainder = ticks % perSecond
        let attoseconds = remainder * attosecondsPerTick
        return Duration(secondsComponent: seconds, attosecondsComponent: attoseconds)
    }
}
