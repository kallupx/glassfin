import CoreModels
import CoreNetworking
import Foundation

func encodeJSON<T: Encodable>(_ value: T) throws(APIError) -> Data {
    do {
        return try JSONEncoder().encode(value)
    } catch {
        throw APIError.decoding
    }
}

/// Item ids are interpolated into URL paths. Reject anything that is not a GUID first.
func validatedItemID(_ raw: String) throws(APIError) -> String {
    try ItemID.require(raw).value
}

public protocol SystemService: Sendable {
    func publicInfo() async throws(APIError) -> ServerInfo
    func ping() async throws(APIError) -> String
}

public protocol AuthenticationService: Sendable {
    func authenticate(username: String, password: String) async throws(APIError) -> AuthenticatedSession
    func quickConnectEnabled() async throws(APIError) -> Bool
    func initiateQuickConnect() async throws(APIError) -> QuickConnectChallenge
    func quickConnectState(secret: String) async throws(APIError) -> QuickConnectChallenge
    func authenticate(quickConnectSecret: String) async throws(APIError) -> AuthenticatedSession
    func logout() async throws(APIError)
    func currentUser() async throws(APIError) -> UserSession
    func publicUsers() async throws(APIError) -> [PublicUser]
    func postCapabilities(playableMediaTypes: [String], supportsMediaControl: Bool) async throws(APIError)
}

public protocol LibraryService: Sendable {
    func userViews() async throws(APIError) -> [Library]
    func items(in library: Library.ID, query: ItemQuery, page: PageRequest) async throws(APIError) -> Page<MediaItem>
    func resume(limit: Int) async throws(APIError) -> [MediaItem]
    func nextUp(limit: Int) async throws(APIError) -> [MediaItem]
    func latest(in library: Library.ID, limit: Int) async throws(APIError) -> [MediaItem]
    func seasons(series: MediaItem.ID) async throws(APIError) -> [MediaItem]
    func episodes(series: MediaItem.ID, season: MediaItem.ID?) async throws(APIError) -> [MediaItem]
    func item(id: MediaItem.ID) async throws(APIError) -> MediaItem
    func similar(id: MediaItem.ID, limit: Int) async throws(APIError) -> [MediaItem]
    func filters(in library: Library.ID) async throws(APIError) -> ItemFilterSet
    func setPlayed(_ id: MediaItem.ID, _ played: Bool) async throws(APIError)
    func setFavorite(_ id: MediaItem.ID, _ favorite: Bool) async throws(APIError)
    func userData(id: MediaItem.ID) async throws(APIError) -> UserItemState
    func updateUserData(id: MediaItem.ID, position: Duration, played: Bool) async throws(APIError)
}

public protocol SearchService: Sendable {
    func hints(term: String, limit: Int) async throws(APIError) -> [MediaItem]
}

public protocol PlaybackInfoService: Sendable {
    func playbackInfo(itemID: String, start: Duration, maxBitrate: Int) async throws(APIError) -> PlaybackSource
    func mediaSegments(itemID: String) async throws(APIError) -> [MediaSegment]
    func bitrateTest(size: Int) async throws(APIError) -> Data
}

public protocol ReportingService: Sendable {
    func started(itemID: String, position: Duration, playSessionID: String) async throws(APIError)
    func progress(itemID: String, position: Duration, playSessionID: String, paused: Bool) async throws(APIError)
    func stopped(itemID: String, position: Duration, playSessionID: String, failed: Bool) async throws(APIError)
    func ping(playSessionID: String) async throws(APIError)
}

public struct JellyfinSystemService: SystemService {
    public var client: any JellyfinAPIClient
    public var server: URL
    public init(client: any JellyfinAPIClient, server: URL) {
        self.client = client
        self.server = server
    }

    public func publicInfo() async throws(APIError) -> ServerInfo {
        let dto = try await client.send(
            APIRequest(method: "GET", path: "/System/Info/Public"), as: PublicSystemInfoDTO.self)
        guard let info = DTOMapper.serverInfo(dto, url: server) else { throw APIError.decoding }
        return info
    }

    public func ping() async throws(APIError) -> String {
        let text = try await client.send(APIRequest(method: "GET", path: "/System/Ping"), as: PlainText.self)
        return text.value
    }
}

public struct JellyfinAuthenticationService: AuthenticationService {
    public var client: any JellyfinAPIClient
    public var server: URL
    public var serverName: String
    public var knownServer: ServerInfo?
    public init(client: any JellyfinAPIClient, server: URL, serverName: String = "", knownServer: ServerInfo? = nil) {
        self.client = client
        self.server = server
        self.serverName = serverName
        self.knownServer = knownServer
    }

    public func authenticate(username: String, password: String) async throws(APIError) -> AuthenticatedSession {
        let body = try encodeJSON(AuthNameBody(Username: username, Pw: password))
        let dto = try await client.send(
            APIRequest(method: "POST", path: "/Users/AuthenticateByName", body: body),
            as: AuthenticationResultDTO.self
        )
        guard let session = DTOMapper.session(auth: dto, serverURL: server, fallbackServerName: serverName) else {
            throw APIError.decoding
        }
        return session
    }

    public func quickConnectEnabled() async throws(APIError) -> Bool {
        let flag = try await client.send(APIRequest(method: "GET", path: "/QuickConnect/Enabled"), as: JSONFlag.self)
        return flag.value
    }

    public func initiateQuickConnect() async throws(APIError) -> QuickConnectChallenge {
        // Jellyfin 12 removed GET /QuickConnect/Initiate. POST is valid on 10.10 and 12.x.
        let dto = try await client.send(
            APIRequest(method: "POST", path: "/QuickConnect/Initiate"), as: QuickConnectResultDTO.self)
        guard let code = dto.Code, let secret = dto.Secret else { throw APIError.decoding }
        return QuickConnectChallenge(code: code, secret: secret, authenticated: dto.Authenticated ?? false)
    }

    public func quickConnectState(secret: String) async throws(APIError) -> QuickConnectChallenge {
        let dto = try await client.send(
            APIRequest(
                method: "GET", path: "/QuickConnect/Connect", query: [URLQueryItem(name: "secret", value: secret)]),
            as: QuickConnectResultDTO.self
        )
        guard let code = dto.Code, let value = dto.Secret else { throw APIError.decoding }
        return QuickConnectChallenge(code: code, secret: value, authenticated: dto.Authenticated ?? false)
    }

    public func authenticate(quickConnectSecret: String) async throws(APIError) -> AuthenticatedSession {
        let body = try encodeJSON(QuickConnectBody(Secret: quickConnectSecret))
        let dto = try await client.send(
            APIRequest(method: "POST", path: "/Users/AuthenticateWithQuickConnect", body: body),
            as: AuthenticationResultDTO.self
        )
        guard let session = DTOMapper.session(auth: dto, serverURL: server, fallbackServerName: serverName) else {
            throw APIError.decoding
        }
        return session
    }

    public func logout() async throws(APIError) {
        _ = try await client.send(APIRequest(method: "POST", path: "/Sessions/Logout"), as: EmptyResponse.self)
    }

    public func currentUser() async throws(APIError) -> UserSession {
        let dto = try await client.send(APIRequest(method: "GET", path: "/Users/Me"), as: UserDTO.self)
        let serverInfo =
            knownServer
            ?? ServerInfo(id: "", name: serverName, url: server, version: SemVer(major: 0, minor: 0, patch: 0))
        guard let session = DTOMapper.userSession(dto, server: serverInfo) else { throw APIError.decoding }
        return session
    }

    public func publicUsers() async throws(APIError) -> [PublicUser] {
        let dto = try await client.send(APIRequest(method: "GET", path: "/Users/Public"), as: [UserDTO].self)
        return dto.compactMap { user in
            guard let id = user.Id else { return nil }
            return PublicUser(id: id, name: user.Name ?? "", host: server.host ?? "")
        }
    }

    public func postCapabilities(playableMediaTypes: [String], supportsMediaControl: Bool) async throws(APIError) {
        let body = try encodeJSON(
            CapabilitiesBody(
                PlayableMediaTypes: playableMediaTypes, SupportsMediaControl: supportsMediaControl,
                SupportedCommands: [])
        )
        _ = try await client.send(
            APIRequest(method: "POST", path: "/Sessions/Capabilities/Full", body: body), as: EmptyResponse.self)
    }
}

public struct JellyfinLibraryService: LibraryService {
    public var client: any JellyfinAPIClient
    public var log: any GlassfinLog
    public init(client: any JellyfinAPIClient, log: any GlassfinLog = SilentLog()) {
        self.client = client
        self.log = log
    }

    public func userViews() async throws(APIError) -> [Library] {
        let dto = try await client.send(APIRequest(method: "GET", path: "/UserViews"), as: QueryResultDTO.self)
        return (dto.Items ?? []).compactMap(DTOMapper.library)
    }

    public func items(in library: Library.ID, query: ItemQuery, page: PageRequest) async throws(APIError) -> Page<
        MediaItem
    > {
        var items = [
            URLQueryItem(name: "parentId", value: library),
            URLQueryItem(name: "startIndex", value: String(page.startIndex)),
            URLQueryItem(name: "limit", value: String(page.limit)),
            URLQueryItem(name: "recursive", value: query.recursive ? "true" : "false"),
            URLQueryItem(name: "enableTotalRecordCount", value: "true"),
        ]
        items.append(contentsOf: query.includeItemTypes.map { URLQueryItem(name: "includeItemTypes", value: $0) })
        items.append(contentsOf: query.sortBy.map { URLQueryItem(name: "sortBy", value: $0) })
        if let sortOrder = query.sortOrder { items.append(URLQueryItem(name: "sortOrder", value: sortOrder)) }
        items.append(contentsOf: query.filters.map { URLQueryItem(name: "filters", value: $0) })
        items.append(contentsOf: query.genres.map { URLQueryItem(name: "genres", value: $0) })
        items.append(contentsOf: query.years.map { URLQueryItem(name: "years", value: String($0)) })
        if let nameStartsWith = query.nameStartsWith {
            items.append(URLQueryItem(name: "nameStartsWith", value: nameStartsWith))
        }
        if let searchTerm = query.searchTerm { items.append(URLQueryItem(name: "searchTerm", value: searchTerm)) }
        let data = try await client.send(APIRequest(method: "GET", path: "/Items", query: items))
        let decoded = try ResilientItemDecoder.mediaItems(from: data, log: log)
        return Page(items: decoded.items, totalCount: decoded.totalCount)
    }

    public func resume(limit: Int) async throws(APIError) -> [MediaItem] {
        try await list(
            path: "/UserItems/Resume",
            query: [
                URLQueryItem(name: "mediaTypes", value: "Video"), URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "fields", value: "PrimaryImageAspectRatio,Overview"),
                URLQueryItem(name: "enableImageTypes", value: "Primary,Backdrop,Thumb,Logo"),
                URLQueryItem(name: "enableUserData", value: "true"),
            ]
        )
    }

    public func nextUp(limit: Int) async throws(APIError) -> [MediaItem] {
        try await list(
            path: "/Shows/NextUp",
            query: [
                URLQueryItem(name: "enableResumable", value: "false"),
                URLQueryItem(name: "enableRewatching", value: "false"),
                URLQueryItem(name: "fields", value: "PrimaryImageAspectRatio,Overview"),
                URLQueryItem(name: "enableImageTypes", value: "Primary,Backdrop,Thumb,Logo"),
                URLQueryItem(name: "enableUserData", value: "true"),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
    }

    public func latest(in library: Library.ID, limit: Int) async throws(APIError) -> [MediaItem] {
        let data = try await client.send(
            APIRequest(
                method: "GET",
                path: "/Items/Latest",
                query: [
                    URLQueryItem(name: "parentId", value: library),
                    URLQueryItem(name: "limit", value: String(limit)),
                    URLQueryItem(name: "groupItems", value: "true"),
                ]
            )
        )
        return try ResilientItemDecoder.mediaItems(from: data, log: log).items
    }

    public func seasons(series: MediaItem.ID) async throws(APIError) -> [MediaItem] {
        try await list(
            path: "/Shows/\(try validatedItemID(series))/Seasons",
            query: [URLQueryItem(name: "enableUserData", value: "true")]
        )
    }

    public func episodes(series: MediaItem.ID, season: MediaItem.ID?) async throws(APIError) -> [MediaItem] {
        var query: [URLQueryItem] = []
        if let season { query.append(URLQueryItem(name: "seasonId", value: season)) }
        return try await list(path: "/Shows/\(try validatedItemID(series))/Episodes", query: query)
    }

    public func item(id: MediaItem.ID) async throws(APIError) -> MediaItem {
        let dto = try await client.send(
            APIRequest(method: "GET", path: "/Items/\(try validatedItemID(id))"), as: BaseItemDTO.self)
        guard let item = DTOMapper.mediaItem(dto, log: log) else { throw APIError.decoding }
        return item
    }

    public func similar(id: MediaItem.ID, limit: Int) async throws(APIError) -> [MediaItem] {
        try await list(
            path: "/Items/\(try validatedItemID(id))/Similar",
            query: [URLQueryItem(name: "limit", value: String(limit))]
        )
    }

    public func filters(in library: Library.ID) async throws(APIError) -> ItemFilterSet {
        let dto = try await client.send(
            APIRequest(method: "GET", path: "/Items/Filters2", query: [URLQueryItem(name: "parentId", value: library)]),
            as: QueryFiltersDTO.self
        )
        return ItemFilterSet(
            genres: (dto.Genres ?? []).prefix(MetadataPolicy.genresMax).map {
                MetadataSanitizer.displayText($0, limit: MetadataPolicy.genreMax)
            }, years: dto.Years ?? [])
    }

    public func setPlayed(_ id: MediaItem.ID, _ played: Bool) async throws(APIError) {
        let method = played ? "POST" : "DELETE"
        _ = try await client.send(
            APIRequest(method: method, path: "/UserPlayedItems/\(try validatedItemID(id))"), as: EmptyResponse.self)
    }

    public func setFavorite(_ id: MediaItem.ID, _ favorite: Bool) async throws(APIError) {
        let method = favorite ? "POST" : "DELETE"
        _ = try await client.send(
            APIRequest(method: method, path: "/UserFavoriteItems/\(try validatedItemID(id))"), as: EmptyResponse.self)
    }

    public func userData(id: MediaItem.ID) async throws(APIError) -> UserItemState {
        let dto = try await client.send(
            APIRequest(method: "GET", path: "/UserItems/\(try validatedItemID(id))/UserData"), as: UserItemDataDTO.self)
        return UserItemState(
            played: dto.Played ?? false,
            playbackPosition: Ticks.positionDuration(from: dto.PlaybackPositionTicks ?? 0, log: log),
            isFavorite: dto.IsFavorite ?? false,
            unplayedCount: dto.UnplayedItemCount,
            playedPercentage: dto.PlayedPercentage
        )
    }

    public func updateUserData(id: MediaItem.ID, position: Duration, played: Bool) async throws(APIError) {
        let body = try encodeJSON(
            UserDataWrite(PlaybackPositionTicks: Ticks.outboundPositionTicks(from: position), Played: played)
        )
        _ = try await client.send(
            APIRequest(method: "POST", path: "/UserItems/\(try validatedItemID(id))/UserData", body: body),
            as: EmptyResponse.self)
    }

    private func list(path: String, query: [URLQueryItem]) async throws(APIError) -> [MediaItem] {
        let data = try await client.send(APIRequest(method: "GET", path: path, query: query))
        return try ResilientItemDecoder.mediaItems(from: data, log: log).items
    }
}

public struct JellyfinSearchService: SearchService {
    public var client: any JellyfinAPIClient
    public var log: any GlassfinLog
    public init(client: any JellyfinAPIClient, log: any GlassfinLog = SilentLog()) {
        self.client = client
        self.log = log
    }

    public func hints(term: String, limit: Int) async throws(APIError) -> [MediaItem] {
        let data = try await client.send(QueryTransport.searchHints(term: term, limit: limit))
        return try ResilientItemDecoder.searchHints(from: data, log: log)
    }
}

public struct JellyfinPlaybackInfoService: PlaybackInfoService {
    public var client: any JellyfinAPIClient
    public var server: URL
    public init(client: any JellyfinAPIClient, server: URL) {
        self.client = client
        self.server = server
    }

    public func playbackInfo(itemID: String, start: Duration, maxBitrate: Int) async throws(APIError) -> PlaybackSource
    {
        let body = try encodeJSON(
            PlaybackInfoBody(
                StartTimeTicks: Ticks.outboundPositionTicks(from: start),
                MaxStreamingBitrate: maxBitrate,
                EnableDirectPlay: true,
                EnableDirectStream: true,
                EnableTranscoding: true,
                AllowVideoStreamCopy: true,
                AllowAudioStreamCopy: true
            )
        )
        let dto = try await client.send(
            APIRequest(method: "POST", path: "/Items/\(try validatedItemID(itemID))/PlaybackInfo", body: body),
            as: PlaybackInfoResponseDTO.self
        )
        guard let source = DTOMapper.playbackSource(dto, server: server) else { throw APIError.decoding }
        return source
    }

    public func mediaSegments(itemID: String) async throws(APIError) -> [MediaSegment] {
        let dto = try await client.send(
            APIRequest(method: "GET", path: "/MediaSegments/\(try validatedItemID(itemID))"), as: [MediaSegmentDTO].self
        )
        return dto.compactMap(DTOMapper.segment)
    }

    public func bitrateTest(size: Int) async throws(APIError) -> Data {
        try await client.send(
            APIRequest(
                method: "GET", path: "/Playback/BitrateTest", query: [URLQueryItem(name: "size", value: String(size))]))
    }
}

public struct JellyfinReportingService: ReportingService {
    public var client: any JellyfinAPIClient
    public init(client: any JellyfinAPIClient) { self.client = client }

    public func started(itemID: String, position: Duration, playSessionID: String) async throws(APIError) {
        try await post(
            "/Sessions/Playing",
            body: PlaybackReportBody(
                ItemId: itemID,
                PositionTicks: Ticks.outboundPositionTicks(from: position),
                PlaySessionId: playSessionID,
                IsPaused: false,
                Failed: nil
            )
        )
    }

    public func progress(itemID: String, position: Duration, playSessionID: String, paused: Bool) async throws(APIError)
    {
        try await post(
            "/Sessions/Playing/Progress",
            body: PlaybackReportBody(
                ItemId: itemID,
                PositionTicks: Ticks.outboundPositionTicks(from: position),
                PlaySessionId: playSessionID,
                IsPaused: paused,
                Failed: nil
            )
        )
    }

    public func stopped(itemID: String, position: Duration, playSessionID: String, failed: Bool) async throws(APIError)
    {
        try await post(
            "/Sessions/Playing/Stopped",
            body: PlaybackReportBody(
                ItemId: itemID,
                PositionTicks: Ticks.outboundPositionTicks(from: position),
                PlaySessionId: playSessionID,
                IsPaused: nil,
                Failed: failed
            )
        )
    }

    public func ping(playSessionID: String) async throws(APIError) {
        _ = try await client.send(
            APIRequest(
                method: "POST", path: "/Sessions/Playing/Ping",
                query: [URLQueryItem(name: "playSessionId", value: playSessionID)]),
            as: EmptyResponse.self
        )
    }

    private func post(_ path: String, body: PlaybackReportBody) async throws(APIError) {
        let data = try encodeJSON(body)
        _ = try await client.send(APIRequest(method: "POST", path: path, body: data), as: EmptyResponse.self)
    }
}

public struct JellyfinImageService: Sendable {
    public var server: URL
    public var identity: ClientIdentity
    public init(server: URL, identity: ClientIdentity) {
        self.server = server
        self.identity = identity
    }

    /// Images are loaded with our URLSession and the Authorization header, never `ApiKey`.
    public func imageRequest(itemID: String, imageType: String, maxWidth: Int?) throws -> PreparedMediaRequest {
        var query: [URLQueryItem] = []
        if let maxWidth { query.append(URLQueryItem(name: "maxWidth", value: String(maxWidth))) }
        return try MediaRequestBuilder.prepare(
            server: server,
            path: "/Items/\(try validatedItemID(itemID))/Images/\(imageType)",
            query: query,
            identity: identity,
            mode: .header
        )
    }
}

public struct JellyfinMediaURLService: Sendable {
    public var server: URL
    public var identity: ClientIdentity
    public init(server: URL, identity: ClientIdentity) {
        self.server = server
        self.identity = identity
    }

    public func stream(
        itemID: String,
        mediaSourceID: String,
        playSessionID: String,
        mode: MediaAuthorizationMode
    ) throws -> PreparedMediaRequest {
        try MediaRequestBuilder.prepare(
            server: server,
            path: "/Videos/\(try validatedItemID(itemID))/stream",
            query: [
                URLQueryItem(name: "static", value: "true"),
                URLQueryItem(name: "mediaSourceId", value: mediaSourceID),
                URLQueryItem(name: "playSessionId", value: playSessionID),
                URLQueryItem(name: "deviceId", value: identity.deviceID),
            ],
            identity: identity,
            mode: mode
        )
    }

    public func trickplay(itemID: String, width: Int, index: Int, mediaSourceID: String) throws -> PreparedMediaRequest
    {
        try MediaRequestBuilder.prepare(
            server: server,
            path: "/Videos/\(try validatedItemID(itemID))/Trickplay/\(width)/\(index).jpg",
            query: [URLQueryItem(name: "mediaSourceId", value: mediaSourceID)],
            identity: identity,
            mode: .header
        )
    }

    public func subtitles(itemID: String, mediaSourceID: String, index: Int) throws -> PreparedMediaRequest {
        try MediaRequestBuilder.prepare(
            server: server,
            path:
                "/Videos/\(try validatedItemID(itemID))/\(try validatedItemID(mediaSourceID))/Subtitles/\(index)/Stream.vtt",
            identity: identity,
            mode: .header
        )
    }
}

struct AuthNameBody: Encodable {
    var Username: String
    var Pw: String
}
struct QuickConnectBody: Encodable { var Secret: String }
struct CapabilitiesBody: Encodable {
    var PlayableMediaTypes: [String]
    var SupportsMediaControl: Bool
    var SupportedCommands: [String]
}
struct UserDataWrite: Encodable {
    var PlaybackPositionTicks: Int64
    var Played: Bool
}
struct PlaybackInfoBody: Encodable {
    var StartTimeTicks: Int64
    var MaxStreamingBitrate: Int
    var EnableDirectPlay: Bool
    var EnableDirectStream: Bool
    var EnableTranscoding: Bool
    var AllowVideoStreamCopy: Bool
    var AllowAudioStreamCopy: Bool
}
struct PlaybackReportBody: Encodable {
    var ItemId: String
    var PositionTicks: Int64
    var PlaySessionId: String
    var IsPaused: Bool?
    var Failed: Bool?
}
