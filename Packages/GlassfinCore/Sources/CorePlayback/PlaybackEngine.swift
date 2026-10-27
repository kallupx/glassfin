import CoreModels
import CoreNetworking
import Foundation

public enum PlaybackFailure: Error, Sendable, Equatable {
    case unsupportedVideo
    case couldNotPlay
    case insecureRedirect

    public var localizedKey: String {
        switch self {
        case .unsupportedVideo: PlaybackCopy.unsupportedVideoKey
        case .couldNotPlay: PlaybackCopy.couldNotPlayKey
        case .insecureRedirect: PlaybackCopy.insecureRedirectKey
        }
    }
}

public enum PlaybackState: Sendable, Equatable {
    case idle
    case loading
    case playing
    case paused
    case buffering
    case ended
    case failed(localizedKey: String)
    /// The auth provider applies S2.2 and the existing session-expired sign-in handling.
    case sessionExpired
}

public enum PlaybackEngineEvent: Sendable, Equatable {
    case ready
    case playing
    case paused
    case buffering
    case seeked
    case ended
    case failed(APIError)
}

/// The engine is created without an AVPlayer; a player is allocated only in `load`.
@MainActor
public protocol PlaybackEngine: AnyObject {
    var events: AsyncStream<PlaybackEngineEvent> { get }
    var position: Duration { get }
    var canSeek: Bool { get }
    func load(_ carrier: ResourceLoaderCarrier, startAt: Duration) async throws(APIError)
    func play()
    func pause()
    func seek(to position: Duration) async
    func stop()
}

/// M04 supplies a snapshot of the active session, without coupling playback to its implementation.
@MainActor
public protocol PlaybackSessionProviding: AnyObject {
    var serverURL: URL { get }
    var userID: String { get }
    var identity: ClientIdentity { get }
    var trust: ServerTrustClass { get }
    /// A CoreNetworking HTTPClient configured with this server's credentials and trust/pin.
    var apiClient: any JellyfinAPIClient { get }
    func sessionExpired() async
}

@MainActor
public protocol PlaybackProgressScheduling: AnyObject {
    func start(_ tick: @escaping @MainActor @Sendable () async -> Void)
    func cancel()
}

@MainActor
public final class PlaybackProgressTimer: PlaybackProgressScheduling {
    private let clock: any GlassfinClock
    private var task: Task<Void, Never>?

    public init(clock: any GlassfinClock = SystemGlassfinClock()) { self.clock = clock }

    public func start(_ tick: @escaping @MainActor @Sendable () async -> Void) {
        cancel()
        task = Task { [clock] in
            while !Task.isCancelled {
                do { try await clock.sleep(for: .seconds(10)) } catch { return }
                guard !Task.isCancelled else { return }
                await tick()
            }
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}
