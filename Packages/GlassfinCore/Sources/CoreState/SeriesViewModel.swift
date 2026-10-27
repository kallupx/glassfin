import CoreModels
import CoreNetworking
import Foundation
import GlassfinServices
import Observation

public enum SeriesFocus: Sendable, Hashable {
    case play
    case season(String)
    case episode(String)
}

@MainActor
@Observable
public final class SeriesViewModel: ViewContentProviding {
    public private(set) var seasons: LoadState<[MediaItem]> = .idle
    public private(set) var episodes: LoadState<[MediaItem]> = .idle
    public private(set) var selectedSeasonID: String?
    public private(set) var playTarget: MediaItem?
    public private(set) var focusedEpisodeID: String?
    public private(set) var initialEpisodeID: String?
    public private(set) var focus: SeriesFocus = .play
    public static let seasonDebounce: Duration = .milliseconds(200)

    @ObservationIgnored private let library: any LibraryService
    @ObservationIgnored private let userData: UserDataStore
    @ObservationIgnored private let app: AppState
    @ObservationIgnored private let clock: any GlassfinClock
    @ObservationIgnored private var seriesID = ""
    @ObservationIgnored private var lastEpisodes: [MediaItem]?
    @ObservationIgnored private var lastSeasonID: String?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var selectionGeneration = 0
    @ObservationIgnored private var selectionTask: Task<Void, Never>?
    @ObservationIgnored private var episodeTask: Task<Void, Never>?
    @ObservationIgnored private var episodeCache: [String: [MediaItem]] = [:]

    public init(
        library: any LibraryService, userData: UserDataStore, app: AppState, log: any GlassfinLog = SilentLog(),
        clock: any GlassfinClock = SystemGlassfinClock()
    ) {
        self.library = library
        self.userData = userData
        self.app = app
        self.clock = clock
    }

    public var hasContent: Bool {
        seasons.value?.isEmpty == false || episodes.value?.isEmpty == false
    }

    public var preferredEpisodeID: String? {
        let items = episodes.value ?? []
        return items.first(where: { !$0.userData.played })?.id ?? items.first?.id
    }

    /// The per-season picker stays visible even when the series has only one season (Q7-25).
    public var showsSeasonPicker: Bool { seasons.value?.isEmpty == false }

    public var selectedOverview: String {
        episodes.value?.first(where: { $0.id == focusedEpisodeID })?.overview ?? ""
    }

    public func load(seriesID: String, seasonID: String? = nil) async {
        app.currentView = self
        guard ItemID(seriesID) != nil else {
            seasons = .failed(.internalInvariant, previous: seasons.value)
            return
        }
        generation += 1
        let expected = generation
        let sessionGeneration = app.requestGeneration
        let wasLoaded = self.seriesID == seriesID && seasons.value != nil
        selectionTask?.cancel()
        episodeTask?.cancel()
        selectionGeneration += 1
        if self.seriesID != seriesID { episodeCache.removeAll() }
        let previousSeason = wasLoaded ? selectedSeasonID : nil
        let previousEpisode = wasLoaded ? focusedEpisodeID : nil
        self.seriesID = seriesID
        seasons = .loading(previous: seasons.value)
        do {
            async let next = library.nextUp(series: seriesID)
            let loaded = try await library.seasons(series: seriesID)
            let ordered = loaded.sorted {
                let lhs = $0.indexNumber == 0 ? Int.max : ($0.indexNumber ?? Int.max - 1)
                let rhs = $1.indexNumber == 0 ? Int.max : ($1.indexNumber ?? Int.max - 1)
                return lhs < rhs
            }
            let projected = await userData.project(ordered.map { $0.cleanedForDisplay() })
            guard expected == generation, sessionGeneration == app.requestGeneration, !Task.isCancelled else { return }
            seasons = .loaded(projected)
            let candidate = try await next
            let target = await userData.project(candidate.map { [$0.cleanedForDisplay()] } ?? []).first
            guard expected == generation, sessionGeneration == app.requestGeneration, !Task.isCancelled else { return }
            playTarget = target
            let nextSeason = target?.seasonID.flatMap { id in projected.first { $0.id == id }?.id }
            let targetSeason = seasonID ?? previousSeason ?? nextSeason ?? projected.first?.id
            if let targetSeason { await select(seasonID: targetSeason) } else { episodes = .loaded([]) }
            guard expected == generation, sessionGeneration == app.requestGeneration, !Task.isCancelled else { return }
            if playTarget == nil || seasonID != nil {
                let items = episodes.value ?? []
                playTarget =
                    items.first { !$0.userData.played && $0.userData.playbackPosition > .zero }
                    ?? items.first { !$0.userData.played } ?? items.first
            }
            initialEpisodeID = playTarget?.seasonID == selectedSeasonID ? playTarget?.id : preferredEpisodeID
            if let previousEpisode, episodes.value?.contains(where: { $0.id == previousEpisode }) == true {
                focusedEpisodeID = previousEpisode
            } else {
                focusedEpisodeID = initialEpisodeID
            }
            if !wasLoaded { focus = .play }
        } catch {
            guard expected == generation, sessionGeneration == app.requestGeneration, !Task.isCancelled else { return }
            let mapped = map(error)
            guard mapped != .cancelled else { return }
            seasons = .failed(mapped, previous: seasons.value)
            app.handle(mapped)
        }
    }

    /// Focus changes drive the picker, not clicks. Older debounce and network work are cancelled.
    public func focusSeason(_ id: String) {
        guard ItemID(id) != nil else { return }
        focus = .season(id)
        selectionTask?.cancel()
        episodeTask?.cancel()
        selectionGeneration += 1
        guard id != selectedSeasonID || episodes.isLoading else { return }
        let expected = selectionGeneration
        let task = Task { @MainActor in
            do { try await clock.sleep(for: Self.seasonDebounce) } catch { return }
            guard expected == selectionGeneration, !Task.isCancelled else { return }
            await select(seasonID: id)
        }
        selectionTask = task
        app.scope.track(task)
    }

    public func select(seasonID: String) async {
        guard ItemID(seasonID) != nil, ItemID(seriesID) != nil else {
            episodes = .failed(.internalInvariant, previous: episodes.value)
            return
        }
        selectionGeneration += 1
        episodeTask?.cancel()
        let expected = selectionGeneration
        let sessionGeneration = app.requestGeneration
        let previous = episodes.value ?? lastEpisodes
        let previousSeasonID = episodes.value == nil ? lastSeasonID : selectedSeasonID
        let sameSeason = selectedSeasonID == seasonID
        selectedSeasonID = seasonID
        episodes = .loading(previous: sameSeason ? previous : nil)
        let task = Task { @MainActor in
            await self.loadSeason(
                seasonID, expected: expected, sessionGeneration: sessionGeneration,
                previous: previous, previousSeasonID: previousSeasonID)
        }
        episodeTask = task
        app.scope.track(task)
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func loadSeason(
        _ seasonID: String, expected: Int, sessionGeneration: Int,
        previous: [MediaItem]?, previousSeasonID: String?
    ) async {
        do {
            let raw: [MediaItem]
            if let cached = episodeCache[seasonID] {
                raw = cached
            } else {
                raw = try await library.episodes(series: seriesID, season: seasonID)
            }
            let items = await userData.project(raw)
            guard expected == selectionGeneration, sessionGeneration == app.requestGeneration, !Task.isCancelled else {
                return
            }
            let cleaned = items.map { $0.cleanedForDisplay() }
            episodeCache[seasonID] = cleaned
            episodes = .loaded(cleaned)
            lastEpisodes = cleaned
            lastSeasonID = seasonID
            focusedEpisodeID = preferredEpisodeID
        } catch {
            guard expected == selectionGeneration, sessionGeneration == app.requestGeneration, !Task.isCancelled else {
                return
            }
            let mapped = map(error)
            guard mapped != .cancelled else { return }
            // Q7-19: retain a previous row during an outage, never relabel it as another season.
            if previous != nil { selectedSeasonID = previousSeasonID }
            episodes = .failed(mapped, previous: previous)
            app.handle(mapped)
        }
    }

    public func moveDownFromSeason() {
        if let id = preferredEpisodeID {
            focusedEpisodeID = id
            focus = .episode(id)
        }
    }

    public func focusEpisode(_ id: String) {
        focusedEpisodeID = id
        focus = .episode(id)
    }

    public func moveUpFromEpisodes() {
        if let id = selectedSeasonID { focus = .season(id) }
    }

    /// M08 calls this hook after dismissing playback.
    public func returnedFromPlayback(itemID: String, finished: Bool) async {
        if let items = episodes.value { episodes = .loaded(await userData.project(items)) }
        let items = episodes.value ?? []
        var target = itemID
        if finished, let index = items.firstIndex(where: { $0.id == itemID }) {
            if let next = items.dropFirst(index + 1).first(where: { !$0.userData.played }) {
                target = next.id
            } else if let seasonIndex = seasons.value?.firstIndex(where: { $0.id == selectedSeasonID }),
                let nextSeason = seasons.value?.dropFirst(seasonIndex + 1).first
            {
                await select(seasonID: nextSeason.id)
                target = preferredEpisodeID ?? itemID
            }
        }
        if let updated = episodes.value?.first(where: { $0.id == target }) { playTarget = updated }
        focusEpisode(target)
    }

    public func refreshFromStore() async {
        if let values = episodes.value { episodes = .loaded(await userData.project(values)) }
        if let target = playTarget { playTarget = await userData.project([target]).first }
    }

    public func onDisappear() {
        generation += 1
        selectionGeneration += 1
        selectionTask?.cancel()
        episodeTask?.cancel()
    }

    private func map(_ error: any Error) -> AppError {
        let api = (error as? APIError) ?? (error is CancellationError ? .cancelled : .network)
        return AppErrorMapping.map(api, context: .authenticated, deviceOffline: app.connectivity == .offline)
    }
}
