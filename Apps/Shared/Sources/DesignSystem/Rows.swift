import SwiftUI

struct MediaRow: View {
    var rowID: String
    var title: CopyKey
    var items: [PosterContent]
    var style: CardStyle
    @Binding var rememberedID: String?
    var onSelect: (PosterContent) -> Void
    var onTogglePlayed: (PosterContent) -> Void
    var onToggleFavorite: (PosterContent) -> Void

    @FocusState private var focus: String?

    private var preferred: String? {
        rememberedID ?? items.first?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingToken.s) {
            Copy.text(title)
                .font(.title3)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal) {
                LazyHStack(spacing: CardMetrics.spacing) {
                    ForEach(items) { item in
                        PosterCard(
                            content: item,
                            style: style,
                            identifier: "\(rowID).item.\(item.id)",
                            isFocused: focus == item.id,
                            onSelect: { onSelect(item) },
                            onTogglePlayed: { onTogglePlayed(item) },
                            onToggleFavorite: { onToggleFavorite(item) }
                        )
                        .focused($focus, equals: item.id)
                    }
                }
                .padding(.vertical, SpacingToken.m)
            }
        }
        .designFocusSection()
        .defaultFocus($focus, preferred, priority: .userInitiated)
        .onChange(of: focus) { _, newValue in
            if let newValue {
                rememberedID = newValue
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(rowID)
    }
}

struct GlassActionBar: View {
    var actions: [GlassAction]
    var prominentID: String
    var onActivate: (String) -> Void

    @FocusState private var focus: String?
    @Namespace private var glassNamespace
    @DesignAccessibility private var accessibility

    var body: some View {
        ContainedGlass(spacing: SpacingToken.m) {
            HStack(spacing: SpacingToken.s) {
                ForEach(actions) { action in
                    Button {
                        onActivate(action.id)
                    } label: {
                        Label {
                            Copy.text(action.title)
                                .lineLimit(TruncationPolicy.playButtonLineLimit)
                        } icon: {
                            GlassIcon(systemName: action.systemImage, label: action.iconLabel)
                        }
                    }
                    .glassButtonChrome(prominent: action.prominent, contrast: accessibility.contrast)
                    .glassMorphID(
                        action.id,
                        in: glassNamespace,
                        enabled: MotionPolicy.allowsMorph(accessibility.reduceMotion)
                    )
                    .focused($focus, equals: action.id)
                    .accessibilityIdentifier(action.identifier)
                }
            }
        }
        .defaultFocus($focus, Optional(prominentID), priority: .userInitiated)
        .onAppear {
            if focus == nil {
                focus = prominentID
            }
        }
    }
}

struct ErrorStateView: View {
    var messageOverride: String? = nil
    var failure: DesignFailure
    var attempts: Int
    var onRetry: () -> Void
    var onSwitchServer: () -> Void

    private var actions: [GlassAction] {
        guard case .blocking(_, let retry, let switchServer) = failure.screen else {
            return []
        }
        var built: [GlassAction] = []
        if retry {
            built.append(
                GlassAction(
                    id: "retry",
                    title: .actionRetry,
                    systemImage: "arrow.clockwise",
                    iconLabel: .actionRetry,
                    prominent: true,
                    identifier: "design.error.retry"
                )
            )
        }
        if switchServer {
            built.append(
                GlassAction(
                    id: "switch",
                    title: .actionSwitchServer,
                    systemImage: "server.rack",
                    iconLabel: .actionSwitchServer,
                    prominent: !retry,
                    identifier: "design.error.switchServer"
                )
            )
        }
        return built
    }

    var body: some View {
        VStack(spacing: SpacingToken.l) {
            if let message = failure.messageKey {
                GlassIcon(systemName: iconName, label: message)
                    .font(.largeTitle)
                Group {
                    if let messageOverride {
                        Text(verbatim: messageOverride)
                    } else if case .unsupported(let required) = failure, message == .errorUnsupported {
                        Text(verbatim: Copy.format(.errorUnsupported, text: required))
                    } else {
                        Copy.text(message)
                    }
                }
                .font(.title3)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(TruncationPolicy.errorMessageLineLimit)
                .accessibilityIdentifier("design.error.message")
            }
            if !actions.isEmpty {
                GlassActionBar(actions: actions, prominentID: actions[0].id) { id in
                    if id == "retry" {
                        onRetry()
                    } else {
                        onSwitchServer()
                    }
                }
            }
            Text(verbatim: String(attempts))
                .accessibilityIdentifier("design.error.attempts")
                .accessibilityValue(String(attempts))
                .frame(width: 1, height: 1)
        }
        .padding(SpacingToken.xl)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("design.error.root")
    }

    private var iconName: String {
        switch failure {
        case .offline:
            "wifi.slash"
        case .serverUnreachable:
            "exclamationmark.icloud"
        case .unauthorized:
            "person.crop.circle.badge.exclamationmark"
        case .forbidden:
            "lock"
        case .notFound:
            "magnifyingglass"
        case .server:
            "server.rack"
        case .unsupported:
            "arrow.down.circle"
        case .playback:
            "play.slash"
        case .decoding, .cancelled:
            "circle"
        }
    }
}
