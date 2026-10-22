import SwiftUI

enum SpacingToken {
    static let xxs = 4.0
    static let xs = 8.0
    static let s = 12.0
    static let m = 16.0
    static let l = 24.0
    static let xl = 40.0
    static let row = 48.0
}

enum CardMetrics {
    static let spacing = 40.0
    static let titleHeight = 44.0
    static let posterWidth = 250.0
    static let posterHeight = 375.0
    static let landscapeWidth = 420.0
    static let landscapeHeight = 236.25

    static func size(for style: CardStyle) -> CGSize {
        switch style {
        case .poster:
            CGSize(width: posterWidth, height: posterHeight)
        case .landscape:
            CGSize(width: landscapeWidth, height: landscapeHeight)
        }
    }

    static func rowHeight(for style: CardStyle) -> Double {
        size(for: style).height + titleHeight
    }
}

enum CardStyle: Sendable {
    case poster
    case landscape
}

enum TypographyToken {
    static let heroTitle = Font.TextStyle.largeTitle
    static let rowTitle = Font.TextStyle.title3
    static let cardTitle = Font.TextStyle.headline
    static let meta = Font.TextStyle.subheadline
    static let body = Font.TextStyle.body
    static let caption = Font.TextStyle.caption
}

enum MotionToken {
    /// Poster placeholder crossfade. T05-19.
    static let imageFadeSeconds = 0.15

    /// Q5-08 asks whether Reduce Motion includes this fade. T05-37 removes crossfades,
    /// so the reduced duration is zero until that question says otherwise.
    static func imageFade(reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : imageFadeSeconds
    }
}

enum MotionPolicy {
    static func allowsMorph(_ reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    /// Cards use the system card style for parallax. Custom parallax is never added.
    static func allowsCustomParallax(_ reduceMotion: Bool) -> Bool {
        _ = reduceMotion
        false
    }
}

enum ContentPaint {
    static let scrim = Color.black
    static let subtitleBacking = Color.black.opacity(0.6)
    static let progressFill = Color.white
    static let progressTrack = Color.black.opacity(0.55)
}

/// Bottom scrim: transparent until 60% of the height, then black at 60% opacity.
struct ScrimGradient: Equatable, Sendable {
    var clearUntil = 0.6
    var endOpacity = 0.6
    var end = 1.0

    func opacity(at heightFraction: Double) -> Double {
        if heightFraction <= clearUntil {
            return 0
        }
        let span = end - clearUntil
        if span <= 0 {
            return endOpacity
        }
        let progress = min(1, max(0, (heightFraction - clearUntil) / span))
        return endOpacity * progress
    }
}

struct RGB: Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    var relativeLuminance: Double {
        func linearize(_ channel: Double) -> Double {
            if channel <= 0.04045 {
                return channel / 12.92
            }
            return pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    func contrast(against other: RGB) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    func composited(over background: RGB, alpha: Double) -> RGB {
        RGB(
            r: r * alpha + background.r * (1 - alpha),
            g: g * alpha + background.g * (1 - alpha),
            b: b * alpha + background.b * (1 - alpha)
        )
    }
}

enum ContrastFixture {
    static let text = RGB(r: 1, g: 1, b: 1)
    static let scrim = RGB(r: 0, g: 0, b: 0)
    static let bright = RGB(r: 1, g: 1, b: 1)
    static let dark = RGB(r: 0.05, g: 0.05, b: 0.05)
    static let colorful = RGB(r: 0.95, g: 0.15, b: 0.45)
    static let bodyMinimum = 4.5
    static let largeMinimum = 3.0

    static func scrimmed(_ background: RGB, gradient: ScrimGradient = ScrimGradient()) -> RGB {
        scrim.composited(over: background, alpha: gradient.endOpacity)
    }
}

enum ContentShape {
    static var concentric: ConcentricRectangle {
        ConcentricRectangle(corners: .concentric, isUniform: true)
    }
}
