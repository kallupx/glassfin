import GlassfinCore
import SwiftUI

struct SeriesEpisodeSection: View {
    let model: SeriesViewModel
    let session: LibrarySession
    var focus: FocusState<SeriesFocus?>.Binding
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingToken.l) {
            seasonPicker
            episodeRow
            Text(verbatim: model.selectedOverview)
                .font(.body).focusable(false)
                .accessibilityIdentifier("series.overview")
            if let error = model.seasons.presentedError ?? model.episodes.presentedError {
                LibraryInlineError(error: error)
            }
        }
        .padding(.horizontal, SpacingToken.xl)
        .onChange(of: focus.wrappedValue) { _, value in
            switch value {
            case .season(let id): model.focusSeason(id)
            case .episode(let id): model.focusEpisode(id)
            case .play, nil: break
            }
        }
        .onChange(of: model.focus) { _, value in
            if value != .play { focus.wrappedValue = value }
        }
        #if os(tvOS)
            .onMoveCommand { direction in
                switch (direction, focus.wrappedValue) {
                case (.down, .season(let id)):
                    Task {
                        if id != model.selectedSeasonID { await model.select(seasonID: id) }
                        model.moveDownFromSeason()
                        focus.wrappedValue = model.focus
                    }
                case (.up, .episode):
                    model.moveUpFromEpisodes()
                    focus.wrappedValue = model.focus
                default: break
                }
            }
        #endif
    }

    private var seasonPicker: some View {
        ContainedGlass {
            ScrollView(.horizontal) {
                LazyHStack(spacing: SpacingToken.m) {
                    ForEach(model.seasons.value ?? []) { season in
                        Button {
                            model.focusSeason(season.id)
                        } label: {
                            if season.indexNumber == 0 {
                                Copy.text(.detailSpecials)
                            } else if let number = season.indexNumber {
                                Text(verbatim: Copy.format(.detailSeasonNumber, integer: number))
                            } else {
                                Text(verbatim: season.name)
                            }
                        }
                        .frame(minWidth: CardMetrics.posterWidth)
                        .buttonStyle(.glass)
                        .glassMorphID(season.id, in: glassNamespace, enabled: MotionPolicy.allowsMorph(reduceMotion))
                        .focused(focus, equals: .season(season.id))
                        .accessibilityIdentifier("series.season.\(season.id)")
                        .accessibilityAddTraits(model.selectedSeasonID == season.id ? [.isSelected] : [])
                    }
                }.padding(.vertical, SpacingToken.m)
            }
        }
        .focusSection()
        .defaultFocus(focus, model.selectedSeasonID.map { SeriesFocus.season($0) }, priority: .userInitiated)
        .accessibilityIdentifier("series.seasons")
    }

    @ViewBuilder private var episodeRow: some View {
        if model.episodes.showsSkeleton {
            SkeletonRow(style: .landscape, count: 3, phase: 0, identifier: "series.skeleton")
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: CardMetrics.spacing) {
                        ForEach(model.episodes.value ?? []) { episode in
                            if let id = ItemID(episode.id) {
                                NavigationLink(value: id) {
                                    LibraryMediaCardFace(
                                        item: titled(session.actions.visible(episode)),
                                        focused: focus.wrappedValue == .episode(episode.id), session: session,
                                        style: .landscape)
                                }
                                .posterButtonStyle()
                                .focused(focus, equals: .episode(episode.id))
                                .id(episode.id)
                                .accessibilityIdentifier("series.episode.\(episode.id)")
                                .contextMenu {
                                    Button {
                                        Task { await session.actions.togglePlayed(episode) }
                                    } label: {
                                        Copy.text(
                                            session.actions.visible(episode).userData.played
                                                ? .actionMarkUnplayed : .actionMarkPlayed)
                                    }
                                }
                            }
                        }
                    }.padding(.vertical, SpacingToken.m)
                }
                .onAppear { scroll(proxy) }
                .onChange(of: model.preferredEpisodeID) { _, _ in scroll(proxy) }
                .onChange(of: model.focusedEpisodeID) { _, _ in scroll(proxy) }
            }
            .focusSection()
            .defaultFocus(focus, model.preferredEpisodeID.map { SeriesFocus.episode($0) }, priority: .userInitiated)
            .accessibilityIdentifier("series.episodes")
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        if let id = model.focusedEpisodeID ?? model.preferredEpisodeID { proxy.scrollTo(id, anchor: .leading) }
    }

    private func titled(_ item: MediaItem) -> MediaItem {
        var copy = item
        let number = String(
            format: Copy.string(.detailEpisodeNumber), Int64(item.parentIndexNumber ?? 1), Int64(item.indexNumber ?? 1))
        let runtime = item.runtime.map { Copy.format(.detailRuntime, integer: Int($0.components.seconds / 60)) }
        copy.name = [number, item.name, runtime].compactMap { $0 }.joined(separator: " · ")
        return copy
    }
}
