import GlassfinCore
import SwiftUI

/// The authenticated branch uses the M05 shell; each feature keeps its own navigation stack.
struct HomeRootView: View {
    let flow: AuthFlow
    var librarySession: LibrarySession? = nil
    @Binding var selectedTab: String
    @Binding var restoreSettingsFocus: Bool
    @State private var context: HomeContext?
    @State private var detailPath: [MediaItem] = []
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        PlaybackPresentationHost(makeCoordinator: makePlaybackCoordinator, librarySession: librarySession) { start in
            Group {
                if let context {
                    LibraryTabShell(
                        libraries: (context.model.libraries.value ?? librarySession?.libraries.value ?? []).map {
                            LibraryTabItem(id: $0.id, title: $0.name)
                        },
                        home: AnyView(home(context, start: start)), settings: AnyView(settings),
                        libraryContent: libraryContent, overflowContent: overflowContent,
                        search: AnyView(SearchFeatureHost(flow: flow)), selection: $selectedTab)
                } else {
                    ProgressView().accessibilityIdentifier("home.loading")
                }
            }
            #if DEBUG
                .modifier(HomeAccessibilityOverrides())
            #endif
            .task {
                guard context == nil, case .signedIn(let session) = flow.appPhase else { return }
                context = HomeContext(flow: flow, session: session)
                context?.connectEvents(flow: flow)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { context?.stopEvents() }
                if phase == .active { context?.connectEvents(flow: flow) }
            }
            .onDisappear {
                context?.stopEvents()
                context?.model.onDisappear()
            }
        }
    }

    private var libraryContent: ((LibraryTabItem) -> AnyView)? {
        guard let librarySession else { return nil }
        return { library in
            AnyView(
                LibraryNavigationRoot(
                    library: context?.model.libraries.value?.first { $0.id == library.id }
                        ?? librarySession.libraries.value?.first { $0.id == library.id }
                        ?? Library(id: library.id, name: library.title), session: librarySession))
        }
    }

    private var overflowContent: (([LibraryTabItem]) -> AnyView)? {
        guard let librarySession else { return nil }
        return { libraries in
            if libraries.isEmpty {
                return AnyView(LibraryIndexStateView(session: librarySession))
            }
            return AnyView(
                LibraryOverflowView(
                    session: librarySession,
                    libraries: libraries.map { library in
                        context?.model.libraries.value?.first { $0.id == library.id }
                            ?? librarySession.libraries.value?.first { $0.id == library.id }
                            ?? Library(id: library.id, name: library.title)
                    }))
        }
    }

    private func home(_ context: HomeContext, start: @escaping PlaybackAction) -> some View {
        NavigationStack(path: $detailPath) {
            HomeView(
                model: context.model, app: flow.homeApp, session: context.session, imageLoader: context.images,
                onDetail: { detailPath.append($0) },
                onPlay: { value in
                    guard let id = ItemID(value.item.id) else { return }
                    start(
                        PlaybackRequest(itemID: id, startTicks: Ticks.outboundPositionTicks(from: value.position)),
                        value.returnFocusID ?? "home.resume.item.\(id.value)")
                }
            )
            .navigationDestination(for: MediaItem.self) { item in
                if let librarySession {
                    ItemDetailScreen(id: item.id, session: librarySession)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("home.detail")
                }
            }
            .navigationDestination(for: ItemID.self) { id in
                if let librarySession { ItemDetailScreen(id: id.value, session: librarySession) }
            }
        }
    }

    private func makePlaybackCoordinator() throws -> PlaybackCoordinator {
        #if DEBUG
            if HomeMockLaunch.enabled {
                return MockPlaybackFactory.makeCoordinator(onStopped: { [app = flow.featureApp] in
                    await app.recordPlaybackStop($0)
                })
            }
        #endif
        return try flow.makePlaybackCoordinator()
    }

    private var settings: some View {
        NavigationStack {
            SettingsView(flow: flow, restoreSignOutFocus: $restoreSettingsFocus)
        }
    }
}

@MainActor
private final class HomeContext {
    let model: HomeViewModel
    let images: any HomeImageLoading
    let session: UserSession
    private var events: (any ServerEventStream)?

    init(flow: AuthFlow, session: UserSession) {
        self.session = session
        let app = flow.homeApp
        let service: any LibraryService
        #if DEBUG
            if HomeMockLaunch.enabled {
                service = HomeMockLibrary(mode: HomeMockLaunch.mode, controls: HomeMockControls.current)
                images = HomeMockImages()
            } else {
                let client = (try? flow.makeHomeClient()) ?? HomeUnavailableClient()
                service = JellyfinLibraryService(client: client)
                images = HomeImageLoader(client: client, disk: app.images.disk)
            }
        #else
            let client = (try? flow.makeHomeClient()) ?? HomeUnavailableClient()
            service = JellyfinLibraryService(client: client)
            images = HomeImageLoader(client: client, disk: app.images.disk)
        #endif
        model = HomeViewModel(
            library: service, userData: app.userData, snapshots: app.snapshots, responses: app.responses,
            app: app, clock: SystemGlassfinClock(), signposter: app.signposter, scope: app.scope,
            requireSnapshotOwner: true)
    }

    func connectEvents(flow: AuthFlow) {
        guard events == nil else { return }
        #if DEBUG
            if HomeMockLaunch.enabled { return }
        #endif
        guard let stream = try? flow.makeHomeEvents() else { return }
        events = stream
        flow.homeApp.watch(stream)
    }

    func stopEvents() {
        events?.stop()
        events = nil
    }
}

private struct HomeUnavailableClient: JellyfinAPIClient {
    func send(_ request: APIRequest) async throws(APIError) -> Data { throw .network }
}

#if DEBUG
    private struct HomeAccessibilityOverrides: ViewModifier {
        @DesignAccessibility private var accessibility

        func body(content: Content) -> some View {
            let args = ProcessInfo.processInfo.arguments
            let reduceTransparency = args.contains("-uitest-home-reduce-transparency")
            let reduceMotion = args.contains("-uitest-home-reduce-motion")
            content
                .environment(
                    \.designAccessibilityOverride,
                    reduceTransparency || reduceMotion
                        ? DesignAccessibilityValues(
                            reduceTransparency: accessibility.reduceTransparency || reduceTransparency,
                            increaseContrast: accessibility.increaseContrast,
                            reduceMotion: accessibility.reduceMotion || reduceMotion
                        ) : nil
                )
        }
    }
#endif
