import CoreModels
import CoreNetworking
import CorePlayback
import Foundation

@MainActor
final class AuthPlaybackSession: PlaybackSessionProviding {
    let serverURL: URL
    let userID: String
    let identity: ClientIdentity
    let trust: ServerTrustClass
    let apiClient: any JellyfinAPIClient
    private let app: AppState

    init(
        serverURL: URL, userID: String, identity: ClientIdentity, trust: ServerTrustClass,
        apiClient: any JellyfinAPIClient, app: AppState
    ) {
        self.serverURL = serverURL
        self.userID = userID
        self.identity = identity
        self.trust = trust
        self.apiClient = apiClient
        self.app = app
    }

    func sessionExpired() async { app.handle(.unauthorized) }
}

extension AppState {
    public func recordPlaybackStop(_ stop: PlaybackStop) async {
        let previous = await userData.state(for: stop.itemID)
        await userData.recordPlayback(
            id: stop.itemID, position: stop.finished ? .zero : stop.position,
            played: stop.finished || previous?.played == true, log: SilentLog())
        await responses.invalidateAll()
    }
}
