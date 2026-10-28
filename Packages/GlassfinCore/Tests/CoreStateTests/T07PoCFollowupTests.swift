import CoreModels
import CoreNetworking
import CoreState
import CoreTestSupport
import Foundation
import GlassfinServices
import XCTest

final class T07PoCFollowupTests: XCTestCase {
    /// T07-41: both requests must be suspended inside the fake before either response is released.
    @MainActor
    func testT07_41_openingSeriesStartsItemAndSeasonsConcurrently() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let itemStarted = expectation(description: "Item request entered")
        let seasonsStarted = expectation(description: "Seasons request entered")
        let finished = expectation(description: "Series opening finished")
        let client = T07SeriesGateClient(itemStarted: itemStarted, seasonsStarted: seasonsStarted)
        let service = JellyfinLibraryService(client: client)
        let detail = ItemDetailViewModel(library: service, app: rig.app)
        let series = SeriesViewModel(library: service, userData: rig.app.userData, app: rig.app)
        let opening = Task {
            await detail.load(id: LibraryFixtureClient.series, kind: .series, series: series)
            finished.fulfill()
        }
        defer { opening.cancel() }
        let started = await XCTWaiter.fulfillment(of: [itemStarted, seasonsStarted], timeout: 2)
        let pending = await client.pendingPaths
        let completed = await client.completedPaths
        let requests = await client.requests
        XCTAssertEqual(started, .completed, "Sequential loading cannot reach both gates")
        let itemPath = "/Items/\(LibraryFixtureClient.series)"
        let seasonsPath = "/Shows/\(LibraryFixtureClient.series)/Seasons"
        XCTAssertEqual(Set(pending), [itemPath, seasonsPath])
        XCTAssertEqual(pending.count, 2)
        XCTAssertTrue(completed.isEmpty, "Neither gated response may complete before release")
        for path in [itemPath, seasonsPath] {
            let matches = requests.filter { $0.path == path }
            XCTAssertEqual(matches.count, 1, path)
            XCTAssertEqual(matches.first?.method, "GET", path)
            XCTAssertEqual(
                matches.first?.query.filter { $0.name == "enableUserData" },
                [URLQueryItem(name: "enableUserData", value: "true")], path)
        }
        XCTAssertEqual(
            requests.first { $0.path == itemPath }?.query.first { $0.name == "fields" }?.value,
            "Overview,People,Studios,Genres,Taglines,MediaStreams,MediaSources")
        XCTAssertEqual(
            requests.first { $0.path == seasonsPath }?.query, [URLQueryItem(name: "enableUserData", value: "true")])
        // Always release, including after a failed start assertion, so a sequential regression cannot hang.
        await client.release()
        let result = await XCTWaiter.fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(result, .completed)
        if result == .completed { await opening.value }
        XCTAssertEqual(detail.state.value?.kind, .series)
        XCTAssertEqual(series.seasons.value?.count, 3)
    }

    /// T07-34: external and embedded subtitles use metadata only, in first-seen language order.
    @MainActor
    func testT07_34_subtitleLanguagesAreStableAndDeduplicatedWithoutDownloadingFiles() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/m07-subtitles.json"))
        let client = MockAPIClient { request throws(APIError) in
            if request.path == "/Items/\(Sample.movie)" { return data }
            if request.path == "/Items/\(Sample.movie)/Similar" {
                return Data(#"{"Items":[],"TotalRecordCount":0}"#.utf8)
            }
            XCTFail("Unexpected request while reading subtitle metadata: \(request.path)")
            throw .notFound
        }
        let detail = ItemDetailViewModel(library: JellyfinLibraryService(client: client), app: rig.app)
        await detail.load(id: Sample.movie)
        let metadata = try XCTUnwrap(detail.state.value?.detail)
        let subtitles = metadata.technicalStreams.filter { $0.kind == "Subtitle" }
        XCTAssertEqual(subtitles.map(\.technicalLabel), ["fin", "eng", "swe"])
        XCTAssertEqual(subtitles.map(\.id), [2, 3, 7])
        XCTAssertEqual(metadata.streams.filter { $0.kind == "Subtitle" }.count, 7)
        await detail.refreshFromStore()
        XCTAssertEqual(detail.state.value?.detail?.technicalStreams.filter { $0.kind == "Subtitle" }, subtitles)
        let requests = await client.calls
        XCTAssertEqual(requests.map(\.path), ["/Items/\(Sample.movie)", "/Items/\(Sample.movie)/Similar"])
        XCTAssertEqual(requests.map(\.method), ["GET", "GET"])
        XCTAssertFalse(requests.contains { $0.path.localizedCaseInsensitiveContains("subtitle") })
    }
}

private actor T07SeriesGateClient: JellyfinAPIClient {
    private let fixture = LibraryFixtureClient()
    private let itemStarted: XCTestExpectation
    private let seasonsStarted: XCTestExpectation
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var released = false
    var requests: [APIRequest] = []
    var pendingPaths: [String] = []
    var completedPaths: [String] = []

    init(itemStarted: XCTestExpectation, seasonsStarted: XCTestExpectation) {
        self.itemStarted = itemStarted
        self.seasonsStarted = seasonsStarted
    }

    func send(_ request: APIRequest) async throws(APIError) -> Data {
        requests.append(request)
        let item = request.path == "/Items/\(LibraryFixtureClient.series)"
        let seasons = request.path == "/Shows/\(LibraryFixtureClient.series)/Seasons"
        if item || seasons {
            if !released {
                await withCheckedContinuation { continuation in
                    waiting.append(continuation)
                    pendingPaths.append(request.path)
                    if item { itemStarted.fulfill() } else { seasonsStarted.fulfill() }
                }
            }
            completedPaths.append(request.path)
        }
        return try await fixture.send(request)
    }

    func release() {
        released = true
        let continuations = waiting
        waiting.removeAll()
        pendingPaths.removeAll()
        for continuation in continuations { continuation.resume() }
    }
}
