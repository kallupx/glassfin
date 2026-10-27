import CoreModels
import CoreNetworking
import Foundation
import GlassfinServices
import Observation

@MainActor
@Observable
public final class SearchViewModel {
    public private(set) var term = ""
    public private(set) var state: LoadState<[MediaItem]> = .idle
    public private(set) var groups: [SearchGroup] = []
    public private(set) var recentQueries: [String] = []
    public private(set) var historyFailed = false
    public var rememberedIDs: [SearchKind: String] = [:]
    public var focusedKind: SearchKind?
    public var selectedItem: MediaItem?
    public private(set) var paging: Set<SearchKind> = []

    @ObservationIgnored private let backend: any SearchBackend
    @ObservationIgnored private let app: AppState
    @ObservationIgnored private let clock: any GlassfinClock
    @ObservationIgnored private let signposter: any Signposting
    @ObservationIgnored private let userData: UserDataStore
    @ObservationIgnored private let session: UserSession?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var pageTasks: [SearchKind: Task<Void, Never>] = [:]
    @ObservationIgnored private var ticket = 0
    @ObservationIgnored private var visible = true
    @ObservationIgnored private var needsResume = false
    @ObservationIgnored private var resultsTerm: String?

    public init(
        backend: any SearchBackend, app: AppState,
        clock: any GlassfinClock = SystemGlassfinClock(),
        signposter: any Signposting = Signposters.production()
    ) {
        self.backend = backend
        self.app = app
        self.userData = app.userData
        self.clock = clock
        self.signposter = signposter
        if case .signedIn(let session) = app.phase { self.session = session } else { self.session = nil }
        loadRecents()
    }

    /// Keeps M02's protocol-injected foundation tests source compatible.
    public convenience init(
        search: any SearchService, userData: UserDataStore, app: AppState,
        clock: any GlassfinClock, signposter: any Signposting
    ) {
        self.init(backend: SearchServiceBackend(service: search), app: app, clock: clock, signposter: signposter)
    }

    public var hasContent: Bool { !(state.value ?? []).isEmpty }
    public var showsEmpty: Bool {
        if case .loaded(let items) = state { return items.isEmpty }
        return false
    }
    public var blockingErrorKey: AuthCopy.Key? {
        guard !hasContent else { return nil }
        return state.presentedError.flatMap { AppErrorMessage.key(for: $0) }
    }
    public var bannerKey: AuthCopy.Key? { app.bannerKey }
    public var isOffline: Bool { app.connectivity == .offline }

    public func setTerm(_ newTerm: String) {
        let bounded = String(newTerm.prefix(SearchPolicy.maximumQueryCharacters))
        guard bounded != term else { return }
        term = bounded
        cancelWork()
        ticket += 1
        rememberedIDs = [:]
        focusedKind = nil
        guard SearchPolicy.accepts(term) else {
            groups = []
            state = .idle
            loadRecents()
            return
        }
        groups = []
        state = .idle
        start(debounce: true)
    }

    public func retry() {
        guard SearchPolicy.accepts(term) else { return }
        cancelWork()
        ticket += 1
        start(debounce: false)
    }

    public func retryAfterRecovery() {
        guard let error = state.presentedError, AppErrorMapping.isConnectivity(error) else { return }
        if visible { retry() } else { needsResume = true }
    }

    public func onAppear() {
        visible = true
        loadRecents()
        let recovered =
            app.connectivity == .online
            && state.presentedError.map(AppErrorMapping.isConnectivity) == true
        if needsResume || recovered, SearchPolicy.accepts(term) { start(debounce: false) }
        needsResume = false
    }

    /// Navigation owns this instance, so cancelling work never resets text/results/focus.
    public func onDisappear() {
        visible = false
        needsResume = needsResume || state.isLoading
        cancelWork()
        ticket += 1
        if state.isLoading { state = state.value.map { .loaded($0) } ?? .idle }
    }

    /// Q9-06: save only a deliberate result selection, never each debounce or empty result.
    public func open(_ item: MediaItem) {
        selectedItem = item
        guard let session, app.phase == .signedIn(session) else { return }
        do {
            try app.recentSearches.record(normalizedTerm, serverID: session.server.id, userID: session.userID)
            loadRecents()
        } catch { historyFailed = true }
    }

    public func clearRecents() {
        guard let session else { return }
        do {
            try app.recentSearches.clear(serverID: session.server.id, userID: session.userID)
            recentQueries = []
            historyFailed = false
        } catch { historyFailed = true }
    }

    public func loadNextPage(kind: SearchKind, visibleID: String) {
        guard !state.isLoading, resultsTerm == normalizedTerm, !paging.contains(kind),
            let group = groups.first(where: { $0.id == kind }),
            group.items.suffix(5).contains(where: { $0.id == visibleID }), let next = group.nextIndex
        else { return }
        paging.insert(kind)
        let current = ticket
        let query = normalizedTerm
        let generation = app.requestGeneration
        let work = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if current == ticket {
                    paging.remove(kind)
                    pageTasks[kind] = nil
                }
            }
            do {
                let response = try await backend.results(
                    term: query, kind: kind, page: PageRequest(startIndex: next, limit: SearchPolicy.pageSize))
                guard isCurrent(current, query, generation), response.term == query,
                    let index = groups.firstIndex(where: { $0.id == kind }),
                    let page = response.groups.first(where: { $0.id == kind })
                else { return }
                let projected = await userData.project(page.items.map { $0.searchDisplayItem })
                guard isCurrent(current, query, generation) else { return }
                var seen = Set(groups[index].items.map(\.id))
                groups[index].items += projected.filter { seen.insert($0.id).inserted }
                groups[index].nextIndex = page.nextIndex
                publish()
            } catch {
                fail(error as? APIError ?? .network, current: current, query: query, generation: generation)
            }
        }
        pageTasks[kind] = work
        track(work)
    }

    private var normalizedTerm: String { term.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func start(debounce: Bool) {
        guard !isOffline else {
            state = .failed(.offline, previous: state.value)
            return
        }
        let current = ticket
        let query = normalizedTerm
        let generation = app.requestGeneration
        state = .loading(previous: state.value)
        let work = Task { @MainActor [weak self] in
            guard let self else { return }
            if debounce {
                do { try await clock.sleep(for: NetworkThresholds.searchDebounce) } catch { return }
            }
            guard isCurrent(current, query, generation) else { return }
            let interval = signposter.begin(.searchResults)
            defer { signposter.end(interval) }
            do {
                let response = try await backend.results(
                    term: query, kind: nil, page: PageRequest(limit: SearchPolicy.pageSize))
                guard isCurrent(current, query, generation), response.term == query else { return }
                var projected: [SearchGroup] = []
                for kind in SearchKind.allCases {
                    if let group = response.groups.first(where: { $0.id == kind }) {
                        let items = await userData.project(group.items.map { $0.searchDisplayItem })
                        projected.append(SearchGroup(id: kind, items: items, nextIndex: group.nextIndex))
                    }
                }
                guard isCurrent(current, query, generation) else { return }
                groups = projected
                resultsTerm = query
                publish()
                for error in response.failedRows.values {
                    app.handle(AppErrorMapping.map(error, context: .authenticated, deviceOffline: isOffline))
                }
            } catch {
                fail(error as? APIError ?? .network, current: current, query: query, generation: generation)
            }
        }
        task = work
        track(work)
    }

    private func isCurrent(_ current: Int, _ query: String, _ generation: Int) -> Bool {
        !Task.isCancelled && current == ticket && query == normalizedTerm && generation == app.requestGeneration
    }

    private func fail(_ error: APIError, current: Int, query: String, generation: Int) {
        if error == .unauthorized, generation == app.requestGeneration { app.handle(.unauthorized) }
        guard isCurrent(current, query, generation) else { return }
        let mapped = AppErrorMapping.map(error, context: .authenticated, deviceOffline: app.connectivity == .offline)
        guard mapped != .cancelled else {
            state = state.value.map { .loaded($0) } ?? .idle
            return
        }
        state = .failed(mapped, previous: state.value)
        app.handle(mapped)
    }

    private func publish() { state = .loaded(groups.flatMap(\.items)) }

    private func cancelWork() {
        task?.cancel()
        for work in pageTasks.values { work.cancel() }
        pageTasks = [:]
        paging = []
    }

    private func track(_ work: Task<Void, Never>) {
        let id = app.scope.track(work)
        let scope = app.scope
        Task {
            await work.value
            scope.untrack(id)
        }
    }

    private func loadRecents() {
        guard let session else { return }
        do {
            recentQueries = try app.recentSearches.queries(serverID: session.server.id, userID: session.userID)
            historyFailed = false
        } catch { historyFailed = true }
    }
}
