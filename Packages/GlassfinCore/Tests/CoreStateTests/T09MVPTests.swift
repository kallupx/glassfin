import CoreModels
import CoreNetworking
import CoreState
import Foundation
import GlassfinServices
import XCTest

final class T09MVPTests: XCTestCase {
    /// T09-19: returning to the same text within the debounce sends just the final text.
    @MainActor
    func testT09_19_debouncedABAReturnsIdenticalResultsWithOneFinalRequest() async throws {
        let harness = Harness.make(suspendingClock: true)
        defer { harness.cleanup() }
        try harness.signIn()
        let clock = try XCTUnwrap(harness.suspending)
        let model = SearchViewModel(
            search: harness.search, userData: harness.app.userData, app: harness.app,
            clock: clock, signposter: harness.signposter)
        defer { model.onDisappear() }
        model.setTerm("star")
        await clock.waitForSleeps(1)
        clock.resumeAll()
        await waitUntil { model.hasContent }
        let original = model.state.value
        model.setTerm("sta")
        await clock.waitForSleeps(2)
        model.setTerm("star")
        await clock.waitForSleeps(3)
        XCTAssertEqual(harness.search.termsSeen(), ["star"])
        clock.resumeAll()
        await waitUntil { model.hasContent }
        XCTAssertEqual(harness.search.termsSeen(), ["star", "star"])
        XCTAssertEqual(model.state.value, original)
    }

    /// T09-30, T09-31: only P0 rows reach the view model, in canonical group order.
    @MainActor
    func testT09_30_onlyMovieSeriesAndEpisodeRowsInCanonicalOrder() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        harness.search.results = [
            MediaItem(id: "episode", kind: .episode, name: "Episode"),
            MediaItem(id: "person", kind: .other("Person"), name: "Person"),
            MediaItem(id: "series", kind: .series, name: "Series"),
            MediaItem(id: "music", kind: .other("Audio"), name: "Music"),
            MediaItem(id: "collection", kind: .other("BoxSet"), name: "Collection"),
            MediaItem(id: "movie", kind: .movie, name: "Movie"),
        ]
        let model = SearchViewModel(
            search: harness.search, userData: harness.app.userData, app: harness.app,
            clock: harness.clock, signposter: harness.signposter)
        defer { model.onDisappear() }
        model.setTerm("star")
        await waitUntil { model.hasContent }
        XCTAssertEqual(model.groups.map(\.id), [.movies, .series, .episodes])
        XCTAssertEqual(model.state.value?.map(\.id), ["movie", "series", "episode"])
    }

    /// T09-41: a full 24-item final page survives mapping, and its last card does not fetch again.
    @MainActor
    func testT09_41_all24ResultsRemainInServerOrderWithoutAnotherPage() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        let ids = (1...24).map { String(format: "%032x", $0) }
        let items = ids.map { ["Id": $0, "Type": "Movie", "Name": $0] }
        let data = try JSONSerialization.data(withJSONObject: ["Items": items, "TotalRecordCount": 24])
        let client = ScriptedClient(results: [.success(data)])
        // Query a single kind through the real backend so sibling fixture failures cannot hide a card.
        let page = try await ItemsSearchBackend(client: client).results(
            term: "star", kind: .movies, page: PageRequest(limit: 24))
        XCTAssertEqual(page.groups.first?.items.map(\.id), ids)
        XCTAssertNil(page.groups.first?.nextIndex)
        let allRowsClient = ScriptedClient(results: [.success(data), .success(data), .success(data)])
        let allRows = SearchViewModel(
            backend: ItemsSearchBackend(client: allRowsClient), app: harness.app, clock: harness.clock)
        defer { allRows.onDisappear() }
        allRows.setTerm("star")
        await waitUntil { allRows.hasContent }
        XCTAssertEqual(allRows.groups.first?.items.map(\.id), ids)
        XCTAssertEqual(allRows.state.value?.count, 24)
        allRows.loadNextPage(kind: .movies, visibleID: try XCTUnwrap(ids.last))
        XCTAssertTrue(allRows.paging.isEmpty)
        XCTAssertEqual(allRowsClient.requests().count, 3)
    }
}
