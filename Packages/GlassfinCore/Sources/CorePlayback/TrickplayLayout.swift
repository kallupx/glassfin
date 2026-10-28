import CoreModels
import CoreNetworking
import Foundation

public struct TrickplayFrame: Equatable, Sendable {
    public let tile: Int
    public let column: Int
    public let row: Int

    public init(tile: Int, column: Int, row: Int) {
        self.tile = tile
        self.column = column
        self.row = row
    }
}

public struct TrickplayLayout: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let columns: Int
    public let rows: Int
    public let count: Int
    /// Jellyfin's Interval is milliseconds, unlike segment timestamps (100 ns ticks).
    public let intervalMilliseconds: Int64

    public init?(_ info: TrickplayInfoDTO) {
        guard let width = info.Width, let height = info.Height, let columns = info.TileWidth,
            let rows = info.TileHeight, let count = info.ThumbnailCount, let interval = info.Interval,
            width > 0, width <= 1024, height > 0, height <= 1024,
            columns > 0, columns <= 20, rows > 0, rows <= 20,
            count > 0, interval > 0,
            width * columns <= 8192, height * rows <= 8192,
            width * columns * height * rows <= 16_777_216
        else { return nil }
        self.width = width
        self.height = height
        self.columns = columns
        self.rows = rows
        self.count = count
        self.intervalMilliseconds = interval
    }

    public var tileCount: Int { (count - 1) / (columns * rows) + 1 }
    public var decodedByteCost: Int { width * columns * height * rows * 4 }

    public func frame(at position: Duration) -> TrickplayFrame {
        let milliseconds = Ticks.outboundPositionTicks(from: position) / 10_000
        let index = Int(min(Int64(count - 1), milliseconds / intervalMilliseconds))
        let local = index % (columns * rows)
        return TrickplayFrame(tile: index / (columns * rows), column: local % columns, row: local / columns)
    }

    public func prefetchTiles(at position: Duration) -> [Int] {
        let tile = frame(at: position).tile
        // Current first: a slow neighbor must never hold up the preview.
        return [tile, tile - 1, tile + 1, tile - 2, tile + 2].filter { $0 >= 0 && $0 < tileCount }
    }

    public static func select(_ values: [String: TrickplayInfoDTO], displayedWidth: Int = 320) -> TrickplayLayout? {
        let layouts = values.values.compactMap(Self.init).sorted { $0.width < $1.width }
        return layouts.first { $0.width >= displayedWidth } ?? layouts.last
    }
}

public struct TrickplayTileResource: Hashable, Sendable {
    public let itemID: String
    public let mediaSourceID: String
    public let width: Int
    public let index: Int

    public init(itemID: String, mediaSourceID: String, width: Int, index: Int) {
        self.itemID = itemID
        self.mediaSourceID = mediaSourceID
        self.width = width
        self.index = index
    }

    public func request() throws(APIError) -> APIRequest {
        let item = try ItemID.require(itemID).value
        let source = try ItemID.require(mediaSourceID).value
        guard width > 0, width <= 1024, index >= 0 else { throw .invalidURL }
        return APIRequest(
            method: "GET", path: "/Videos/\(item)/Trickplay/\(width)/\(index).jpg",
            query: [URLQueryItem(name: "mediaSourceId", value: source)],
            maximumResponseBytes: MetadataPolicy.imageMaxBytes)
    }
}
