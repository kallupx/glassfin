import CoreModels
import CoreNetworking
import Foundation
import GlassfinServices
import Observation

@MainActor
@Observable
public final class UserDataEditor {
    @ObservationIgnored private let store: UserDataStore
    @ObservationIgnored private let library: any LibraryService
    @ObservationIgnored private let app: AppState
    @ObservationIgnored private let log: any GlassfinLog
    public private(set) var lastError: AppError?

    public init(store: UserDataStore, library: any LibraryService, app: AppState, log: any GlassfinLog = SilentLog()) {
        self.store = store
        self.library = library
        self.app = app
        self.log = log
    }

    public func setPlayed(id: String, played: Bool) async {
        await edit(
            id: id, write: { $0.played = played },
            send: {
                try await self.library.setPlayed(id, played)
            })
    }

    public func setFavorite(id: String, favorite: Bool) async {
        await edit(
            id: id, write: { $0.isFavorite = favorite },
            send: {
                try await self.library.setFavorite(id, favorite)
            })
    }

    private func edit(
        id: String,
        write: (inout UserItemState) -> Void,
        send: () async throws -> Void
    ) async {
        guard ItemID(id) != nil else {
            lastError = .internalInvariant
            log.warning("Non-fatal invariant failure")
            return
        }
        let current = await store.state(for: id) ?? UserItemState()
        var next = current
        write(&next)
        let previous = await store.applyOptimistic(id: id, next: next)
        do {
            try await send()
            await store.commit(id: id)
            lastError = nil
        } catch let error as APIError {
            await store.rollback(id: id, to: previous)
            let mapped = map(error)
            lastError = mapped
            app.handle(mapped)
        } catch {
            await store.rollback(id: id, to: previous)
            lastError = .serverUnreachable
        }
    }

    private func map(_ error: APIError) -> AppError {
        AppErrorMapping.map(error, context: .authenticated, deviceOffline: app.connectivity == .offline)
    }
}

@MainActor
@Observable
public final class PlayerViewModel: ViewContentProviding {
    public private(set) var state: LoadState<PlaybackSource> = .idle
    public private(set) var stallMessageKey: String?

    public var hasContent: Bool { state.value != nil }

    public var stallMessage: String? {
        stallMessageKey.map(AppErrorMessage.localized)
    }
    public private(set) var method: PlayMethod?

    @ObservationIgnored private let playback: any PlaybackInfoService
    @ObservationIgnored private let reporting: any ReportingService
    @ObservationIgnored private let userData: UserDataStore
    @ObservationIgnored private let app: AppState
    @ObservationIgnored private let signposter: any Signposting
    @ObservationIgnored private let log: any GlassfinLog
    @ObservationIgnored private var openInterval: SignpostInterval?

    public init(
        playback: any PlaybackInfoService,
        reporting: any ReportingService,
        userData: UserDataStore,
        app: AppState,
        signposter: any Signposting,
        log: any GlassfinLog = SilentLog()
    ) {
        self.playback = playback
        self.reporting = reporting
        self.userData = userData
        self.app = app
        self.signposter = signposter
        self.log = log
    }

    public func load(itemID: String, maxBitrate: Int = 120_000_000) async {
        app.currentView = self
        guard ItemID(itemID) != nil else {
            state = .failed(.internalInvariant, previous: state.value)
            log.warning("Non-fatal invariant failure")
            return
        }
        let interval = signposter.begin(.playbackFirstFrame)
        state = .loading(previous: state.value)
        do {
            let source = try await playback.playbackInfo(itemID: itemID, start: .zero, maxBitrate: maxBitrate)
            method = source.method
            var measured = interval
            if source.method == .transcode {
                signposter.end(interval)
                measured = signposter.begin(.playbackTranscodeFirstFrame)
            }
            openInterval = measured
            state = .loaded(source)
            log.debug("Playback info loaded.")
        } catch let error {
            signposter.end(interval)
            let mapped = AppErrorMapping.map(
                error, context: .authenticated, deviceOffline: app.connectivity == .offline)
            if case .cancelled = mapped { return }
            state = .failed(mapped, previous: state.value)
            app.handle(mapped)
        }
    }

    public func noteFirstFrame() {
        guard let openInterval else { return }
        signposter.end(openInterval)
        self.openInterval = nil
    }

    public func noteBuffering(elapsed: Duration) {
        if elapsed > NetworkThresholds.stallMessageAfter {
            stallMessageKey = AppErrorMessage.bufferingKey
        } else {
            stallMessageKey = nil
        }
    }

    public func measureScrub<T>(_ body: () async throws -> T) async rethrows -> T {
        let interval = signposter.begin(.playbackScrub)
        defer { signposter.end(interval) }
        return try await body()
    }

    public func measureTrickplay<T>(_ body: () async throws -> T) async rethrows -> T {
        let interval = signposter.begin(.trickplayPreview)
        defer { signposter.end(interval) }
        return try await body()
    }

    public func measureTrackSwitch<T>(_ body: () async throws -> T) async rethrows -> T {
        let interval = signposter.begin(.trackSwitch)
        defer { signposter.end(interval) }
        return try await body()
    }

    public func stop(itemID: String, position: Duration, playSessionID: String, finished: Bool) async {
        let interval = signposter.begin(.watchedStateHome)
        await userData.recordPlayback(id: itemID, position: position, played: finished, log: log)
        signposter.end(interval)
        let safe = position < .zero ? Duration.zero : position
        do {
            try await reporting.stopped(itemID: itemID, position: safe, playSessionID: playSessionID, failed: false)
            await userData.commit(id: itemID)
        } catch let error {
            let mapped = AppErrorMapping.map(
                error, context: .authenticated, deviceOffline: app.connectivity == .offline)
            app.handle(mapped)
        }
    }
}

@MainActor
@Observable
public final class SearchViewModel: ViewContentProviding {
    public private(set) var term = ""
    public private(set) var state: LoadState<[MediaItem]> = .idle

    public var hasContent: Bool { state.value?.isEmpty == false }

    @ObservationIgnored private let search: any SearchService
    @ObservationIgnored private let userData: UserDataStore
    @ObservationIgnored private let app: AppState
    @ObservationIgnored private let clock: any GlassfinClock
    @ObservationIgnored private let signposter: any Signposting
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var ticket = 0

    public init(
        search: any SearchService,
        userData: UserDataStore,
        app: AppState,
        clock: any GlassfinClock,
        signposter: any Signposting
    ) {
        self.search = search
        self.userData = userData
        self.app = app
        self.clock = clock
        self.signposter = signposter
    }

    public func setTerm(_ newTerm: String) {
        app.currentView = self
        term = newTerm
        task?.cancel()
        ticket += 1
        let current = ticket
        let query = newTerm
        task = Task { @MainActor in
            do {
                try await self.clock.sleep(for: NetworkThresholds.searchDebounce)
            } catch {
                return
            }
            guard !Task.isCancelled, current == self.ticket else { return }
            await self.execute(term: query, ticket: current)
        }
    }

    public func onDisappear() {
        task?.cancel()
    }

    private func execute(term: String, ticket: Int) async {
        let interval = signposter.begin(.searchResults)
        defer { signposter.end(interval) }
        state = .loading(previous: state.value)
        do {
            let items = try await search.hints(term: term, limit: 20)
            guard ticket == self.ticket, !Task.isCancelled else { return }
            state = .loaded(await userData.project(items))
        } catch let error {
            guard ticket == self.ticket else { return }
            let mapped = AppErrorMapping.map(
                error, context: .authenticated, deviceOffline: app.connectivity == .offline)
            if case .cancelled = mapped { return }
            state = .failed(mapped, previous: state.value)
            app.handle(mapped)
        }
    }
}
