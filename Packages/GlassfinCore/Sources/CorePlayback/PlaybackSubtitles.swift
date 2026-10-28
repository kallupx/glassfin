import CoreModels
import Foundation

public struct SubtitleCue: Sendable, Equatable {
    public let start: Duration
    public let end: Duration
    public let text: String
}

/// VTT is plain text. No markup, HTML, URL or script interpretation is performed.
public enum WebVTT {
    public static let maximumBytes = 10 * 1024 * 1024
    public static func parse(_ data: Data) throws(APIError) -> [SubtitleCue] {
        guard data.count <= maximumBytes, let value = String(data: data, encoding: .utf8) else { throw .decoding }
        let normalized = value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard normalized.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("WEBVTT") else { throw .decoding }
        return normalized.components(separatedBy: "\n\n").compactMap { block in
            let lines = block.components(separatedBy: "\n")
            guard !block.hasPrefix("NOTE"), !block.hasPrefix("STYLE"), !block.hasPrefix("REGION"),
                let index = lines.firstIndex(where: { $0.contains(" --> ") })
            else { return nil }
            let times = lines[index].components(separatedBy: " --> ")
            guard times.count == 2, let start = timestamp(times[0]),
                let endToken = times[1].split(separator: " ").first,
                let end = timestamp(String(endToken)), end > start
            else { return nil }
            let text = lines.dropFirst(index + 1).map { MetadataSanitizer.displayText($0, limit: 2000) }.joined(
                separator: "\n")
            return SubtitleCue(start: .seconds(start), end: .seconds(end), text: String(text.prefix(4000)))
        }.sorted { $0.start < $1.start }
    }

    public static func text(at position: Duration, cues: [SubtitleCue]) -> String {
        cues.filter { $0.start <= position && position < $0.end }.map(\.text).joined(separator: "\n")
    }

    private static func timestamp(_ string: String) -> Double? {
        let fields = string.split(separator: ":")
        guard (2...3).contains(fields.count) else { return nil }
        var result = 0.0
        for field in fields {
            guard let value = Double(field), value.isFinite, value >= 0 else { return nil }
            result = result * 60 + value
            guard result.isFinite, result <= Double(Int64.max / Ticks.perSecond) else { return nil }
        }
        return result
    }
}
