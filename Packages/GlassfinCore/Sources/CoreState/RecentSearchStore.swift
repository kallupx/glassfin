import CoreModels
import CoreNetworking
import Foundation

public protocol RecentSearchStoring: Sendable {
    func queries(serverID: String, userID: String) throws -> [String]
    func record(_ query: String, serverID: String, userID: String) throws
    func clear(serverID: String, userID: String) throws
    func removeServer(id: String) throws
}

/// S6.7. Local query text only. No preferences, credentials, URLs, timestamps or logging.
/// The lock also serializes sign-out/removal against writes from another scene.
public final class RecentSearchStore: RecentSearchStoring, @unchecked Sendable {
    public static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Glassfin/RecentSearches", isDirectory: true)
    }

    public static let maximumFileBytes = 256 * 1024

    private let directory: URL
    private let lock = NSLock()

    public init(directory: URL = RecentSearchStore.applicationSupportDirectory) {
        self.directory = directory
    }

    public func queries(serverID: String, userID: String) throws -> [String] {
        try lock.withLock { try read(file(serverID: serverID, userID: userID)) }
    }

    public func record(_ query: String, serverID: String, userID: String) throws {
        let query = String(
            query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(SearchPolicy.maximumQueryCharacters))
        guard !query.isEmpty else { return }
        try lock.withLock {
            var url = file(serverID: serverID, userID: userID)
            let old = try read(url)
            let values = Array(
                ([query] + old.filter { $0.lowercased() != query.lowercased() }).prefix(
                    MetadataPolicy.recentSearchesMax))
            var folder = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var excluded = URLResourceValues()
            excluded.isExcludedFromBackup = true
            try folder.setResourceValues(excluded)
            try JSONEncoder().encode(values).write(to: url, options: .atomic)
            try url.setResourceValues(excluded)
        }
    }

    public func clear(serverID: String, userID: String) throws {
        try lock.withLock { try removeIfPresent(file(serverID: serverID, userID: userID)) }
    }

    public func removeServer(id: String) throws {
        try lock.withLock { try removeIfPresent(serverDirectory(id)) }
    }

    private func serverDirectory(_ id: String) -> URL {
        directory.appendingPathComponent(hash(id), isDirectory: true)
    }

    private func file(serverID: String, userID: String) -> URL {
        serverDirectory(serverID).appendingPathComponent(hash(userID) + ".json")
    }

    private func hash(_ text: String) -> String {
        CertificateFingerprint.sha256Hex(Data(text.lowercased().replacingOccurrences(of: "-", with: "").utf8))
    }

    private func read(_ url: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= Self.maximumFileBytes else {
            try removeIfPresent(url)
            return []
        }
        let data = try Data(contentsOf: url)
        guard data.count <= Self.maximumFileBytes,
            let values = try? JSONDecoder().decode([String].self, from: data)
        else {
            try removeIfPresent(url)
            return []
        }
        var seen: Set<String> = []
        return Array(
            values.map {
                String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(SearchPolicy.maximumQueryCharacters))
            }.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }.prefix(MetadataPolicy.recentSearchesMax))
    }

    private func removeIfPresent(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
