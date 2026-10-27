import CoreModels
import CoreNetworking
import Foundation

#if canImport(ImageIO)
    import ImageIO
#endif

public protocol HomeImageLoading: Sendable {
    func data(for resource: ImageResource) async throws -> Data
}

/// Only the disk image LRU stores compressed bytes. URLSession's URL cache is disabled.
public struct HomeImageLoader: HomeImageLoading {
    private let client: any JellyfinAPIClient
    private let disk: DiskImageCache

    public init(client: any JellyfinAPIClient, disk: DiskImageCache) {
        self.client = client
        self.disk = disk
    }

    public func data(for resource: ImageResource) async throws -> Data {
        try Task.checkCancellation()
        if let data = await disk.data(for: resource.cacheKey) {
            try ImageDataPolicy.validate(data)
            return data
        }
        let data = try await client.send(resource.request())
        try Task.checkCancellation()
        try ImageDataPolicy.validate(data)
        await disk.store(key: resource.cacheKey, data: data)
        return data
    }
}

#if canImport(ImageIO)
    /// ImageIO thumbnail creation always runs on a worker executor, before SwiftUI sees an image.
    public enum HomeImageDecoder {
        public static func downsample(_ data: Data, width: Int, height: Int) async throws -> CGImage {
            try await Task.detached(priority: .utility) {
                try Task.checkCancellation()
                try ImageDataPolicy.validate(data)
                let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
                    throw ImageDataError.invalidImage
                }
                let options =
                    [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: max(1, max(width, height)),
                        kCGImageSourceShouldCacheImmediately: true,
                    ] as CFDictionary
                guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
                    throw ImageDataError.invalidImage
                }
                return thumbnail
            }.value
        }
    }
#endif
