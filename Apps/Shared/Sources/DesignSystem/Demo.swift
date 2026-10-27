import SwiftUI

enum DemoFixtures {
    static let htmlOverview =
        "<p>A <a href=\"https://example.com\">story</a> &amp; more.</p><script>alert(1)</script> Tail marker."
    static let plainOverview = PlainText.overview(htmlOverview)
    static let blurHash = "00TSUA"

    static func posters() -> [PosterContent] {
        (0..<6).map(poster(at:))
    }

    private static func poster(at index: Int) -> PosterContent {
        let elapsedSeconds: Int = index * 60
        let runtime: Duration = .seconds(32 * 60)
        let progress = PlaybackProgress.measure(position: .seconds(elapsedSeconds), runtime: runtime)
        return PosterContent(
            id: String(index),
            title: "Poster \(index)",
            progress: progress,
            isWatched: index == 3,
            unplayedCount: index == 4 ? 3 : nil,
            blurHash: blurHash
        )
    }

    static func primary() -> [PosterContent] {
        [
            PosterContent(
                id: "0",
                title: "Wide 0",
                progress: PlaybackProgress.measure(position: .zero, runtime: .seconds(32 * 60)),
                isWatched: false,
                unplayedCount: nil,
                blurHash: blurHash
            ),
            PosterContent(
                id: "1",
                title: "Wide 1",
                progress: PlaybackProgress.measure(position: .seconds(10 * 60), runtime: .seconds(40 * 60)),
                isWatched: false,
                unplayedCount: nil,
                blurHash: blurHash
            ),
        ]
    }

    static var posterVariants: [PosterContent] {
        [
            PosterContent(
                id: "zero",
                title: "Start",
                progress: PlaybackProgress.measure(position: .zero, runtime: .seconds(100)),
                isWatched: false,
                unplayedCount: nil,
                blurHash: blurHash
            ),
            PosterContent(
                id: "half",
                title: "Half",
                progress: PlaybackProgress.measure(position: .seconds(50), runtime: .seconds(100)),
                isWatched: false,
                unplayedCount: nil,
                blurHash: blurHash
            ),
            PosterContent(
                id: "done",
                title: "Done",
                progress: PlaybackProgress.measure(position: .seconds(100), runtime: .seconds(100)),
                isWatched: true,
                unplayedCount: nil,
                blurHash: blurHash
            ),
            PosterContent(
                id: "count",
                title: "Episodes",
                progress: PlaybackProgress.measure(position: .zero, runtime: .seconds(100)),
                isWatched: false,
                unplayedCount: 4,
                blurHash: blurHash
            ),
            PosterContent(
                id: "unknown",
                title: "Unknown",
                progress: PlaybackProgress.measure(position: .seconds(10), runtime: nil),
                isWatched: false,
                unplayedCount: nil,
                blurHash: blurHash
            ),
        ]
    }
}

struct DesignSystemFocusDemo: View {
    @State private var primaryMemory: String?
    @State private var posterMemory: String?
    @State private var expanded = false
    @State private var playbackTarget = "play"
    @State private var focusedItemID = "play"

    var body: some View {
        LibraryTabShell(libraries: [], home: AnyView(page))
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SpacingToken.row) {
                GlassBanner(message: .bannerOffline, systemImage: "wifi.slash", identifier: "design.banner.offline")
                hero
                primaryRow
                posterRow
                SkeletonRow(style: .poster, count: 4, phase: 0)
            }
            .padding(SpacingToken.l)
        }
        .onChange(of: primaryMemory) { _, newValue in
            if let newValue {
                focusedItemID = "primary-\(newValue)"
            }
        }
        .onChange(of: posterMemory) { _, newValue in
            if let newValue {
                focusedItemID = "poster-\(newValue)"
            }
        }
        .modifier(PlayPauseHook(target: $playbackTarget, current: focusedItemID))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("design.root")
        .background {
            Text(verbatim: playbackTarget)
                .accessibilityIdentifier("design.playback.target")
                .accessibilityValue(playbackTarget)
                .frame(width: 1, height: 1)
        }
    }

    private var hero: HeroHeader {
        HeroHeader(
            title: "Night Market",
            meta: "2019  12  134 min",
            overview: DemoFixtures.plainOverview,
            expanded: expanded,
            canResume: false,
            backdrop: Color.orange.opacity(0.85),
            onPlay: { focusedItemID = "play" },
            onWatched: {},
            onFavorite: {},
            onMore: { expanded.toggle() }
        )
    }

    private var primaryRow: MediaRow {
        MediaRow(
            rowID: "design.row.primary",
            title: .rowPrimary,
            items: DemoFixtures.primary(),
            style: .landscape,
            rememberedID: $primaryMemory,
            onSelect: { focusedItemID = "primary-\($0.id)" },
            onTogglePlayed: { _ in },
            onToggleFavorite: { _ in }
        )
    }

    private var posterRow: MediaRow {
        MediaRow(
            rowID: "design.row.posters",
            title: .rowPosters,
            items: DemoFixtures.posters(),
            style: .poster,
            rememberedID: $posterMemory,
            onSelect: { focusedItemID = "poster-\($0.id)" },
            onTogglePlayed: { _ in },
            onToggleFavorite: { _ in }
        )
    }
}

private struct PlayPauseHook: ViewModifier {
    @Binding var target: String
    var current: String

    func body(content: Content) -> some View {
        #if os(tvOS)
            content.onPlayPauseCommand {
                target = current
            }
        #else
            content
        #endif
    }
}

struct DesignSystemErrorDemo: View {
    @State private var attempts = 0

    var body: some View {
        ErrorStateView(
            failure: .serverUnreachable,
            attempts: attempts,
            onRetry: { attempts += 1 },
            onSwitchServer: {}
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DesignSystemGallery: View {
    var backdrop: Color
    @State private var season = "1"

    var body: some View {
        ZStack {
            backdrop
            ScrollView {
                VStack(alignment: .leading, spacing: SpacingToken.l) {
                    GlassBanner(message: .bannerOffline, systemImage: "wifi.slash", identifier: "gallery.banner")
                    hero.frame(height: 420)
                    posterStrip
                    PosterFace(content: DemoFixtures.primary()[0], style: .landscape, isFocused: true)
                    SkeletonRow(style: .poster, count: 3, phase: 0, identifier: "gallery.skeleton")
                    ErrorStateView(failure: .serverUnreachable, attempts: 0, onRetry: {}, onSwitchServer: {})
                    SeasonPickerBar(seasons: ["1", "2", "3"], selection: $season)
                    NextUpCard(title: "Episode 4")
                    LoginPanel()
                    SubtitleCue()
                    FocusGlassSample(forcedFocus: false)
                    FocusGlassSample(forcedFocus: true)
                    InteractiveGlassProbe()
                    standardButton
                }
                .padding(SpacingToken.l)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var hero: HeroHeader {
        HeroHeader(
            title: "Night Market",
            meta: "2019",
            overview: DemoFixtures.plainOverview,
            expanded: false,
            canResume: false,
            backdrop: backdrop,
            onPlay: {},
            onWatched: {},
            onFavorite: {},
            onMore: {}
        )
    }

    private var posterStrip: some View {
        HStack(alignment: .top, spacing: SpacingToken.m) {
            ForEach(DemoFixtures.posterVariants) { item in
                PosterFace(content: item, style: .poster, isFocused: item.id == "half")
            }
        }
    }

    private var standardButton: some View {
        Button(action: {}) {
            Copy.text(.actionPlay)
        }
        .accessibilityIdentifier("gallery.standardButton")
    }
}

struct BrowseGridProbe: View {
    var count: Int

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: SpacingToken.xs) {
                ForEach(0..<count, id: \.self) { index in
                    Color.primary.opacity(0.2)
                        .frame(height: 40)
                        .accessibilityIdentifier("design.grid.\(index)")
                }
            }
        }
        .frame(width: 1920, height: 1080)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("design.grid.root")
    }
}

struct ContrastBackdropSample: View {
    var background: Color
    var label: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            background
            BackdropScrim()
            Text(verbatim: label)
                .font(.body)
                .foregroundStyle(.primary)
                .padding(SpacingToken.l)
        }
        .frame(width: 640, height: 360)
    }
}
