import Foundation

public struct ItemPerson: Sendable, Hashable, Codable {
    public var name: String
    public var role: String?

    public init(name: String, role: String? = nil) {
        self.name = MetadataSanitizer.displayText(name, limit: MetadataPolicy.nameMax)
        self.role = role.map { MetadataSanitizer.displayText($0, limit: MetadataPolicy.nameMax) }
    }
}

public struct ItemStream: Sendable, Hashable, Codable, Identifiable {
    public var id: Int
    public var kind: String
    public var title: String?
    public var language: String?
    public var codec: String?
    public var profile: String?
    public var channels: Int?
    public var width: Int?
    public var height: Int?
    public var videoRange: String?
    public var dolbyVisionProfile: Int?
    public var isDefault: Bool?

    public init(
        id: Int, kind: String, title: String? = nil, language: String? = nil, codec: String? = nil,
        profile: String? = nil,
        channels: Int? = nil, width: Int? = nil, height: Int? = nil, videoRange: String? = nil,
        dolbyVisionProfile: Int? = nil, isDefault: Bool? = nil
    ) {
        self.id = id
        self.kind = MetadataSanitizer.displayText(kind, limit: MetadataPolicy.nameMax)
        self.title = title.map { MetadataSanitizer.displayText($0, limit: MetadataPolicy.nameMax) }
        self.language = language.map { MetadataSanitizer.displayText($0, limit: MetadataPolicy.nameMax) }
        self.codec = codec.map { MetadataSanitizer.displayText($0, limit: MetadataPolicy.nameMax) }
        self.profile = profile.map { MetadataSanitizer.displayText($0, limit: MetadataPolicy.nameMax) }
        self.channels = channels
        self.width = width
        self.height = height
        self.videoRange = videoRange.map { MetadataSanitizer.displayText($0, limit: MetadataPolicy.nameMax) }
        self.dolbyVisionProfile = dolbyVisionProfile
        self.isDefault = isDefault
    }

    public var resolutionLabel: String? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        if width >= 3840 || height >= 2160 { return "4K" }
        if width >= 1920 || height >= 1080 { return "1080p" }
        return "\(width) × \(height)"
    }

    public var hdrLabel: String? {
        switch videoRange?.uppercased() {
        case "HDR10": return "HDR10"
        case "HDR10PLUS": return "HDR10+"
        case "DOVI", "DOVIWITHHDR10", "DOVIWITHHLG", "DOVIWITHSDR": return "Dolby Vision"
        case "HLG": return "HLG"
        default: return nil
        }
    }

    /// Compact detail-row labels; keep all raw streams available for track selection.
    public var technicalLabel: String {
        if kind == "Video" { return [resolutionLabel, hdrLabel].compactMap { $0 }.joined(separator: " · ") }
        if kind == "Subtitle" { return language ?? "" }
        guard kind == "Audio" else { return technicalValue }
        if profile?.localizedCaseInsensitiveContains("Atmos") == true
            || title?.localizedCaseInsensitiveContains("Atmos") == true
        {
            return "Dolby Atmos"
        }
        var parts: [String] = []
        if let codec {
            let name = profile.flatMap { $0.uppercased().hasPrefix(codec.uppercased()) ? $0 : nil } ?? codec
            parts.append(MetadataSanitizer.displayText(name.uppercased(), limit: MetadataPolicy.nameMax))
        }
        if let channels, channels > 0 {
            parts.append(channels == 8 ? "7.1" : channels == 6 ? "5.1" : channels == 2 ? "2.0" : String(channels))
        }
        return parts.joined(separator: " · ")
    }

    /// Technical values only; UI labels are supplied by the app's String Catalog.
    public var technicalValue: String {
        var parts: [String] = []
        if let width, let height, width > 0, height > 0 { parts.append("\(width) × \(height)") }
        if let videoRange { parts.append(videoRange) }
        if let dolbyVisionProfile { parts.append("DV P\(dolbyVisionProfile)") }
        if let codec {
            if let profile, profile.uppercased().hasPrefix(codec.uppercased()) {
                parts.append(MetadataSanitizer.displayText(profile.uppercased(), limit: MetadataPolicy.nameMax))
            } else {
                parts.append(MetadataSanitizer.displayText(codec.uppercased(), limit: MetadataPolicy.nameMax))
                if let profile { parts.append(profile) }
            }
        }
        if let channels, channels > 0 {
            parts.append(channels == 8 ? "7.1" : channels == 6 ? "5.1" : String(channels))
        }
        if let language { parts.append(language) }
        return parts.joined(separator: " · ")
    }
}

public struct ItemMetadata: Sendable, Hashable, Codable {
    public var taglines: [String]
    public var genres: [String]
    public var people: [ItemPerson]
    public var studios: [String]
    public var streams: [ItemStream]

    public init(
        taglines: [String] = [], genres: [String] = [], people: [ItemPerson] = [], studios: [String] = [],
        streams: [ItemStream] = []
    ) {
        self.taglines = taglines.prefix(MetadataPolicy.taglinesMax).map {
            MetadataSanitizer.displayText($0, limit: MetadataPolicy.taglineMax)
        }
        self.genres = genres.prefix(MetadataPolicy.genresMax).map {
            MetadataSanitizer.displayText($0, limit: MetadataPolicy.genreMax)
        }
        self.people = people.map { ItemPerson(name: $0.name, role: $0.role) }
        self.studios = studios.map { MetadataSanitizer.displayText($0, limit: MetadataPolicy.nameMax) }
        self.streams = streams.map {
            ItemStream(
                id: $0.id, kind: $0.kind, title: $0.title, language: $0.language, codec: $0.codec, profile: $0.profile,
                channels: $0.channels, width: $0.width, height: $0.height, videoRange: $0.videoRange,
                dolbyVisionProfile: $0.dolbyVisionProfile, isDefault: $0.isDefault)
        }
    }

    /// First default video/audio (or first of that type), then distinct subtitle languages in server order.
    public var technicalStreams: [ItemStream] {
        let defaults = ["Video", "Audio"].compactMap { kind in
            streams.first { $0.kind == kind && $0.isDefault == true } ?? streams.first { $0.kind == kind }
        }
        var languages: Set<String> = []
        let subtitles = streams.filter {
            guard $0.kind == "Subtitle", let language = $0.language, !language.isEmpty else { return false }
            return languages.insert(language).inserted
        }
        return defaults + subtitles
    }
}

extension MediaItem {
    /// Also sanitize protocol mocks and decoded snapshots at the presentation boundary.
    public func cleanedForDisplay() -> MediaItem {
        var result = self
        result.name = MetadataSanitizer.displayText(name, limit: MetadataPolicy.nameMax)
        result.overview = overview.map { MetadataSanitizer.displayText($0, limit: MetadataPolicy.overviewMax) }
        result.officialRating = officialRating.map { MetadataSanitizer.displayText($0, limit: MetadataPolicy.nameMax) }
        result.chapters = chapters.map {
            ChapterMark(
                name: $0.name.map { MetadataSanitizer.displayText($0, limit: MetadataPolicy.nameMax) }, start: $0.start)
        }
        if let detail {
            result.detail = ItemMetadata(
                taglines: detail.taglines, genres: detail.genres, people: detail.people, studios: detail.studios,
                streams: detail.streams)
        }
        return result
    }
}
