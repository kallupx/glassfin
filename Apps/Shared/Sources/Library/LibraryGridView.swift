import GlassfinCore
import SwiftUI

struct LibraryNavigationRoot: View {
    let library: Library
    let session: LibrarySession

    var body: some View {
        NavigationStack {
            LibraryGridView(library: library, session: session)
                .navigationDestination(for: ItemID.self) { id in
                    ItemDetailScreen(id: id.value, session: session)
                }
        }
    }
}

struct LibraryGridView: View {
    let library: Library
    let session: LibrarySession
    @State private var model: LibraryViewModel
    @FocusState private var focus: String?
    @State private var started = false
    @State private var scrollPosition = ScrollPosition()
    @State private var playbackNotice = false
    @State private var playbackError: AuthCopy.Key?

    init(library: Library, session: LibrarySession) {
        self.library = library
        self.session = session
        _model = State(initialValue: session.makeBrowser())
    }

    var body: some View {
        ScrollViewReader { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: SpacingToken.l) {
                    Text(verbatim: library.name).font(.largeTitle)
                    LibraryFilterBar(model: model)
                    if let count = model.totalCount {
                        Text(verbatim: Copy.format(countKey, text: count.formatted(.number)))
                            .accessibilityIdentifier("library.count")
                    }
                    if let key = session.app.bannerKey {
                        GlassBanner(
                            message: .errorServerUnreachable, systemImage: "exclamationmark.icloud",
                            identifier: "library.banner", literalMessage: AuthCopy.localized(key))
                    }
                    if let error = session.actions.lastError ?? model.filterError {
                        LibraryInlineError(error: error)
                    }
                    if let playbackError {
                        Text(verbatim: AuthCopy.localized(playbackError)).accessibilityIdentifier(
                            "library.playback.error")
                    }
                    if playbackNotice {
                        Copy.text(.detailPlaybackPending).accessibilityIdentifier("library.playback.pending")
                    }
                    gridState
                }
                .padding(SpacingToken.xl)
            }
            .scrollPosition($scrollPosition)
            .onAppear { focus = model.focusedID }
            .onChange(of: focus) { _, id in
                if let id {
                    model.focusedID = id
                    model.scrollID = id
                }
            }
            .onChange(of: model.state.value?.first?.id) { _, _ in
                if focus == nil { focus = model.focusedID ?? model.state.value?.first?.id }
            }
        }
        .accessibilityIdentifier("library.root")
        .task {
            if !started || model.state.value == nil {
                started = true
                await model.browse(library)
            } else {
                await model.refreshFromStore()
            }
        }
        .onChange(of: session.app.userDataGeneration) { _, _ in
            Task {
                await model.refreshFromStore()
                await session.actions.refreshFromStore()
            }
        }
        .onDisappear { model.onDisappear() }
        .onChange(of: session.app.connectivity) { previous, current in
            if current == .online, previous == .serverUnreachable || previous == .offline {
                Task { await model.retry() }
            }
        }
        #if os(tvOS)
            .onPlayPauseCommand {
                guard !session.app.playbackBlocked else {
                    playbackError = session.app.playbackBlockedKey
                    return
                }
                playbackError = nil
                if let item = model.state.value?.first(where: { $0.id == focus }), let id = ItemID(item.id) {
                    session.requestPlayback(LibraryPlaybackIntent(itemID: id, start: item.userData.playbackPosition))
                    playbackNotice = true
                }
            }
        #endif
    }

    @ViewBuilder private var gridState: some View {
        if model.state.showsSkeleton || (!started && model.state.value == nil) {
            SkeletonRow(style: .poster, count: 6, phase: 0)
        } else if let error = model.state.presentedError, !model.hasContent {
            LibraryBlockingError(error: error) { Task { await model.retry() } }
        } else if let items = model.state.value {
            if items.isEmpty { Copy.text(.libraryEmpty).accessibilityIdentifier("library.empty") }
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(CardMetrics.posterWidth), spacing: CardMetrics.spacing), count: 6),
                alignment: .leading, spacing: SpacingToken.row
            ) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if let id = ItemID(item.id) {
                        NavigationLink(value: id) {
                            LibraryMediaCardFace(
                                item: session.actions.visible(item), focused: focus == item.id, session: session)
                        }
                        .posterButtonStyle()
                        .id(item.id)
                        .focused($focus, equals: item.id)
                        .accessibilityIdentifier("library.item.\(item.id)")
                        .accessibilityLabel(item.name)
                        .contextMenu {
                            Button {
                                if session.app.playbackBlocked {
                                    playbackError = session.app.playbackBlockedKey
                                } else {
                                    session.requestPlayback(
                                        LibraryPlaybackIntent(itemID: id, start: item.userData.playbackPosition))
                                    playbackNotice = true
                                }
                            } label: {
                                Copy.text(.actionPlay)
                            }
                            Button {
                                Task { await session.actions.togglePlayed(item) }
                            } label: {
                                Copy.text(
                                    session.actions.visible(item).userData.played
                                        ? .actionMarkUnplayed : .actionMarkPlayed)
                            }.accessibilityIdentifier("library.context.played")
                            Button {
                                Task { await session.actions.toggleFavorite(item) }
                            } label: {
                                Copy.text(
                                    session.actions.visible(item).userData.isFavorite
                                        ? .actionRemoveFavorite : .actionAddFavorite)
                            }
                        }
                        .onAppear {
                            // The model owns cancellation so a recycled cell cannot abort a shared page.
                            Task { await model.loadNextPageIfNeeded(visibleIndex: index) }
                        }
                    }
                }
            }
            .focusSection()
            .defaultFocus($focus, model.focusedID ?? items.first?.id)
            if let error = model.state.presentedError, model.hasContent {
                LibraryInlineError(error: error)
                Button {
                    Task { await model.retry() }
                } label: {
                    Copy.text(.actionRetry)
                }.buttonStyle(.glass)
            }
        }
    }

    private var countKey: CopyKey {
        library.collectionType == "movies"
            ? .libraryMoviesCount : library.collectionType == "tvshows" ? .librarySeriesCount : .libraryItemsCount
    }
}

struct LibraryMediaCardFace: View {
    var item: MediaItem
    var focused: Bool
    let session: LibrarySession
    var style: CardStyle = .poster
    var body: some View {
        VStack(alignment: .leading, spacing: SpacingToken.xs) {
            LibraryArtwork(
                item: item, type: style == .poster ? .primary : .thumb, size: CardMetrics.size(for: style),
                session: session
            )
            .overlay(alignment: .bottom) {
                if let fraction = PlaybackProgress.measure(
                    position: item.userData.playbackPosition, runtime: item.runtime
                ).fraction {
                    ProgressTrack(fraction: fraction).padding(SpacingToken.xs)
                }
            }
            .overlay(alignment: .topLeading) {
                if item.userData.played {
                    GlassIcon(systemName: "checkmark.circle.fill", label: .badgeWatched).padding(SpacingToken.xs)
                }
            }
            Text(verbatim: item.name).font(.headline).lineLimit(2)
                .frame(
                    width: CardMetrics.size(for: style).width, height: CardMetrics.titleHeight, alignment: .topLeading
                )
                .opacity(focused || style == .landscape ? 1 : 0)
        }
    }
}

struct LibraryFilterBar: View {
    let model: LibraryViewModel
    var body: some View {
        ContainedGlass {
            HStack(spacing: SpacingToken.m) {
                Menu {
                    ForEach(LibrarySort.allCases, id: \.self) { sort in
                        Button {
                            change { $0.sort = sort }
                        } label: {
                            Copy.text(key(sort))
                        }
                    }
                    Button {
                        change { $0.descending.toggle() }
                    } label: {
                        Copy.text(.libraryDescending)
                    }
                } label: {
                    Copy.text(key(model.choices.sort))
                }
                .buttonStyle(.glass).accessibilityIdentifier("library.sort")
                Button {
                    binding(\.unplayed).wrappedValue.toggle()
                } label: {
                    Copy.text(.libraryUnplayed)
                }
                .buttonStyle(.glass)
                .accessibilityValue(Copy.text(model.choices.unplayed ? .libraryFilterOn : .libraryFilterOff))
                .accessibilityAddTraits(model.choices.unplayed ? .isSelected : [])
                .accessibilityIdentifier("library.unplayed")
                Button {
                    binding(\.favorites).wrappedValue.toggle()
                } label: {
                    Copy.text(.libraryFavorites)
                }
                .buttonStyle(.glass)
                .accessibilityValue(Copy.text(model.choices.favorites ? .libraryFilterOn : .libraryFilterOff))
                .accessibilityAddTraits(model.choices.favorites ? .isSelected : [])
                .accessibilityIdentifier("library.favorites")
                Menu {
                    Button {
                        change { $0.genre = nil }
                    } label: {
                        Copy.text(.libraryAll)
                    }
                    ForEach(model.filters?.genres ?? [], id: \.self) { genre in
                        Button {
                            change { $0.genre = genre }
                        } label: {
                            Text(verbatim: MetadataSanitizer.displayText(genre, limit: MetadataPolicy.genreMax))
                        }
                    }
                } label: {
                    Copy.text(.libraryGenre)
                }.buttonStyle(.glass).accessibilityIdentifier("library.genre")
                Menu {
                    Button {
                        change { $0.year = nil }
                    } label: {
                        Copy.text(.libraryAll)
                    }
                    ForEach(model.filters?.years ?? [], id: \.self) { year in
                        Button {
                            change { $0.year = year }
                        } label: {
                            Text(verbatim: String(year))
                        }
                    }
                } label: {
                    Copy.text(.libraryYear)
                }.buttonStyle(.glass).accessibilityIdentifier("library.year")
            }
        }
        .focusSection()
    }

    private func binding(_ path: WritableKeyPath<LibraryChoices, Bool>) -> Binding<Bool> {
        Binding(get: { model.choices[keyPath: path] }, set: { value in change { $0[keyPath: path] = value } })
    }
    private func change(_ edit: (inout LibraryChoices) -> Void) {
        var choices = model.choices
        edit(&choices)
        Task { await model.choose(choices) }
    }
    private func key(_ sort: LibrarySort) -> CopyKey {
        switch sort {
        case .name: .libraryName
        case .dateAdded: .libraryDateAdded
        case .releaseYear: .libraryReleaseYear
        case .rating: .libraryRating
        case .random: .libraryRandom
        }
    }
}

struct LibraryInlineError: View {
    var error: AppError
    var body: some View {
        if let message = AppErrorMessage.userFacing(error) {
            Text(verbatim: message).accessibilityIdentifier("library.inlineError").focusable(false)
        }
    }
}

struct LibraryBlockingError: View {
    var error: AppError
    var retry: () -> Void
    var body: some View {
        ErrorStateView(
            failure: .serverUnreachable, attempts: 0, onRetry: retry, onSwitchServer: {},
            messageOverride: AppErrorMessage.userFacing(error)
        )
        .accessibilityValue(AppErrorMessage.key(for: error)?.rawValue ?? "")
    }
}
