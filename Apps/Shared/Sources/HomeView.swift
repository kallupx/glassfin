import GlassfinCore
import SwiftUI

struct HomeView: View {
    @Bindable var model: HomeViewModel
    let app: AppState
    let session: UserSession
    let imageLoader: any HomeImageLoading
    var onDetail: (MediaItem) -> Void
    var onPlay: (HomePlaybackRequest) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @DesignAccessibility private var accessibility
    @Environment(\.displayScale) private var displayScale
    @State private var focusedItem: MediaItem?
    @State private var focusedRowID: String?
    @State private var needsDefaultFocus = true
    @State private var backdropSelection = HomeBackdropModel()
    @State private var backdropID: String?
    @State private var backdrop: Image?
    #if DEBUG
        @State private var testRefreshFinished = false
    #endif

    var body: some View {
        ZStack(alignment: .top) {
            ContentPaint.scrim.ignoresSafeArea()
            if let backdrop {
                backdrop.resizable().scaledToFill().ignoresSafeArea()
                    .backgroundExtensionEffect()
                    .overlay(ContentPaint.subtitleBacking)
                    .overlay(BackdropScrim())
                    .id(backdropID)
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
            content
            if let key = model.bannerKey {
                GlassBanner(
                    messageOverride: AppErrorMessage.localized(key), message: .bannerOffline,
                    systemImage: "wifi.exclamationmark", identifier: "home.banner"
                )
                .accessibilityValue(key)
                .padding(.top, SpacingToken.s)
            }
        }
        .clipped()
        #if DEBUG
            .overlay(alignment: .bottomTrailing) {
                if testRefreshFinished {
                    Text(verbatim: "1").frame(width: 1, height: 1)
                    .accessibilityIdentifier("home.test.refreshed")
                }
            }
            .task {
                guard ProcessInfo.processInfo.arguments.contains("-uitest-home-refresh") else { return }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                await model.load()
                testRefreshFinished = true
            }
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.root")
        .onAppear { model.onAppear() }
        .task { model.start() }
        .task { await model.observePlayback() }
        .onChange(of: focusedItem?.id) { _, _ in backdropSelection.focus(focusedItem) }
        .task(id: backdropSelection.item?.id) { await loadBackdrop() }
        .onDisappear {
            model.onDisappear()
            backdropSelection.cancel()
            needsDefaultFocus = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.foreground() }
            if phase == .background { model.onDisappear() }
        }
        .onChange(of: app.connectivity) { old, new in
            if new == .online && (old == .serverUnreachable || old == .offline) { model.reconnect() }
        }
        .onChange(of: app.userDataGeneration) { _, _ in model.perform { await $0.userDataDidChange() } }
        .onChange(of: app.libraryGeneration) { _, _ in model.libraryDidChange() }
    }

    @ViewBuilder
    private var content: some View {
        if let key = model.serverDownTitleKey {
            ErrorStateView(
                messageOverride: AppErrorMessage.localized(key), failure: .serverUnreachable, attempts: 0,
                onRetry: {
                    model.perform { home in
                        await app.retryNow()
                        home.start()
                    }
                }, onSwitchServer: { app.beginServerSwitch() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("home.error")
            .accessibilityValue(key)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SpacingToken.row) {
                    row(id: "resume", title: Copy.string(.homeContinue), state: model.resume, style: .landscape)
                    row(id: "nextUp", title: Copy.string(.homeNextUp), state: model.nextUp, style: .landscape)
                    ForEach(model.latestRows) { row in
                        self.row(
                            id: row.id, title: Copy.format(.homeLatest, text: row.library.name),
                            state: row.state, style: .poster)
                    }
                    if HomePolicy.sectionErrorKey(for: model.libraries) != nil {
                        VStack(alignment: .leading, spacing: SpacingToken.s) {
                            Copy.text(.homeLibrariesRetry)
                            Button {
                                model.start()
                            } label: {
                                Copy.text(.actionRetry)
                            }
                            .buttonStyle(.glass)
                            .accessibilityIdentifier("home.libraries.retry")
                        }
                    }
                    if model.isEmpty {
                        VStack(spacing: SpacingToken.l) {
                            Copy.text(.homeEmpty).font(.title)
                            Copy.text(.homeEmptyGuidance)
                            Button {
                                model.start()
                            } label: {
                                Copy.text(.actionRetry)
                            }
                            .buttonStyle(.glassProminent)
                            .accessibilityIdentifier("home.empty.retry")
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("home.empty")
                    }
                    if let error = model.actionError, let key = AppErrorMessage.messageKey(for: error) {
                        Text(verbatim: AppErrorMessage.localized(key))
                            .accessibilityIdentifier("home.action.error")
                            .accessibilityValue(key)
                    }
                }
                .padding(SpacingToken.xl)
                .padding(.top, SpacingToken.row)
            }
        }
    }

    @ViewBuilder
    private func row(id: String, title: String, state: LoadState<[MediaItem]>, style: CardStyle) -> some View {
        if state.showsSkeleton || isIdle(state) {
            SkeletonRow(style: style, count: 3, phase: 0, identifier: "home.\(id).skeleton")
        } else if !(state.value ?? []).isEmpty || HomePolicy.sectionErrorKey(for: state) != nil {
            VStack(alignment: .leading, spacing: SpacingToken.s) {
                Text(verbatim: title).font(.title3).accessibilityAddTraits(.isHeader)
                if let key = HomePolicy.sectionErrorKey(for: state) {
                    HStack(spacing: SpacingToken.m) {
                        Text(verbatim: AppErrorMessage.localized(key)).accessibilityValue(key)
                        Button {
                            model.perform { await $0.retry(rowID: id) }
                        } label: {
                            Copy.text(.actionRetry)
                        }
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("home.\(id).retry")
                    }
                }
                HomeMediaRow(
                    rowID: id, items: state.value ?? [], style: style,
                    rememberedID: Binding(get: { model.rememberedIDs[id] }, set: { model.rememberedIDs[id] = $0 }),
                    receivesDefaultFocus: id == defaultFocusRowID, needsDefaultFocus: $needsDefaultFocus,
                    session: session, imageLoader: imageLoader,
                    onFocus: {
                        focusedItem = $0
                        focusedRowID = id
                    }, onDetail: onDetail,
                    onPlay: { play($0) },
                    onPlayed: { item in model.perform { await $0.setPlayed(item, played: !item.userData.played) } },
                    onFavorite: { item in model.perform { await $0.setFavorite(item) } },
                    onRemove: { item in model.perform { await $0.removeFromResume(item) } })
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.\(id)")
        }
    }

    private var defaultFocusRowID: String? {
        if let focusedRowID {
            if focusedRowID == "resume", !(model.resume.value ?? []).isEmpty { return focusedRowID }
            if focusedRowID == "nextUp", !(model.nextUp.value ?? []).isEmpty { return focusedRowID }
            if model.latestRows.contains(where: { $0.id == focusedRowID && !($0.state.value ?? []).isEmpty }) {
                return focusedRowID
            }
        }
        if !(model.resume.value ?? []).isEmpty { return "resume" }
        if !(model.nextUp.value ?? []).isEmpty { return "nextUp" }
        return model.latestRows.first { !($0.state.value ?? []).isEmpty }?.id
    }

    private func isIdle(_ state: LoadState<[MediaItem]>) -> Bool {
        if case .idle = state { return true }
        return false
    }

    private func play(_ item: MediaItem) {
        guard model.playbackBlockedKey == nil else { return }
        onPlay(HomePlaybackRequest(item: item))
    }

    private func loadBackdrop() async {
        guard let item = backdropSelection.item, let tag = item.images.backdropTags.first else { return }
        let resource = JellyfinImageResource(
            serverID: session.server.id, itemID: item.id, type: .backdrop, tag: tag,
            width: Int(1920 * displayScale), height: Int(1080 * displayScale))
        do {
            let data = try await imageLoader.data(for: resource)
            let decoded = try await HomeImageDecoder.downsample(data, width: resource.width, height: resource.height)
            guard !Task.isCancelled else { return }
            withAnimation(accessibility.reduceMotion ? nil : .easeInOut(duration: HomePolicy.backdropFade)) {
                backdropID = item.id
                backdrop = Image(decorative: decoded, scale: displayScale)
            }
        } catch {
            // Keep the previous backdrop or content scrim.
        }
    }
}

private struct HomeMediaRow: View {
    let rowID: String
    let items: [MediaItem]
    let style: CardStyle
    @Binding var rememberedID: String?
    let receivesDefaultFocus: Bool
    @Binding var needsDefaultFocus: Bool
    let session: UserSession
    let imageLoader: any HomeImageLoading
    var onFocus: (MediaItem) -> Void
    var onDetail: (MediaItem) -> Void
    var onPlay: (MediaItem) -> Void
    var onPlayed: (MediaItem) -> Void
    var onFavorite: (MediaItem) -> Void
    var onRemove: (MediaItem) -> Void
    @FocusState private var focus: String?
    @Namespace private var rowNamespace

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: CardMetrics.spacing) {
                ForEach(items) { item in
                    HomeCard(
                        item: item, style: style, focused: focus == item.id, session: session, loader: imageLoader,
                        onSelect: { onDetail(item) }
                    )
                    .focused($focus, equals: item.id)
                    .accessibilityIdentifier("home.\(rowID).item.\(item.id)")
                    #if os(tvOS)
                        .onPlayPauseCommand { onPlay(item) }
                        .prefersDefaultFocus(item.id == (rememberedID ?? items.first?.id), in: rowNamespace)
                    #endif
                    .contextMenu {
                        Button {
                            onPlay(item)
                        } label: {
                            Copy.text(.actionPlay)
                        }
                        .accessibilityIdentifier("home.context.play")
                        Button {
                            onPlayed(item)
                        } label: {
                            Copy.text(item.userData.played ? .actionMarkUnplayed : .actionMarkPlayed)
                        }
                        .accessibilityIdentifier("home.context.played")
                        if rowID == "resume" {
                            Button {
                                onRemove(item)
                            } label: {
                                Copy.text(.homeRemoveResume)
                            }
                            .accessibilityIdentifier("home.context.removeResume")
                        }
                        if let series = HomeNavigation.seriesDestination(for: item) {
                            Button {
                                onDetail(series)
                            } label: {
                                Copy.text(.homeGoToSeries)
                            }
                            .accessibilityIdentifier("home.context.series")
                        }
                        Button {
                            onFavorite(item)
                        } label: {
                            Copy.text(item.userData.isFavorite ? .actionRemoveFavorite : .actionAddFavorite)
                        }
                        .accessibilityIdentifier("home.context.favorite")
                    }
                }
            }
            .padding(.vertical, SpacingToken.m)
        }
        .designFocusSection()
        #if os(tvOS)
            .focusScope(rowNamespace)
        #endif
        .defaultFocus($focus, rememberedID ?? items.first?.id)
        #if os(tvOS)
            .onAppear {
                guard receivesDefaultFocus, needsDefaultFocus else { return }
                needsDefaultFocus = false
                // Request focus after the asynchronously loaded row joins the tab's focus hierarchy.
                DispatchQueue.main.async {
                    focus = rememberedID ?? items.first?.id
                }
            }
        #endif
        .onChange(of: focus) { _, value in
            guard let item = items.first(where: { $0.id == value }) else { return }
            rememberedID = value
            onFocus(item)
        }
        .onChange(of: items.map(\.id)) { _, new in
            if let focus, !new.contains(focus) { self.focus = rememberedID ?? new.first }
        }
    }
}

private struct HomeCard: View {
    let item: MediaItem
    let style: CardStyle
    let focused: Bool
    let session: UserSession
    let loader: any HomeImageLoading
    var onSelect: () -> Void
    @State private var image: Image?
    @State private var placeholderImage: Image?
    @Environment(\.displayScale) private var displayScale

    private var resource: JellyfinImageResource? {
        let type: ItemImageType = style == .poster ? .primary : (item.images.thumbTag != nil ? .thumb : .backdrop)
        let tag = style == .poster ? item.images.primaryTag : (item.images.thumbTag ?? item.images.backdropTags.first)
        guard let tag else { return nil }
        let size = CardMetrics.size(for: style)
        return JellyfinImageResource(
            serverID: session.server.id, itemID: item.id, type: type, tag: tag,
            width: Int(size.width * displayScale), height: Int(size.height * displayScale))
    }

    var body: some View {
        Button(action: onSelect) {
            PosterFace(
                image: image, placeholderImage: placeholderImage,
                content: PosterContent(
                    id: item.id, title: item.name,
                    progress: PlaybackProgress.measure(position: item.userData.playbackPosition, runtime: item.runtime),
                    isWatched: item.userData.played, unplayedCount: item.userData.unplayedCount,
                    blurHash: nil),
                style: style, isFocused: focused)
        }
        .posterButtonStyle()
        .accessibilityLabel(Text(verbatim: item.name))
        .task(id: resource) {
            image = nil
            let hash = item.images.primaryBlurHash
            let decodedPlaceholder = await Task.detached(priority: .utility) {
                hash.flatMap { BlurHash.image(from: $0, width: 32, height: 32) }
            }.value
            guard !Task.isCancelled else { return }
            placeholderImage = decodedPlaceholder.map { Image(decorative: $0, scale: 1) }
            guard let resource else { return }
            do {
                let data = try await loader.data(for: resource)
                let decoded = try await HomeImageDecoder.downsample(
                    data, width: resource.width, height: resource.height)
                guard !Task.isCancelled else { return }
                image = Image(decorative: decoded, scale: displayScale)
            } catch {
                // AsyncPoster keeps its placeholder.
            }
        }
    }
}
