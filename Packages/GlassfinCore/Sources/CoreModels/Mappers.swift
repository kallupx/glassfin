import Foundation

public enum DTOMapper {
    public static func serverInfo(_ dto: PublicSystemInfoDTO, url: URL) -> ServerInfo? {
        guard let id = dto.Id, let name = dto.ServerName, let version = dto.Version.flatMap(SemVer.init(parsing:))
        else {
            return nil
        }
        return ServerInfo(id: id, name: name, url: url, version: version)
    }

    public static func session(auth: AuthenticationResultDTO, serverURL: URL, fallbackServerName: String)
        -> AuthenticatedSession?
    {
        guard let token = auth.AccessToken, let user = auth.User, let userID = user.Id else { return nil }
        let server = ServerInfo(
            id: auth.ServerId ?? "",
            name: fallbackServerName,
            url: serverURL,
            version: SemVer(major: 0, minor: 0, patch: 0)
        )
        let session = UserSession(
            server: server,
            userID: userID,
            userName: user.Name ?? "",
            isAdministrator: user.Policy?.IsAdministrator ?? false
        )
        return AuthenticatedSession(session: session, accessToken: token)
    }

    public static func userSession(_ user: UserDTO, server: ServerInfo) -> UserSession? {
        guard let id = user.Id else { return nil }
        return UserSession(
            server: server,
            userID: id,
            userName: user.Name ?? "",
            isAdministrator: user.Policy?.IsAdministrator ?? false
        )
    }

    public static func mediaItem(_ dto: BaseItemDTO, log: any GlassfinLog) -> MediaItem? {
        guard let id = dto.Id else { return nil }
        let positionTicks = dto.UserData?.PlaybackPositionTicks ?? 0
        let images = ImageSet(
            primaryTag: dto.ImageTags?.Primary,
            backdropTags: dto.BackdropImageTags ?? [],
            logoTag: dto.ImageTags?.Logo,
            thumbTag: dto.ImageTags?.Thumb,
            primaryBlurHash: dto.ImageBlurHashes?.Primary?.values.first
        )
        let userData = UserItemState(
            played: dto.UserData?.Played ?? false,
            playbackPosition: Ticks.positionDuration(from: positionTicks, log: log),
            isFavorite: dto.UserData?.IsFavorite ?? false,
            unplayedCount: dto.UserData?.UnplayedItemCount,
            playedPercentage: dto.UserData?.PlayedPercentage
        )
        return MediaItem(
            id: id,
            kind: MediaKind.from(serverType: dto.`Type` ?? ""),
            name: MetadataPolicy.clean(dto.Name ?? "", limit: MetadataPolicy.nameMax),
            overview: dto.Overview.map { MetadataPolicy.clean($0, limit: MetadataPolicy.overviewMax) },
            seriesID: dto.SeriesId,
            seasonID: dto.SeasonId,
            indexNumber: dto.IndexNumber,
            parentIndexNumber: dto.ParentIndexNumber,
            runtime: Ticks.runtimeDuration(from: dto.RunTimeTicks),
            productionYear: dto.ProductionYear,
            officialRating: dto.OfficialRating,
            communityRating: dto.CommunityRating,
            images: images,
            userData: userData,
            trickplay: trickplay(dto.Trickplay),
            chapters: chapters(dto.Chapters, log: log),
            detail: ItemMetadata(
                taglines: dto.Taglines ?? [], genres: dto.Genres ?? [],
                people: (dto.People ?? []).map { ItemPerson(name: $0.Name ?? "", role: $0.Role) },
                studios: (dto.Studios ?? []).compactMap(\.Name),
                streams: (dto.MediaStreams ?? dto.MediaSources?.first?.MediaStreams ?? []).map {
                    ItemStream(
                        id: $0.Index ?? 0, kind: $0.Type ?? "", title: $0.DisplayTitle,
                        language: $0.Language, codec: $0.Codec, profile: $0.Profile, channels: $0.Channels,
                        width: $0.Width, height: $0.Height, videoRange: $0.VideoRangeType,
                        dolbyVisionProfile: $0.DvProfile)
                })
        )
    }

    public static func library(_ dto: BaseItemDTO) -> Library? {
        guard let id = dto.Id else { return nil }
        return Library(
            id: id, name: MetadataPolicy.clean(dto.Name ?? "", limit: MetadataPolicy.nameMax),
            collectionType: dto.CollectionType)
    }

    public static func page(_ dto: QueryResultDTO, log: any GlassfinLog) -> Page<MediaItem> {
        Page(items: (dto.Items ?? []).compactMap { mediaItem($0, log: log) }, totalCount: dto.TotalRecordCount)
    }

    public static func segment(_ dto: MediaSegmentDTO) -> MediaSegment? {
        let start = Ticks.runtimeDuration(from: dto.StartTicks) ?? .zero
        guard let end = Ticks.runtimeDuration(from: dto.EndTicks), end > start else {
            return nil
        }
        return MediaSegment(kind: MediaSegment.kind(from: dto.`Type` ?? ""), range: start..<end)
    }

    public static func playbackSource(_ dto: PlaybackInfoResponseDTO, server: URL) -> PlaybackSource? {
        guard let source = dto.MediaSources?.first, let id = source.Id else { return nil }
        let method: PlayMethod
        if source.SupportsDirectPlay == true {
            method = .directPlay
        } else if source.SupportsDirectStream == true {
            method = .directStream
        } else {
            method = .transcode
        }
        let relative = source.TranscodingUrl ?? source.DirectStreamUrl
        let url = relative.flatMap { resolve(server: server, relative: $0) }
        let streams = source.MediaStreams ?? []
        return PlaybackSource(
            mediaSourceID: id,
            playSessionID: dto.PlaySessionId ?? "",
            method: method,
            url: url,
            audioTracks: tracks(streams, type: "Audio"),
            subtitleTracks: tracks(streams, type: "Subtitle"),
            transcodeReasons: source.TranscodeReasons ?? []
        )
    }

    public static func resolve(server: URL, relative: String) -> URL? {
        if let absolute = URL(string: relative), absolute.scheme != nil {
            return absolute
        }
        guard var components = URLComponents(url: server, resolvingAgainstBaseURL: false) else { return nil }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        if relative.hasPrefix("/") {
            components.path = basePath + relative
            components.query = nil
            components.percentEncodedQuery = nil
            if let question = relative.firstIndex(of: "?") {
                let pathPart = String(relative[..<question])
                let queryPart = String(relative[relative.index(after: question)...])
                components.path = basePath + pathPart
                components.percentEncodedQuery = queryPart
            }
        } else {
            components.path = basePath + "/" + relative
        }
        return components.url
    }

    private static func tracks(_ streams: [MediaStreamDTO], type: String) -> [Track] {
        streams.filter { $0.`Type` == type }.map { stream in
            Track(
                id: stream.Index ?? 0,
                displayTitle: stream.DisplayTitle.map(MetadataSanitizer.plainText),
                language: stream.Language,
                codec: stream.Codec
            )
        }
    }

    private static func chapters(_ chapters: [ChapterDTO]?, log: any GlassfinLog) -> [ChapterMark] {
        (chapters ?? []).map { chapter in
            ChapterMark(
                name: chapter.Name.map(MetadataSanitizer.plainText),
                start: Ticks.positionDuration(from: chapter.StartPositionTicks ?? 0, log: log)
            )
        }
    }

    private static func trickplay(_ raw: [String: [String: TrickplayInfoDTO]]?) -> [Int: TrickplayInfo]? {
        guard let raw else { return nil }
        var mapped: [Int: TrickplayInfo] = [:]
        for widths in raw.values {
            for (key, info) in widths {
                guard let width = Int(key) ?? info.Width else { continue }
                let intervalTicks = info.Interval ?? 0
                mapped[width] = TrickplayInfo(
                    width: info.Width ?? width,
                    height: info.Height ?? 0,
                    tileWidth: info.TileWidth ?? 0,
                    tileHeight: info.TileHeight ?? 0,
                    thumbnailCount: info.ThumbnailCount ?? 0,
                    interval: Ticks.runtimeDuration(from: intervalTicks) ?? .zero
                )
            }
        }
        return mapped.isEmpty ? nil : mapped
    }
}

public enum ResponseDecoder {
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws(APIError) -> T {
        if data.isEmpty, let empty = EmptyResponse() as? T {
            return empty
        }
        if T.self == PlainText.self, let text = PlainText(value: String(decoding: data, as: UTF8.self)) as? T {
            return text
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }
}
