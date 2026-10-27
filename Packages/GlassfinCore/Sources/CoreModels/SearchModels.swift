import Foundation

public enum SearchKind: String, CaseIterable, Sendable, Hashable, Codable {
    case movies = "Movie"
    case series = "Series"
    case episodes = "Episode"

    public var mediaKind: MediaKind { MediaKind.from(serverType: rawValue) }
}

public enum SearchPolicy {
    public static let pageSize = 24
    public static let minimumCharacters = 2

    public static func accepts(_ term: String) -> Bool {
        let text = term.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count >= minimumCharacters { return true }
        guard text.count == 1 else { return false }
        // TODO(Q9-01): Treat Han, kana and Hangul as CJK, including supplementary Han.
        return text.unicodeScalars.contains {
            (0x3400...0x9FFF).contains($0.value) || (0x20000...0x323AF).contains($0.value)
                || (0x3040...0x30FF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value)
                || (0x1100...0x11FF).contains($0.value) || (0xFF66...0xFF9D).contains($0.value)
        }
    }
}

public struct SearchGroup: Identifiable, Sendable, Equatable {
    public var id: SearchKind
    public var items: [MediaItem]
    public var nextIndex: Int?

    public init(id: SearchKind, items: [MediaItem], nextIndex: Int? = nil) {
        self.id = id
        self.items = items.map { $0.searchDisplayItem }
        self.nextIndex = nextIndex
    }
}

public struct SearchResponse: Sendable, Equatable {
    public var term: String
    public var groups: [SearchGroup]

    public init(term: String, groups: [SearchGroup]) {
        self.term = term
        self.groups = groups
    }
}

extension MediaItem {
    /// Apply again at the view-model boundary, including mock and cached input.
    public var searchDisplayItem: MediaItem {
        var result = self
        result.name = MetadataPolicy.clean(name)
        result.overview = overview.map { MetadataPolicy.clean($0, limit: MetadataPolicy.overviewMaxCharacters) }
        result.officialRating = officialRating.map { MetadataPolicy.clean($0) }
        result.chapters = chapters.map { ChapterMark(name: $0.name.map { MetadataPolicy.clean($0) }, start: $0.start) }
        if case .other(let type) = kind { result.kind = .other(MetadataPolicy.clean(type)) }
        return result
    }
}
