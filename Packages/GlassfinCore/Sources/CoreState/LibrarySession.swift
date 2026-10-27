import CoreModels
import CoreNetworking
import Foundation
import GlassfinServices
import Observation

@MainActor
@Observable
public final class LibrarySession {
    public private(set) var libraries: LoadState<[Library]> = .idle
    public let app: AppState
    public let service: any LibraryService
    public let images: any LibraryImageLoading
    public let actions: LibraryUserActions
    public let preferences: LibraryChoicesStore
    public static let directTabCount = 5
    public private(set) var playbackIntent: LibraryPlaybackIntent?
    @ObservationIgnored public var onPlayback: (@MainActor (LibraryPlaybackIntent) -> Void)?

    public func requestPlayback(_ intent: LibraryPlaybackIntent) {
        guard !app.playbackBlocked else { return }
        playbackIntent = intent
        // TODO(Q7-08): M08 supplies the presentation closure.
        onPlayback?(intent)
    }

    public init(
        app: AppState, service: any LibraryService, images: any LibraryImageLoading,
        settings: any SettingsStore, serverID: String, userID: String
    ) {
        self.app = app
        self.service = service
        self.images = images
        self.actions = LibraryUserActions(service: service, app: app)
        self.preferences = LibraryChoicesStore(settings: settings, serverID: serverID, userID: userID)
    }

    public var directLibraries: [Library] { Array((libraries.value ?? []).prefix(Self.directTabCount)) }
    public var overflowLibraries: [Library] { Array((libraries.value ?? []).dropFirst(Self.directTabCount)) }

    public func load() async {
        let generation = app.requestGeneration
        libraries = .loading(previous: libraries.value)
        do {
            let values = try await service.userViews().filter { ItemID($0.id) != nil }.map {
                Library(
                    id: $0.id, name: MetadataPolicy.clean($0.name, limit: MetadataPolicy.nameMax),
                    collectionType: $0.collectionType)
            }
            guard !Task.isCancelled, generation == app.requestGeneration else { return }
            libraries = .loaded(values)
        } catch {
            guard !Task.isCancelled, generation == app.requestGeneration else { return }
            let mapped = AppErrorMapping.map(
                error, context: .authenticated, deviceOffline: app.connectivity == .offline)
            guard mapped != .cancelled else { return }
            libraries = .failed(mapped, previous: libraries.value)
            app.handle(mapped)
        }
    }

    public func makeBrowser() -> LibraryViewModel {
        LibraryViewModel(
            library: service, userData: app.userData, responses: app.responses, app: app,
            clock: SystemGlassfinClock(), preferences: preferences)
    }
}
