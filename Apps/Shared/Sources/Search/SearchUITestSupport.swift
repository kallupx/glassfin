#if DEBUG
    import GlassfinCore
    import SwiftUI

    /// In-process protocol fixture. No socket, credentials, or flags survive a Release build.
    struct SearchUITestClient: JellyfinAPIClient {
        static let firstID = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        static let secondID = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

        func send(_ request: APIRequest) async throws(APIError) -> Data {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-uitest-search-error") { throw .server(status: 500) }
            if request.path.hasPrefix("/Items/") {
                return Data(
                    "{\"Id\":\"\(Self.secondID)\",\"Name\":\"<b>Literal detail</b>\",\"Type\":\"Movie\",\"Overview\":\"**Literal overview**\"}"
                        .utf8)
            }
            if arguments.contains("-uitest-search-empty") { return Data("{\"Items\":[]}".utf8) }
            let kind = request.query.first { $0.name == "includeItemTypes" }?.value ?? "Movie"
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
            let items: [[String: String]] = [
                ["Id": first, "Name": "<b>First result</b>", "Type": kind],
                ["Id": second, "Name": "Second result", "Type": kind],
            ]
            do {
                return try JSONSerialization.data(withJSONObject: ["Items": items, "TotalRecordCount": 2])
            } catch { throw .decoding }
        }
    }

    struct SearchUITestRoot: View {
        @State private var feature: SearchFeature

        init() {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let app = AppState(
                secureStore: InMemorySecureStore(), settings: InMemorySettingsStore(),
                path: StaticConnectivityPath(online: true), pinger: SearchUITestPinger(), cacheRoot: root,
                recentSearches: RecentSearchStore(directory: root.appendingPathComponent("history")))
            let session = UserSession(
                server: ServerInfo(
                    id: "11111111111111111111111111111111", name: "Search fixture",
                    url: URL(string: "https://media.example")!, version: SemVer(major: 12, minor: 2, patch: 0)),
                userID: "22222222222222222222222222222222", userName: "Ada", isAdministrator: false)
            try? app.didSignIn(session, token: "fixture-token")
            _feature = State(initialValue: SearchFeature(app: app, session: session, client: SearchUITestClient()))
        }

        var body: some View { SearchView(feature: feature) }
    }

    private struct SearchUITestPinger: ReachabilityPinging {
        func ping() async -> PingOutcome { .ok }
    }
#endif
