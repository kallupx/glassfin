import CoreModels
import CoreNetworking
import Foundation

public enum SearchImageError: Error, Sendable, Equatable {
    case oversized
    case invalidImage
}

/// Encoded bytes live only in DiskImageCache. The HTTP transport's URLCache is disabled.
public actor SearchImageLoader {
    private let client: any JellyfinAPIClient
    private let disk: DiskImageCache

    public init(client: any JellyfinAPIClient, disk: DiskImageCache) {
        self.client = client
        self.disk = disk
    }

    public func bytes(for image: ItemImageRequest) async throws -> Data {
        if let data = await disk.data(for: image.cacheKey) { return data }
        let data: Data
        do { data = try await client.send(image.request) } catch APIError.responseTooLarge {
            throw SearchImageError.oversized
        }
        guard data.count <= MetadataPolicy.imageMaxBytes else { throw SearchImageError.oversized }
        try Task.checkCancellation()
        _ = await disk.store(imageKey: image.cacheKey, data: data)
        return data
    }
}

/// The same option dictionary is tested on Linux and passed directly to ImageIO on Apple.
public enum SearchImageDecoder {
    public static func thumbnailOptions(maximumPixelSize: Int) -> [String: Any] {
        [
            "kCGImageSourceCreateThumbnailFromImageAlways": true,
            "kCGImageSourceThumbnailMaxPixelSize": max(1, maximumPixelSize),
            "kCGImageSourceCreateThumbnailWithTransform": true,
            "kCGImageSourceShouldCacheImmediately": true,
        ]
    }
}

#if canImport(ImageIO)
    import CoreGraphics
    import ImageIO

    public struct DecodedSearchImage: @unchecked Sendable {
        public let image: CGImage
        public let decodedOffMainThread: Bool
    }

    extension SearchImageDecoder {
        public static func downsample(_ data: Data, maximumPixelSize: Int) async throws -> DecodedSearchImage {
            guard data.count <= MetadataPolicy.imageMaxBytes else { throw SearchImageError.oversized }
            let work = Task.detached(priority: .utility) {
                try Task.checkCancellation()
                let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
                    throw SearchImageError.invalidImage
                }
                let options = thumbnailOptions(maximumPixelSize: maximumPixelSize) as CFDictionary
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
                    throw SearchImageError.invalidImage
                }
                try Task.checkCancellation()
                return DecodedSearchImage(image: image, decodedOffMainThread: !Thread.isMainThread)
            }
            return try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                work.cancel()
            }
        }
    }
#endif
