import CoreModels
import CoreNetworking
import Foundation

public protocol LibraryImageLoading: Sendable {
    func data(for request: LibraryImageRequest) async throws(APIError) -> Data
}

/// Compressed image bytes are persisted only in DiskImageCache using the tuple digest.
public actor LibraryImageLoader: LibraryImageLoading {
    private let client: any JellyfinAPIClient
    private let cache: DiskImageCache

    public init(client: any JellyfinAPIClient, cache: DiskImageCache) {
        self.client = client
        self.cache = cache
    }

    public func data(for request: LibraryImageRequest) async throws(APIError) -> Data {
        if Task.isCancelled { throw .cancelled }
        if let data = await cache.data(for: request.cacheKey), data.count <= MetadataPolicy.imageMaxBytes {
            return data
        }
        let data = try await client.send(request.apiRequest)
        if Task.isCancelled { throw .cancelled }
        guard data.count <= MetadataPolicy.imageMaxBytes else { throw .decoding }
        await cache.store(key: request.cacheKey, data: data)
        return data
    }
}
