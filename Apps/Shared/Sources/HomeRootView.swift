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
    @State private var playback: HomePlaybackRequest?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let context {
                LibraryTabShell(
                    libraries: (context.model.libraries.value ?? librarySession?.libraries.value ?? []).map {
                        LibraryTabItem(id: $0.id, title: $0.name)
                    },
                    home: AnyView(home(context)), settings: AnyView(settings),
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
        .fullScreenCover(item: $playback) { request in
            // TODO(M08): replace this destination with the M08 player adapter.
            VStack(spacing: SpacingToken.l) {
                Text(verbatim: request.item.name).font(.title)
                Copy.text(.homePlaybackPending)
                Button {
                    playback = nil
                } label: {
                    Text(verbatim: AuthCopy.localized(.back))
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("home.playback.close")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.playback")
            .accessibilityValue(String(Ticks.outboundPositionTicks(from: request.position)))
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

    private func home(_ context: HomeContext) -> some View {
        NavigationStack(path: $detailPath) {
            HomeView(
                model: context.model, app: flow.homeApp, session: context.session, imageLoader: context.images,
                onDetail: { detailPath.append($0) }, onPlay: { playback = $0 }
            )
            .navigationDestination(for: MediaItem.self) { item in
                // TODO(M07): route this value to the M07 detail destination.
                VStack(spacing: SpacingToken.l) {
                    Text(verbatim: item.name).font(.largeTitle)
                    if let overview = item.overview { Text(verbatim: overview) }
                    Copy.text(.homeDetailPending)
                    Button {
                        playback = HomePlaybackRequest(item: item)
                    } label: {
                        Copy.text(.actionPlay)
                    }
                    .buttonStyle(.glassProminent)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("home.detail")
                #if os(tvOS)
                    .onPlayPauseCommand { playback = HomePlaybackRequest(item: item) }
                #endif
            }
        }
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
