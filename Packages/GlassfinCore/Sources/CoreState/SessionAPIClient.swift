import CoreModels
import CoreNetworking
import Foundation

/// All content calls (including images and detail) share the session cancellation scope.
/// Handle a 401 before propagating it, even if a newer search has replaced its caller.
public struct SessionAPIClient: JellyfinAPIClient {
    private let inner: any JellyfinAPIClient
    private let app: AppState

    public init(inner: any JellyfinAPIClient, app: AppState) {
        self.inner = inner
        self.app = app
    }

    public func send(_ request: APIRequest) async throws(APIError) -> Data {
        let (generation, signedIn, scope) = await MainActor.run {
            let signedIn: Bool
            if case .signedIn = app.phase { signedIn = true } else { signedIn = false }
            return (app.requestGeneration, signedIn, app.scope)
        }
        guard signedIn, !Task.isCancelled else { throw .cancelled }
        let work = Task { try await inner.send(request) }
        let id = scope.trackCancellation { work.cancel() }
        defer { scope.untrack(id) }
        do {
            return try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                work.cancel()
            }
        } catch let error as APIError {
            if error == .unauthorized || error == .server(status: 503) {
                await MainActor.run {
                    if app.requestGeneration == generation {
                        app.handle(error == .unauthorized ? .unauthorized : .serverStarting)
                    }
                }
            }
            throw error
        } catch {
            throw .cancelled
        }
    }
}
