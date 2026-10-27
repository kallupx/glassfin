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
