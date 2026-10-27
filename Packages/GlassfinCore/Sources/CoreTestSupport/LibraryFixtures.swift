#if DEBUG
    import CoreModels
    import CoreNetworking
    import Foundation

    /// Deterministic fixture responses exercise the production service and presentation models.
    public actor LibraryFixtureClient: JellyfinAPIClient {
        public static let movieLibrary = id(10)
        public static let seriesLibrary = id(11)
        public static let series = id(1000)
        public static let seasonOne = id(2001)
        public static let seasonTwo = id(2002)
        public static let specials = id(2000)
        private let scenario: String
        private var outageInjected = false

        public init(scenario: String = "grid") { self.scenario = scenario }
        public static func id(_ value: Int) -> String { String(format: "%032x", value) }
        public static func episodeID(season: Int, episode: Int) -> String { id(30000 + season * 100 + episode) }

        public func send(_ request: APIRequest) async throws(APIError) -> Data {
            if Task.isCancelled { throw .cancelled }
            let query = Dictionary(
                request.query.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
            if request.path == "/System/Ping" { return Data("ok".utf8) }
            if request.method != "GET" { return Data("{}".utf8) }
            if request.path == "/UserViews" {
                return json([
                    "Items": (0..<7).map { index in
                        [
                            "Id": Self.id(10 + index), "Name": index == 1 ? "Series" : "Library \(index + 1)",
                            "CollectionType": index == 1 ? "tvshows" : "movies",
                        ]
                    }
                ])
            }
            if request.path == "/Items/Filters2" {
                return json(["Genres": ["Drama", "Comedy"], "Years": [2024, 2025]])
            }
            if request.path == "/Items" {
                let start = Int(query["startIndex"] ?? "0") ?? 0
                if scenario == "down", start > 0, !outageInjected {
                    outageInjected = true
                    throw .network
                }
                if scenario == "unauthorized" { throw .unauthorized }
                if query["parentId"] == Self.seriesLibrary {
                    return json(["Items": [seriesItem()], "TotalRecordCount": 1])
                }
                let total = query["filters"] == nil ? 2000 : 60
                let end = min(total, start + (Int(query["limit"] ?? "50") ?? 50))
                return json(["Items": start < end ? (start..<end).map { movie($0) } : [], "TotalRecordCount": total])
            }
            if request.path.hasSuffix("/Seasons") {
                return json(["Items": [season(0), season(1), season(2)], "TotalRecordCount": 3])
            }
            if request.path == "/Shows/NextUp" {
                return json(["Items": [episode(season: 2, number: 5)], "TotalRecordCount": 1])
            }
            if request.path.hasSuffix("/Episodes") {
                let number = query["seasonId"].flatMap { Int($0, radix: 16) }.map { $0 - 2000 }
                let episodes = (number.map { [$0] } ?? [1, 2, 0]).flatMap { season in
                    (1...8).map { episode(season: season, number: $0) }
                }
                return json(["Items": episodes, "TotalRecordCount": episodes.count])
            }
            if request.path.hasSuffix("/Similar") { return json(["Items": [movie(99)]]) }
            if request.path.hasPrefix("/Items/"), let raw = request.path.split(separator: "/").last,
                let number = Int(raw, radix: 16)
            {
                if number == 1000 { return json(seriesItem()) }
                if (2000...2002).contains(number) { return json(season(number - 2000)) }
                if number >= 30000 {
                    let offset = number - 30000
                    return json(episode(season: offset / 100, number: offset % 100))
                }
                return json(movie(number - 100))
            }
            throw .notFound
        }

        private func movie(_ number: Int) -> [String: Any] {
            [
                "Id": Self.id(100 + number), "Type": "Movie", "Name": "Movie \(number + 1)",
                "Overview": "<b>Literal overview</b> &amp; **plain text**", "RunTimeTicks": 72_000_000_000,
                "ProductionYear": 2025, "Taglines": ["A fixture film"], "Genres": ["Drama"],
                "People": [["Name": "Ada Example", "Role": "Lead"]], "Studios": [["Name": "Fixture Studio"]],
                "MediaStreams": [
                    [
                        "Index": 0, "Type": "Video", "Width": 3840, "Height": 2160, "VideoRangeType": "HDR10",
                        "DvProfile": 8,
                    ],
                    ["Index": 1, "Type": "Audio", "Codec": "DTS-HD MA", "Channels": 8],
                    ["Index": 2, "Type": "Subtitle", "Language": "fin"],
                ], "UserData": ["Played": false, "PlaybackPositionTicks": 19_300_000_000],
            ]
        }
        private func seriesItem() -> [String: Any] {
            ["Id": Self.series, "Type": "Series", "Name": "Fixture Series", "Overview": "Series overview"]
        }
        private func season(_ number: Int) -> [String: Any] {
            [
                "Id": Self.id(2000 + number), "Type": "Season", "SeriesId": Self.series, "IndexNumber": number,
                "Name": "Season \(number)",
            ]
        }
        private func episode(season: Int, number: Int) -> [String: Any] {
            [
                "Id": Self.episodeID(season: season, episode: number), "Type": "Episode", "SeriesId": Self.series,
                "SeasonId": Self.id(2000 + season), "ParentIndexNumber": season, "IndexNumber": number,
                "Name": "Episode \(number)", "Overview": "Overview \(season)-\(number)", "RunTimeTicks": 27_000_000_000,
                "UserData": [
                    "Played": season == 1 || (season == 2 && number < 5),
                    "PlaybackPositionTicks": season == 2 && number == 5 ? 10_000_000_000 : 0,
                ],
            ]
        }
        private func json(_ value: Any) -> Data {
            (try? JSONSerialization.data(withJSONObject: value)) ?? Data()
        }
    }
#endif
