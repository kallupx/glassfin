import CoreModels
import CoreNetworking
import Foundation
import GlassfinServices
import Observation

/// M08 integration boundary. No playback URL, player, or playback report is created by M07.
public struct LibraryPlaybackIntent: Sendable, Equatable {
    public let itemID: ItemID
    public let start: Duration
    public let audioStreamIndex: Int?
    public let subtitleStreamIndex: Int?

    public init(itemID: ItemID, start: Duration, audioStreamIndex: Int? = nil, subtitleStreamIndex: Int? = nil) {
        self.itemID = itemID
        self.start = max(.zero, start)
        self.audioStreamIndex = audioStreamIndex
        self.subtitleStreamIndex = subtitleStreamIndex
    }
}

@MainActor
@Observable
public final class LibraryUserActions {
    public private(set) var revision = 0
    public private(set) var lastError: AppError?
    public private(set) var pending: Set<String> = []
    @ObservationIgnored private let service: any LibraryService
    @ObservationIgnored private let app: AppState
    private var visibleStates: [String: UserItemState] = [:]

    public init(service: any LibraryService, app: AppState) {
        self.service = service
        self.app = app
    }

    public func visible(_ item: MediaItem) -> MediaItem {
        var result = item.cleanedForDisplay()
        result.userData = visibleStates[item.id] ?? result.userData
        return result
    }

    public func refreshFromStore() async {
        for id in Array(visibleStates.keys) {
            guard !pending.contains(id), let state = await app.userData.state(for: id), !pending.contains(id) else {
                continue
            }
            visibleStates[id] = state
        }
        revision += 1
    }

    public func togglePlayed(_ item: MediaItem) async { await edit(item, favorite: false) }
    public func toggleFavorite(_ item: MediaItem) async { await edit(item, favorite: true) }

    private func edit(_ item: MediaItem, favorite: Bool) async {
        guard ItemID(item.id) != nil, !pending.contains(item.id) else { return }
        let sessionGeneration = app.requestGeneration
        pending.insert(item.id)
        defer { pending.remove(item.id) }
        let current = visible(item).userData
        var next = current
        if favorite { next.isFavorite.toggle() } else { next.played.toggle() }
        visibleStates[item.id] = next
        revision += 1
        _ = await app.userData.project([item])
        let previous = await app.userData.applyOptimistic(id: item.id, next: next)
        do {
            if favorite {
                try await service.setFavorite(item.id, next.isFavorite)
            } else {
                try await service.setPlayed(item.id, next.played)
            }
            guard sessionGeneration == app.requestGeneration else { return }
            await app.userData.commit(id: item.id)
            lastError = nil
        } catch {
            await app.userData.rollback(id: item.id, to: previous)
            visibleStates[item.id] = current
            let mapped = AppErrorMapping.map(
                error, context: .authenticated, deviceOffline: app.connectivity == .offline)
            if mapped != .cancelled {
                lastError = mapped
                app.handle(mapped)
            }
        }
        revision += 1
    }
}

@MainActor
@Observable
public final class ItemDetailViewModel: ViewContentProviding {
    public private(set) var state: LoadState<MediaItem> = .idle
    public private(set) var similar: LoadState<[MediaItem]> = .idle
    public var audioStreamIndex: Int?
    public var subtitleStreamIndex: Int?
    public var overviewExpanded = false

    @ObservationIgnored private let library: any LibraryService
    @ObservationIgnored private let app: AppState
    @ObservationIgnored private var generation = 0

    public init(library: any LibraryService, app: AppState) {
        self.library = library
        self.app = app
    }

    public var hasContent: Bool { state.value != nil }

    /// Returning to a retained screen must restore its content provider without reloading.
    public func onAppear() {
        app.currentView = self
    }

    public func load(id: String) async {
        app.currentView = self
        guard ItemID(id) != nil else {
            state = .failed(.internalInvariant, previous: state.value)
            return
        }
        generation += 1
        let expected = generation
        let sessionGeneration = app.requestGeneration
        state = .loading(previous: state.value)
        do {
            let item = try await library.item(id: id).cleanedForDisplay()
            let projected = await app.userData.project([item])
            guard expected == generation, sessionGeneration == app.requestGeneration, !Task.isCancelled else { return }
            state = .loaded(projected.first ?? item)
        } catch {
            guard expected == generation, sessionGeneration == app.requestGeneration, !Task.isCancelled else { return }
            let mapped = map(error)
            guard mapped != .cancelled else { return }
            state = .failed(mapped, previous: state.value)
            app.handle(mapped)
            return
        }
        guard state.value?.kind == .movie || state.value?.kind == .episode else { return }
        similar = .loading(previous: similar.value)
        do {
            let items = try await library.similar(id: id, limit: ListPaging.pageSize)
            let projected = await app.userData.project(items.map { $0.cleanedForDisplay() })
            guard expected == generation, sessionGeneration == app.requestGeneration, !Task.isCancelled else { return }
            similar = .loaded(projected)
        } catch {
            guard expected == generation, sessionGeneration == app.requestGeneration, !Task.isCancelled else { return }
            let mapped = map(error)
            guard mapped != .cancelled else { return }
            similar = .failed(mapped, previous: similar.value)
            app.handle(mapped)
        }
    }

    public func refreshFromStore() async {
        if let item = state.value, let projected = await app.userData.project([item]).first {
            if case .failed(let error, _) = state {
                state = .failed(error, previous: projected)
            } else {
                state = .loaded(projected)
            }
        }
        if let items = similar.value { similar = .loaded(await app.userData.project(items)) }
    }

    public func playbackIntent(for target: MediaItem? = nil, startOver: Bool = false) -> LibraryPlaybackIntent? {
        guard let item = target ?? state.value, let id = ItemID(item.id) else { return nil }
        return LibraryPlaybackIntent(
            itemID: id, start: startOver ? .zero : item.userData.playbackPosition,
            audioStreamIndex: audioStreamIndex, subtitleStreamIndex: subtitleStreamIndex)
    }

    public func onDisappear() { generation += 1 }

    private func map(_ error: APIError) -> AppError {
        AppErrorMapping.map(error, context: .authenticated, deviceOffline: app.connectivity == .offline)
    }
}
