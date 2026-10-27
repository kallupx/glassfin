import SwiftUI

struct HeroHeader: View {
    var title: String
    var meta: String
    var overview: String
    var expanded: Bool
    var canResume: Bool
    var backdrop: Color
    var onPlay: () -> Void
    var onWatched: () -> Void
    var onFavorite: () -> Void
    var onMore: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
                .backgroundExtensionEffect()
                .overlay(BackdropScrim())
            VStack(alignment: .leading, spacing: SpacingToken.s) {
                Text(verbatim: title)
                    .font(.largeTitle)
                    .foregroundStyle(ContentPaint.heroText)
                    .lineLimit(2)
                    .accessibilityIdentifier("design.hero.title")
                Text(verbatim: meta)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("design.hero.meta")
                Text(verbatim: overview)
                    .font(.body)
                    .foregroundStyle(ContentPaint.heroText)
                    .lineLimit(expanded ? TruncationPolicy.errorMessageLineLimit : 2)
                    .focusable(false)
                    .accessibilityIdentifier(overviewIdentifier)
                GlassActionBar(actions: Self.actions(canResume: canResume), prominentID: "play") { id in
                    switch id {
                    case "play":
                        onPlay()
                    case "watched":
                        onWatched()
                    case "favorite":
                        onFavorite()
                    default:
                        onMore()
                    }
                }
            }
            .padding(SpacingToken.xl)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 640)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("design.hero.root")
    }

    private var overviewIdentifier: String {
        expanded ? "design.hero.overview.expanded" : "design.hero.overview.collapsed"
    }

    static func actions(canResume: Bool) -> [GlassAction] {
        [
            GlassAction(
                id: "play",
                title: canResume ? .actionResume : .actionPlay,
                systemImage: "play.fill",
                iconLabel: canResume ? .actionResume : .actionPlay,
                prominent: true,
                identifier: "design.hero.play"
            ),
            GlassAction(
                id: "watched",
                title: .actionPlayed,
                systemImage: "checkmark",
                iconLabel: .actionPlayed,
                prominent: false,
                identifier: "design.hero.watched"
            ),
            GlassAction(
                id: "favorite",
                title: .actionFavorite,
                systemImage: "heart",
                iconLabel: .actionFavorite,
                prominent: false,
                identifier: "design.hero.favorite"
            ),
            GlassAction(
                id: "more",
                title: .actionMore,
                systemImage: "text.alignleft",
                iconLabel: .actionMore,
                prominent: false,
                identifier: "design.hero.more"
            ),
        ]
    }
}

struct SeasonPickerBar: View {
    var seasons: [String]
    @Binding var selection: String

    var body: some View {
        ContainedGlass {
            Picker(selection: $selection) {
                ForEach(seasons, id: \.self) { season in
                    Text(verbatim: season).tag(season)
                }
            } label: {
                Copy.text(.seasonPicker)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("design.season.picker")
        }
    }
}

struct NextUpCard: View {
    var title: String
    @DesignAccessibility private var accessibility

    var body: some View {
        ContainedGlass {
            HStack(spacing: SpacingToken.m) {
                ContentPaint.progressTrack
                    .frame(width: 180, height: 100)
                    .clipShape(ContentShape.concentric)
                VStack(alignment: .leading, spacing: SpacingToken.s) {
                    Copy.text(.prototypeNextUp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(verbatim: title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Button(action: {}) {
                        Copy.text(.actionPlayNow)
                    }
                    .glassButtonChrome(prominent: true, contrast: accessibility.contrast)
                    .accessibilityIdentifier("design.nextUp.play")
                }
            }
            .padding(SpacingToken.m)
            .ownGlassSurface(in: ContentShape.concentric)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("design.nextUp.root")
    }
}

struct LoginPanel: View {
    var body: some View {
        ContainedGlass {
            VStack(alignment: .leading, spacing: SpacingToken.s) {
                Copy.text(.prototypeLogin)
                    .font(.title3)
                    .foregroundStyle(.primary)
            }
            .padding(SpacingToken.l)
            .frame(maxWidth: 480, alignment: .leading)
            .ownGlassSurface(in: ContentShape.concentric)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("design.login.root")
    }
}

struct FocusGlassSample: View {
    var forcedFocus: Bool?

    @Environment(\.isFocused) private var environmentFocus

    private var isFocused: Bool {
        forcedFocus ?? environmentFocus
    }

    var body: some View {
        ContainedGlass {
            Copy.text(.prototypeFocus)
                .padding(.horizontal, SpacingToken.l)
                .padding(.vertical, SpacingToken.s)
                .ownGlassSurface(in: Capsule(), kind: .focused(isFocused))
                .focusable(forcedFocus == nil)
                .accessibilityIdentifier(isFocused ? "design.focusGlass.focused" : "design.focusGlass.idle")
        }
    }
}

struct InteractiveGlassProbe: View {
    var body: some View {
        ContainedGlass {
            Copy.text(.prototypeInteractive)
                .padding(.horizontal, SpacingToken.l)
                .padding(.vertical, SpacingToken.s)
                .ownGlassSurface(in: Capsule(), kind: .interactiveProbe)
                .accessibilityIdentifier("design.probe.interactive")
        }
    }
}

struct SubtitleCue: View {
    var body: some View {
        Copy.text(.prototypeSubtitle)
            .font(.title3)
            .foregroundStyle(.primary)
            .padding(.horizontal, SpacingToken.m)
            .padding(.vertical, SpacingToken.xs)
            .background(ContentPaint.subtitleBacking, in: RoundedRectangle(cornerRadius: SpacingToken.xs))
            .accessibilityIdentifier("design.subtitle.cue")
    }
}
