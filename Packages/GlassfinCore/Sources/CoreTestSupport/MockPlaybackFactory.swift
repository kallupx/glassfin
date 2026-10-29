#if DEBUG
    import CoreModels
    import CoreNetworking
    import CorePlayback
    import Foundation

    /// Exercises the production coordinator and reporting path without any network or AV decoding.
    public enum MockPlaybackFactory {
        @MainActor
        public static func makeCoordinator(
            cannotPlay: Bool = false, onStopped: (@MainActor (PlaybackStop) async -> Void)? = nil
        ) -> PlaybackCoordinator {
            let session = MockPlaybackSession(
                serverURL: URL(string: "https://fixture.example")!, userID: LibraryFixtureClient.id(2),
                identity: ClientIdentity(deviceName: "Fixture", deviceID: "fixture", version: "1", token: "fixture"),
                apiClient: MockAPIClient { request throws(APIError) in
                    if cannotPlay { throw .network }
                    return response(for: request)
                })
            return PlaybackCoordinator(
                session: session, engine: MockPlaybackEngine(), origin: MockPlaybackOrigin(),
                timer: ManualPlaybackTimer(), onStopped: onStopped)
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
