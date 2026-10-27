import CoreModels
import Foundation

/// M07/M08 consume these navigation requests when their UI modules are installed.
public struct HomePlaybackRequest: Identifiable, Sendable, Hashable {
    public var item: MediaItem
    public var position: Duration
    public var id: String { item.id }

    public init(item: MediaItem) {
        self.item = HomeMetadata.item(item)
        self.position = max(.zero, item.userData.playbackPosition)
    }
}

/// The series handoff retains the selected season for M07's one-season-at-a-time picker.
public enum HomeNavigation {
    public static func seriesDestination(for item: MediaItem) -> MediaItem? {
        guard item.kind == .episode, let seriesID = item.seriesID, ItemID(seriesID) != nil else { return nil }
        return MediaItem(
            id: seriesID, kind: .series, name: HomeMetadata.item(item).name,
            seasonID: item.seasonID, parentIndexNumber: item.parentIndexNumber)
    }
}
