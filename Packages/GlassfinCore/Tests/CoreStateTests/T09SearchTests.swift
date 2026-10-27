import CoreModels
import CoreNetworking
import CoreState
import Foundation
import GlassfinServices
import XCTest

final class T09SearchTests: XCTestCase {
    /// T09-03: a single Latin character sends no request and keeps recents available.
    @MainActor
    func testT09_03_oneLatinCharacterKeepsRecentsWithoutSearching() async throws {
        let fixture = try SearchFixture()
        defer { fixture.cleanup() }
        try fixture.store.record("previous", serverID: Sample.serverID, userID: Sample.userID)
        fixture.model.setTerm("s")
        XCTAssertTrue(fixture.backend.calls.isEmpty)
        XCTAssertEqual(fixture.model.recentQueries, ["previous"])
        XCTAssertEqual(fixture.model.state, .idle)
    }

    /// T09-04: two characters start a request.
    @MainActor
    func testT09_04_twoCharactersSearch() async throws {
        let fixture = try SearchFixture()
        defer { fixture.cleanup() }
        fixture.model.setTerm("st")
        await waitUntil { fixture.backend.calls.count == 1 }
        XCTAssertEqual(fixture.backend.calls.first?.term, "st")
    }

    /// T09-06: whitespace alone sends nothing; transmitted input has surrounding whitespace trimmed.
    @MainActor
    func testT09_06_whitespaceIsIgnoredForEligibilityAndTransmission() async throws {
        let fixture = try SearchFixture()
        defer { fixture.cleanup() }
        fixture.model.setTerm("   ")
        XCTAssertTrue(fixture.backend.calls.isEmpty)
        fixture.model.setTerm("  star  ")
        await waitUntil { fixture.backend.calls.count == 1 }
        XCTAssertEqual(fixture.backend.calls.first?.term, "star")
    }

    /// T09-07: twenty rapidly entered characters result in exactly one final request.
    @MainActor
    func testT09_07_twentyCharactersDebounceToOneRequest() async throws {
        let clock = SuspendingClock()
        let fixture = try SearchFixture(clock: clock)
        defer {
            clock.resumeAll()
            fixture.cleanup()
        }
        let text = "abcdefghijklmnopqrst"
        for count in 1...text.count {
            fixture.model.setTerm(String(text.prefix(count)))
            if count >= 2 { await clock.waitForSleeps(count - 1) }
        }
        XCTAssertTrue(fixture.backend.calls.isEmpty)
        clock.resumeAll()
        await waitUntil { fixture.backend.calls.count == 1 }
        XCTAssertEqual(fixture.backend.calls.first?.term, text)
        XCTAssertEqual(fixture.model.term, text)
    }

    /// T09-08: the canonical default is 100 graphemes, including multi-scalar emoji.
    @MainActor
    func testT09_08_longQueryIsCappedBeforeRequest() async throws {
        let fixture = try SearchFixture()
        defer { fixture.cleanup() }
        fixture.model.setTerm(String(repeating: "👩🏽‍🚀", count: 500))
        await waitUntil { fixture.backend.calls.count == 1 }
        XCTAssertEqual(fixture.model.term.count, 100)
        XCTAssertEqual(fixture.backend.calls.first?.term, String(repeating: "👩🏽‍🚀", count: 100))
    }

    /// T09-09, T09-15: clearing cancels pending work and rejects a late response.
    @MainActor
    func testT09_09_clearDiscardsLateResultsAndShowsRecents() async throws {
        let fixture = try SearchFixture()
        defer { fixture.cleanup() }
        try fixture.store.record("previous", serverID: Sample.serverID, userID: Sample.userID)
        fixture.model.setTerm("star")
        await waitUntil { fixture.backend.calls.count == 1 }
        fixture.model.setTerm("")
        fixture.backend.succeed(0, names: ["late"])
        await waitUntil { fixture.backend.completed == 1 }
        XCTAssertTrue(fixture.model.groups.isEmpty)
        XCTAssertEqual(fixture.model.state, .idle)
        XCTAssertEqual(fixture.model.recentQueries, ["previous"])
        XCTAssertEqual(fixture.backend.cancelledCompletions, 1)
    }

    /// T09-16: a cancellation response is never displayed or reported as an error.
    @MainActor
    func testT09_16_cancelledResponseIsSilent() async throws {
        let fixture = try SearchFixture()
        defer { fixture.cleanup() }
        fixture.model.setTerm("star")
        await waitUntil { fixture.backend.calls.count == 1 }
        let previousLogs = fixture.log.messages()
        fixture.backend.fail(0, .cancelled)
        await waitUntil { !fixture.model.state.isLoading }
        XCTAssertNil(fixture.model.blockingErrorKey)
        XCTAssertEqual(fixture.model.state, .idle)
        XCTAssertEqual(fixture.app.connectivity, .online)
        XCTAssertEqual(fixture.log.messages(), previousLogs)
    }

    /// T09-43: completing or retrying a query does not save it; opening a result does.
    @MainActor
    func testT09_43_historyRecordsOnlyResultSelection() async throws {
        let fixture = try SearchFixture()
        defer { fixture.cleanup() }
        fixture.model.setTerm("star")
        await waitUntil { fixture.backend.calls.count == 1 }
        fixture.backend.succeed(0, names: ["match"])
        await waitUntil { fixture.model.hasContent }
        XCTAssertTrue(fixture.model.recentQueries.isEmpty)
        fixture.model.open(try XCTUnwrap(fixture.model.state.value?.first))
        XCTAssertEqual(fixture.model.recentQueries, ["star"])
    }

    /// T09-56: offline searches send no request and retain usable recent-query text.
    @MainActor
    func testT09_56_offlineSearchKeepsRecentsAndDoesNotSend() async throws {
        let fixture = try SearchFixture()
        defer { fixture.cleanup() }
        try fixture.store.record("previous", serverID: Sample.serverID, userID: Sample.userID)
        fixture.app.handle(.offline)
        fixture.model.onAppear()
        fixture.model.setTerm("previous")
        XCTAssertTrue(fixture.backend.calls.isEmpty)
        XCTAssertEqual(fixture.model.term, "previous")
        XCTAssertEqual(fixture.model.recentQueries, ["previous"])
        XCTAssertEqual(fixture.model.bannerKey, .noNetworkConnection)
        XCTAssertEqual(fixture.model.blockingErrorKey, .noNetworkConnection)
    }

    /// T09-02: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.
    @MainActor
    func testT09_02_debounceAndCancellationBeforeRequest() async throws {
        let clock = SuspendingClock()
        let fixture = try SearchFixture(clock: clock)
        defer {
            clock.resumeAll()
            fixture.cleanup()
        }
        fixture.model.setTerm("st")
        await clock.waitForSleeps(1)
        XCTAssertTrue(fixture.backend.calls.isEmpty)
        XCTAssertEqual(clock.sleeps(), [NetworkThresholds.searchDebounce])
        fixture.model.setTerm("star")
        await clock.waitForSleeps(2)
        clock.resumeAll()
        await waitUntil { fixture.backend.calls.count == 1 }
        XCTAssertEqual(fixture.backend.calls.first?.term, "star")
    }

    /// T09-14: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    @MainActor
    func testT09_14_reverseResponsesOnlyLatestWins() async throws {
        let fixture = try SearchFixture()
        defer { fixture.cleanup() }
        fixture.model.setTerm("s")
        for (index, term) in ["st", "sta", "star"].enumerated() {
            fixture.model.setTerm(term)
            await waitUntil { fixture.backend.calls.count == index + 1 }
        }
        fixture.backend.succeed(2, names: ["star"])
        await waitUntil { fixture.model.state.value?.first?.name == "star" }
        fixture.backend.succeed(1, names: ["sta"])
        fixture.backend.succeed(0, names: ["st"])
        await waitUntil { fixture.backend.completed == 3 }
        XCTAssertEqual(fixture.model.state.value?.map(\.name), ["star"])
        XCTAssertEqual(fixture.model.term, "star")
        XCTAssertEqual(fixture.backend.cancelledCompletions, 2)
    }

    /// T09-05: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    @MainActor
    func testT09_05_minimumLengthAndCJK() async {
        for term in ["", " ", "a", "ä", "🎬"] { XCTAssertFalse(SearchPolicy.accepts(term)) }
        for term in ["ab", "ä&", "日", "本", "한", "あ", "𠀀", "  日  "] {
            XCTAssertTrue(SearchPolicy.accepts(term))
        }
    }

    /// T09-34: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    @MainActor
    func testT09_34_loadingThenEmptyAndInvalidTermClearsRows() async throws {
        let fixture = try SearchFixture()
        defer { fixture.cleanup() }
        fixture.model.setTerm("nothing")
        XCTAssertTrue(fixture.model.state.showsSkeleton)
        await waitUntil { fixture.backend.calls.count == 1 }
        fixture.backend.succeed(0, names: [])
        await waitUntil { fixture.model.showsEmpty }
        XCTAssertFalse(fixture.model.hasContent)
        fixture.model.setTerm("x")
        XCTAssertEqual(fixture.model.state, .idle)
        XCTAssertTrue(fixture.model.groups.isEmpty)
    }

    /// T09-29: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    @MainActor
    func testT09_29_errorAndRetry() async throws {
        let fixture = try SearchFixture()
        defer { fixture.cleanup() }
        fixture.model.setTerm("star")
        await waitUntil { fixture.backend.calls.count == 1 }
        fixture.backend.fail(0, .server(status: 500))
        await waitUntil { fixture.model.blockingErrorKey == .serverError }
        fixture.model.retry()
        await waitUntil { fixture.backend.calls.count == 2 }
        fixture.backend.succeed(1, names: ["recovered"])
        await waitUntil { fixture.model.hasContent }
        XCTAssertNil(fixture.model.blockingErrorKey)
    }

    /// T09-12: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    @MainActor
    func testT09_12_backKeepsTextResultsAndFocus() async throws {
        let fixture = try SearchFixture()
        defer { fixture.cleanup() }
        fixture.model.setTerm("star")
        await waitUntil { fixture.backend.calls.count == 1 }
        fixture.backend.succeed(0, names: ["first", "second"])
        await waitUntil { fixture.model.hasContent }
        let results = fixture.model.state.value
        fixture.model.rememberedIDs[.movies] = results?.last?.id
        fixture.model.selectedItem = results?.last
        fixture.model.onDisappear()
        fixture.model.selectedItem = nil
        fixture.model.onAppear()
        XCTAssertEqual(fixture.model.term, "star")
        XCTAssertEqual(fixture.model.state.value, results)
        XCTAssertEqual(fixture.model.rememberedIDs[.movies], results?.last?.id)
        XCTAssertEqual(fixture.backend.calls.count, 1)
    }

    /// T09-28: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    @MainActor
    func testT09_28_pagingDeduplicatesAndRetainsServerOrder() async throws {
        let fixture = try SearchFixture()
        defer { fixture.cleanup() }
        fixture.model.setTerm("star")
        await waitUntil { fixture.backend.calls.count == 1 }
        fixture.backend.succeed(0, names: ["zeta", "alpha"], nextIndex: 24)
        await waitUntil { fixture.model.hasContent }
        let last = try XCTUnwrap(fixture.model.state.value?.last?.id)
        fixture.model.loadNextPage(kind: .movies, visibleID: last)
        fixture.model.loadNextPage(kind: .movies, visibleID: last)
        await waitUntil { fixture.backend.calls.count == 2 }
        XCTAssertEqual(fixture.backend.calls[1].kind, .movies)
        XCTAssertEqual(fixture.backend.calls[1].page.startIndex, 24)
        fixture.backend.succeed(1, names: ["duplicate", "duplicate", "omega"], ids: [last, last, Sample.other])
        await waitUntil { fixture.model.paging.isEmpty }
        XCTAssertEqual(fixture.model.state.value?.map(\.name), ["zeta", "alpha", "omega"])
        XCTAssertNil(fixture.model.groups.first?.nextIndex)
    }

    /// T09-18: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    @MainActor
    func testT09_18_disappearCancelsAndResumesPendingSearch() async throws {
        let fixture = try SearchFixture()
        defer { fixture.cleanup() }
        fixture.model.setTerm("star")
        await waitUntil { fixture.backend.calls.count == 1 }
        fixture.model.onDisappear()
        fixture.backend.succeed(0, names: ["stale"])
        await waitUntil { fixture.backend.completed == 1 }
        XCTAssertNil(fixture.model.state.value)
        fixture.model.onAppear()
        await waitUntil { fixture.backend.calls.count == 2 }
        fixture.backend.succeed(1, names: ["fresh"])
        await waitUntil { fixture.model.state.value?.first?.name == "fresh" }
    }

    /// T09-59: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    @MainActor
    func testT09_59_errorsNeverSignOutExcept401() async throws {
        for error in [APIError.network, .timeout, .tls, .forbidden, .notFound, .server(status: 500), .decoding] {
            let fixture = try SearchFixture()
            fixture.model.setTerm("star")
            await waitUntil { fixture.backend.calls.count == 1 }
            fixture.backend.fail(0, error)
            await waitUntil { !fixture.model.state.isLoading }
            XCTAssertEqual(fixture.app.phase, .signedIn(Sample.session()))
            XCTAssertNotNil(try fixture.secure.data(for: Sample.account()))
            fixture.cleanup()
        }
    }

    /// T09-64: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    @MainActor
    func testT09_64_metadataIsLiteralThroughViewModel() async throws {
        let fixture = try SearchFixture()
        defer { fixture.cleanup() }
        fixture.model.setTerm("literal")
        await waitUntil { fixture.backend.calls.count == 1 }
        fixture.backend.succeed(0, names: ["\u{202E}<b>x</b>\u{0000}&amp; **link**"], overview: "a\u{2067}<i>b</i>\n")
        await waitUntil { fixture.model.hasContent }
        XCTAssertEqual(fixture.model.state.value?.first?.name, "<b>x</b>&amp; **link**")
        XCTAssertEqual(fixture.model.state.value?.first?.overview, "a<i>b</i>")
    }

    /// T09-64: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    @MainActor
    func testT09_64_viewModelBoundsNamesAndOverviewByGraphemes() async throws {
        let fixture = try SearchFixture()
        defer { fixture.cleanup() }
        fixture.model.setTerm("emoji")
        await waitUntil { fixture.backend.calls.count == 1 }
        fixture.backend.succeed(
            0,
            names: ["\u{202E}" + String(repeating: "👩🏽‍🚀", count: MetadataPolicy.nameMax + 1)],
            overview: "\u{0000}" + String(repeating: "e\u{301}", count: MetadataPolicy.overviewMax + 1))
        await waitUntil { fixture.model.hasContent }
        XCTAssertEqual(fixture.model.state.value?.first?.name.count, MetadataPolicy.nameMax)
        XCTAssertEqual(fixture.model.state.value?.first?.overview?.count, MetadataPolicy.overviewMax)
    }

    /// T09-66: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    @MainActor
    func testT09_66_queriesNeverReachLogs() async throws {
        let fixture = try SearchFixture()
        defer { fixture.cleanup() }
        let query = "private-search-marker"
        fixture.model.setTerm(query)
        await waitUntil { fixture.backend.calls.count == 1 }
        fixture.backend.succeed(0, names: ["match"])
        await waitUntil { fixture.model.hasContent }
        fixture.model.open(try XCTUnwrap(fixture.model.state.value?.first))
        XCTAssertEqual(fixture.model.recentQueries, [query])
        XCTAssertFalse(fixture.log.messages().joined().contains(query))
    }

    /// T09-53: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    @MainActor
    func testT09_53_userClearRemovesDiskHistoryAndViewState() async throws {
        let fixture = try SearchFixture()
        defer { fixture.cleanup() }
        fixture.model.setTerm("star")
        await waitUntil { fixture.backend.calls.count == 1 }
        fixture.backend.succeed(0, names: ["match"])
        await waitUntil { fixture.model.hasContent }
        fixture.model.open(try XCTUnwrap(fixture.model.state.value?.first))
        XCTAssertEqual(fixture.model.recentQueries, ["star"])
        fixture.model.clearRecents()
        XCTAssertTrue(fixture.model.recentQueries.isEmpty)
        XCTAssertEqual(try fixture.store.queries(serverID: Sample.serverID, userID: Sample.userID), [])
    }

    /// T09-59: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    @MainActor
    func testT09_59_stale401EndsSessionOnceCancelsWorkAndClearsHistory() async throws {
        let fixture = try SearchFixture()
        defer { fixture.cleanup() }
        try fixture.store.record("private", serverID: Sample.serverID, userID: Sample.userID)
        fixture.model.setTerm("older")
        await waitUntil { fixture.backend.calls.count == 1 }
        fixture.model.setTerm("newer")
        await waitUntil { fixture.backend.calls.count == 2 }
        fixture.backend.fail(0, .unauthorized)
        await waitUntil { fixture.app.sessionNoticeKey == .sessionExpired }
        fixture.backend.fail(1, .unauthorized)
        await waitUntil { fixture.backend.completed == 2 }
        XCTAssertEqual(fixture.app.requestGeneration, 1)
        XCTAssertEqual(fixture.app.phase, .needsLogin(Sample.server()))
        XCTAssertNil(try fixture.secure.data(for: Sample.account()))
        XCTAssertEqual(try fixture.store.queries(serverID: Sample.serverID, userID: Sample.userID), [])
        XCTAssertEqual(fixture.backend.calls.count, 2)
    }

    /// T09-57: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    @MainActor
    func testT09_57_serverDownKeepsContentSharedKeyAndTenSecondRecovery() async throws {
        let fixture = try SearchFixture()
        defer { fixture.cleanup() }
        fixture.model.setTerm("star")
        await waitUntil { fixture.backend.calls.count == 1 }
        fixture.backend.succeed(0, names: ["retained"])
        await waitUntil { fixture.model.hasContent }
        fixture.model.retry()
        await waitUntil { fixture.backend.calls.count == 2 }
        fixture.backend.fail(1, .network)
        await waitUntil { fixture.app.connectivity == .serverUnreachable }
        XCTAssertEqual(fixture.model.state.value?.first?.name, "retained")
        XCTAssertEqual(fixture.model.bannerKey, .serverUnreachable)
        XCTAssertNil(fixture.model.blockingErrorKey)
        XCTAssertEqual(fixture.app.scheduledPingDelay, .seconds(10))
        await fixture.app.probeServer()
        XCTAssertEqual(fixture.app.connectivity, .online)
        fixture.model.retryAfterRecovery()
        await waitUntil { fixture.backend.calls.count == 3 }
        fixture.backend.fail(2, .network)
        await waitUntil { fixture.app.connectivity == .serverUnreachable }
        fixture.model.setTerm("s")
        fixture.model.setTerm("empty-screen")
        await waitUntil { fixture.backend.calls.count == 4 }
        fixture.backend.fail(3, .network)
        await waitUntil { fixture.model.blockingErrorKey == .serverUnreachable }
        XCTAssertEqual(fixture.model.blockingErrorKey, AppErrorMessage.key(for: .serverUnreachable))
        fixture.model.onDisappear()
        await fixture.app.probeServer()
        fixture.model.retryAfterRecovery()
        XCTAssertFalse(fixture.model.state.isLoading, "Recovery must not restart requests in a hidden tab")
        fixture.model.onAppear()
        await waitUntil { fixture.backend.calls.count == 5 }
        fixture.backend.succeed(4, names: ["visible again"])
        await waitUntil { fixture.model.state.value?.first?.name == "visible again" }
    }

    /// T09-19: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    @MainActor
    func testT09_19_sameTermABAAndWrongResponseTermAreRejected() async throws {
        let fixture = try SearchFixture()
        defer { fixture.cleanup() }
        for (index, term) in ["star", "start", "star"].enumerated() {
            fixture.model.setTerm(term)
            await waitUntil { fixture.backend.calls.count == index + 1 }
        }
        fixture.backend.succeed(2, names: ["current"])
        await waitUntil { fixture.model.hasContent }
        fixture.backend.succeed(0, names: ["old same term"])
        fixture.backend.succeed(1, names: ["old different term"])
        await waitUntil { fixture.backend.completed == 3 }
        XCTAssertEqual(fixture.model.state.value?.first?.name, "current")
        fixture.model.retry()
        await waitUntil { fixture.backend.calls.count == 4 }
        fixture.backend.succeed(3, names: ["wrong"], responseTerm: "unrelated")
        await waitUntil { fixture.backend.completed == 4 }
        XCTAssertEqual(fixture.model.state.value?.first?.name, "current")
    }
}

@MainActor
private struct SearchFixture {
    let app: AppState
    let model: SearchViewModel
    let backend = GatedSearchBackend()
    let secure = CountingSecureStore()
    let log = CapturingLog()
    let store: RecentSearchStore
    let root: URL

    init(clock: any GlassfinClock = ManualClock()) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = RecentSearchStore(directory: root.appendingPathComponent("history"))
        app = AppState(
            secureStore: secure, settings: InMemorySettingsStore(), path: StaticConnectivityPath(online: true),
            pinger: StubPinger(), cacheRoot: root, clock: clock, automaticPing: false, log: log, recentSearches: store)
        try app.didSignIn(Sample.session(), token: Sample.token)
        model = SearchViewModel(backend: backend, app: app, clock: clock)
    }

    func cleanup() {
        model.onDisappear()
        backend.finishAll()
        try? FileManager.default.removeItem(at: root)
    }
}

/// Deliberately ignores cancellation, as a buffered SDK response can arrive after Task.cancel().
private final class GatedSearchBackend: SearchBackend, @unchecked Sendable {
    struct Call {
        var term: String
        var kind: SearchKind?
        var page: PageRequest
    }
    private let lock = NSLock()
    private var recorded: [Call] = []
    private var pending: [Int: CheckedContinuation<SearchResponse, any Error>] = [:]
    private var finished = 0
    private var cancelled = 0
    var calls: [Call] { lock.withLock { recorded } }
    var completed: Int { lock.withLock { finished } }
    var cancelledCompletions: Int { lock.withLock { cancelled } }

    func results(term: String, kind: SearchKind?, page: PageRequest) async throws(APIError) -> SearchResponse {
        defer {
            let isCancelled = Task.isCancelled
            lock.withLock {
                finished += 1
                if isCancelled { cancelled += 1 }
            }
        }
        do {
            return try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    let index = recorded.count
                    recorded.append(Call(term: term, kind: kind, page: page))
                    pending[index] = continuation
                }
            }
        } catch { throw error as? APIError ?? .network }
    }

    func succeed(
        _ index: Int, names: [String], ids: [String]? = nil, nextIndex: Int? = nil,
        overview: String? = nil, responseTerm: String? = nil
    ) {
        let call = calls[index]
        let items = names.enumerated().map { offset, name in
            MediaItem(
                id: ids?[offset] ?? String(format: "%032x", offset + 1), kind: .movie, name: name, overview: overview)
        }
        let response = SearchResponse(
            term: responseTerm ?? call.term, groups: [SearchGroup(id: .movies, items: items, nextIndex: nextIndex)])
        lock.withLock { pending.removeValue(forKey: index) }?.resume(returning: response)
    }

    func fail(_ index: Int, _ error: APIError) {
        lock.withLock { pending.removeValue(forKey: index) }?.resume(throwing: error)
    }

    func finishAll() {
        let values = lock.withLock {
            let values = Array(pending.values)
            pending = [:]
            return values
        }
        for value in values { value.resume(throwing: APIError.cancelled) }
    }
}
