import Foundation

public struct PublicSystemInfoDTO: Decodable, Sendable {
    public var ServerName: String?
    public var Version: String?
    public var Id: String?
    public var StartupWizardCompleted: Bool?
    public var ProductName: String?
}

public struct UserPolicyDTO: Decodable, Sendable {
    public var IsAdministrator: Bool?
}

public struct UserDTO: Decodable, Sendable {
    public var Id: String?
    public var Name: String?
    public var Policy: UserPolicyDTO?
    public var Configuration: PlaybackUserConfigurationDTO?
}

public struct AuthenticationResultDTO: Decodable, Sendable {
    public var AccessToken: String?
    public var ServerId: String?
    public var User: UserDTO?
}

public struct QuickConnectResultDTO: Decodable, Sendable {
    public var Secret: String?
    public var Code: String?
    public var Authenticated: Bool?
}

public struct ImageTagsDTO: Decodable, Sendable {
    public var Primary: String?
    public var Logo: String?
    public var Thumb: String?
}

public struct ImageBlurHashesDTO: Decodable, Sendable {
    public var Primary: [String: String]?
}

public struct UserItemDataDTO: Decodable, Sendable {
    public var Played: Bool?
    public var PlaybackPositionTicks: Int64?
    public var IsFavorite: Bool?
    public var UnplayedItemCount: Int?
    public var PlayedPercentage: Double?
}

public struct ChapterDTO: Decodable, Sendable {
    public var Name: String?
    public var StartPositionTicks: Int64?
}

public struct TrickplayInfoDTO: Decodable, Sendable {
    public var Width: Int?
    public var Height: Int?
    public var TileWidth: Int?
    public var TileHeight: Int?
    public var ThumbnailCount: Int?
    public var Interval: Int64?
}

public struct BaseItemDTO: Decodable, Sendable {
    public var Id: String?
    public var Name: String?
    public var `Type`: String?
    public var Overview: String?
    public var SeriesId: String?
    public var SeriesName: String?
    public var SeasonId: String?
    public var IndexNumber: Int?
    public var ParentIndexNumber: Int?
    public var RunTimeTicks: Int64?
    public var ProductionYear: Int?
    public var OfficialRating: String?
    public var CommunityRating: Double?
    public var ImageTags: ImageTagsDTO?
    public var BackdropImageTags: [String]?
    public var ImageBlurHashes: ImageBlurHashesDTO?
    public var UserData: UserItemDataDTO?
    public var Trickplay: [String: [String: TrickplayInfoDTO]]?
    public var Chapters: [ChapterDTO]?
    public var CollectionType: String?
    public var Taglines: [String]?
    public var Genres: [String]?
    public var People: [ItemPersonDTO]?
    public var Studios: [ItemStudioDTO]?
    public var MediaStreams: [MediaStreamDTO]?
    public var MediaSources: [MediaSourceDTO]?
}

public struct QueryResultDTO: Decodable, Sendable {
    public var Items: [BaseItemDTO]?
    public var TotalRecordCount: Int?
}

public struct MediaStreamDTO: Decodable, Sendable {
    public var Index: Int?
    public var `Type`: String?
    public var DisplayTitle: String?
    public var Language: String?
    public var Codec: String?
    public var Profile: String?
    public var Width: Int?
    public var Height: Int?
    public var VideoRangeType: String?
    public var DvProfile: Int?
    public var IsDefault: Bool?
    public var IsForced: Bool?
    public var IsExternal: Bool?
    public var IsHearingImpaired: Bool?
    public var Channels: Int?
    public var DeliveryMethod: String?
    public var DeliveryUrl: String?
    public var SupportsExternalStream: Bool?
}

public struct MediaSourceDTO: Decodable, Sendable {
    public var Id: String?
    public var Container: String?
    public var Bitrate: Int?
    public var SupportsDirectPlay: Bool?
    public var SupportsDirectStream: Bool?
    public var SupportsTranscoding: Bool?
    public var TranscodingUrl: String?
    public var DirectStreamUrl: String?
    public var TranscodingSubProtocol: String?
    public var MediaStreams: [MediaStreamDTO]?
    public var DefaultVideoStreamIndex: Int?
    public var DefaultAudioStreamIndex: Int?
    public var DefaultSubtitleStreamIndex: Int?
}

public struct PlaybackInfoResponseDTO: Decodable, Sendable {
    public var MediaSources: [MediaSourceDTO]?
    public var PlaySessionId: String?
    public var ErrorCode: String?
}

public struct MediaSegmentDTO: Decodable, Sendable {
    public var `Type`: String?
    public var StartTicks: Int64?
    public var EndTicks: Int64?
}

public struct SearchHintDTO: Decodable, Sendable {
    public var PrimaryImageTag: String?
    public var ThumbImageTag: String?
    public var ItemId: String?
    public var Id: String?
    public var Name: String?
    public var `Type`: String?
}

public struct SearchHintResultDTO: Decodable, Sendable {
    public var SearchHints: [SearchHintDTO]?
    public var TotalRecordCount: Int?
}

public struct QueryFiltersDTO: Decodable, Sendable {
    public var Genres: [String]?
    public var Years: [Int]?
}

public struct PlainText: Decodable, Sendable, Equatable {
    public var value: String
    public init(value: String) { self.value = value }
}

public struct EmptyResponse: Decodable, Sendable, Equatable {
    public init() {}
    public init(from decoder: Decoder) throws {}
}

public struct JSONFlag: Decodable, Sendable, Equatable {
    public var value: Bool
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(Bool.self)
    }
}

public struct ItemPersonDTO: Decodable, Sendable {
    public var Name: String?
    public var Role: String?
}

public struct ItemStudioDTO: Decodable, Sendable {
    public var Name: String?
}

public struct PlaybackUserConfigurationDTO: Decodable, Sendable {
    public var AudioLanguagePreference: String?
    public var SubtitleLanguagePreference: String?
    public var SubtitleMode: String?
    public var PlayDefaultAudioTrack: Bool?
}
