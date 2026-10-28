import CoreModels
import CoreNetworking
import Foundation

/// All Home API and image calls join the session cancellation scope. No 401 retry.
public struct HomeSessionClient: JellyfinAPIClient {
    private let inner: any JellyfinAPIClient
    private let app: AppState
    private let scope: RequestScope

    public init(inner: any JellyfinAPIClient, app: AppState, scope: RequestScope) {
        self.inner = inner
        self.app = app
        self.scope = scope
    }

    public func send(_ request: APIRequest) async throws(APIError) -> Data {
        if Task.isCancelled { throw .cancelled }
        guard case .signedIn = await app.phase else { throw .cancelled }
        let inner = inner
        let child = Task { try await inner.send(request) }
        let id = scope.track(child)
        defer { scope.untrack(id) }
        do {
            return try await withTaskCancellationHandler {
                try await child.value
            } onCancel: {
                child.cancel()
            }
        } catch {
            let failure = error as? APIError ?? .network
            if failure == .unauthorized { await app.handle(.unauthorized) }
            if failure == .server(status: 503) { await app.handle(.serverStarting) }
            throw failure
        }
    }
}
