import CoreAPI
import CoreModels
import CoreNetworking
import Foundation
import GlassfinServices

/// Session-owned dependencies shared by search, result images and its detail destination.
@MainActor
public final class SearchFeature {
    public let model: SearchViewModel
    public let images: SearchImageLoader
    public let serverID: String
    private let client: any JellyfinAPIClient
    private let app: AppState

    public init(app: AppState, session: UserSession, client: any JellyfinAPIClient, backend: (any SearchBackend)? = nil)
    {
        let scoped = SessionAPIClient(
            inner: RetryingAPIClient(inner: SearchQueryClient(inner: client), clock: SystemGlassfinClock()), app: app)
        self.client = scoped
        self.app = app
        serverID = session.server.id
        model = SearchViewModel(backend: backend ?? ItemsSearchBackend(client: scoped), app: app)
        images = SearchImageLoader(client: scoped, disk: app.imageDisk)
    }

    public func detail(_ item: MediaItem) async throws(APIError) -> MediaItem {
        guard let id = ItemID(item.id) else { throw .invalidItemID }
        let dto = try await client.send(
            APIRequest(method: "GET", path: "/Items/\(id.value)"), as: BaseItemDTO.self)
        guard let result = DTOMapper.mediaItem(dto, log: SilentLog()) else { throw .decoding }
        return result.searchDisplayItem
    }

    public func handle(_ error: APIError) {
        app.handle(AppErrorMapping.map(error, context: .authenticated, deviceOffline: app.connectivity == .offline))
    }
}
