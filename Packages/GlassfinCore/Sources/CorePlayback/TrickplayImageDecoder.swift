import CoreModels
import CoreNetworking
import Foundation

#if canImport(ImageIO)
    import ImageIO

    /// Decoder and decoded LRU run off the main actor. Compressed and decoded caches together
    /// stay below 104 MB; a decoded image is at most 4096 pixels on its longest edge.
    public actor TrickplayImageDecoder {
        private var images: [TrickplayTileResource: CGImage] = [:]
        private var recency: [TrickplayTileResource] = []
        private var bytes = 0
        private let maximumBytes = 64 * 1024 * 1024
        public init() {}

        public func image(data: Data, resource: TrickplayTileResource, layout: TrickplayLayout) throws -> CGImage {
            if let image = images[resource] {
                touch(resource)
                return image
            }
            try Task.checkCancellation()
            try ImageDataPolicy.validate(data)
            guard
                let source = CGImageSourceCreateWithData(
                    data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                let width = properties[kCGImagePropertyPixelWidth] as? Int,
                let height = properties[kCGImagePropertyPixelHeight] as? Int,
                width == layout.width * layout.columns, height == layout.height * layout.rows,
                let image = CGImageSourceCreateThumbnailAtIndex(
                    source, 0,
                    [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: min(4096, max(width, height)),
                        kCGImageSourceShouldCacheImmediately: true,
                    ] as CFDictionary)
            else { throw ImageDataError.invalidImage }
            try Task.checkCancellation()
            let cost = image.bytesPerRow * image.height
            guard cost <= maximumBytes else { throw ImageDataError.oversized }
            while images.count >= 20 || bytes > maximumBytes - cost {
                guard let oldest = recency.first else { break }
                recency.removeFirst()
                if let removed = images.removeValue(forKey: oldest) { bytes -= removed.bytesPerRow * removed.height }
            }
            images[resource] = image
            bytes += cost
            touch(resource)
            return image
        }

        private func touch(_ resource: TrickplayTileResource) {
            recency.removeAll { $0 == resource }
            recency.append(resource)
        }

        public func removeAll() {
            images.removeAll()
            recency.removeAll()
            bytes = 0
        }
    }
#endif
