import Foundation

public struct ServerInfo: Sendable, Hashable, Codable {
    public var id: String
    public var name: String
    public var url: URL
    public var version: SemVer

    public init(id: String, name: String, url: URL, version: SemVer) {
        self.id = id
        self.name = name
        self.url = url
        self.version = version
    }
}

/// Authenticated user. The access token is intentionally absent; only `SecureStore` holds it.
public struct UserSession: Sendable, Hashable, Codable, CustomStringConvertible {
    public var server: ServerInfo
    public var userID: String
    public var userName: String
    public var isAdministrator: Bool

    public init(server: ServerInfo, userID: String, userName: String, isAdministrator: Bool) {
        self.server = server
        self.userID = userID
        self.userName = userName
        self.isAdministrator = isAdministrator
    }

    public var description: String {
        "UserSession(userID: \(userID), userName: \(userName), server: \(server.name))"
    }
}

public enum MediaKind: Sendable, Hashable, Codable {
    case movie
    case series
    case season
    case episode
    case boxSet
    case musicAlbum
    case audio
    case audioBook
    case liveTVChannel
    case folder
    case other(String)

    public static func from(serverType: String) -> MediaKind {
        switch serverType {
        case "Movie": .movie
        case "Series": .series
        case "Season": .season
        case "Episode": .episode
        case "BoxSet": .boxSet
        case "MusicAlbum": .musicAlbum
        case "Audio": .audio
        case "AudioBook": .audioBook
        case "TvChannel": .liveTVChannel
        case "Folder", "CollectionFolder", "UserView": .folder
        default: .other(serverType)
        }
    }
}

public struct ImageSet: Sendable, Hashable, Codable {
    public var primaryTag: String?
    public var backdropTags: [String]
    public var logoTag: String?
    public var thumbTag: String?
    public var primaryBlurHash: String?

    public init(
        primaryTag: String? = nil,
        backdropTags: [String] = [],
        logoTag: String? = nil,
        thumbTag: String? = nil,
        primaryBlurHash: String? = nil
    ) {
        self.primaryTag = primaryTag
        self.backdropTags = backdropTags
        self.logoTag = logoTag
        self.thumbTag = thumbTag
        self.primaryBlurHash = primaryBlurHash
    }
}

public struct UserItemState: Sendable, Hashable, Codable {
    public var played: Bool
    public var playbackPosition: Duration
    public var isFavorite: Bool
    public var unplayedCount: Int?
    public var playedPercentage: Double?

    public init(
        played: Bool = false,
        playbackPosition: Duration = .zero,
        isFavorite: Bool = false,
        unplayedCount: Int? = nil,
        playedPercentage: Double? = nil
    ) {
        self.played = played
        self.playbackPosition = playbackPosition
        self.isFavorite = isFavorite
        self.unplayedCount = unplayedCount
        self.playedPercentage = playedPercentage
    }
}

public struct ChapterMark: Sendable, Hashable, Codable {
    public var name: String?
    public var start: Duration

    public init(name: String?, start: Duration) {
        self.name = name
        self.start = start
    }
}

public struct TrickplayInfo: Sendable, Hashable, Codable {
    public var width: Int
    public var height: Int
    public var tileWidth: Int
    public var tileHeight: Int
    public var thumbnailCount: Int
    public var interval: Duration

    public init(width: Int, height: Int, tileWidth: Int, tileHeight: Int, thumbnailCount: Int, interval: Duration) {
        self.width = width
        self.height = height
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        self.thumbnailCount = thumbnailCount
        self.interval = interval
    }
}

public struct MediaItem: Sendable, Identifiable, Hashable, Codable {
    public var id: String
    public var kind: MediaKind
    public var name: String
    public var overview: String?
    public var seriesID: String?
    public var seasonID: String?
    public var indexNumber: Int?
    public var parentIndexNumber: Int?
    public var runtime: Duration?
    public var productionYear: Int?
    public var officialRating: String?
    public var communityRating: Double?
    public var images: ImageSet
    public var userData: UserItemState
    public var trickplay: [Int: TrickplayInfo]?
    public var chapters: [ChapterMark]

    public init(
        id: String,
        kind: MediaKind,
        name: String,
        overview: String? = nil,
        seriesID: String? = nil,
        seasonID: String? = nil,
        indexNumber: Int? = nil,
        parentIndexNumber: Int? = nil,
        runtime: Duration? = nil,
        productionYear: Int? = nil,
        officialRating: String? = nil,
        communityRating: Double? = nil,
        images: ImageSet = ImageSet(),
        userData: UserItemState = UserItemState(),
        trickplay: [Int: TrickplayInfo]? = nil,
        chapters: [ChapterMark] = []
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.overview = overview
        self.seriesID = seriesID
        self.seasonID = seasonID
        self.indexNumber = indexNumber
        self.parentIndexNumber = parentIndexNumber
        self.runtime = runtime
        self.productionYear = productionYear
        self.officialRating = officialRating
        self.communityRating = communityRating
        self.images = images
        self.userData = userData
        self.trickplay = trickplay
        self.chapters = chapters
    }
}

public struct Library: Sendable, Identifiable, Hashable, Codable {
    public var id: String
    public var name: String
    public var collectionType: String?

    public init(id: String, name: String, collectionType: String? = nil) {
        self.id = id
        self.name = name
        self.collectionType = collectionType
    }
}

public struct PageRequest: Sendable, Hashable, Codable {
    public var startIndex: Int
    public var limit: Int

    public init(startIndex: Int = 0, limit: Int = 50) {
        self.startIndex = startIndex
        self.limit = limit
    }
}

public struct Page<Item: Sendable>: Sendable {
    public var items: [Item]
    public var totalCount: Int?

    public init(items: [Item], totalCount: Int?) {
        self.items = items
        self.totalCount = totalCount
    }
}

public struct ItemQuery: Sendable, Hashable, Codable {
    public var includeItemTypes: [String]
    public var sortBy: [String]
    public var sortOrder: String?
    public var filters: [String]
    public var genres: [String]
    public var years: [Int]
    public var recursive: Bool
    public var nameStartsWith: String?
    public var searchTerm: String?

    public init(
        includeItemTypes: [String] = [],
        sortBy: [String] = [],
        sortOrder: String? = nil,
        filters: [String] = [],
        genres: [String] = [],
        years: [Int] = [],
        recursive: Bool = true,
        nameStartsWith: String? = nil,
        searchTerm: String? = nil
    ) {
        self.includeItemTypes = includeItemTypes
        self.sortBy = sortBy
        self.sortOrder = sortOrder
        self.filters = filters
        self.genres = genres
        self.years = years
        self.recursive = recursive
        self.nameStartsWith = nameStartsWith
        self.searchTerm = searchTerm
    }
}

public struct MediaSegment: Sendable, Hashable, Codable {
    public enum Kind: Sendable, Hashable, Codable {
        case intro
        case outro
        case recap
        case preview
        case commercial
        case unknown
    }

    public var kind: Kind
    public var range: Range<Duration>

    public init(kind: Kind, range: Range<Duration>) {
        self.kind = kind
        self.range = range
    }

    public static func kind(from serverType: String) -> Kind {
        switch serverType {
        case "Intro": .intro
        case "Outro": .outro
        case "Recap": .recap
        case "Preview": .preview
        case "Commercial": .commercial
        default: .unknown
        }
    }
}

public enum PlayMethod: Sendable, Hashable, Codable {
    case directPlay
    case directStream
    case transcode
}

public struct Track: Sendable, Identifiable, Hashable, Codable {
    public var id: Int
    public var displayTitle: String?
    public var language: String?
    public var codec: String?

    public init(id: Int, displayTitle: String? = nil, language: String? = nil, codec: String? = nil) {
        self.id = id
        self.displayTitle = displayTitle
        self.language = language
        self.codec = codec
    }
}

public struct PlaybackSource: Sendable, Hashable {
    public var mediaSourceID: String
    public var playSessionID: String
    public var method: PlayMethod
    public var url: URL?
    public var audioTracks: [Track]
    public var subtitleTracks: [Track]
    public var transcodeReasons: [String]

    public init(
        mediaSourceID: String,
        playSessionID: String,
        method: PlayMethod,
        url: URL?,
        audioTracks: [Track],
        subtitleTracks: [Track],
        transcodeReasons: [String]
    ) {
        self.mediaSourceID = mediaSourceID
        self.playSessionID = playSessionID
        self.method = method
        self.url = url
        self.audioTracks = audioTracks
        self.subtitleTracks = subtitleTracks
        self.transcodeReasons = transcodeReasons
    }
}

public struct AuthenticatedSession: Sendable, Hashable {
    public var session: UserSession
    public var accessToken: String

    public init(session: UserSession, accessToken: String) {
        self.session = session
        self.accessToken = accessToken
    }
}

public struct QuickConnectChallenge: Sendable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    public var code: String
    public var secret: String
    public var authenticated: Bool

    public init(code: String, secret: String, authenticated: Bool = false) {
        self.code = code
        self.secret = secret
        self.authenticated = authenticated
    }

    /// The secret is omitted. Do not log the value itself.
    public var description: String {
        "QuickConnectChallenge(code: \(code), authenticated: \(authenticated))"
    }

    public var debugDescription: String { description }
}

public struct ItemFilterSet: Sendable, Hashable {
    public var genres: [String]
    public var years: [Int]

    public init(genres: [String], years: [Int]) {
        self.genres = genres
        self.years = years
    }
}

public struct PublicUser: Sendable, Hashable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
