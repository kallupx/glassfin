import GlassfinCore
import SwiftUI

struct SearchFeatureHost: View {
    let flow: AuthFlow
    @State private var feature: SearchFeature?

    var body: some View {
        Group {
            if let feature {
                SearchView(feature: feature)
            } else {
                ProgressView()
            }
        }
        .task {
            guard feature == nil else { return }
            #if DEBUG
                if LaunchConfiguration(arguments: ProcessInfo.processInfo.arguments).useMockServer {
                    feature = flow.makeSearchFeature(client: SearchUITestClient())
                    return
                }
            #endif
            feature = flow.makeSearchFeature()
        }
    }
}

struct SearchView: View {
    let feature: SearchFeature
    @Bindable private var model: SearchViewModel
    @FocusState private var searchFocused: Bool

    init(feature: SearchFeature) {
        self.feature = feature
        self.model = feature.model
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SpacingToken.l) {
                    if !SearchPolicy.accepts(model.term) {
                        recentSearches
                    } else if model.state.showsSkeleton {
                        SkeletonRow(style: .poster, count: 4, phase: 0, identifier: "search.loading")
                    } else if let key = model.blockingErrorKey {
                        SearchErrorState(key: key, retry: model.retry)
                    } else if model.showsEmpty {
                        Text(verbatim: Copy.format(.searchEmpty, text: model.term))
                            .accessibilityIdentifier("search.empty")
                            .accessibilityValue(CopyKey.searchEmpty.rawValue)
                    } else if !SearchPolicy.accepts(model.term) {
                        Copy.text(.searchMinimum)
                            .accessibilityIdentifier("search.minimum")
                    }
                    if model.isOffline, SearchPolicy.accepts(model.term) { recentSearches }
                    ForEach(model.groups.filter { !$0.items.isEmpty }) { group in
                        SearchResultRow(
                            feature: feature, group: group,
                            rememberedID: Binding(
                                get: { model.rememberedIDs[group.id] },
                                set: { model.rememberedIDs[group.id] = $0 }),
                            onSelect: model.open)
                    }
                    if model.hasContent, model.state.presentedError != nil {
                        Button(action: model.retry) { Copy.text(.actionRetry) }
                            .buttonStyle(.glass)
                            .accessibilityIdentifier("search.retry")
                    }
                }
                .padding(SpacingToken.xl)
            }
            .safeAreaInset(edge: .top) {
                if let key = model.bannerKey {
                    ContainedGlass {
                        Text(verbatim: AppErrorMessage.localized(key))
                            .padding(SpacingToken.s)
                            .ownGlassSurface(in: Capsule())
                            .focusable(false)
                            .accessibilityIdentifier("search.banner")
                            .accessibilityValue(key)
                    }
                }
            }
            .searchable(
                text: Binding(get: { model.term }, set: { model.setTerm($0) }),
                prompt: Text(CopyKey.searchPrompt.resource)
            )
            .searchFocused($searchFocused)
            .navigationTitle(Copy.string(.tabSearch))
            .navigationDestination(item: $model.selectedItem) { item in
                SearchItemDetail(feature: feature, initial: item)
            }
            .onAppear {
                model.onAppear()
                if model.term.isEmpty { searchFocused = true }
            }
            .onChange(of: model.bannerKey) { old, new in
                if old != nil && new == nil { model.retryAfterRecovery() }
            }
            .onDisappear { model.onDisappear() }
            .accessibilityIdentifier("search.root")
        }
    }

    private var recentSearches: some View {
        VStack(alignment: .leading, spacing: SpacingToken.m) {
            Copy.text(.searchRecent)
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(model.recentQueries.enumerated()), id: \.offset) { index, query in
                Button {
                    model.setTerm(query)
                } label: {
                    Text(verbatim: query)
                }
                .accessibilityIdentifier("search.recent.\(index)")
            }
            if !model.recentQueries.isEmpty || model.historyFailed {
                Button(action: model.clearRecents) { Copy.text(.searchClearRecent) }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("search.clearRecent")
            }
            if model.historyFailed {
                Copy.text(.searchHistoryFailure)
                    .accessibilityIdentifier("search.historyFailure")
            }
        }
        .focusSection()
    }
}

struct SearchErrorState: View {
    let key: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: SpacingToken.l) {
            Text(verbatim: AppErrorMessage.localized(key))
                .font(.title2)
                .accessibilityIdentifier("search.error")
                .accessibilityValue(key)
            GlassActionBar(
                actions: [
                    GlassAction(
                        id: "retry", title: .actionRetry, systemImage: "arrow.clockwise", iconLabel: .actionRetry,
                        prominent: true, identifier: "search.retry")
                ], prominentID: "retry"
            ) { _ in retry() }
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }
}

private struct SearchResultRow: View {
    let feature: SearchFeature
    let group: SearchGroup
    @Binding var rememberedID: String?
    let onSelect: (MediaItem) -> Void
    @FocusState private var focus: String?

    private var title: CopyKey {
        switch group.id {
        case .movies: .searchMovies
        case .series: .searchSeries
        case .episodes: .searchEpisodes
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingToken.s) {
            Copy.text(title)
                .font(.title3)
                .accessibilityAddTraits(.isHeader)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: CardMetrics.spacing) {
                        ForEach(group.items) { item in
                            SearchResultCard(
                                feature: feature, item: item,
                                style: group.id == .episodes ? .landscape : .poster,
                                focused: focus == item.id,
                                onSelect: {
                                    rememberedID = item.id
                                    feature.model.focusedKind = group.id
                                    onSelect(item)
                                }
                            )
                            .id(item.id)
                            .focused($focus, equals: item.id)
                            .onAppear { feature.model.loadNextPage(kind: group.id, visibleID: item.id) }
                        }
                    }
                    .padding(.vertical, SpacingToken.m)
                }
                .onAppear {
                    if let rememberedID {
                        proxy.scrollTo(rememberedID, anchor: .center)
                        if feature.model.focusedKind == group.id { focus = rememberedID }
                    }
                }
            }
        }
        .focusSection()
        .defaultFocus($focus, rememberedID ?? group.items.first?.id, priority: .userInitiated)
        .onChange(of: focus) { _, value in
            if let value {
                rememberedID = value
                feature.model.focusedKind = group.id
            }
        }
        .accessibilityIdentifier("search.row.\(group.id.rawValue)")
    }
}

private struct SearchResultCard: View {
    let feature: SearchFeature
    let item: MediaItem
    let style: CardStyle
    let focused: Bool
    let onSelect: () -> Void
    @Environment(\.displayScale) private var displayScale
    @State private var image: Image?

    private var size: CGSize { CardMetrics.size(for: style) }
    private var request: ItemImageRequest? {
        guard let id = ItemID(item.id), let tag = item.images.primaryTag else { return nil }
        return ItemImageRequest(
            serverID: feature.serverID, itemID: id, type: .primary, tag: tag,
            width: Int(size.width * displayScale), height: Int(size.height * displayScale))
    }

    var body: some View {
        Button(action: onSelect) {
            PosterFace(
                content: PosterContent(
                    id: item.id, title: item.name,
                    progress: PlaybackProgress.measure(position: item.userData.playbackPosition, runtime: item.runtime),
                    isWatched: item.userData.played, unplayedCount: item.userData.unplayedCount,
                    blurHash: item.images.primaryBlurHash),
                style: style, isFocused: focused, image: image)
        }
        .posterButtonStyle()
        .accessibilityIdentifier("search.item.\(item.id)")
        .accessibilityLabel(Text(verbatim: item.name))
        .task(id: request?.cacheKey.sha256) {
            image = nil
            guard let request else { return }
            do {
                let data = try await feature.images.bytes(for: request)
                let decoded = try await SearchImageDecoder.downsample(data, maximumPixelSize: request.maximumPixelSize)
                try Task.checkCancellation()
                image = Image(decorative: decoded.image, scale: displayScale)
            } catch let error as APIError {
                if error != .notFound && error != .cancelled { feature.handle(error) }
            } catch {}
        }
    }
}

/// TODO(Q9-12): Route to M07 when its destination lands; keep the search model owned by this tab.
private struct SearchItemDetail: View {
    let feature: SearchFeature
    let initial: MediaItem
    @State private var item: MediaItem?
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingToken.l) {
                Text(verbatim: (item ?? initial).name)
                    .font(.largeTitle)
                    .accessibilityIdentifier("search.detail.title")
                if let overview = (item ?? initial).overview {
                    Text(verbatim: overview)
                        .focusable(false)
                        .accessibilityIdentifier("search.detail.overview")
                }
                if let failure {
                    SearchErrorState(key: failure) { Task { await load() } }
                }
                Button(action: { dismiss() }) { Copy.text(.searchBack) }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("search.detail.back")
            }
            .padding(SpacingToken.xl)
        }
        .task { await load() }
    }

    private func load() async {
        do {
            item = try await feature.detail(initial)
            failure = nil
        } catch {
            guard error != .cancelled else { return }
            feature.handle(error)
            let mapped = AppErrorMapping.map(error, context: .authenticated, deviceOffline: false)
            failure = AppErrorMessage.messageKey(for: mapped)
        }
    }
}
