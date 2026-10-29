import CoreModels
import CoreNetworking
import Foundation

#if canImport(ImageIO)
    import ImageIO
#endif

public protocol HomeImageLoading: Sendable {
    func data(for resource: JellyfinImageResource) async throws -> Data
}

/// Only the disk image LRU stores compressed bytes. URLSession's URL cache is disabled.
public struct HomeImageLoader: HomeImageLoading {
    private let client: any JellyfinAPIClient
    private let disk: DiskImageCache

    public init(client: any JellyfinAPIClient, disk: DiskImageCache) {
        self.client = client
        self.disk = disk
    }

    public func data(for resource: JellyfinImageResource) async throws -> Data {
        try Task.checkCancellation()
        let cacheInterval = DevicePerformance.begin(.posterCache)
        let cached = await disk.data(for: resource.cacheKey)
        cacheInterval?.end(completed: cached != nil)
        if let data = cached {
            try ImageDataPolicy.validate(data)
            return data
        }
        let networkInterval = DevicePerformance.begin(.posterNetwork)
        defer { networkInterval?.end(completed: false) }
        let data: Data
        do {
            data = try await client.send(resource.request())
        } catch APIError.responseTooLarge {
            throw ImageDataError.oversized
        }
        try Task.checkCancellation()
        try ImageDataPolicy.validate(data)
        await disk.store(key: resource.cacheKey, data: data)
        networkInterval?.end()
        return data
    }
}

/// The same option dictionary is tested on Linux and passed directly to ImageIO on Apple platforms.
public enum HomeImageDecoder {
    public static func thumbnailOptions(width: Int, height: Int) -> [String: Any] {
        [
            "kCGImageSourceCreateThumbnailFromImageAlways": true,
            "kCGImageSourceCreateThumbnailWithTransform": true,
            "kCGImageSourceThumbnailMaxPixelSize": max(1, max(width, height)),
            "kCGImageSourceShouldCacheImmediately": true,
        ]
    }

    #if canImport(ImageIO)
        /// Thumbnail creation runs on a worker executor, before SwiftUI sees an image.
        public static func downsample(_ data: Data, width: Int, height: Int) async throws -> CGImage {
            let child = Task.detached(priority: .utility) {
                let interval = DevicePerformance.begin(.imageDecode)
                defer { interval?.end(completed: false) }
                try Task.checkCancellation()
                try ImageDataPolicy.validate(data)
                let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
                    throw ImageDataError.invalidImage
                }
                let options = thumbnailOptions(width: width, height: height) as CFDictionary
                guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
                    throw ImageDataError.invalidImage
                }
                interval?.end()
                return thumbnail
            }
            return try await withTaskCancellationHandler {
                try await child.value
            } onCancel: {
                child.cancel()
            }
        }
    #endif
}
