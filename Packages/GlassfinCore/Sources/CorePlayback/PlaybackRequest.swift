import CoreModels
import Foundation

/// The presentation boundary contains identifiers, positions and track choices only.
public struct PlaybackRequest: Sendable, Equatable {
    public let itemID: ItemID
    public let startTicks: Int64
    public let audioStreamIndex: Int?
    public let subtitleStreamIndex: Int?

    public init(
        itemID: ItemID, startTicks: Int64, audioStreamIndex: Int? = nil, subtitleStreamIndex: Int? = nil
    ) {
        self.itemID = itemID
        self.startTicks = max(0, startTicks)
        self.audioStreamIndex = audioStreamIndex
        self.subtitleStreamIndex = subtitleStreamIndex
    }
}

public struct PlaybackStop: Sendable, Equatable {
    public let itemID: String
    public let position: Duration
    public let finished: Bool
}
