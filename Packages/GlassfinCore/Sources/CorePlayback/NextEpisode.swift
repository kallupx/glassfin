import CoreModels
import Foundation

public struct NextEpisode: Equatable, Sendable {
    public let id: String
    public let title: String
    public let imageTag: String?

    public init?(item: BaseItemDTO, seriesID: String) {
        guard let id = item.Id, ItemID(id) != nil, item.Type == "Episode",
            item.SeriesId == seriesID
        else { return nil }
        self.id = id
        let number: String
        if let season = item.ParentIndexNumber, let episode = item.IndexNumber, season >= 0, episode >= 0 {
            number = "S\(season)E\(episode) – "
        } else {
            number = ""
        }
        self.title = number + MetadataSanitizer.displayText(item.Name ?? "", limit: 200)
        self.imageTag = item.ImageTags?.Primary
    }
}

public enum NextEpisodeResolver {
    /// startItemId includes the current episode. Preserve server order across season boundaries.
    /// Missing current item is ambiguous (deleted item / server semantics); never replay an older item.
    public static func resolve(currentID: String, seriesID: String, items: [BaseItemDTO]) -> NextEpisode? {
        guard let current = items.firstIndex(where: { $0.Id == currentID }), current + 1 < items.count else {
            return nil
        }
        guard let next = NextEpisode(item: items[current + 1], seriesID: seriesID), next.id != currentID else {
            return nil
        }
        return next
    }
}

public struct NextEpisodeCountdown: Equatable, Sendable {
    public private(set) var deadline: Duration?
    public private(set) var cancelled = false
    public private(set) var consumed = false

    public init() {}

    /// Monotonic elapsed time, independent of playback position, pauses and buffering.
    public mutating func update(now: Duration, eligible: Bool) -> Bool {
        guard !cancelled, !consumed else { return false }
        guard eligible else {
            deadline = nil
            return false
        }
        if deadline == nil { deadline = now + .seconds(10) }
        if let deadline, now >= deadline {
            consumed = true
            self.deadline = nil
            return true
        }
        return false
    }

    public func remaining(now: Duration) -> Int? {
        guard let deadline else { return nil }
        let seconds = (deadline - now).components
        return max(0, Int(seconds.seconds) + (seconds.attoseconds > 0 ? 1 : 0))
    }

    public mutating func cancel() {
        cancelled = true
        deadline = nil
    }
    public mutating func consume() {
        consumed = true
        deadline = nil
    }
}
