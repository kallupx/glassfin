import CoreModels
import Foundation

#if canImport(ImageIO)
    import CoreGraphics
    import ImageIO
#endif

/// The same option dictionary is tested on Linux and passed directly to ImageIO on Apple.
public enum LibraryThumbnailOptions {
    public static func make(maxPixelSize: Int) -> [String: Any] {
        [
            "kCGImageSourceCreateThumbnailFromImageAlways": true,
            "kCGImageSourceThumbnailMaxPixelSize": max(1, maxPixelSize),
            "kCGImageSourceCreateThumbnailWithTransform": true,
            "kCGImageSourceShouldCacheImmediately": true,
        ]
    }
}

#if canImport(ImageIO)
    public struct DecodedLibraryImage: @unchecked Sendable {
        public let value: CGImage
    }

    public enum LibraryArtworkDecoder {
        /// Only the thumbnail is decoded, in a utility task outside the main actor.
        nonisolated public static func downsample(_ data: Data, pixels: Int) async -> DecodedLibraryImage? {
            let job = Task.detached(priority: .utility) { () -> DecodedLibraryImage? in
                guard !Task.isCancelled, data.count <= MetadataPolicy.imageMaxBytes,
                    let source = CGImageSourceCreateWithData(
                        data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
                else { return nil }
                let options = LibraryThumbnailOptions.make(maxPixelSize: pixels)
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                    !Task.isCancelled
                else { return nil }
                return DecodedLibraryImage(value: image)
            }
            return await withTaskCancellationHandler {
                await job.value
            } onCancel: {
                job.cancel()
            }
        }
    }
#endif
