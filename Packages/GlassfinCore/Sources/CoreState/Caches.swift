import CoreModels
import CoreNetworking
import Foundation

public enum CacheBudget {
    public static let userDefaultsBytes = 50 * 1_024
    public static let imageDiskBytes = 300 * 1_024 * 1_024
    public static let imageMemoryBytes = 150 * 1_024 * 1_024
}

enum CacheKey {
    static func filename(for key: String) -> String {
        if key.count == 64, key.allSatisfy(\.isHexDigit) { return key.lowercased() }
        return CertificateFingerprint.sha256Hex(Data(SensitiveRedactor.redact(key).utf8))
    }
}

public struct HomeSnapshot: Codable, Sendable, Equatable {
    public var resume: [MediaItem]
    public var nextUp: [MediaItem]
    public var latest: [MediaItem]
    public var libraries: [Library]?
    public var latestByLibrary: [String: [MediaItem]]?
    public var serverID: String?
    public var userID: String?

    public init(resume: [MediaItem], nextUp: [MediaItem], latest: [MediaItem]) {
        self.resume = resume
        self.nextUp = nextUp
        self.latest = latest
    }
}

public struct HomeSnapshotStore: Sendable {
    public var file: URL

    public init(file: URL) {
        self.file = file
    }

    public func load() -> HomeSnapshot? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(HomeSnapshot.self, from: data)
    }

    @discardableResult
    public func save(_ snapshot: HomeSnapshot) -> Bool {
        let directory = file.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: file, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public func purge() {
        try? FileManager.default.removeItem(at: file)
    }
}

public actor ResponseCache {
    private struct Entry {
        var data: Data
        var expiresAt: Duration
    }

    private var values: [String: Entry] = [:]

    public init() {}

    public func insert(_ data: Data, for key: String, ttl: Duration, now: Duration) {
        values[key] = Entry(data: data, expiresAt: now + ttl)
    }

    public func data(for key: String, now: Duration) -> Data? {
        guard let entry = values[key] else { return nil }
        if entry.expiresAt <= now {
            values[key] = nil
            return nil
        }
        return entry.data
    }

    public func invalidateAll() {
        values.removeAll()
    }
}

/// Disk LRU for images. The original key is not stored, so a token in the key cannot land in the directory.
public actor DiskImageCache {
    public let byteLimit: Int
    private let directory: URL
    private var entries: [Entry] = []
    private var clock = 0
    private var loaded = false

    private struct Entry: Codable {
        var name: String
        var bytes: Int
        var access: Int
    }

    public init(directory: URL, byteLimit: Int) {
        self.directory = directory
        self.byteLimit = byteLimit
    }

    @discardableResult
    public func store(key: String, data: Data) -> Bool {
        loadIfNeeded()
        guard data.count <= byteLimit, data.count <= MetadataPolicy.imageMaxBytes, byteLimit > 0 else { return false }
        let name = CacheKey.filename(for: key)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch {
            return false
        }
        clock += 1
        entries.removeAll { $0.name == name }
        entries.append(Entry(name: name, bytes: data.count, access: clock))
        evict()
        persistIndex()
        return true
    }

    public func data(for key: String) -> Data? {
        loadIfNeeded()
        let name = CacheKey.filename(for: key)
        guard let index = entries.firstIndex(where: { $0.name == name }) else { return nil }
        let url = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else {
            entries.remove(at: index)
            persistIndex()
            return nil
        }
        clock += 1
        entries[index].access = clock
        persistIndex()
        return data
    }

    public func purge() {
        try? FileManager.default.removeItem(at: directory)
        entries = []
        loaded = true
    }

    public func storedByteCount() -> Int {
        loadIfNeeded()
        return entries.reduce(0) { $0 + $1.bytes }
    }

    public func containsToken(_ secret: String) -> Bool {
        loadIfNeeded()
        if entries.contains(where: { $0.name.contains(secret) }) { return true }
        let indexURL = directory.appendingPathComponent("index.json")
        if let text = try? String(contentsOf: indexURL, encoding: .utf8), text.contains(secret) { return true }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return false }
        return names.contains { $0.contains(secret) }
    }

    private func evict() {
        while entries.reduce(0, { $0 + $1.bytes }) > byteLimit, !entries.isEmpty {
            var oldest = 0
            for offset in entries.indices where entries[offset].access < entries[oldest].access {
                oldest = offset
            }
            let removed = entries.remove(at: oldest)
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(removed.name))
        }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        let url = directory.appendingPathComponent("index.json")
        guard let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([Entry].self, from: data)
        else { return }
        entries = decoded
        clock = entries.map(\.access).max() ?? 0
    }

    private func persistIndex() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent("index.json"), options: .atomic)
    }
}

public final class MemoryImageCache: @unchecked Sendable {
    public let byteLimit: Int
    private let cache = NSCache<NSString, NSData>()
    private let lock = NSLock()
    private var order: [String] = []
    private var costs: [String: Int] = [:]
    private var total = 0
    private var observer: NSObjectProtocol?

    public init(byteLimit: Int) {
        self.byteLimit = byteLimit
        cache.totalCostLimit = byteLimit
        #if os(iOS) || os(tvOS)
            observer = NotificationCenter.default.addObserver(
                forName: Notification.Name("UIApplicationDidReceiveMemoryWarningNotification"),
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.purgeForMemoryWarning()
            }
        #endif
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    @discardableResult
    public func store(key: String, data: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard data.count <= byteLimit, data.count <= MetadataPolicy.imageMaxBytes, byteLimit > 0 else { return false }
        if let previous = costs[key] {
            total -= previous
            order.removeAll { $0 == key }
            cache.removeObject(forKey: key as NSString)
        }
        costs[key] = data.count
        total += data.count
        order.append(key)
        evictLocked()
        guard costs[key] != nil else { return false }
        cache.setObject(NSData(data: data), forKey: key as NSString, cost: data.count)
        return true
    }

    public func data(for key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard costs[key] != nil else { return nil }
        order.removeAll { $0 == key }
        order.append(key)
        guard let object = cache.object(forKey: key as NSString) else {
            if let cost = costs.removeValue(forKey: key) {
                total -= cost
            }
            order.removeAll { $0 == key }
            return nil
        }
        return Data(referencing: object)
    }

    public func purgeForMemoryWarning() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAllObjects()
        order.removeAll()
        costs.removeAll()
        total = 0
    }

    public func byteCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return total
    }

    private func evictLocked() {
        while total > byteLimit, let oldest = order.first {
            guard let cost = costs[oldest] else {
                order.removeFirst()
                continue
            }
            total -= cost
            costs[oldest] = nil
            order.removeFirst()
            cache.removeObject(forKey: oldest as NSString)
        }
    }
}

public final class ImageStore: @unchecked Sendable {
    public let memory: MemoryImageCache
    public let disk: DiskImageCache

    public init(memory: MemoryImageCache, disk: DiskImageCache) {
        self.memory = memory
        self.disk = disk
    }

    public func data(for key: String) async -> Data? {
        if let cached = memory.data(for: key) { return cached }
        guard let stored = await disk.data(for: key) else { return nil }
        memory.store(key: key, data: stored)
        return stored
    }

    public func store(key: String, data: Data) async {
        memory.store(key: key, data: data)
        await disk.store(key: key, data: data)
    }
}
