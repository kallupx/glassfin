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
public final class HomeViewModel {
    public private(set) var resume: LoadState<[MediaItem]> = .idle
    public private(set) var nextUp: LoadState<[MediaItem]> = .idle
    public private(set) var latest: LoadState<[MediaItem]> = .idle

    @ObservationIgnored private let library: any LibraryService
    @ObservationIgnored private let userData: UserDataStore
    @ObservationIgnored private let snapshots: HomeSnapshotStore
    @ObservationIgnored private let responses: ResponseCache
    @ObservationIgnored private let app: AppState
    @ObservationIgnored private let clock: any GlassfinClock
    @ObservationIgnored private let signposter: any Signposting
    @ObservationIgnored private let log: any GlassfinLog
    @ObservationIgnored private let scope: RequestScope
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(
        library: any LibraryService,
        userData: UserDataStore,
        snapshots: HomeSnapshotStore,
        responses: ResponseCache,
        app: AppState,
        clock: any GlassfinClock,
        signposter: any Signposting,
        scope: RequestScope,
        log: any GlassfinLog = SilentLog()
    ) {
        self.library = library
        self.userData = userData
        self.snapshots = snapshots
        self.responses = responses
        self.app = app
        self.clock = clock
        self.signposter = signposter
        self.scope = scope
        self.log = log
    }

    public func start(libraryIDs: [String], coldStart: Bool = false) {
        task?.cancel()
        let child = Task { @MainActor in
            await self.reload(libraryIDs: libraryIDs, coldStart: coldStart)
        }
        task = child
        scope.track(child)
    }

    public func onDisappear() {
        task?.cancel()
    }

    public func reload(libraryIDs: [String], coldStart: Bool = false) async {
        let generation = app.requestGeneration
        var cold = coldStart ? signposter.begin(.coldStartHomeFirstRow) : nil
        let sections = signposter.begin(.homeSectionsLoaded)
        defer {
            signposter.end(sections)
            if let interval = cold {
                signposter.end(interval)
            }
        }
        if let snapshot = snapshots.load() {
            resume = .loading(previous: snapshot.resume)
            nextUp = .loading(previous: snapshot.nextUp)
            latest = .loading(previous: snapshot.latest)
            if let interval = cold {
                signposter.end(interval)
                cold = nil
            }
        } else {
            resume = .loading(previous: resume.value)
            nextUp = .loading(previous: nextUp.value)
            latest = .loading(previous: latest.value)
        }
        async let resumeResult = fetchResume()
        async let nextResult = fetchNext()
        async let latestResult = fetchLatest(libraryIDs)
        let resumeItems = await resumeResult
        let nextItems = await nextResult
        let latestItems = await latestResult
        guard !Task.isCancelled, generation == app.requestGeneration else { return }
        apply(resumeItems, to: \.resume)
        apply(nextItems, to: \.nextUp)
        apply(latestItems, to: \.latest)
        if let interval = cold {
            signposter.end(interval)
            cold = nil
        }
        let snapshot = HomeSnapshot(
            resume: resume.value ?? [], nextUp: nextUp.value ?? [], latest: latest.value ?? [])
        if resume.presentedError == nil || snapshot.resume.isEmpty == false {
            snapshots.save(snapshot)
        }
    }

    public func refreshFromStore() async {
        let interval = signposter.begin(.watchedStateHome)
        if let items = resume.value {
            resume = .loaded(await userData.project(items))
        }
        if let items = nextUp.value {
            nextUp = .loaded(await userData.project(items))
        }
        if let items = latest.value {
            latest = .loaded(await userData.project(items))
        }
        signposter.end(interval)
    }

    private func fetchResume() async -> Result<[MediaItem], APIError> {
        await cached("home.resume", ttl: NetworkThresholds.homeTTL) {
            try await self.library.resume(limit: 20)
        }
    }

    private func fetchNext() async -> Result<[MediaItem], APIError> {
        await cached("home.nextUp", ttl: NetworkThresholds.homeTTL) {
            try await self.library.nextUp(limit: 20)
        }
    }

    private func fetchLatest(_ libraryIDs: [String]) async -> Result<[MediaItem], APIError> {
        if libraryIDs.isEmpty { return .success([]) }
        return await cached("home.latest", ttl: NetworkThresholds.homeTTL) {
            var combined: [MediaItem] = []
            var firstError: APIError?
            for id in libraryIDs {
                guard ItemID(id) != nil else { continue }
                do {
                    let page = try await self.library.latest(in: id, limit: 20)
                    combined.append(contentsOf: page)
                } catch let error as APIError {
                    if firstError == nil { firstError = error }
                } catch {
                    if firstError == nil { firstError = .network }
                }
            }
            if combined.isEmpty, let firstError { throw firstError }
            return combined
        }
    }

    private func cached(
        _ key: String, ttl: Duration, load: () async throws -> [MediaItem]
    ) async -> Result<[MediaItem], APIError> {
        let now = clock.now()
        if let data = await responses.data(for: key, now: now),
            let items = try? JSONDecoder().decode([MediaItem].self, from: data)
        {
            return .success(await userData.project(items))
        }
        do {
            let items = try await load()
            let projected = await userData.project(items)
            if let data = try? JSONEncoder().encode(projected) {
                await responses.insert(data, for: key, ttl: ttl, now: clock.now())
            }
            return .success(projected)
        } catch let error as APIError {
            return .failure(error)
        } catch {
            return .failure(.network)
        }
    }

    private func apply(
        _ result: Result<[MediaItem], APIError>,
        to keyPath: ReferenceWritableKeyPath<HomeViewModel, LoadState<[MediaItem]>>
    ) {
        switch result {
        case .success(let items):
            self[keyPath: keyPath] = .loaded(items)
        case .failure(let error):
            let mapped = AppErrorMapping.map(
                error, context: .authenticated, deviceOffline: app.connectivity == .offline)
            if case .cancelled = mapped { return }
            let previous = self[keyPath: keyPath].value
            self[keyPath: keyPath] = .failed(mapped, previous: previous)
            AppErrorMessage.report(mapped, log: log)
            app.handle(mapped)
        }
    }
}

private struct CachedPage: Codable, Sendable {
    var items: [MediaItem]
    var totalCount: Int?
}

@MainActor
@Observable
public final class LibraryViewModel {
    public private(set) var state: LoadState<[MediaItem]> = .idle
    public private(set) var totalCount: Int?

    @ObservationIgnored private let library: any LibraryService
    @ObservationIgnored private let userData: UserDataStore
    @ObservationIgnored private let responses: ResponseCache
    @ObservationIgnored private let app: AppState
    @ObservationIgnored private let clock: any GlassfinClock
    @ObservationIgnored private let log: any GlassfinLog
    @ObservationIgnored private var libraryID = ""
    @ObservationIgnored private var query = ItemQuery()
    @ObservationIgnored private var nextIndex = 0
    @ObservationIgnored private var pageInFlight = false

    public init(
        library: any LibraryService,
        userData: UserDataStore,
        responses: ResponseCache,
        app: AppState,
        clock: any GlassfinClock,
        log: any GlassfinLog = SilentLog()
    ) {
        self.library = library
        self.userData = userData
        self.responses = responses
        self.app = app
        self.clock = clock
        self.log = log
    }

    public func reload(libraryID: String, query: ItemQuery = ItemQuery()) async {
        guard ItemID(libraryID) != nil else {
            state = .failed(.internalInvariant, previous: state.value)
            log.warning("Non-fatal invariant failure")
            return
        }
        self.libraryID = libraryID
        self.query = query
        nextIndex = 0
        totalCount = nil
        state = .loading(previous: nil)
        await loadPage(reset: true)
    }

    public func loadNextPageIfNeeded(visibleIndex: Int) async {
        let loaded = state.value?.count ?? 0
        guard ListPaging.shouldPrefetch(index: visibleIndex, loaded: loaded, total: totalCount) else { return }
        guard !pageInFlight else { return }
        pageInFlight = true
        defer { pageInFlight = false }
        await loadPage(reset: false)
    }

    private func loadPage(reset: Bool) async {
        let start = reset ? 0 : nextIndex
        let key = "library.\(libraryID).\(start)"
        if reset, let data = await responses.data(for: key, now: clock.now()),
            let cached = try? JSONDecoder().decode(CachedPage.self, from: data)
        {
            state = .loaded(await userData.project(cached.items))
            totalCount = cached.totalCount
            nextIndex = cached.items.count
            return
        }
        do {
            let page = try await library.items(
                in: libraryID, query: query, page: PageRequest(startIndex: start, limit: ListPaging.pageSize))
            let projected = await userData.project(page.items)
            var combined = reset ? [] : (state.value ?? [])
            combined.append(contentsOf: projected)
            if page.items.count < ListPaging.pageSize {
                totalCount = combined.count
            } else {
                totalCount = page.totalCount
            }
            nextIndex = combined.count
            state = .loaded(combined)
            let payload = CachedPage(items: projected, totalCount: totalCount)
            if let data = try? JSONEncoder().encode(payload) {
                await responses.insert(data, for: key, ttl: NetworkThresholds.libraryListTTL, now: clock.now())
            }
        } catch let error {
            let mapped = AppErrorMapping.map(
                error, context: .authenticated, deviceOffline: app.connectivity == .offline)
            if case .cancelled = mapped { return }
            state = .failed(mapped, previous: state.value)
            AppErrorMessage.report(mapped, log: log)
            app.handle(mapped)
        }
    }
}

@MainActor
@Observable
public final class SeriesViewModel {
    public private(set) var seasons: LoadState<[MediaItem]> = .idle
    public private(set) var episodes: LoadState<[MediaItem]> = .idle

    @ObservationIgnored private let library: any LibraryService
    @ObservationIgnored private let userData: UserDataStore
    @ObservationIgnored private let app: AppState
    @ObservationIgnored private let log: any GlassfinLog
    @ObservationIgnored private var seriesID = ""

    public init(
        library: any LibraryService, userData: UserDataStore, app: AppState, log: any GlassfinLog = SilentLog()
    ) {
        self.library = library
        self.userData = userData
        self.app = app
        self.log = log
    }

    public func load(seriesID: String) async {
        guard ItemID(seriesID) != nil else {
            seasons = .failed(.internalInvariant, previous: seasons.value)
            log.warning("Non-fatal invariant failure")
            return
        }
        self.seriesID = seriesID
        seasons = .loading(previous: seasons.value)
        do {
            let items = await userData.project(try await library.seasons(series: seriesID))
            seasons = .loaded(items)
            if let first = items.first {
                await select(seasonID: first.id)
            } else {
                episodes = .loaded([])
            }
        } catch let error {
            let mapped = AppErrorMapping.map(
                error, context: .authenticated, deviceOffline: app.connectivity == .offline)
            seasons = .failed(mapped, previous: seasons.value)
            app.handle(mapped)
        }
    }

    public func select(seasonID: String) async {
        guard ItemID(seasonID) != nil, ItemID(seriesID) != nil else {
            episodes = .failed(.internalInvariant, previous: episodes.value)
            return
        }
        episodes = .loading(previous: episodes.value)
        do {
            let items = await userData.project(try await library.episodes(series: seriesID, season: seasonID))
            episodes = .loaded(items)
        } catch let error {
            let mapped = AppErrorMapping.map(
                error, context: .authenticated, deviceOffline: app.connectivity == .offline)
            episodes = .failed(mapped, previous: episodes.value)
            app.handle(mapped)
        }
    }
}

@MainActor
@Observable
public final class PlayerViewModel {
    public private(set) var state: LoadState<PlaybackSource> = .idle
    public private(set) var stallMessageKey: String?

    public var stallMessage: String? {
        stallMessageKey != nil ? AppErrorMessage.buffering : nil
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
public final class SearchViewModel {
    public private(set) var term = ""
    public private(set) var state: LoadState<[MediaItem]> = .idle

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
