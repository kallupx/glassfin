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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var focusedItem: MediaItem?
    @State private var backdropItem: MediaItem?
    @State private var backdrop: Image?

    var body: some View {
        ZStack(alignment: .top) {
            ContentPaint.scrim.ignoresSafeArea()
            if let backdrop {
                backdrop.resizable().scaledToFill().ignoresSafeArea()
                    .backgroundExtensionEffect()
                    .overlay(ContentPaint.subtitleBacking)
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
            content
            if let key = model.bannerKey {
                GlassBanner(
                    messageOverride: AuthCopy.localized(key), message: .bannerOffline,
                    systemImage: "wifi.exclamationmark", identifier: "home.banner"
                )
                .accessibilityValue(key.rawValue)
                .padding(.top, SpacingToken.s)
            }
        }
        .clipped()
        .accessibilityIdentifier("home.root")
        .task { model.start() }
        .task { await model.observePlayback() }
        .task(id: focusedItem?.id) {
            let item = focusedItem
            do { try await Task.sleep(for: HomePolicy.backdropDebounce) } catch { return }
            guard !Task.isCancelled else { return }
            backdropItem = item
        }
        .task(id: backdropItem?.id) { await loadBackdrop() }
        .onDisappear { model.onDisappear() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.foreground() }
            if phase == .background { model.onDisappear() }
        }
        .onChange(of: app.connectivity) { old, new in
            if new == .online && (old == .serverUnreachable || old == .offline) { model.reconnect() }
        }
        .onChange(of: app.userDataGeneration) { _, _ in Task { await model.userDataDidChange() } }
        .onChange(of: app.libraryGeneration) { _, _ in model.libraryDidChange() }
    }

    @ViewBuilder
    private var content: some View {
        if let key = model.serverDownTitleKey {
            ErrorStateView(
                messageOverride: AuthCopy.localized(key), failure: .serverUnreachable, attempts: 0,
                onRetry: {
                    Task {
                        await app.retryNow()
                        model.start()
                    }
                }, onSwitchServer: { app.beginServerSwitch() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("home.error")
            .accessibilityValue(key.rawValue)
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
                    if model.libraries.presentedError != nil {
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
                        .accessibilityIdentifier("home.empty")
                    }
                    if let error = model.actionError, let key = AppErrorMessage.key(for: error) {
                        Text(verbatim: AuthCopy.localized(key))
                            .accessibilityIdentifier("home.action.error")
                            .accessibilityValue(key.rawValue)
                    }
                }
                .padding(SpacingToken.xl)
                .padding(.top, SpacingToken.row)
            }
        }
    }

    @ViewBuilder
    private func row(id: String, title: String, state: LoadState<[MediaItem]>, style: CardStyle) -> some View {
        if state.showsSkeleton || (state.value == nil && state.presentedError == nil) {
            SkeletonRow(style: style, count: 3, phase: 0, identifier: "home.\(id).skeleton")
        } else if !(state.value ?? []).isEmpty || state.presentedError != nil {
            VStack(alignment: .leading, spacing: SpacingToken.s) {
                Text(verbatim: title).font(.title3).accessibilityAddTraits(.isHeader)
                if let error = state.presentedError, let key = AppErrorMessage.key(for: error) {
                    HStack(spacing: SpacingToken.m) {
                        Text(verbatim: AuthCopy.localized(key)).accessibilityValue(key.rawValue)
                        Button {
                            Task { await model.retry(rowID: id) }
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
                    session: session, imageLoader: imageLoader,
                    onFocus: { focusedItem = $0 }, onDetail: onDetail,
                    onPlay: { play($0) },
                    onPlayed: { item in Task { await model.setPlayed(item, played: !item.userData.played) } },
                    onFavorite: { item in Task { await model.setFavorite(item) } },
                    onRemove: { item in Task { await model.removeFromResume(item) } })
            }
            .accessibilityIdentifier("home.\(id)")
        }
    }

    private func play(_ item: MediaItem) {
        guard model.playbackBlockedKey == nil else { return }
        onPlay(HomePlaybackRequest(item: item))
    }

    private func loadBackdrop() async {
        guard let item = backdropItem, let tag = item.images.backdropTags.first else { return }
        let resource = ImageResource(
            serverID: session.server.id, itemID: item.id, type: .backdrop, tag: tag,
            width: Int(1920 * displayScale), height: Int(1080 * displayScale))
        do {
            let data = try await imageLoader.data(for: resource)
            let decoded = try await HomeImageDecoder.downsample(data, width: resource.width, height: resource.height)
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: HomePolicy.backdropFade)) {
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
                        Button {
                            onPlayed(item)
                        } label: {
                            Copy.text(item.userData.played ? .actionMarkUnplayed : .actionMarkPlayed)
                        }
                        if rowID == "resume" {
                            Button {
                                onRemove(item)
                            } label: {
                                Copy.text(.homeRemoveResume)
                            }
                        }
                        if let seriesID = item.seriesID {
                            Button {
                                onDetail(MediaItem(id: seriesID, kind: .series, name: item.name))
                            } label: {
                                Copy.text(.homeGoToSeries)
                            }
                        }
                        Button {
                            onFavorite(item)
                        } label: {
                            Copy.text(item.userData.isFavorite ? .actionRemoveFavorite : .actionAddFavorite)
                        }
                    }
                }
            }
            .padding(.vertical, SpacingToken.m)
        }
        .focusSection()
        #if os(tvOS)
            .focusScope(rowNamespace)
        #endif
        .defaultFocus($focus, rememberedID ?? items.first?.id)
        .onChange(of: focus) { _, value in
            guard let item = items.first(where: { $0.id == value }) else { return }
            rememberedID = value
            onFocus(item)
        }
        .onChange(of: items.map(\.id)) { old, new in
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
    @Environment(\.displayScale) private var displayScale

    private var resource: ImageResource? {
        let type: ItemImageType = style == .poster ? .primary : (item.images.thumbTag != nil ? .thumb : .backdrop)
        let tag = style == .poster ? item.images.primaryTag : (item.images.thumbTag ?? item.images.backdropTags.first)
        guard let tag else { return nil }
        let size = CardMetrics.size(for: style)
        return ImageResource(
            serverID: session.server.id, itemID: item.id, type: type, tag: tag,
            width: Int(size.width * displayScale), height: Int(size.height * displayScale))
    }

    var body: some View {
        Button(action: onSelect) {
            PosterFace(
                image: image,
                content: PosterContent(
                    id: item.id, title: item.name,
                    progress: PlaybackProgress.measure(position: item.userData.playbackPosition, runtime: item.runtime),
                    isWatched: item.userData.played, unplayedCount: item.userData.unplayedCount,
                    blurHash: item.images.primaryBlurHash),
                style: style, isFocused: focused)
        }
        .posterButtonStyle()
        .accessibilityLabel(Text(verbatim: item.name))
        .task(id: resource) {
            image = nil
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
