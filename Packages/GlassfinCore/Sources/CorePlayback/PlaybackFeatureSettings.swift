import CoreNetworking
import Foundation

/// Fixed-size preferences contain no server metadata, URLs, or credentials (< 1 KB).
public struct PlaybackFeatureSettings: Codable, Equatable, Sendable {
    public var autoplay = true
    public var segments: [SegmentKind: SegmentBehavior] = [:]
    public init() {}
    public func behavior(for kind: SegmentKind) -> SegmentBehavior { segments[kind] ?? .ask }
    public static let storageKey = "org.glassfin.playbackFeatures"

    public static func load(from store: any SettingsStore) -> Self {
        guard let raw = store.string(forKey: storageKey), raw.utf8.count < 1024,
            let data = raw.data(using: .utf8), let value = try? JSONDecoder().decode(Self.self, from: data)
        else { return Self() }
        return value
    }

    public func save(to store: any SettingsStore) {
        guard let data = try? JSONEncoder().encode(self), data.count < 1024 else { return }
        store.set(String(decoding: data, as: UTF8.self), forKey: Self.storageKey)
    }
}
