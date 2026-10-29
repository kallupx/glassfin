#if DEBUG
    import CoreModels
    import CoreNetworking
    import CorePlayback
    import Foundation

    /// Exercises the production coordinator and reporting path without any network or AV decoding.
    public enum MockPlaybackFactory {
        @MainActor
        public static func makeCoordinator(
            cannotPlay: Bool = false, nextEpisodePrompt: Bool = false,
            onStopped: (@MainActor (PlaybackStop) async -> Void)? = nil
        ) -> PlaybackCoordinator {
            let session = MockPlaybackSession(
                serverURL: URL(string: "https://fixture.example")!, userID: LibraryFixtureClient.id(2),
                identity: ClientIdentity(deviceName: "Fixture", deviceID: "fixture", version: "1", token: "fixture"),
                apiClient: MockAPIClient { request throws(APIError) in
                    if cannotPlay { throw .network }
                    if nextEpisodePrompt, let data = nextEpisodeResponse(for: request) { return data }
                    return response(for: request)
                })
            return PlaybackCoordinator(
                session: session, engine: MockPlaybackEngine(), origin: MockPlaybackOrigin(),
                timer: ManualPlaybackTimer(), onStopped: onStopped)
        }

        /// S2E5 resumes at an early fixture Outro so the real ten-second prompt is immediately reachable.
        private static func nextEpisodeResponse(for request: APIRequest) -> Data? {
            guard request.method == "GET" else { return nil }
            let currentID = LibraryFixtureClient.episodeID(season: 2, episode: 5)
            let nextID = LibraryFixtureClient.episodeID(season: 2, episode: 6)
            let current: [String: Any] = [
                "Id": currentID, "Type": "Episode", "SeriesId": LibraryFixtureClient.series,
                "ParentIndexNumber": 2, "IndexNumber": 5, "Name": "Episode 5", "RunTimeTicks": 27_000_000_000,
                "MediaStreams": [["Type": "Video", "Codec": "h264"]],
                "UserData": ["PlaybackPositionTicks": 10_000_000_000],
            ]
            let value: [String: Any]
            if request.path == "/Users/\(LibraryFixtureClient.id(2))/Items/\(currentID)" {
                value = current
            } else if request.path == "/MediaSegments/\(currentID)" {
                value = ["Items": [["Type": "Outro", "StartTicks": 10_000_000_000, "EndTicks": 27_000_000_000]]]
            } else if request.path == "/Shows/\(LibraryFixtureClient.series)/Episodes" {
                value = [
                    "Items": [
                        current,
                        [
                            "Id": nextID, "Type": "Episode", "SeriesId": LibraryFixtureClient.series,
                            "ParentIndexNumber": 2, "IndexNumber": 6, "Name": "Episode 6",
                        ],
                    ]
                ]
            } else {
                return nil
            }
            return try? JSONSerialization.data(withJSONObject: value)
        }

        public static func response(for request: APIRequest) -> Data {
            if request.path.hasSuffix("/PlaybackInfo") {
                return Data(
                    #"{"MediaSources":[{"Id":"00000000000000000000000000000003","Container":"mp4","SupportsDirectPlay":true,"MediaStreams":[{"Type":"Video","Codec":"h264"},{"Type":"Audio","Codec":"aac"}]}],"PlaySessionId":"fixture-session"}"#
                        .utf8)
            }
            if request.method == "GET" {
                return Data(#"{"MediaStreams":[{"Type":"Video","Codec":"h264"}]}"#.utf8)
            }
            return Data()
        }
    }
#endif
