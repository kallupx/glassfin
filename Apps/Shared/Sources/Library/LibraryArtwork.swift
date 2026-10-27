import GlassfinCore
import ImageIO
import SwiftUI

struct DecodedLibraryImage: @unchecked Sendable {
    let value: CGImage
}

enum LibraryArtworkDecoder {
    /// ImageIO creates and immediately decodes only the requested thumbnail off the main actor.
    nonisolated static func downsample(_ data: Data, pixels: Int) async -> DecodedLibraryImage? {
        let job = Task.detached(priority: .utility) { () -> DecodedLibraryImage? in
            guard !Task.isCancelled, data.count <= MetadataPolicy.imageMaxBytes,
                let source = CGImageSourceCreateWithData(
                    data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
            else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, pixels),
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary), !Task.isCancelled
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

struct LibraryArtwork: View {
    var item: MediaItem
    var type: LibraryImageType
    var size: CGSize
    let session: LibrarySession
    @Environment(\.displayScale) private var scale
    @State private var image: Image?

    private var tag: String? {
        switch type {
        case .primary: item.images.primaryTag
        case .thumb: item.images.thumbTag ?? item.images.primaryTag
        case .backdrop: item.images.backdropTags.first
        case .logo: item.images.logoTag
        }
    }

    private var request: LibraryImageRequest? {
        guard let tag, let id = ItemID(item.id), let server = session.app.activeServer else { return nil }
        return LibraryImageRequest(
            serverID: server.id, itemID: id, type: type == .thumb && item.images.thumbTag == nil ? .primary : type,
            tag: tag, width: Int((size.width * scale).rounded(.up)), height: Int((size.height * scale).rounded(.up)))
    }

    var body: some View {
        AsyncPoster(blurHash: nil, image: image, failed: false, size: size)
            .task(id: request?.cacheKey) {
                image = nil
                guard let request else { return }
                do {
                    let data = try await session.images.data(for: request)
                    let decoded = await LibraryArtworkDecoder.downsample(
                        data, pixels: max(request.width, request.height))
                    guard !Task.isCancelled, let decoded else { return }
                    image = Image(decorative: decoded.value, scale: scale)
                } catch {
                    // Missing or malformed artwork keeps the content placeholder.
                }
            }
    }
}

extension PosterContent {
    init(item: MediaItem) {
        id = item.id
        title = MetadataPolicy.clean(item.name, limit: MetadataPolicy.nameMax)
        progress = PlaybackProgress.measure(position: item.userData.playbackPosition, runtime: item.runtime)
        isWatched = item.userData.played
        unplayedCount = item.userData.unplayedCount
        blurHash = nil
    }
}
