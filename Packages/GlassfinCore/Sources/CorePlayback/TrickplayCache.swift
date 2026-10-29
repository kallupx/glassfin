import CoreModels
import CoreNetworking
import Foundation

/// Compressed tiles only, scoped to a single playback session. There is no disk or URL cache.
/// Both bytes and count are hard limits; callers cannot increase the spec's 20-tile ceiling.
public actor TrickplayCache {
    private var values: [TrickplayTileResource: Data] = [:]
    private var recency: [TrickplayTileResource] = []
    public private(set) var byteCount = 0
    public var count: Int { values.count }
    public let maximumBytes: Int
    public let maximumTiles: Int

    public init(maximumBytes: Int = 40 * 1024 * 1024, maximumTiles: Int = 20) {
        self.maximumBytes = max(0, min(maximumBytes, 40 * 1024 * 1024))
        self.maximumTiles = max(0, min(maximumTiles, 20))
    }

    public func data(for key: TrickplayTileResource) -> Data? {
        guard let value = values[key] else { return nil }
        touch(key)
        return value
    }

    public func store(_ data: Data, for key: TrickplayTileResource) {
        guard maximumTiles > 0, data.count <= min(maximumBytes, MetadataPolicy.imageMaxBytes) else { return }
        if let previous = values.removeValue(forKey: key) { byteCount -= previous.count }
        recency.removeAll { $0 == key }
        while values.count >= maximumTiles || byteCount > maximumBytes - data.count {
            guard let oldest = recency.first else { break }
            recency.removeFirst()
            byteCount -= values.removeValue(forKey: oldest)?.count ?? 0
        }
        values[key] = data
        byteCount += data.count
        touch(key)
    }

    private func touch(_ key: TrickplayTileResource) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    public func removeAll() {
        values.removeAll()
        recency.removeAll()
        byteCount = 0
    }
}
