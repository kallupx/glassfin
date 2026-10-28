#if DEBUG
    import GlassfinCore
    import SwiftUI

    struct LibraryDebugHost: View {
        let scenario: String
        @State private var session: LibrarySession
        @State private var selectedTab = "libraries"

        init(scenario: String) {
            self.scenario = scenario
            _session = State(initialValue: Self.make(scenario))
        }

        var body: some View {
            Group {
                if scenario.hasPrefix("series") {
                    NavigationStack {
                        ItemDetailScreen(id: LibraryFixtureClient.series, kind: .series, session: session)
                            .navigationDestination(for: ItemID.self) { id in
                                ItemDetailScreen(id: id.value, session: session)
                            }
                    }
                } else {
                    TabView(selection: $selectedTab) {
                        Tab(Copy.string(.tabHome), systemImage: "house", value: "home") { Copy.text(.tabHome) }
                        Tab(Copy.string(.tabLibraries), systemImage: "books.vertical", value: "libraries") {
                            LibraryNavigationRoot(
                                library: Library(
                                    id: LibraryFixtureClient.movieLibrary, name: "Fixture Movies",
                                    collectionType: "movies"),
                                session: session)
                        }
                        Tab(Copy.string(.tabSettings), systemImage: "gear", value: "settings") {
                            Copy.text(.tabSettings)
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if session.playbackReturn != nil {
                    Copy.text(.detailPlaybackPending).accessibilityIdentifier("library.playback.returned")
                }
            }
            .task { await session.load() }
        }

        private static func make(_ scenario: String) -> LibrarySession {
            let secure = InMemorySecureStore()
            let settings = InMemorySettingsStore()
            let fixture = LibraryFixtureClient(scenario: scenario)
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "library-preview-\(UUID().uuidString)")
            let app = AppState(
                secureStore: secure, settings: settings, path: StaticConnectivityPath(online: true),
                pinger: LibraryDebugPinger(client: fixture), cacheRoot: root)
            let server = ServerInfo(
                id: LibraryFixtureClient.id(1), name: "Fixture", url: URL(string: "https://fixture.example")!,
                version: SemVer(major: 12, minor: 2, patch: 0))
            try? app.didSignIn(
                UserSession(
                    server: server, userID: LibraryFixtureClient.id(2), userName: "Fixture User", isAdministrator: false
                ), token: "fixture-token")
            let client = SessionFeatureClient(inner: fixture, app: app)
            let session = LibrarySession(
                app: app, service: JellyfinLibraryService(client: client),
                images: LibraryImageLoader(client: client, cache: app.images.disk),
                settings: settings, serverID: server.id, userID: LibraryFixtureClient.id(2))
            if scenario == "series-return" || scenario == "series-finished" {
                session.onPlayback = { [weak session] intent in
                    guard let session else { return }
                    Task {
                        let finished = scenario == "series-finished"
                        if finished {
                            await app.userData.recordPlayback(
                                id: intent.itemID.value, position: .seconds(2700), played: true, log: SilentLog())
                        }
                        session.playbackDidEnd(itemID: intent.itemID.value, finished: finished)
                    }
                }
            }
            return session
        }
    }

    private struct LibraryDebugPinger: ReachabilityPinging {
        let client: any JellyfinAPIClient
        func ping() async -> PingOutcome {
            do {
                _ = try await client.send(APIRequest(method: "GET", path: "/System/Ping"))
                return .ok
            } catch { return .failed(.serverUnreachable) }
        }
    }
#endif
