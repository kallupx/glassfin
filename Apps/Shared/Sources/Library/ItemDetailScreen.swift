import GlassfinCore
import SwiftUI

struct ItemDetailScreen: View {
    let id: String
    let session: LibrarySession
    @State private var model: ItemDetailViewModel
    @State private var series: SeriesViewModel
    @State private var playbackNotice = false
    @State private var playbackError: String?
    @FocusState private var focus: SeriesFocus?

    init(id: String, session: LibrarySession) {
        self.id = id
        self.session = session
        _model = State(initialValue: ItemDetailViewModel(library: session.service, app: session.app))
        _series = State(
            initialValue: SeriesViewModel(library: session.service, userData: session.app.userData, app: session.app))
    }

    private var item: MediaItem? { model.state.value.map { session.actions.visible($0) } }
    private var isSeries: Bool { item?.kind == .series || item?.kind == .season }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingToken.l) {
                if let item {
                    hero(item)
                    if isSeries { SeriesEpisodeSection(model: series, session: session, focus: $focus) }
                    metadata(item)
                    if let error = model.similar.presentedError { LibraryInlineError(error: error) }
                    if let items = model.similar.value, !items.isEmpty {
                        similar(items)
                    }
                    if let error = model.state.presentedError { LibraryInlineError(error: error) }
                } else if let error = model.state.presentedError {
                    LibraryBlockingError(error: error) { Task { await load() } }
                } else {
                    SkeletonRow(style: .landscape, count: 3, phase: 0)
                }
            }
            .padding(.bottom, SpacingToken.xl)
        }
        .overlay(alignment: .top) {
            VStack(spacing: SpacingToken.s) {
                if let key = session.app.bannerKey {
                    GlassBanner(
                        message: .errorServerUnreachable, systemImage: "exclamationmark.icloud",
                        identifier: "detail.banner", literalMessage: AppErrorMessage.localized(key))
                }
                if let error = session.actions.lastError { LibraryInlineError(error: error) }
                if let playbackError {
                    Text(verbatim: AppErrorMessage.localized(playbackError)).accessibilityIdentifier(
                        "detail.playback.error")
                }
                if playbackNotice {
                    Copy.text(.detailPlaybackPending).accessibilityIdentifier("detail.playback.pending")
                }
            }
        }
        .accessibilityIdentifier("detail.root")
        .onAppear { model.onAppear() }
        .defaultFocus($focus, Optional(.play), priority: .userInitiated)
        .task {
            if model.state.value == nil {
                await load()
            } else {
                await series.refreshFromStore()
                if isSeries { focus = series.focus }
            }
        }
        .onChange(of: session.app.userDataGeneration) { _, _ in
            Task {
                await model.refreshFromStore()
                await series.refreshFromStore()
                await session.actions.refreshFromStore()
            }
        }
        .onChange(of: session.playbackReturn) { _, result in
            if let result, isSeries {
                Task { await series.returnedFromPlayback(itemID: result.itemID, finished: result.finished) }
            }
        }
        .sheet(isPresented: $model.overviewExpanded) { LibraryOverviewSheet(overview: item?.overview ?? "") }
        .onDisappear {
            model.onDisappear()
            series.onDisappear()
        }
        .onChange(of: session.app.connectivity) { previous, current in
            if current == .online, previous == .serverUnreachable || previous == .offline { Task { await load() } }
        }
        #if os(tvOS)
            .onPlayPauseCommand { play(startOver: false) }
        #endif
    }

    private func load() async {
        await model.load(id: id)
        guard !Task.isCancelled, let item else { return }
        if item.kind == .series { await series.load(seriesID: item.id) }
        if item.kind == .season, let seriesID = item.seriesID {
            await series.load(seriesID: seriesID, seasonID: item.id)
        }
    }

    private func hero(_ item: MediaItem) -> some View {
        HeroHeader(
            title: item.name, meta: meta(item), overview: item.overview ?? "", expanded: model.overviewExpanded,
            canResume: item.userData.playbackPosition > .zero, backdrop: ContentPaint.scrim,
            onPlay: { play(startOver: false) }, onWatched: { Task { await session.actions.togglePlayed(item) } },
            onFavorite: { Task { await session.actions.toggleFavorite(item) } },
            onMore: { model.overviewExpanded.toggle() },
            backdropContent: AnyView(
                LibraryArtwork(item: item, type: .backdrop, size: CGSize(width: 1920, height: 640), session: session)),
            logoContent: item.images.logoTag == nil
                ? nil
                : AnyView(
                    LibraryArtwork(item: item, type: .logo, size: CGSize(width: 300, height: 100), session: session)),
            actionContent: AnyView(
                LibraryDetailActions(
                    item: item, target: isSeries ? series.playTarget : item, model: model, session: session,
                    onPlay: { play(startOver: $0) }, focus: $focus)))
    }

    private func meta(_ item: MediaItem) -> String {
        var values: [String] = []
        if let year = item.productionYear { values.append(String(year)) }
        if let rating = item.officialRating { values.append(rating) }
        if let rating = item.communityRating, rating.isFinite {
            values.append(rating.formatted(.number.precision(.fractionLength(1))))
        }
        if let runtime = item.runtime {
            values.append(Copy.format(.detailRuntime, integer: Int(runtime.components.seconds / 60)))
        }
        return values.joined(separator: " · ")
    }

    private func metadata(_ item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: SpacingToken.m) {
            ForEach(Array((item.detail?.taglines ?? []).enumerated()), id: \.offset) { _, tagline in
                Text(verbatim: tagline).font(.headline)
            }
            Text(verbatim: (item.detail?.genres ?? []).joined(separator: " · "))
            Text(verbatim: (item.detail?.studios ?? []).joined(separator: " · "))
            if let streams = item.detail?.streams, !streams.isEmpty {
                Copy.text(.detailTechnical).font(.title3)
                ForEach(Array(streams.enumerated()), id: \.offset) { _, stream in
                    Text(verbatim: stream.technicalValue).accessibilityIdentifier("detail.technical.\(stream.id)")
                }
            }
            if let people = item.detail?.people, !people.isEmpty {
                Copy.text(.detailCast).font(.title3)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: SpacingToken.l) {
                        ForEach(Array(people.enumerated()), id: \.offset) { _, person in
                            VStack(alignment: .leading, spacing: SpacingToken.xs) {
                                Text(verbatim: person.name).font(.headline)
                                if let role = person.role { Text(verbatim: role).font(.caption) }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, SpacingToken.xl)
        .focusable(false)
    }

    private func similar(_ items: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: SpacingToken.m) {
            Copy.text(.detailSimilar).font(.title3)
            ScrollView(.horizontal) {
                LazyHStack(spacing: CardMetrics.spacing) {
                    ForEach(items) { item in
                        if let target = ItemID(item.id) {
                            NavigationLink(value: target) {
                                LibraryMediaCardFace(
                                    item: session.actions.visible(item), focused: true, session: session)
                            }
                            .posterButtonStyle()
                            .accessibilityIdentifier("detail.similar.\(item.id)")
                        }
                    }
                }.padding(.vertical, SpacingToken.m)
            }
        }
        .padding(.horizontal, SpacingToken.xl)
        .designFocusSection()
    }

    private func play(startOver: Bool) {
        guard !session.app.playbackBlocked else {
            playbackNotice = false
            playbackError = session.app.playbackBlockedMessageKey
            return
        }
        playbackError = nil
        let target: MediaItem?
        if case .episode(let id) = focus {
            target = series.episodes.value?.first { $0.id == id }
        } else {
            target = isSeries ? series.playTarget : item
        }
        guard let intent = model.playbackIntent(for: target, startOver: startOver) else { return }
        session.requestPlayback(intent)
        // TODO(Q7-08): inject the M08 playback presentation closure and pass this intent.
        playbackNotice = true
    }
}

struct LibraryDetailActions: View {
    var item: MediaItem
    var target: MediaItem?
    @Bindable var model: ItemDetailViewModel
    let session: LibrarySession
    var onPlay: (Bool) -> Void
    var focus: FocusState<SeriesFocus?>.Binding

    private var hasProgress: Bool { (target?.userData.playbackPosition ?? .zero) > .zero }
    private var title: String {
        if let target, target.kind == .episode, item.kind == .series || item.kind == .season {
            let episode = String(
                format: Copy.string(.detailEpisodeNumber), Int64(target.parentIndexNumber ?? 1),
                Int64(target.indexNumber ?? 1))
            return Copy.format(hasProgress ? .detailResumeEpisode : .detailPlayEpisode, text: episode)
        }
        if let target, hasProgress {
            let seconds = max(0, target.userData.playbackPosition.components.seconds)
            return Copy.format(.detailResumeTime, text: String(format: "%lld:%02lld", seconds / 60, seconds % 60))
        }
        return Copy.string(.actionPlay)
    }

    private var playKey: CopyKey {
        if target?.kind == .episode, item.kind == .series || item.kind == .season {
            return hasProgress ? .detailResumeEpisode : .detailPlayEpisode
        }
        return hasProgress ? .detailResumeTime : .actionPlay
    }

    var body: some View {
        ContainedGlass {
            HStack(spacing: SpacingToken.s) {
                Button {
                    onPlay(false)
                } label: {
                    Text(verbatim: title)
                }
                .buttonStyle(.glassProminent).focused(focus, equals: .play)
                .accessibilityIdentifier("detail.play")
                #if DEBUG
                    .accessibilityValue(playKey.rawValue)
                #endif
                if hasProgress {
                    Button {
                        onPlay(true)
                    } label: {
                        Copy.text(.detailStartOver)
                    }
                    .buttonStyle(.glass).accessibilityIdentifier("detail.startOver")
                }
                Button {
                    Task { await session.actions.togglePlayed(item) }
                } label: {
                    Copy.text(item.userData.played ? .actionMarkUnplayed : .actionMarkPlayed)
                }.buttonStyle(.glass).accessibilityIdentifier("detail.played")
                Button {
                    Task { await session.actions.toggleFavorite(item) }
                } label: {
                    Copy.text(item.userData.isFavorite ? .actionRemoveFavorite : .actionAddFavorite)
                }.buttonStyle(.glass).accessibilityIdentifier("detail.favorite")
                trackMenu
                Button {
                    model.overviewExpanded.toggle()
                } label: {
                    Copy.text(.actionMore)
                }
                .buttonStyle(.glass).accessibilityIdentifier("detail.more")
            }
        }
        .designFocusSection()
        .defaultFocus(focus, Optional(.play))
        .onAppear { if focus.wrappedValue == nil { focus.wrappedValue = .play } }
    }

    private var trackMenu: some View {
        Menu {
            Menu {
                Button {
                    model.audioStreamIndex = nil
                } label: {
                    Copy.text(.detailDefault)
                }
                ForEach(item.detail?.streams.filter { $0.kind == "Audio" } ?? []) { stream in
                    Button {
                        model.audioStreamIndex = stream.id
                    } label: {
                        Text(verbatim: stream.title ?? stream.technicalValue)
                    }
                }
            } label: {
                Copy.text(.detailAudio)
            }
            Menu {
                Button {
                    model.subtitleStreamIndex = nil
                } label: {
                    Copy.text(.detailDefault)
                }
                Button {
                    model.subtitleStreamIndex = -1
                } label: {
                    Copy.text(.detailNone)
                }
                ForEach(item.detail?.streams.filter { $0.kind == "Subtitle" } ?? []) { stream in
                    Button {
                        model.subtitleStreamIndex = stream.id
                    } label: {
                        Text(verbatim: stream.title ?? stream.technicalValue)
                    }
                }
            } label: {
                Copy.text(.detailSubtitles)
            }
        } label: {
            Copy.text(.detailTracks)
        }
        .buttonStyle(.glass).accessibilityIdentifier("detail.tracks")
    }
}

struct LibraryOverviewSheet: View {
    let overview: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var closeFocused: Bool

    var body: some View {
        VStack(spacing: SpacingToken.l) {
            ScrollView {
                Text(verbatim: overview).font(.body).focusable(false)
            }
            .focusable()
            .accessibilityIdentifier("detail.overview.full")
            ContainedGlass {
                Button {
                    dismiss()
                } label: {
                    Text(verbatim: AuthCopy.localized(.back))
                }
                .buttonStyle(.glassProminent).focused($closeFocused)
            }
        }
        .padding(SpacingToken.xl)
        .defaultFocus($closeFocused, true)
    }
}
