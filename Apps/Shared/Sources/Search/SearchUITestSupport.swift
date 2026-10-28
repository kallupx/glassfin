#if DEBUG
    import GlassfinCore
    import Observation
    import SwiftUI

    /// In-process protocol fixture. No socket, credentials, or flags survive a Release build.
    struct SearchUITestClient: JellyfinAPIClient {
        static let firstID = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        static let secondID = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        private let requests = SearchUITestRequests()
        let imageFailures: SearchUITestImageFailures

        @MainActor
        init() { imageFailures = SearchUITestImageFailures() }

        func send(_ request: APIRequest) async throws(APIError) -> Data {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-uitest-search-down") { throw .network }
            if arguments.contains("-uitest-search-error") { throw .server(status: 500) }
            if request.path.hasPrefix("/Items/"), request.path.contains("/Images/") {
                await imageFailures.record()
                throw .responseTooLarge
            }
            if request.path.hasPrefix("/Items/") {
                return Data(
                    "{\"Id\":\"\(Self.secondID)\",\"Name\":\"<b>Literal detail</b>\",\"Type\":\"Movie\",\"Overview\":\"**Literal overview**\"}"
                        .utf8)
            }
            if arguments.contains("-uitest-search-empty") { return Data("{\"Items\":[]}".utf8) }
            let kind = request.query.first { $0.name == "includeItemTypes" }?.value ?? "Movie"
            if arguments.contains("-uitest-search-partial-error"), kind == "Series" { throw .server(status: 500) }
            if arguments.contains("-uitest-search-empty-series"), kind == "Series" {
                return Data("{\"Items\":[],\"TotalRecordCount\":0}".utf8)
            }
            let count = await requests.record(kind)
            if arguments.contains("-uitest-search-refresh-down"), count > 1 { throw .network }
            let first: String
            let second: String
            switch kind {
            case "Series":
                first = "cccccccccccccccccccccccccccccccc"
                second = "dddddddddddddddddddddddddddddddd"
            case "Episode":
                first = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
                second = "ffffffffffffffffffffffffffffffff"
            default:
                first = Self.firstID
                second = Self.secondID
            }
            var items: [[String: Any]] = [
                ["Id": first, "Name": "<b>First result</b>", "Type": kind],
                ["Id": second, "Name": "Second result", "Type": kind],
            ]
            if arguments.contains("-uitest-search-refresh"), count > 1 {
                items[0]["Name"] = "Updated first result"
                items[1]["Name"] = "Updated second result"
                items.reverse()
                if arguments.contains("-uitest-search-remove-focused") {
                    items.removeAll { $0["Id"] as? String == second }
                }
            }
            if arguments.contains("-uitest-search-24") {
                items = (1...24).map { index in
                    ["Id": String(format: "%032x", index), "Name": "Result \(index)", "Type": kind]
                }
                if kind != "Movie" { items = [] }
            }
            if arguments.contains("-uitest-search-images-fail") {
                for index in items.indices { items[index]["ImageTags"] = ["Primary": "missing"] }
            }
            do {
                return try JSONSerialization.data(withJSONObject: ["Items": items, "TotalRecordCount": items.count])
            } catch { throw .decoding }
        }
    }

    struct SearchUITestRoot: View {
        @State private var feature: SearchFeature
        @State private var client: SearchUITestClient

        init() {
            let arguments = ProcessInfo.processInfo.arguments
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let app = AppState(
                secureStore: InMemorySecureStore(), settings: InMemorySettingsStore(),
                path: StaticConnectivityPath(online: !arguments.contains("-uitest-search-offline")),
                pinger: SearchUITestPinger(), cacheRoot: root, automaticPing: false,
                recentSearches: RecentSearchStore(directory: root.appendingPathComponent("history")))
            let session = UserSession(
                server: ServerInfo(
                    id: "11111111111111111111111111111111", name: "Search fixture",
                    url: URL(string: "https://media.example")!, version: SemVer(major: 12, minor: 2, patch: 0)),
                userID: "22222222222222222222222222222222", userName: "Ada", isAdministrator: false)
            try? app.didSignIn(session, token: "fixture-token")
            if arguments.contains("-uitest-search-recents") {
                try? app.recentSearches.record("previous", serverID: session.server.id, userID: session.userID)
            }
            if arguments.contains("-uitest-search-offline") { app.handle(.offline) }
            let client = SearchUITestClient()
            _client = State(initialValue: client)
            _feature = State(initialValue: SearchFeature(app: app, session: session, client: client))
        }

        var body: some View {
            if ProcessInfo.processInfo.arguments.contains("-uitest-search-tabs") {
                LibraryTabShell(
                    libraries: [],
                    home: AnyView(Copy.text(.tabHome).accessibilityIdentifier("search.fixture.home")),
                    search: AnyView(search))
            } else {
                search
            }
        }

        private var search: some View {
            SearchView(feature: feature)
                .overlay(alignment: .bottomTrailing) {
                    if client.imageFailures.count > 0 {
                        Text(verbatim: String(client.imageFailures.count)).frame(width: 1, height: 1)
                            .accessibilityIdentifier("search.fixture.imageFailures")
                    }
                }
                #if os(tvOS)
                    .onPlayPauseCommand {
                        if ProcessInfo.processInfo.arguments.contains("-uitest-search-refresh") {
                            feature.model.retry()
                        }
                    }
                #endif
        }
    }

    @MainActor
    @Observable
    final class SearchUITestImageFailures {
        private(set) var count = 0
        func record() { count += 1 }
    }

    private actor SearchUITestRequests {
        private var counts: [String: Int] = [:]

        func record(_ kind: String) -> Int {
            counts[kind, default: 0] += 1
            return counts[kind, default: 0]
        }
    }

    private struct SearchUITestPinger: ReachabilityPinging {
        func ping() async -> PingOutcome { .ok }
    }
#endif
