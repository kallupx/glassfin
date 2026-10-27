import CoreModels
import CoreNetworking
import Foundation
import GlassfinServices
import Observation

public enum HomePolicy {
    public static let rowLimit = 20
    public static let foregroundAge: Duration = .seconds(60)
    public static let libraryDebounce: Duration = .seconds(2)
    public static let backdropDebounce: Duration = .milliseconds(250)
    public static let backdropFade = 0.3
    public static func backdropFade(reduceMotion: Bool) -> Double { reduceMotion ? 0 : backdropFade }
}

public struct HomeLibraryRow: Identifiable, Sendable {
    public var library: Library
    public var state: LoadState<[MediaItem]>
    public var id: String { library.id }
}

public enum HomeMetadata {
    public static func item(_ source: MediaItem) -> MediaItem {
        var item = source
        item.name = MetadataPolicy.clean(item.name, limit: MetadataPolicy.nameMax)
        item.overview = item.overview.map { MetadataPolicy.clean($0, limit: MetadataPolicy.overviewMax) }
        item.officialRating = item.officialRating.map { MetadataPolicy.clean($0, limit: MetadataPolicy.nameMax) }
        item.chapters = item.chapters.map {
            ChapterMark(name: $0.name.map { MetadataPolicy.clean($0, limit: MetadataPolicy.nameMax) }, start: $0.start)
        }
        return item
    }

    public static func items(_ sources: [MediaItem]) -> [MediaItem] {
        var seen: Set<String> = []
        return sources.filter { ItemID($0.id) != nil && seen.insert($0.id).inserted }
            .prefix(HomePolicy.rowLimit).map(item)
    }

    public static func library(_ source: Library) -> Library {
        var library = source
        library.name = MetadataPolicy.clean(library.name, limit: MetadataPolicy.nameMax)
        return library
    }

    public static func isVideoLibrary(_ library: Library) -> Bool {
        switch library.collectionType?.lowercased() {
        case nil, "", "movies", "tvshows", "homevideos", "boxsets", "mixed", "musicvideos", "trailers": true
        default: false
        }
    }
}

public enum HomeFocus {
    public static func restoredID(_ id: String?, old: [MediaItem], new: [MediaItem]) -> String? {
        if let id, new.contains(where: { $0.id == id }) { return id }
        let index = old.firstIndex { $0.id == id } ?? 0
        return new.isEmpty ? nil : new[min(index, new.count - 1)].id
    }
}

@MainActor
@Observable
public final class HomeViewModel {
    public private(set) var resume: LoadState<[MediaItem]> = .idle
    public private(set) var nextUp: LoadState<[MediaItem]> = .idle
    /// Compatibility projection for M02 clients. The Home UI uses `latestRows`.
    public private(set) var latest: LoadState<[MediaItem]> = .idle
    public private(set) var libraries: LoadState<[Library]> = .idle
    public private(set) var latestRows: [HomeLibraryRow] = []
    public private(set) var lastFetch: Duration?
    public var rememberedIDs: [String: String] = [:]
    public private(set) var actionError: AppError?

    public var hasContent: Bool {
        !(resume.value ?? []).isEmpty || !(nextUp.value ?? []).isEmpty
            || latestRows.contains { !($0.state.value ?? []).isEmpty }
    }
    public var isLoading: Bool {
        resume.isLoading || nextUp.isLoading || libraries.isLoading || latestRows.contains { $0.state.isLoading }
    }
    public var isEmpty: Bool {
        (lastFetch != nil || (resume.value != nil && nextUp.value != nil)) && !hasContent && !isLoading
            && resume.presentedError == nil
            && nextUp.presentedError == nil
            && libraries.presentedError == nil && latestRows.allSatisfy { $0.state.presentedError == nil }
    }
    public var serverDownTitleKey: AuthCopy.Key? {
        !hasContent && (app.connectivity == .serverUnreachable || app.connectivity == .offline)
            ? AppErrorMessage.key(for: .serverUnreachable) : nil
    }
    public var bannerKey: AuthCopy.Key? { app.bannerKey }
    public var playbackBlockedKey: AuthCopy.Key? { app.playbackBlockedKey }

    @ObservationIgnored private let library: any LibraryService
    @ObservationIgnored private let userData: UserDataStore
    @ObservationIgnored private let snapshots: HomeSnapshotStore
    @ObservationIgnored private let responses: ResponseCache
    @ObservationIgnored private let app: AppState
    @ObservationIgnored private let clock: any GlassfinClock
    @ObservationIgnored private let signposter: any Signposting
    @ObservationIgnored private let scope: RequestScope
    @ObservationIgnored private let log: any GlassfinLog
    @ObservationIgnored private let requireSnapshotOwner: Bool
    @ObservationIgnored private var actions: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var libraryTask: Task<Void, Never>?
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var restoredSnapshot = false
    @ObservationIgnored private var resetResumeIDs: Set<String> = []

    public init(
        library: any LibraryService, userData: UserDataStore, snapshots: HomeSnapshotStore,
        responses: ResponseCache, app: AppState, clock: any GlassfinClock,
        signposter: any Signposting, scope: RequestScope, log: any GlassfinLog = SilentLog(),
        requireSnapshotOwner: Bool = false
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
        self.requireSnapshotOwner = requireSnapshotOwner
    }

    /// Discover libraries concurrently with the two personal rows.
    public func load() async {
        let interval = signposter.begin(.homeSectionsLoaded)
        defer { signposter.end(interval) }
        restoreSnapshot()
        async let personal: Void = reload(
            libraryIDs: [], coldStart: lastFetch == nil, refreshLatest: false, measureSections: false)
        await discoverLibraries()
        await reloadLatest()
        await personal
        saveSnapshot()
    }

    public func start(libraryIDs: [String], coldStart: Bool = false) {
        task?.cancel()
        let id = UUID()
        task = Task {
            defer { scope.untrack(id) }
            await reload(libraryIDs: libraryIDs, coldStart: coldStart)
        }
        if let task { scope.track(task, id: id) }
    }

    public func start() {
        task?.cancel()
        let id = UUID()
        task = Task {
            defer { scope.untrack(id) }
            await load()
        }
        if let task { scope.track(task, id: id) }
    }

    public func perform(_ work: @escaping @MainActor @Sendable (HomeViewModel) async -> Void) {
        let id = UUID()
        actions[id] = Task {
            defer { actions[id] = nil }
            await work(self)
        }
    }

    public func onDisappear() {
        for action in actions.values { action.cancel() }
        actions.removeAll()
        revision += 1
        task?.cancel()
        libraryTask?.cancel()
    }

    public func foreground() {
        guard lastFetch.map({ clock.now() - $0 > HomePolicy.foregroundAge }) ?? true else { return }
        start()
    }

    public func reconnect() { start() }

    public func observePlayback() async {
        for await _ in await userData.playbackChanges() {
            guard !Task.isCancelled else { return }
            await userDataDidChange()
        }
    }

    public func libraryDidChange() {
        libraryTask?.cancel()
        let id = UUID()
        libraryTask = Task {
            defer { scope.untrack(id) }
            do { try await clock.sleep(for: HomePolicy.libraryDebounce) } catch { return }
            guard !Task.isCancelled else { return }
            await discoverLibraries()
            await reloadLatest()
            saveSnapshot()
        }
        if let libraryTask { scope.track(libraryTask, id: id) }
    }

    public func userDataDidChange() async {
        for id in resetResumeIDs {
            if let state = await userData.state(for: id), state.playbackPosition > .zero {
                resetResumeIDs.remove(id)
            }
        }
        await refreshFromStore()
        await responses.invalidateAll()
        await reload(libraryIDs: [], refreshLatest: false)
    }

    public func reload(
        libraryIDs: [String], coldStart: Bool = false, refreshLatest: Bool = true, measureSections: Bool = true
    ) async {
        revision += 1
        let current = revision
        let generation = app.requestGeneration
        var cold = coldStart ? signposter.begin(.coldStartHomeFirstRow) : nil
        let interval = measureSections ? signposter.begin(.homeSectionsLoaded) : nil
        defer {
            if let interval { signposter.end(interval) }
            if let cold { signposter.end(cold) }
        }
        restoreSnapshot()
        if hasContent, let token = cold {
            signposter.end(token)
            cold = nil
        }
        resume = .loading(previous: resume.value)
        nextUp = .loading(previous: nextUp.value)
        if refreshLatest {
            if latestRows.isEmpty {
                latestRows = libraryIDs.filter { ItemID($0) != nil }.map {
                    HomeLibraryRow(library: Library(id: $0, name: ""), state: .idle)
                }
            }
        }
        await withTaskGroup(of: (String, Result<[MediaItem], APIError>).self) { group in
            let service = library
            group.addTask { ("resume", await Self.fetch { try await service.resume(limit: HomePolicy.rowLimit) }) }
            group.addTask { ("nextUp", await Self.fetch { try await service.nextUp(limit: HomePolicy.rowLimit) }) }
            if refreshLatest {
                for row in latestRows {
                    group.addTask {
                        (row.id, await Self.fetch { try await service.latest(in: row.id, limit: HomePolicy.rowLimit) })
                    }
                }
            }
            for await (id, result) in group {
                guard !Task.isCancelled, current == revision, generation == app.requestGeneration else {
                    group.cancelAll()
                    continue
                }
                if case .failure(.unauthorized) = result {
                    resume = .failed(.unauthorized, previous: resume.value)
                    nextUp = .failed(.unauthorized, previous: nextUp.value)
                    app.handle(.unauthorized)
                    group.cancelAll()
                    continue
                }
                await apply(result, id: id)
                if hasContent, let token = cold {
                    signposter.end(token)
                    cold = nil
                }
            }
        }
        guard !Task.isCancelled, current == revision, generation == app.requestGeneration else { return }
        updateLatestProjection()
        lastFetch = clock.now()
        saveSnapshot()
    }

    public func retry(rowID: String) async {
        let service = library
        let generation = app.requestGeneration
        let result = await Self.fetch {
            switch rowID {
            case "resume": try await service.resume(limit: HomePolicy.rowLimit)
            case "nextUp": try await service.nextUp(limit: HomePolicy.rowLimit)
            default: try await service.latest(in: rowID, limit: HomePolicy.rowLimit)
            }
        }
        guard !Task.isCancelled, generation == app.requestGeneration else { return }
        await apply(result, id: rowID)
        updateLatestProjection()
        saveSnapshot()
    }

    public func refreshFromStore() async {
        let interval = signposter.begin(.watchedStateHome)
        defer { signposter.end(interval) }
        if let items = resume.value {
            let projected = await userData.project(items)
            replace(.success(projected.filter { !$0.userData.played && !resetResumeIDs.contains($0.id) }), id: "resume")
        }
        if let items = nextUp.value { replace(.success(await userData.project(items)), id: "nextUp") }
        for row in latestRows {
            if let items = row.state.value { replace(.success(await userData.project(items)), id: row.id) }
        }
        updateLatestProjection()
    }

    public func setPlayed(_ item: MediaItem, played: Bool) async {
        await edit(item, update: { $0.played = played }, send: { try await self.library.setPlayed(item.id, played) })
        await userDataDidChange()
    }

    public func setFavorite(_ item: MediaItem) async {
        await edit(
            item, update: { $0.isFavorite.toggle() },
            send: {
                try await self.library.setFavorite(item.id, !item.userData.isFavorite)
            })
    }

    public func removeFromResume(_ item: MediaItem) async {
        // TODO(Q6-01): verify reset-position semantics against all three Jellyfin versions.
        resetResumeIDs.insert(item.id)
        await edit(
            item,
            update: {
                $0.playbackPosition = .zero
                $0.played = false
            },
            send: { try await self.library.updateUserData(id: item.id, position: .zero, played: false) }
        )
        if actionError != nil { resetResumeIDs.remove(item.id) }
        await userDataDidChange()
    }

    private func edit(
        _ item: MediaItem, update: (inout UserItemState) -> Void, send: () async throws -> Void
    ) async {
        guard ItemID(item.id) != nil else { return }
        var state = item.userData
        update(&state)
        let previousResume = resume
        let previousNext = nextUp
        let previousLatest = latestRows
        let previous = await userData.applyOptimistic(id: item.id, next: state)
        await refreshFromStore()
        do {
            try await send()
            await userData.commit(id: item.id)
            actionError = nil
        } catch {
            await userData.rollback(id: item.id, to: previous)
            resume = previousResume
            nextUp = previousNext
            latestRows = previousLatest
            let mapped = (error as? APIError).map { map($0) } ?? .serverUnreachable
            actionError = mapped
            app.handle(mapped)
        }
        await refreshFromStore()
    }

    private func discoverLibraries() async {
        libraries = .loading(previous: libraries.value)
        do {
            let raw = try await library.userViews()
            var seen: Set<String> = []
            let values = raw.filter {
                ItemID($0.id) != nil && HomeMetadata.isVideoLibrary($0) && seen.insert($0.id).inserted
            }
            .map(HomeMetadata.library)
            guard !Task.isCancelled else { return }
            libraries = .loaded(values)
            let old = latestRows
            latestRows = values.map { lib in
                HomeLibraryRow(library: lib, state: old.first { $0.id == lib.id }?.state ?? .idle)
            }
        } catch {
            let mapped = map(error)
            guard mapped != .cancelled, !Task.isCancelled else { return }
            libraries = .failed(mapped, previous: libraries.value)
            AppErrorMessage.report(mapped, log: log)
            app.handle(mapped)
        }
    }

    private func reloadLatest() async {
        let service = library
        let generation = app.requestGeneration
        await withTaskGroup(of: (String, Result<[MediaItem], APIError>).self) { group in
            for row in latestRows {
                if let index = latestRows.firstIndex(where: { $0.id == row.id }) {
                    latestRows[index].state = .loading(previous: row.state.value)
                }
                group.addTask {
                    (row.id, await Self.fetch { try await service.latest(in: row.id, limit: HomePolicy.rowLimit) })
                }
            }
            for await (id, result) in group {
                guard !Task.isCancelled, generation == app.requestGeneration else {
                    group.cancelAll()
                    continue
                }
                await apply(result, id: id)
                if generation != app.requestGeneration { group.cancelAll() }
            }
        }
        updateLatestProjection()
    }

    private static func fetch(_ load: @Sendable () async throws -> [MediaItem]) async -> Result<[MediaItem], APIError> {
        do {
            return .success(HomeMetadata.items(try await load()))
        } catch { return .failure(error as? APIError ?? .network) }
    }

    private func apply(_ result: Result<[MediaItem], APIError>, id: String) async {
        switch result {
        case .success(let items):
            for item in items { await userData.replaceFromServer(id: item.id, item.userData) }
            let projected = await userData.project(items)
            let visible =
                id == "resume" ? projected.filter { !$0.userData.played && !resetResumeIDs.contains($0.id) } : projected
            replace(.success(visible), id: id)
        case .failure(let error):
            let mapped = map(error)
            guard mapped != .cancelled else { return }
            replace(.failure(mapped), id: id)
            AppErrorMessage.report(mapped, log: log)
            app.handle(mapped)
        }
    }

    private func replace(_ result: Result<[MediaItem], AppError>, id: String) {
        let old: LoadState<[MediaItem]>
        if id == "resume" {
            old = resume
        } else if id == "nextUp" {
            old = nextUp
        } else {
            old = latestRows.first { $0.id == id }?.state ?? .idle
        }
        let state: LoadState<[MediaItem]>
        switch result {
        case .success(let items):
            rememberedIDs[id] = HomeFocus.restoredID(rememberedIDs[id], old: old.value ?? [], new: items)
            state = .loaded(items)
        case .failure(let error): state = .failed(error, previous: old.value)
        }
        if id == "resume" {
            resume = state
        } else if id == "nextUp" {
            nextUp = state
        } else if let index = latestRows.firstIndex(where: { $0.id == id }) {
            latestRows[index].state = state
        }
    }

    private func map(_ error: APIError) -> AppError {
        AppErrorMapping.map(error, context: .authenticated, deviceOffline: app.connectivity == .offline)
    }

    private func updateLatestProjection() {
        let items = latestRows.flatMap { $0.state.value ?? [] }
        if latestRows.allSatisfy({ $0.state.presentedError != nil }), let error = latestRows.first?.state.presentedError
        {
            latest = .failed(error, previous: items)
        } else {
            latest = .loaded(items)
        }
    }

    private func restoreSnapshot() {
        guard !restoredSnapshot else { return }
        restoredSnapshot = true
        guard let saved = snapshots.load() else { return }
        if case .signedIn(let session) = app.phase {
            if requireSnapshotOwner || saved.serverID != nil {
                guard saved.serverID == session.server.id, saved.userID == session.userID else { return }
            }
        }
        resume = .loaded(HomeMetadata.items(saved.resume))
        nextUp = .loaded(HomeMetadata.items(saved.nextUp))
        latest = .loaded(HomeMetadata.items(saved.latest))
        let views = saved.libraries ?? []
        libraries = .loaded(views.map(HomeMetadata.library))
        latestRows = views.map {
            HomeLibraryRow(
                library: HomeMetadata.library($0),
                state: .loaded(HomeMetadata.items(saved.latestByLibrary?[$0.id] ?? [])))
        }
    }

    private func saveSnapshot() {
        guard !Task.isCancelled else { return }
        var snapshot = HomeSnapshot(resume: resume.value ?? [], nextUp: nextUp.value ?? [], latest: latest.value ?? [])
        snapshot.libraries = libraries.value
        snapshot.latestByLibrary = Dictionary(uniqueKeysWithValues: latestRows.map { ($0.id, $0.state.value ?? []) })
        if case .signedIn(let session) = app.phase {
            snapshot.serverID = session.server.id
            snapshot.userID = session.userID
        } else {
            return
        }
        snapshots.save(snapshot)
    }
}
