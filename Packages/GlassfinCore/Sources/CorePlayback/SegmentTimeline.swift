import CoreModels
import Foundation

public enum SegmentKind: String, CaseIterable, Codable, Sendable {
    case intro = "Intro"
    case recap = "Recap"
    case outro = "Outro"
    case preview = "Preview"
    case commercial = "Commercial"

    public var copyKey: String { "playback.segment." + rawValue.lowercased() }
}

public enum SegmentBehavior: String, CaseIterable, Codable, Sendable {
    case ask
    case automatic
    case ignore

    public var copyKey: String { "playback.segmentBehavior." + rawValue }
}

public struct TimedSegment: Equatable, Sendable {
    public let kind: SegmentKind
    public let start: Int64
    public let end: Int64

    public init?(kind: SegmentKind, start: Int64, end: Int64, runtime: Int64? = nil) {
        guard start >= 0, end > start else { return nil }
        let boundedEnd = runtime.flatMap { $0 > 0 ? $0 : nil }.map { min(end, $0) } ?? end
        guard boundedEnd > start else { return nil }
        self.kind = kind
        self.start = start
        self.end = boundedEnd
    }

    public func contains(_ ticks: Int64) -> Bool { ticks >= start && ticks < end }
}

public enum SegmentTimeline {
    /// Half-open intervals. Overlaps resolve by earliest start, then shortest end, then type.
    public static func ordered(_ segments: [TimedSegment]) -> [TimedSegment] {
        segments.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.kind.rawValue < $1.kind.rawValue
        }
    }

    public static func active(at ticks: Int64, segments: [TimedSegment]) -> TimedSegment? {
        ordered(segments).first { $0.contains(ticks) }
    }

    public static func nextEpisodeTrigger(segments: [TimedSegment], runtime: Int64?) -> Int64? {
        if let outro = ordered(segments).first(where: { $0.kind == .outro }) { return outro.start }
        guard let runtime, runtime > 0 else { return nil }
        return max(0, runtime - 30 * Ticks.perSecond)
    }
}
