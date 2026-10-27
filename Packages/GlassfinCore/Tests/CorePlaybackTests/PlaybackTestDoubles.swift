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
    public var loadErrors: [APIError?] = []
    public var automaticallyReady = true
    public var automaticallyPlaying = true
    public private(set) var loadAttempts: [ResourceLoaderCarrier] = []
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
        loadAttempts.append(carrier)
        if !loadErrors.isEmpty {
            if let error = loadErrors.removeFirst() { throw error }
        } else if let loadError {
            throw loadError
        }
        loads.append((carrier, startAt))
        position = startAt
        if automaticallyReady { emit(.ready) }
    }

    public func play() { if automaticallyPlaying { emit(.playing) } }
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
    private var responses: [OriginMediaResponse] = []
    public func setResponses(_ values: [OriginMediaResponse]) { responses = values }
    public var response: OriginMediaResponse
    public init(response: OriginMediaResponse = OriginMediaResponse(status: 200)) {
        self.response = response
    }
    public func fetch(_ request: OriginMediaRequest) async throws(APIError) -> OriginMediaResponse {
        requests.append(request)
        return responses.isEmpty ? response : responses.removeFirst()
    }
}

actor PoCAPIClient: JellyfinAPIClient {
    private(set) var calls: [APIRequest] = []
    var handler: @Sendable (APIRequest) async throws(APIError) -> Data
    init(handler: @escaping @Sendable (APIRequest) async throws(APIError) -> Data) {
        self.handler = handler
    }
    func setHandler(_ handler: @escaping @Sendable (APIRequest) async throws(APIError) -> Data) {
        self.handler = handler
    }
    func send(_ request: APIRequest) async throws(APIError) -> Data {
        calls.append(request)
        return try await handler(request)
    }
}
