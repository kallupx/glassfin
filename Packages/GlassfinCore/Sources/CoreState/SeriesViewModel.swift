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
public final class SeriesViewModel {
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

    public init(
        library: any LibraryService, userData: UserDataStore, app: AppState, log: any GlassfinLog = SilentLog(),
        clock: any GlassfinClock = SystemGlassfinClock()
    ) {
        self.library = library
        self.userData = userData
        self.app = app
        self.clock = clock
    }

    public var preferredEpisodeID: String? {
        let items = episodes.value ?? []
        return items.first(where: { !$0.userData.played })?.id ?? items.first?.id
    }

    public var selectedOverview: String {
        episodes.value?.first(where: { $0.id == focusedEpisodeID })?.overview ?? ""
    }

    public func load(seriesID: String, seasonID: String? = nil) async {
        guard ItemID(seriesID) != nil else {
            seasons = .failed(.internalInvariant, previous: seasons.value)
            return
        }
        generation += 1
        let expected = generation
        let sessionGeneration = app.requestGeneration
        self.seriesID = seriesID
        seasons = .loading(previous: seasons.value)
        do {
            let loaded = try await library.seasons(series: seriesID)
            let ordered = loaded.sorted {
                let lhs = $0.indexNumber == 0 ? Int.max : ($0.indexNumber ?? Int.max - 1)
                let rhs = $1.indexNumber == 0 ? Int.max : ($1.indexNumber ?? Int.max - 1)
                return lhs < rhs
            }
            let projected = await userData.project(ordered.map { $0.cleanedForDisplay() })
            guard expected == generation, sessionGeneration == app.requestGeneration, !Task.isCancelled else { return }
            seasons = .loaded(projected)
            // Fetch all episode metadata once to find an in-progress episode in any season.
            // The visible row still contains only the selected season.
            let all = await userData.project(try await library.episodes(series: seriesID, season: nil))
                .map { $0.cleanedForDisplay() }
            guard expected == generation, sessionGeneration == app.requestGeneration, !Task.isCancelled else { return }
            let chronological = all.sorted {
                let lhs = $0.parentIndexNumber == 0 ? Int.max : ($0.parentIndexNumber ?? 1)
                let rhs = $1.parentIndexNumber == 0 ? Int.max : ($1.parentIndexNumber ?? 1)
                return lhs == rhs ? ($0.indexNumber ?? 0) < ($1.indexNumber ?? 0) : lhs < rhs
            }
            playTarget =
                chronological.first { !$0.userData.played && $0.userData.playbackPosition > .zero }
                ?? chronological.first { !$0.userData.played } ?? chronological.first
            let targetSeason = seasonID ?? playTarget?.seasonID ?? projected.first?.id
            if let targetSeason { await select(seasonID: targetSeason) } else { episodes = .loaded([]) }
            initialEpisodeID = playTarget?.seasonID == selectedSeasonID ? playTarget?.id : preferredEpisodeID
            focusedEpisodeID = initialEpisodeID
            focus = .play
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
        selectionGeneration += 1
        guard id != selectedSeasonID else { return }
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
        let expected = selectionGeneration
        let sessionGeneration = app.requestGeneration
        let previous = episodes.value ?? lastEpisodes
        let previousSeasonID = episodes.value == nil ? lastSeasonID : selectedSeasonID
        selectedSeasonID = seasonID
        episodes = .loading(previous: nil)
        do {
            let items = await userData.project(try await library.episodes(series: seriesID, season: seasonID))
            guard expected == selectionGeneration, sessionGeneration == app.requestGeneration, !Task.isCancelled else {
                return
            }
            let cleaned = items.map { $0.cleanedForDisplay() }
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
        let target: String?
        if finished, let index = items.firstIndex(where: { $0.id == itemID }) {
            target = items.dropFirst(index + 1).first(where: { !$0.userData.played })?.id ?? itemID
        } else {
            target = itemID
        }
        if let target { focusEpisode(target) }
    }

    public func refreshFromStore() async {
        if let values = episodes.value { episodes = .loaded(await userData.project(values)) }
        if let target = playTarget { playTarget = await userData.project([target]).first }
    }

    public func onDisappear() {
        generation += 1
        selectionGeneration += 1
        selectionTask?.cancel()
    }

    private func map(_ error: APIError) -> AppError {
        AppErrorMapping.map(error, context: .authenticated, deviceOffline: app.connectivity == .offline)
    }
}
