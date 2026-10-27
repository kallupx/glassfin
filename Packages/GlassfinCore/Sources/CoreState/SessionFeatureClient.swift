import CoreModels
import CoreNetworking
import Foundation

/// Every feature request, including images and mutations, participates in session cancellation.
@MainActor
public final class SessionFeatureClient: JellyfinAPIClient {
    private let inner: any JellyfinAPIClient
    private let app: AppState
    private let sessionGeneration: Int

    public init(inner: any JellyfinAPIClient, app: AppState) {
        self.inner = inner
        self.app = app
        self.sessionGeneration = app.requestGeneration
    }

    public func send(_ request: APIRequest) async throws(APIError) -> Data {
        guard sessionGeneration == app.requestGeneration, !Task.isCancelled else { throw .cancelled }
        let inner = inner
        let operation = Task { () -> Result<Data, APIError> in
            do { return .success(try await inner.send(request)) } catch let error as APIError {
                return .failure(error)
            } catch { return .failure(.network) }
        }
        let watcher = Task {
            await withTaskCancellationHandler {
                _ = await operation.value
            } onCancel: {
                operation.cancel()
            }
        }
        let identifier = app.scope.track(watcher)
        defer { app.scope.remove(identifier) }
        let result = await withTaskCancellationHandler {
            await operation.value
        } onCancel: {
            operation.cancel()
        }
        guard sessionGeneration == app.requestGeneration, !Task.isCancelled else { throw .cancelled }
        switch result {
        case .success(let data): return data
        case .failure(let error):
            let mapped = AppErrorMapping.map(
                error, context: .authenticated, deviceOffline: app.connectivity == .offline)
            app.handle(mapped)
            throw error
        }
    }
}
