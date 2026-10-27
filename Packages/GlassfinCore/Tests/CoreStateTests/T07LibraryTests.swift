import CoreModels
import CoreNetworking
import CoreState
import CoreTestSupport
import Foundation
import GlassfinServices
import XCTest

@MainActor
final class T07LibraryTests: XCTestCase {
    func testT07_01_browseRequestIncludesPagingSortFiltersAndUserData() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let client = MockAPIClient { request in
            if request.path == "/Items/Filters2" { return Data(#"{"Genres":["Drama"],"Years":[2025]}"#.utf8) }
            return Data(#"{"Items":[],"TotalRecordCount":0}"#.utf8)
        }
        let service = JellyfinLibraryService(client: client)
        let store = LibraryChoicesStore(settings: rig.settings, serverID: Sample.serverID, userID: Sample.userID)
        var choices = LibraryChoices()
        choices.sort = .rating
        choices.descending = true
        choices.unplayed = true
        choices.favorites = true
        choices.genre = "Drama & Comedy"
        choices.year = 2025
        store.save(choices, libraryID: Sample.library)
        let model = make(rig, service: service, preferences: store)
        await model.browse(Library(id: Sample.library, name: "Movies", collectionType: "movies"))
        let calls = await client.calls
        let call = try XCTUnwrap(calls.first { $0.path == "/Items" })
        let query = Dictionary(grouping: call.query, by: \.name).mapValues { $0.compactMap(\.value) }
        XCTAssertEqual(query["limit"], [String(ListPaging.pageSize)])
        XCTAssertEqual(query["startIndex"], ["0"])
        XCTAssertEqual(query["includeItemTypes"], ["Movie"])
        XCTAssertEqual(query["sortBy"], ["CommunityRating"])
        XCTAssertEqual(query["sortOrder"], ["Descending"])
        XCTAssertEqual(query["filters"], ["IsUnplayed", "IsFavorite"])
        XCTAssertEqual(query["genres"], [choices.genre!])
        XCTAssertEqual(query["years"], ["2025"])
        XCTAssertEqual(query["recursive"], ["true"])
        XCTAssertEqual(query["enableTotalRecordCount"], ["true"])
        XCTAssertEqual(query["enableUserData"], ["true"])
        XCTAssertEqual(query["fields"], ["PrimaryImageAspectRatio"])
        XCTAssertEqual(model.filters?.genres, ["Drama"])
        XCTAssertEqual(calls.last?.path, "/Items/Filters2")
    }

    func testT07_02_choicesPersistPerServerUserAndLibraryAndAllSortsMap() {
        let settings = InMemorySettingsStore()
        let store = LibraryChoicesStore(settings: settings, serverID: "s", userID: "u")
        for sort in LibrarySort.allCases {
            var choices = LibraryChoices()
            choices.sort = sort
            store.save(choices, libraryID: "l")
            XCTAssertEqual(store.load(libraryID: "l"), choices)
            XCTAssertEqual(choices.query(collectionType: "tvshows").includeItemTypes, ["Series"])
            XCTAssertEqual(choices.query(collectionType: "movies").sortBy, [sort.rawValue])
        }
        XCTAssertEqual(store.load(libraryID: "other"), LibraryChoices())
        XCTAssertEqual(
            LibraryChoicesStore(settings: settings, serverID: "other", userID: "u").load(libraryID: "l"),
            LibraryChoices())
        XCTAssertEqual(
            LibraryChoicesStore(settings: settings, serverID: "s", userID: "other").load(libraryID: "l"),
            LibraryChoices())
    }

    func testT07_03_pagesTwoThousandItemsAtTenRemainingWithoutDuplicateRequests() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let fixture = LibraryFixtureClient()
        let model = make(rig, service: JellyfinLibraryService(client: fixture))
        await model.reload(libraryID: LibraryFixtureClient.movieLibrary)
        XCTAssertEqual(model.state.value?.count, ListPaging.pageSize)
        for end in stride(from: ListPaging.pageSize, to: 2000, by: ListPaging.pageSize) {
            await model.loadNextPageIfNeeded(visibleIndex: end - ListPaging.prefetchRemaining - 2)
            XCTAssertEqual(model.state.value?.count, end)
            async let first: Void = model.loadNextPageIfNeeded(visibleIndex: end - ListPaging.prefetchRemaining - 1)
            async let second: Void = model.loadNextPageIfNeeded(visibleIndex: end - 1)
            _ = await (first, second)
        }
        XCTAssertEqual(model.state.value?.count, 2000)
        XCTAssertEqual(Set(model.state.value?.map(\.id) ?? []).count, 2000)
        await model.loadNextPageIfNeeded(visibleIndex: 1999)
        XCTAssertEqual(model.totalCount, 2000)
    }

    func testT07_04_cacheIncludesTheQueryAndUserAndStopsAtShortPage() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let client = MockAPIClient { request in
            let sort = request.query.first { $0.name == "sortBy" }?.value ?? ""
            return Self.json(["Items": [["Id": Sample.movie, "Name": sort, "Type": "Movie"]], "TotalRecordCount": 100])
        }
        let model = make(rig, service: JellyfinLibraryService(client: client))
        for sort in LibrarySort.allCases {
            var choice = LibraryChoices()
            choice.sort = sort
            await model.reload(libraryID: Sample.library, query: choice.query(collectionType: "movies"))
            XCTAssertEqual(model.state.value?.first?.name, sort.rawValue)
            await model.loadNextPageIfNeeded(visibleIndex: 0)
        }
        let calls = await client.calls
        XCTAssertEqual(calls.count, LibrarySort.allCases.count)
        await model.reload(libraryID: Sample.library, query: LibraryChoices().query(collectionType: "movies"))
        let cachedCalls = await client.calls
        XCTAssertEqual(cachedCalls.count, calls.count)
    }

    func testT07_05_malformedRecordsAdvanceServerOffsetAndDuplicatesAreRemoved() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let client = MockAPIClient { request in
            let start = request.query.first { $0.name == "startIndex" }?.value
            if start == "0" {
                var items: [[String: Any]] = (0..<48).map {
                    ["Id": LibraryFixtureClient.id($0), "Name": "Item", "Type": "Movie"]
                }
                items.append(["Name": "Missing ID"])
                items.append(["Id": false])
                return Self.json(["Items": items, "TotalRecordCount": 52])
            }
            return Self.json([
                "Items": [
                    ["Id": LibraryFixtureClient.id(47), "Name": "Duplicate", "Type": "Movie"],
                    ["Id": LibraryFixtureClient.id(51), "Name": "Last", "Type": "Movie"],
                ], "TotalRecordCount": 52,
            ])
        }
        let model = make(rig, service: JellyfinLibraryService(client: client))
        await model.reload(libraryID: Sample.library)
        await model.loadNextPageIfNeeded(visibleIndex: 47)
        XCTAssertEqual(model.state.value?.count, 49)
        let calls = await client.calls
        XCTAssertEqual(calls.last?.query.first { $0.name == "startIndex" }?.value, "50")
        await model.loadNextPageIfNeeded(visibleIndex: 48)
        let final = await client.calls
        XCTAssertEqual(final.count, 2)
    }

    func testT07_18_downMidBrowseKeepsContentBannerAndTenSecondRecovery() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let fixture = LibraryFixtureClient(scenario: "down")
        let model = make(rig, service: JellyfinLibraryService(client: fixture))
        await model.reload(libraryID: LibraryFixtureClient.movieLibrary)
        let previous = model.state.value
        await model.loadNextPageIfNeeded(visibleIndex: 49)
        XCTAssertEqual(model.state.value, previous)
        XCTAssertTrue(model.hasContent)
        XCTAssertEqual(model.errorKey, .serverUnreachable)
        XCTAssertEqual(rig.app.connectivity, .serverUnreachable)
        XCTAssertEqual(rig.app.bannerKey, .serverUnreachable)
        XCTAssertEqual(rig.app.scheduledPingDelay, .seconds(10))
        await rig.app.probeServer()
        XCTAssertEqual(rig.app.connectivity, .online)
        XCTAssertNil(rig.app.bannerKey)
        await model.retry()
        XCTAssertEqual(model.state.value?.count, 100)
    }

    func testT07_19_downWithoutContentUsesTheExistingServerDownKey() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let client = MockAPIClient { _ async throws(APIError) -> Data in throw APIError.network }
        let model = make(rig, service: JellyfinLibraryService(client: client))
        await model.reload(libraryID: Sample.library)
        XCTAssertFalse(model.hasContent)
        XCTAssertEqual(model.errorKey, .serverUnreachable)
        XCTAssertEqual(model.errorKey, rig.app.bannerKey)
        guard case .signedIn = rig.app.phase else { return XCTFail("Server down signed out") }
    }

    func testT07_26_viewModelsSanitizeProtocolValuesAndDetailCanResumeAndStartOver() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let raw = "<b>x</b>\u{202E}\u{0007}" + String(repeating: "👩‍👩‍👧‍👦", count: MetadataPolicy.overviewMax)
        rig.library.pages[0] = Page(items: [Sample.movie(name: raw)], totalCount: 1)
        let model = make(rig, service: rig.library)
        await model.reload(libraryID: Sample.library)
        XCTAssertEqual(model.state.value?.first?.name.count, MetadataPolicy.nameMax)
        XCTAssertTrue(model.state.value?.first?.name.hasPrefix("<b>x</b>") == true)
        XCTAssertFalse(model.state.value?.first?.name.contains("\u{202E}") == true)
        let detail = ItemDetailViewModel(library: JellyfinLibraryService(client: LibraryFixtureClient()), app: rig.app)
        await detail.load(id: LibraryFixtureClient.id(100))
        XCTAssertTrue(detail.state.value?.overview?.contains("<b>") == true)
        XCTAssertEqual(detail.playbackIntent()?.start, .seconds(1930))
        XCTAssertEqual(detail.playbackIntent(startOver: true)?.start, .zero)
        detail.audioStreamIndex = 1
        detail.subtitleStreamIndex = -1
        XCTAssertEqual(detail.playbackIntent()?.audioStreamIndex, 1)
        XCTAssertEqual(detail.playbackIntent()?.subtitleStreamIndex, -1)
        XCTAssertEqual(detail.similar.value?.count, 1)
    }

    func testT07_27_directTabsAndOverflowAndSanitizedLibraryNames() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let client = LibraryFixtureClient()
        let session = LibrarySession(
            app: rig.app, service: JellyfinLibraryService(client: client),
            images: LibraryImageLoader(client: client, cache: rig.app.images.disk), settings: rig.settings,
            serverID: Sample.serverID, userID: Sample.userID)
        await session.load()
        XCTAssertEqual(session.directLibraries.count, LibrarySession.directTabCount)
        XCTAssertEqual(session.overflowLibraries.count, 2)
        let intent = LibraryPlaybackIntent(itemID: try XCTUnwrap(ItemID(Sample.movie)), start: .seconds(-1))
        session.requestPlayback(intent)
        XCTAssertEqual(session.playbackIntent?.start, .zero)
    }

    private func make(_ rig: Harness, service: any LibraryService, preferences: LibraryChoicesStore? = nil)
        -> LibraryViewModel
    {
        LibraryViewModel(
            library: service, userData: rig.app.userData, responses: rig.app.responses, app: rig.app, clock: rig.clock,
            preferences: preferences)
    }

    nonisolated private static func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}
