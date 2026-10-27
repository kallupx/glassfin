import SwiftUI
import UIKit
import XCTest

@testable import Glassfin

@MainActor
final class DesignSystemLogicTests: XCTestCase {
    func testT05_01_glassFollowsTheSurfaceTable() {
        XCTAssertEqual(SurfaceAssignment.materials["tabBar"], .systemTabBar)
        XCTAssertEqual(SurfaceAssignment.materials["heroActions"], .glassContainer)
        XCTAssertEqual(SurfaceAssignment.materials["seasonPicker"], .glassContainer)
        XCTAssertEqual(SurfaceAssignment.materials["filterBar"], .glassContainer)
        XCTAssertEqual(SurfaceAssignment.materials["banner"], .customGlassBanner)
        XCTAssertEqual(SurfaceAssignment.materials["posterCard"], .content)
        XCTAssertEqual(SurfaceAssignment.materials["landscapeCard"], .content)
        XCTAssertEqual(SurfaceAssignment.materials["subtitle"], .subtitle)
        XCTAssertTrue(SurfaceAssignment.allowsGlass(.systemTabBar))
        XCTAssertTrue(SurfaceAssignment.allowsGlass(.glassContainer))
        XCTAssertTrue(SurfaceAssignment.allowsGlass(.customGlassBanner))
        XCTAssertFalse(SurfaceAssignment.allowsGlass(.content))
        XCTAssertFalse(SurfaceAssignment.allowsGlass(.subtitle))
    }

    func testT05_06_tintIsRemovedWhenContrastIncreases() {
        XCTAssertTrue(GlassTint.allowsAccent(.standard))
        XCTAssertFalse(GlassTint.allowsAccent(.increased))
    }

    func testT05_08_sharedDesignTypesAreLinked() {
        XCTAssertEqual(CardMetrics.posterWidth, 250)
        XCTAssertEqual(SpacingToken.xl, 40)
        XCTAssertEqual(TypographyToken.body, .body)
    }

    func testT05_09_posterMetricsAndProgressStates() {
        XCTAssertEqual(CardMetrics.posterWidth / CardMetrics.posterHeight, 2.0 / 3.0, accuracy: 0.0001)
        let variants = DemoFixtures.posterVariants
        XCTAssertEqual(variants.map(\.id), ["zero", "half", "done", "count", "unknown"])
        XCTAssertEqual(variants[0].progress.fraction ?? -1, 0, accuracy: 0.0001)
        XCTAssertTrue(variants[0].progress.showsBar)
        XCTAssertEqual(variants[1].progress.fraction ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(variants[2].progress.fraction ?? -1, 1, accuracy: 0.0001)
        XCTAssertTrue(variants[2].isWatched)
        XCTAssertNil(variants[2].progress.remainingMinutes)
        XCTAssertEqual(variants[3].unplayedCount, 4)
        XCTAssertFalse(variants[4].progress.showsBar)
        XCTAssertNil(variants[4].remainingKey)
        XCTAssertEqual(PosterPhase.failed, .failed)
    }

    func testT05_11_landscapeCardKeepsTheRemainingMinutesKey() {
        XCTAssertEqual(
            CardMetrics.landscapeWidth / CardMetrics.landscapeHeight,
            16.0 / 9.0,
            accuracy: 0.0001
        )
        let wide = DemoFixtures.primary()[0]
        XCTAssertEqual(wide.progress.remainingMinutes, 32)
        XCTAssertEqual(wide.remainingKey, .remainingMinutes)
        XCTAssertEqual(CopyKey.remainingMinutes.rawValue, "design.remainingMinutes")
        let unknown = PlaybackProgress.measure(position: .seconds(10), runtime: nil)
        XCTAssertFalse(unknown.showsBar)
        let empty = PlaybackProgress.measure(position: .seconds(1), runtime: .seconds(0))
        XCTAssertFalse(empty.showsBar)
    }

    func testT05_13_playActionIsTheProminentDefault() {
        let play = HeroHeader.actions(canResume: false)[0]
        XCTAssertEqual(play.id, "play")
        XCTAssertTrue(play.prominent)
        XCTAssertEqual(play.title, .actionPlay)
        XCTAssertEqual(play.identifier, "design.hero.play")
        let resume = HeroHeader.actions(canResume: true)[0]
        XCTAssertEqual(resume.title, .actionResume)
        XCTAssertTrue(resume.prominent)
    }

    func testT05_15_overviewIsPlainText() {
        let plain = PlainText.overview(DemoFixtures.htmlOverview)
        XCTAssertEqual(plain, "A story & more. Tail marker.")
        XCTAssertFalse(plain.contains("<"))
        XCTAssertFalse(plain.contains("alert"))
        XCTAssertFalse(plain.contains("example.com"))
        XCTAssertEqual(DemoFixtures.plainOverview, plain)
    }

    func testT05_17_elementBudgetIsReportedAndNotEnforced() {
        XCTAssertFalse(GlassBudget.exceedsElementLimit(8))
        XCTAssertTrue(GlassBudget.exceedsElementLimit(9))
        XCTAssertEqual(GlassBudget.displayedCount(of: 9), 9)
        XCTAssertEqual(GlassBudget.maximumElementsPerContainer, 8)
    }

    func testT05_19_imageFadeAndBlurHashPlaceholder() {
        XCTAssertEqual(MotionToken.imageFade(reduceMotion: false), 0.15, accuracy: 0.0001)
        XCTAssertEqual(MotionToken.imageFade(reduceMotion: true), 0, accuracy: 0.0001)
        guard let image = BlurHash.image(from: "00TSUA", width: 1, height: 1),
            let data = image.dataProvider?.data
        else {
            XCTFail("missing blurhash pixel")
            return
        }
        let bytes = data as Data
        XCTAssertEqual(Array(bytes.prefix(4)), [255, 255, 255, 255])
        XCTAssertNil(BlurHash.image(from: "00TSUA", width: 0, height: 1))
    }

    func testT05_20_skeletonUsesTheCardRowHeight() {
        XCTAssertEqual(CardMetrics.rowHeight(for: .poster), CardMetrics.posterHeight + CardMetrics.titleHeight)
        XCTAssertEqual(CardMetrics.rowHeight(for: .landscape), CardMetrics.landscapeHeight + CardMetrics.titleHeight)
        XCTAssertEqual(CardMetrics.size(for: .poster), CGSize(width: 250, height: 375))
        XCTAssertEqual(CardMetrics.spacing, 40)
    }

    func testT05_21_failurePresentationKeepsContentOrBlocks() {
        XCTAssertEqual(
            LoadPresentation.mode(for: LoadPhase<String>.failed(.offline, nil)),
            .content(banner: .bannerOffline)
        )
        XCTAssertEqual(
            LoadPresentation.mode(for: LoadPhase<String>.failed(.offline, "cached")),
            .content(banner: .bannerOffline)
        )
        XCTAssertEqual(
            LoadPresentation.mode(for: LoadPhase<String>.failed(.serverUnreachable, "cached")),
            .failure(.serverUnreachable)
        )
        XCTAssertEqual(
            LoadPresentation.mode(for: LoadPhase<String>.failed(.unauthorized, "cached")),
            .failure(.unauthorized)
        )
        XCTAssertEqual(
            LoadPresentation.mode(for: LoadPhase<String>.failed(.unsupported(required: "10.11"), "cached")),
            .failure(.unsupported(required: "10.11"))
        )
        XCTAssertEqual(LoadPresentation.mode(for: LoadPhase<String>.failed(.cancelled, nil)), .empty)
        XCTAssertEqual(
            LoadPresentation.mode(for: LoadPhase<String>.failed(.cancelled, "cached")),
            .content(banner: nil)
        )
        XCTAssertEqual(
            LoadPresentation.mode(for: LoadPhase<String>.failed(.decoding, "cached")),
            .content(banner: nil)
        )
        XCTAssertEqual(
            LoadPresentation.mode(for: LoadPhase<String>.failed(.forbidden, "cached")),
            .content(banner: nil)
        )
        XCTAssertEqual(
            LoadPresentation.mode(for: LoadPhase<String>.failed(.forbidden, nil)),
            .failure(.forbidden)
        )
        let retry = DesignFailure.serverUnreachable.screen
        guard case .blocking(let key, true, true) = retry else {
            XCTFail("server unreachable should block with retry and switch server")
            return
        }
        XCTAssertEqual(key, .errorServerUnreachable)
    }

    func testT05_22_copyKeysAreSymbolic() {
        var seen = Set<String>()
        for key in CopyKey.allCases {
            XCTAssertFalse(key.rawValue.contains(" "))
            XCTAssertTrue(key.rawValue.contains("."))
            XCTAssertTrue(seen.insert(key.rawValue).inserted)
        }
        XCTAssertEqual(CopyKey.actionPlay.rawValue, "design.action.play")
        XCTAssertEqual(CopyKey.actionRetry.rawValue, "design.action.retry")
        XCTAssertEqual(CopyKey.bannerOffline.rawValue, "design.banner.offline")
        XCTAssertEqual(CopyKey.tabHome.rawValue, "design.tab.home")
        XCTAssertEqual(CopyKey.welcomeConnect.rawValue, "welcome.connect")
    }

    func testT05_23_fixturesHaveNoSecrets() {
        let blob = [
            DemoFixtures.htmlOverview,
            DemoFixtures.plainOverview,
            DemoFixtures.blurHash,
        ].joined(separator: "\n")
        for word in ["password", "secret", "X-Emby", "Bearer "] {
            XCTAssertFalse(blob.localizedCaseInsensitiveContains(word))
        }
        let queryName = ["api", "_key"].joined()
        XCTAssertFalse(blob.contains(queryName))
    }

    func testT05_25_focusGlassMaterialIsCallable() {
        _ = FocusGlass.material(isFocused: true)
        _ = FocusGlass.material(isFocused: false)
    }

    func testT05_27_libraryTabsFollowTheWrittenDefault() {
        XCTAssertEqual(LibraryTabModel.maximumInlineLibraries, 5)
        let none = LibraryTabModel.plan(libraries: [])
        XCTAssertTrue(none.inline.isEmpty)
        XCTAssertTrue(none.overflow.isEmpty)
        let three = (0..<3).map { LibraryTabItem(id: "\($0)", title: "\($0)") }
        let plan3 = LibraryTabModel.plan(libraries: three)
        XCTAssertEqual(plan3.inline.map(\.id), ["0", "1", "2"])
        XCTAssertTrue(plan3.overflow.isEmpty)
        let seven = (0..<7).map { LibraryTabItem(id: "\($0)", title: "\($0)") }
        let plan7 = LibraryTabModel.plan(libraries: seven)
        XCTAssertEqual(plan7.inline.map(\.id), ["0", "1", "2", "3", "4"])
        XCTAssertEqual(plan7.overflow.map(\.id), ["5", "6"])
    }

    func testT05_32_scrimContrastOnThreeBackgrounds() {
        // T05-32: endpoint contrast uses the same color tokens and gradient as HeroHeader's scrim.
        let gradient = ScrimGradient()
        XCTAssertEqual(gradient.opacity(at: 0.6), 0, accuracy: 0.0001)
        XCTAssertEqual(gradient.opacity(at: 1), 0.6, accuracy: 0.0001)
        XCTAssertEqual(gradient.clearUntil, 0.6)
        let text = ContrastFixture.text
        let bright = text.contrast(against: ContrastFixture.scrimmed(ContrastFixture.bright, at: gradient.end))
        let dark = text.contrast(against: ContrastFixture.scrimmed(ContrastFixture.dark, at: gradient.end))
        let colorful = text.contrast(against: ContrastFixture.scrimmed(ContrastFixture.colorful, at: gradient.end))
        XCTAssertGreaterThanOrEqual(dark, ContrastFixture.bodyMinimum)
        XCTAssertGreaterThanOrEqual(colorful, ContrastFixture.bodyMinimum)
        XCTAssertGreaterThanOrEqual(dark, ContrastFixture.largeMinimum)
        XCTAssertGreaterThanOrEqual(colorful, ContrastFixture.largeMinimum)
        // These passes cover the darkest stop only; higher hero text is checked conservatively below.
        XCTAssertGreaterThanOrEqual(bright, ContrastFixture.bodyMinimum)
        XCTAssertGreaterThanOrEqual(bright, ContrastFixture.largeMinimum)
        XCTAssertLessThan(text.contrast(against: ContrastFixture.bright), ContrastFixture.largeMinimum)
    }

    func testT05_32_contrastFixtureMatchesHeroTokens() {
        // T05-32: resolve independently so fixture colors or opacity cannot drift from the drawn scrim.
        let traits = UITraitCollection(userInterfaceStyle: .dark)
        func components(of color: Color) -> RGB {
            var red: CGFloat = -1
            var green: CGFloat = -1
            var blue: CGFloat = -1
            var alpha: CGFloat = -1
            let resolved = UIColor(color).resolvedColor(with: traits)
            XCTAssertTrue(resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
            XCTAssertEqual(alpha, 1, accuracy: 0.0001)
            return RGB(r: Double(red), g: Double(green), b: Double(blue))
        }
        let text = components(of: ContentPaint.heroText)
        let scrim = components(of: ContentPaint.scrim)
        XCTAssertEqual(ContrastFixture.text, text)
        XCTAssertEqual(ContrastFixture.scrim, scrim)
        let gradient = BackdropScrim().gradient
        XCTAssertEqual(gradient, ScrimGradient())
        for background in [ContrastFixture.bright, ContrastFixture.dark, ContrastFixture.colorful] {
            XCTAssertEqual(
                ContrastFixture.scrimmed(background, at: gradient.end),
                scrim.composited(over: background, alpha: gradient.endOpacity)
            )
        }
    }

    func testT05_32_upperHeroTextUsesConservativeScrimOpacity() {
        // T05-32: HeroHeader's bottom-aligned stack includes padding, actions, and expandable overview text.
        // Its title/overview can reach the transparent region; no minimum text height fraction is enforced.
        // Use the clear stop (zero opacity, also valid above it) as the conservative bound for that text.
        // Endpoint passes therefore do not establish AA for the full hero; Q5-03 remains open.
        let gradient = ScrimGradient()
        let text = ContrastFixture.text
        for background in [ContrastFixture.bright, ContrastFixture.dark, ContrastFixture.colorful] {
            XCTAssertEqual(ContrastFixture.scrimmed(background, at: gradient.clearUntil), background)
        }
        let bright = text.contrast(against: ContrastFixture.scrimmed(ContrastFixture.bright, at: gradient.clearUntil))
        let dark = text.contrast(against: ContrastFixture.scrimmed(ContrastFixture.dark, at: gradient.clearUntil))
        let colorful = text.contrast(
            against: ContrastFixture.scrimmed(ContrastFixture.colorful, at: gradient.clearUntil))
        XCTAssertLessThan(bright, ContrastFixture.largeMinimum)
        XCTAssertLessThan(bright, ContrastFixture.bodyMinimum)
        XCTAssertGreaterThanOrEqual(dark, ContrastFixture.bodyMinimum)
        XCTAssertGreaterThanOrEqual(dark, ContrastFixture.largeMinimum)
        XCTAssertLessThan(colorful, ContrastFixture.bodyMinimum)
        XCTAssertGreaterThanOrEqual(colorful, ContrastFixture.largeMinimum)
    }

    func testT05_35_reduceTransparencyUsesOneFallbackToken() {
        for scheme in [ColorScheme.light, .dark] {
            let color = UIColor(ReduceTransparencyFallback.color(for: scheme))
            var white: CGFloat = -1
            var alpha: CGFloat = -1
            XCTAssertTrue(color.getWhite(&white, alpha: &alpha))
            XCTAssertEqual(alpha, 1, accuracy: 0.001)
            XCTAssertEqual(white, scheme == .dark ? 0 : 1, accuracy: 0.001)
        }
        XCTAssertEqual(GlassContrastChrome.lineWidth, 1)
    }

    func testT05_36_increaseContrastShowsTheSeparatorToken() {
        XCTAssertTrue(GlassContrastChrome.showsSeparator(.increased))
        XCTAssertFalse(GlassContrastChrome.showsSeparator(.standard))
    }

    func testT05_37_reduceMotionDropsMorphAndCrossfade() {
        XCTAssertFalse(MotionPolicy.allowsMorph(true))
        XCTAssertTrue(MotionPolicy.allowsMorph(false))
        XCTAssertFalse(MotionPolicy.allowsCustomParallax(false))
        XCTAssertFalse(MotionPolicy.allowsCustomParallax(true))
        XCTAssertEqual(MotionToken.imageFade(reduceMotion: true), 0, accuracy: 0.0001)
    }

    func testT05_38_primaryCopyIsNotLineLimited() {
        XCTAssertNil(TruncationPolicy.playButtonLineLimit)
        XCTAssertNil(TruncationPolicy.errorMessageLineLimit)
        XCTAssertNil(TruncationPolicy.codeLineLimit)
    }

    func testT05_41_detailAndPlaybackStayInsideTheGlassBudget() {
        XCTAssertEqual(ScreenGlassPlan.detail().count, GlassBudget.maximumContainers)
        XCTAssertEqual(ScreenGlassPlan.detail(), [.heroActions, .seasonPicker])
        XCTAssertEqual(ScreenGlassPlan.playback(), [.nextUp])
        XCTAssertEqual(SurfaceAssignment.materials["banner"], .customGlassBanner)
        XCTAssertLessThanOrEqual(ScreenGlassPlan.playback().count, GlassBudget.maximumContainers)
    }

    func testT05_42_cardsAndSubtitlesAreContentSurfaces() {
        XCTAssertFalse(SurfaceAssignment.allowsGlass(.content))
        XCTAssertFalse(SurfaceAssignment.allowsGlass(.subtitle))
    }

    func testT05_43_playbackGlassIsTheSingleNextUpOverlay() {
        XCTAssertEqual(ScreenGlassPlan.playback(), [.nextUp])
    }

    func testT05_55_customParallaxStaysOff() {
        XCTAssertFalse(MotionPolicy.allowsCustomParallax(false))
        XCTAssertFalse(MotionPolicy.allowsCustomParallax(true))
    }
}
