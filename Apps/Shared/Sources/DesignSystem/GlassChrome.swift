import SwiftUI

/// Q5-01: Increase Contrast draws the separator. The no-border rule applies only in the default contrast mode.
enum GlassContrastChrome {
    static let lineWidth = 1.0

    static func showsSeparator(_ contrast: ColorSchemeContrast) -> Bool {
        contrast == .increased
    }
}

enum GlassTint {
    static func allowsAccent(_ contrast: ColorSchemeContrast) -> Bool {
        contrast != .increased
    }
}

enum FocusGlass {
    static func material(isFocused: Bool) -> Glass {
        isFocused ? .regular : .identity
    }
}

enum OwnGlassKind: Equatable {
    case regular
    case focused(Bool)
    case interactiveProbe
}

struct OwnGlassSurface<S: Shape>: ViewModifier {
    var shape: S
    var kind: OwnGlassKind
    var tinted: Bool

    @DesignAccessibility private var accessibility
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let bordered = applyBody(content)
        if GlassContrastChrome.showsSeparator(accessibility.contrast) {
            bordered.overlay {
                shape.stroke(Color(.separator), lineWidth: GlassContrastChrome.lineWidth)
            }
        } else {
            bordered
        }
    }

    @ViewBuilder
    private func applyBody(_ content: Content) -> some View {
        if accessibility.reduceTransparency {
            content.background(ReduceTransparencyFallback.color(for: colorScheme), in: shape)
        } else {
            content.glassEffect(glass, in: shape)
        }
    }

    private var glass: Glass {
        let base: Glass
        switch kind {
        case .regular:
            base = .regular
        case .focused(let isFocused):
            base = FocusGlass.material(isFocused: isFocused)
        case .interactiveProbe:
            base = Glass.regular.interactive()
        }
        if tinted && GlassTint.allowsAccent(accessibility.contrast) {
            return base.tint(.accentColor)
        }
        return base
    }
}

extension View {
    /// Directional focus sections belong to the Siri Remote interface.
    @ViewBuilder
    func designFocusSection() -> some View {
        #if os(tvOS)
            focusSection()
        #else
            self
        #endif
    }

    func ownGlassSurface<S: Shape>(in shape: S, kind: OwnGlassKind = .regular, tinted: Bool = false) -> some View {
        modifier(OwnGlassSurface(shape: shape, kind: kind, tinted: tinted))
    }

    @ViewBuilder
    func glassButtonChrome(prominent: Bool, contrast: ColorSchemeContrast) -> some View {
        if prominent {
            buttonStyle(.glassProminent)
                .modifier(AccentTintIfAllowed(enabled: GlassTint.allowsAccent(contrast)))
        } else {
            buttonStyle(.glass)
        }
    }

    @ViewBuilder
    func glassMorphID(_ id: String, in namespace: Namespace.ID, enabled: Bool) -> some View {
        if enabled {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func posterButtonStyle() -> some View {
        #if os(tvOS)
            buttonStyle(.card)
        #else
            buttonStyle(.plain)
        #endif
    }
}

private struct AccentTintIfAllowed: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.tint(.accentColor)
        } else {
            content
        }
    }
}

struct ContainedGlass<Content: View>: View {
    var spacing: CGFloat?
    var content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content
        }
        .designFocusSection()
    }
}

struct BackdropScrim: View {
    var gradient = ScrimGradient()

    var body: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: ContentPaint.scrim.opacity(0), location: gradient.clearUntil),
                Gradient.Stop(color: ContentPaint.scrim.opacity(gradient.endOpacity), location: gradient.end),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
