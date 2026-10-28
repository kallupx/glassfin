import GlassfinCore
import SwiftUI

#if DEBUG
    enum HomeMockLaunch {
        static var enabled: Bool {
            let configuration = LaunchConfiguration(arguments: ProcessInfo.processInfo.arguments)
            return configuration.useMockServer || configuration.resetState
        }
        @MainActor
        static func seed(_ app: AppState) {
            guard let url = URL(string: "https://media.example") else { return }
            let server = ServerInfo(
                id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", name: "1", url: url,
                version: SemVer(major: 10, minor: 11, patch: 0))
            let session = UserSession(
                server: server, userID: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", userName: "1", isAdministrator: false)
            try? app.didSignIn(session, token: "uitest-token")
            app.snapshots.purge()
            if ProcessInfo.processInfo.arguments.contains("-uitest-home-cached-down") {
                var snapshot = HomeSnapshot(
                    resume: [HomeMockLibrary.item(0, resume: true)], nextUp: [HomeMockLibrary.item(20)], latest: [])
                snapshot.serverID = session.server.id
                snapshot.userID = session.userID
                snapshot.libraries = [Library(id: HomeMockLibrary.libraryID, name: "1", collectionType: "movies")]
                snapshot.latestByLibrary = [HomeMockLibrary.libraryID: [HomeMockLibrary.item(40)]]
                app.snapshots.save(snapshot)
            }
        }

        static var mode: String {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-uitest-home-empty") { return "empty" }
            if args.contains("-uitest-home-partial") { return "partial" }
            if args.contains("-uitest-home-down") || args.contains("-uitest-home-cached-down") { return "down" }
            if args.contains("-uitest-home-next-only") { return "nextOnly" }
            return "all"
        }
    }

    struct HomeMockImages: HomeImageLoading {
        func data(for resource: JellyfinImageResource) async throws -> Data { throw ImageDataError.invalidImage }
    }

    actor HomeMockLibrary: LibraryService {
        let mode: String
        init(mode: String) { self.mode = mode }
        static let libraryID = "cccccccccccccccccccccccccccccccc"
        static let otherLibraryID = "dddddddddddddddddddddddddddddddd"

        static func item(_ index: Int, resume: Bool = false) -> MediaItem {
            MediaItem(
                id: String(format: "%032x", index + 1), kind: .episode,
                name: String(index + 1), overview: "<b>1</b>&amp;",
                seriesID: "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", runtime: .seconds(3600),
                userData: UserItemState(playbackPosition: resume ? .seconds(120) : .zero))
        }

        func userViews() async throws(APIError) -> [Library] {
            if mode == "down" { throw .network }
            return [
                Library(id: Self.libraryID, name: "1", collectionType: "movies"),
                Library(id: Self.otherLibraryID, name: "2", collectionType: "tvshows"),
            ]
        }
        func resume(limit: Int) async throws(APIError) -> [MediaItem] {
            if mode == "down" { throw .network }
            if mode == "partial" { throw .server(status: 500) }
            if mode == "empty" || mode == "nextOnly" { return [] }
            return (0..<min(limit, HomePolicy.rowLimit)).map { Self.item($0, resume: true) }
        }
        func nextUp(limit: Int) async throws(APIError) -> [MediaItem] {
            if mode == "down" { throw .network }
            return mode == "empty" ? [] : (20..<24).map { Self.item($0) }
        }
        func nextUp(series: MediaItem.ID) async throws(APIError) -> MediaItem? {
            try await nextUp(limit: 1).first { $0.seriesID == series }
        }
        func latest(in library: String, limit: Int) async throws(APIError) -> [MediaItem] {
            if mode == "down" { throw .network }
            return mode == "empty" ? [] : (40..<44).map { Self.item($0) }
        }
        func items(in library: String, query: ItemQuery, page: PageRequest) async throws(APIError) -> Page<MediaItem> {
            Page(items: [], totalCount: 0)
        }
        func seasons(series: String) async throws(APIError) -> [MediaItem] { [] }
        func episodes(series: String, season: String?) async throws(APIError) -> [MediaItem] { [] }
        func item(id: String) async throws(APIError) -> MediaItem { Self.item(0) }
        func similar(id: String, limit: Int) async throws(APIError) -> [MediaItem] { [] }
        func filters(in library: String) async throws(APIError) -> ItemFilterSet {
            ItemFilterSet(genres: [], years: [])
        }
        func setPlayed(_ id: String, _ played: Bool) async throws(APIError) {}
        func setFavorite(_ id: String, _ favorite: Bool) async throws(APIError) {}
        func userData(id: String) async throws(APIError) -> UserItemState { UserItemState() }
        func updateUserData(id: String, position: Duration, played: Bool) async throws(APIError) {}
    }
#endif
