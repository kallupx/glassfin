import CoreModels
import CoreNetworking
import Foundation
import GlassfinServices
import Observation

private struct LibraryCachedPage: Codable, Sendable {
    var items: [MediaItem]
    var totalCount: Int?
    var consumed: Int
    var exhausted: Bool
}

@MainActor
@Observable
public final class LibraryViewModel {
    public private(set) var state: LoadState<[MediaItem]> = .idle
    public private(set) var totalCount: Int?
    public private(set) var choices = LibraryChoices()
    public private(set) var filters: ItemFilterSet?
    public private(set) var filterError: AppError?
    public var focusedID: String?
    public var scrollID: String?

    @ObservationIgnored private let library: any LibraryService
    @ObservationIgnored private let userData: UserDataStore
    @ObservationIgnored private let responses: ResponseCache
    @ObservationIgnored private let app: AppState
    @ObservationIgnored private let clock: any GlassfinClock
    @ObservationIgnored private let log: any GlassfinLog
    @ObservationIgnored private let preferences: LibraryChoicesStore?
    @ObservationIgnored private var libraryID = ""
    @ObservationIgnored private var collectionType: String?
    @ObservationIgnored private var query = ItemQuery()
    @ObservationIgnored private var nextIndex = 0
    @ObservationIgnored private var exhausted = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pageInFlight = false
    @ObservationIgnored private var pageTask: Task<Result<Page<MediaItem>, APIError>, Never>?

    public init(
        library: any LibraryService, userData: UserDataStore, responses: ResponseCache,
        app: AppState, clock: any GlassfinClock, log: any GlassfinLog = SilentLog(),
        preferences: LibraryChoicesStore? = nil
    ) {
        self.library = library
        self.userData = userData
        self.responses = responses
        self.app = app
        self.clock = clock
        self.log = log
        self.preferences = preferences
    }

    public var errorKey: AuthCopy.Key? { state.presentedError.flatMap(AppErrorMessage.key) }
    public var hasContent: Bool { !(state.value ?? []).isEmpty }

    public func browse(_ definition: Library) async {
        collectionType = definition.collectionType
        choices = preferences?.load(libraryID: definition.id) ?? choices
        await reload(libraryID: definition.id, query: choices.query(collectionType: collectionType))
        guard !Task.isCancelled else { return }
        await loadFilters()
    }

    public func choose(_ choices: LibraryChoices) async {
        self.choices = choices
        preferences?.save(choices, libraryID: libraryID)
        await reload(libraryID: libraryID, query: choices.query(collectionType: collectionType))
    }

    public func retry() async {
        // A failed next page resumes at its offset, retaining content and scroll state.
        if nextIndex > 0, hasContent {
            await loadPage(reset: false, force: true)
        } else {
            await reload(libraryID: libraryID, query: query, force: true)
        }
    }

    public func reload(libraryID: String, query: ItemQuery = ItemQuery(), force: Bool = false) async {
        guard ItemID(libraryID) != nil else {
            state = .failed(.internalInvariant, previous: state.value)
            return
        }
        let sameQuery = self.libraryID == libraryID && self.query == query
        // Retain the previous query on failure while showing the shared banner.
        let previous = self.libraryID == libraryID ? state.value : nil
        self.libraryID = libraryID
        self.query = query
        pageTask?.cancel()
        generation += 1
        pageInFlight = false
        nextIndex = 0
        exhausted = false
        totalCount = nil
        if !sameQuery {
            focusedID = nil
            scrollID = nil
        }
        state = .loading(previous: previous)
        await loadPage(reset: true, force: force)
    }

    public func loadNextPageIfNeeded(visibleIndex: Int) async {
        guard !exhausted, !pageInFlight,
            ListPaging.shouldPrefetch(index: visibleIndex, loaded: state.value?.count ?? 0, total: nil)
        else { return }
        await loadPage(reset: false, force: false)
    }

    public func onDisappear() {
        pageTask?.cancel()
        generation += 1
        pageInFlight = false
    }

    public func refreshFromStore() async {
        guard let items = state.value else { return }
        let projected = await userData.project(items)
        guard !Task.isCancelled else { return }
        if case .failed(let error, _) = state {
            state = .failed(error, previous: projected)
        } else {
            state = .loaded(projected)
        }
    }

    private func loadFilters() async {
        let expected = generation
        do {
            let fetched = try await library.filters(in: libraryID)
            guard expected == generation, !Task.isCancelled else { return }
            filters = ItemFilterSet(
                genres: fetched.genres.map { MetadataPolicy.clean($0, limit: MetadataPolicy.genreMax) },
                years: fetched.years)
            filterError = nil
        } catch {
            guard expected == generation, !Task.isCancelled else { return }
            let mapped = map(error)
            filterError = mapped
            app.handle(mapped)
        }
    }

    private func loadPage(reset: Bool, force: Bool) async {
        guard !pageInFlight else { return }
        pageInFlight = true
        let expected = generation
        let sessionGeneration = app.requestGeneration
        defer {
            if generation == expected {
                pageInFlight = false
                pageTask = nil
            }
        }
        let start = reset ? 0 : nextIndex
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let fingerprint = CertificateFingerprint.sha256Hex((try? encoder.encode(query)) ?? Data())
        let namespace: String
        if case .signedIn(let session) = app.phase {
            namespace = "\(session.server.id).\(session.userID)"
        } else {
            namespace = "anonymous"
        }
        let key = "library.\(namespace).\(libraryID).\(fingerprint).\(start)"
        do {
            let payload: LibraryCachedPage
            if !force, !query.sortBy.contains(LibrarySort.random.rawValue),
                let data = await responses.data(for: key, now: clock.now()),
                let cached = try? JSONDecoder().decode(LibraryCachedPage.self, from: data)
            {
                payload = cached
            } else {
                let service = library
                let id = libraryID
                let query = query
                let child = Task { () -> Result<Page<MediaItem>, APIError> in
                    do {
                        return .success(
                            try await service.items(
                                in: id, query: query, page: PageRequest(startIndex: start, limit: ListPaging.pageSize)))
                    } catch let error as APIError { return .failure(error) } catch { return .failure(.network) }
                }
                pageTask = child
                let result = await withTaskCancellationHandler {
                    await child.value
                } onCancel: {
                    child.cancel()
                }
                let page = try result.get()
                let consumed = max(0, page.consumedCount ?? page.items.count)
                let end = start + consumed
                payload = LibraryCachedPage(
                    items: page.items.map { $0.cleanedForDisplay() }, totalCount: page.totalCount,
                    consumed: consumed,
                    exhausted: consumed < ListPaging.pageSize || page.totalCount.map { end >= $0 } == true)
                if generation == expected, sessionGeneration == app.requestGeneration, !Task.isCancelled,
                    let data = try? encoder.encode(payload)
                {
                    await responses.insert(data, for: key, ttl: NetworkThresholds.libraryListTTL, now: clock.now())
                }
            }
            let projected = await userData.project(payload.items.map { $0.cleanedForDisplay() })
            guard generation == expected, sessionGeneration == app.requestGeneration, !Task.isCancelled else { return }
            var seen = Set<String>()
            state = .loaded(((reset ? [] : state.value ?? []) + projected).filter { seen.insert($0.id).inserted })
            totalCount = payload.totalCount
            nextIndex = start + payload.consumed
            exhausted = payload.exhausted
            // Malformed or duplicate items must not leave a blank viewport or stall paging.
            if !exhausted, (state.value?.count ?? 0) <= ListPaging.prefetchRemaining {
                pageInFlight = false
                await loadPage(reset: false, force: force)
            }
        } catch {
            guard generation == expected, sessionGeneration == app.requestGeneration, !Task.isCancelled else { return }
            let mapped = map(error)
            guard mapped != .cancelled else { return }
            state = .failed(mapped, previous: state.value)
            AppErrorMessage.report(mapped, log: log)
            app.handle(mapped)
        }
    }

    private func map(_ error: APIError) -> AppError {
        AppErrorMapping.map(error, context: .authenticated, deviceOffline: app.connectivity == .offline)
    }
}
