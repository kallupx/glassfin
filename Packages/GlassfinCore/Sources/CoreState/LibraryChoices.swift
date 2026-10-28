import CoreModels
import CoreNetworking
import Foundation

public enum LibrarySort: String, CaseIterable, Codable, Sendable {
    case name = "SortName"
    case dateAdded = "DateCreated"
    case releaseYear = "ProductionYear"
    case rating = "CommunityRating"
    case random = "Random"
}

public struct LibraryChoices: Codable, Sendable, Equatable {
    public var sort: LibrarySort = .name
    public var descending = false
    public var unplayed = false
    public var favorites = false
    public var genre: String?
    public var year: Int?

    public init() {}

    public func query(collectionType: String?) -> ItemQuery {
        ItemQuery(
            includeItemTypes: collectionType == "tvshows"
                ? ["Series"] : collectionType == "movies" ? ["Movie"] : ["Movie", "Series"],
            sortBy: [sort.rawValue], sortOrder: descending ? "Descending" : "Ascending",
            filters: (unplayed ? ["IsUnplayed"] : []) + (favorites ? ["IsFavorite"] : []),
            genres: genre.map { [$0] } ?? [], years: year.map { [$0] } ?? [])
    }
}

/// Small per-library choices only. Images and metadata never enter UserDefaults.
public struct LibraryChoicesStore: Sendable {
    private let settings: any SettingsStore
    private let namespace: String

    public init(settings: any SettingsStore, serverID: String, userID: String) {
        self.settings = settings
        self.namespace = "library.choices.\(serverID).\(userID)."
    }

    public func load(libraryID: String) -> LibraryChoices {
        guard let value = settings.string(forKey: namespace + libraryID), let data = value.data(using: .utf8) else {
            return LibraryChoices()
        }
        return (try? JSONDecoder().decode(LibraryChoices.self, from: data)) ?? LibraryChoices()
    }

    public func save(_ choices: LibraryChoices, libraryID: String) {
        guard let data = try? JSONEncoder().encode(choices) else { return }
        settings.set(String(data: data, encoding: .utf8), forKey: namespace + libraryID)
    }
}
