import GlassfinCore
import SwiftUI

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
                let interval = DevicePerformance.begin(.posterReady)
                defer { interval?.end(completed: false) }
                do {
                    let data = try await session.images.data(for: request)
                    let decoded = await LibraryArtworkDecoder.downsample(
                        data, pixels: max(request.width, request.height))
                    guard !Task.isCancelled, let decoded else { return }
                    image = Image(decorative: decoded.value, scale: scale)
                    interval?.end()
                } catch {
                    // Missing or malformed artwork keeps the content placeholder.
                }
            }
    }
}

extension PosterContent {
    init(item: MediaItem) {
        id = item.id
        title = MetadataSanitizer.displayText(item.name, limit: MetadataPolicy.nameMax)
        progress = PlaybackProgress.measure(position: item.userData.playbackPosition, runtime: item.runtime)
        isWatched = item.userData.played
        unplayedCount = item.userData.unplayedCount
        blurHash = nil
    }
}
