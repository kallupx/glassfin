#if DEBUG
    import CoreModels
    import CoreNetworking
    import CorePlayback
    import Foundation

    @MainActor
    public final class MockPlaybackSession: PlaybackSessionProviding {
        public var serverURL: URL
        public var userID: String
        public var identity: ClientIdentity
        public var trust: ServerTrustClass
        public var apiClient: any JellyfinAPIClient
        public private(set) var expirationCount = 0

        public init(
            serverURL: URL, userID: String, identity: ClientIdentity,
            trust: ServerTrustClass = .publiclyTrusted, apiClient: any JellyfinAPIClient
        ) {
            self.serverURL = serverURL
            self.userID = userID
            self.identity = identity
            self.trust = trust
            self.apiClient = apiClient
        }

        public func sessionExpired() async { expirationCount += 1 }
    }

    @MainActor
    public final class MockPlaybackEngine: PlaybackEngine {
        public var position: Duration = .zero
        public var canSeek = true
        public var loadError: APIError?
        public private(set) var loads: [(carrier: ResourceLoaderCarrier, start: Duration)] = []
        public private(set) var stopCount = 0
        private var continuation: AsyncStream<PlaybackEngineEvent>.Continuation?

        public init() {}

        public var events: AsyncStream<PlaybackEngineEvent> {
            let pair = AsyncStream<PlaybackEngineEvent>.makeStream()
            continuation = pair.continuation
            return pair.stream
        }

        public func load(_ carrier: ResourceLoaderCarrier, startAt: Duration) async throws(APIError) {
            if let loadError { throw loadError }
            loads.append((carrier, startAt))
            position = startAt
            emit(.ready)
        }

        public func play() { emit(.playing) }
        public func pause() { emit(.paused) }
        public func seek(to position: Duration) async {
            self.position = position
            emit(.seeked)
        }
        public func emit(_ event: PlaybackEngineEvent) { continuation?.yield(event) }
        public func stop() {
            stopCount += 1
            continuation?.finish()
            continuation = nil
        }
    }

    @MainActor
    public final class ManualPlaybackTimer: PlaybackProgressScheduling {
        private var tick: (@MainActor @Sendable () async -> Void)?
        public private(set) var isRunning = false
        public init() {}
        public func start(_ tick: @escaping @MainActor @Sendable () async -> Void) {
            self.tick = tick
            isRunning = true
        }
        public func cancel() {
            tick = nil
            isRunning = false
        }
        public func fire() async { await tick?() }
    }

    public actor MockPlaybackOrigin: MediaOriginClient {
        public private(set) var requests: [OriginMediaRequest] = []
        public var response: OriginMediaResponse
        public init(response: OriginMediaResponse = OriginMediaResponse(status: 200)) {
            self.response = response
        }
        public func fetch(_ request: OriginMediaRequest) async throws(APIError) -> OriginMediaResponse {
            requests.append(request)
            return response
        }
    }
#endif
