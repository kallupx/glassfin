import GlassfinCore
import SwiftUI

@MainActor
enum LibraryFeatureAssembly {
    static func make(flow: AuthFlow) throws -> LibrarySession? {
        guard case .signedIn(let user) = flow.appPhase else { return nil }
        let client: any JellyfinAPIClient
        #if DEBUG
            if LaunchConfiguration(arguments: ProcessInfo.processInfo.arguments).useMockServer {
                client = SessionFeatureClient(inner: LibraryFixtureClient(), app: flow.featureApp)
            } else {
                client = try flow.makeFeatureClient()
            }
        #else
            client = try flow.makeFeatureClient()
        #endif
        return LibrarySession(
            app: flow.featureApp, service: JellyfinLibraryService(client: client),
            images: LibraryImageLoader(client: client, cache: flow.featureApp.images.disk),
            settings: UserDefaultsSettingsStore(defaults: .standard), serverID: user.server.id, userID: user.userID)
    }
}

struct LibraryOverflowView: View {
    let session: LibrarySession
    var body: some View {
        NavigationStack {
            List(session.overflowLibraries) { library in
                NavigationLink {
                    LibraryGridView(library: library, session: session)
                } label: {
                    Text(verbatim: library.name)
                }
                .accessibilityIdentifier("libraries.library.\(library.id)")
            }
            .navigationDestination(for: ItemID.self) { id in ItemDetailScreen(id: id.value, session: session) }
        }
    }
}

struct LibraryIndexStateView: View {
    let session: LibrarySession
    var body: some View {
        NavigationStack {
            if let error = session.libraries.presentedError {
                LibraryBlockingError(error: error) { Task { await session.load() } }
            } else if session.libraries.value != nil {
                Copy.text(.libraryNoLibraries).accessibilityIdentifier("libraries.empty")
            } else {
                ProgressView()
            }
        }
    }
}
