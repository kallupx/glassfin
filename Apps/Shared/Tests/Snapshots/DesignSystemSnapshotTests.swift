import SwiftUI
import UIKit
import XCTest
import os

@testable import Glassfin

@MainActor
final class DesignSystemSnapshotTests: XCTestCase {
    func testT05_39_galleryMatrixWritesBothScales() {
        let standard = galleryPNG(mode: .standard, scale: 1, name: "gallery-standard-1080.png")
        let standardAgain = galleryPNG(mode: .standard, scale: 1, name: "gallery-standard-1080-repeat.png")
        XCTAssertEqual(standard, standardAgain)
        _ = galleryPNG(mode: .standard, scale: 2, name: "gallery-standard-4k.png")
        for mode in [GalleryMode.reduceTransparency, .increaseContrast, .reduceMotion] {
            _ = galleryPNG(mode: mode, scale: 1, name: "gallery-\(mode.rawValue)-1080.png")
            _ = galleryPNG(mode: mode, scale: 2, name: "gallery-\(mode.rawValue)-4k.png")
        }
        _ = SnapshotCanvas.png(
            posterStrip.frame(height: 460),
            size: CGSize(width: 1600, height: 460),
            scale: 2,
            name: "posters-variants.png"
        )
        _ = SnapshotCanvas.png(
            SkeletonRow(style: .poster, count: 3, phase: 0),
            size: CGSize(width: 1200, height: 460),
            scale: 2,
            name: "skeleton-poster.png"
        )
    }

    func testT05_40_sameRenderIsByteIdentical() {
        let first = bannerPNG(reduceTransparency: false, increaseContrast: false, name: "banner-repeat-a.png")
        let second = bannerPNG(reduceTransparency: false, increaseContrast: false, name: "banner-repeat-b.png")
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
    }

    func testT05_35_reduceTransparencyBannerDiffers() {
        let standard = bannerPNG(reduceTransparency: false, increaseContrast: false, name: "banner-standard.png")
        let reduced = bannerPNG(
            reduceTransparency: true,
            increaseContrast: false,
            name: "banner-reduce-transparency.png"
        )
        XCTAssertNotEqual(standard, reduced)
    }

    func testT05_36_increaseContrastBannerDiffers() {
        let standard = bannerPNG(
            reduceTransparency: false,
            increaseContrast: false,
            name: "banner-standard-contrast.png"
        )
        let increased = bannerPNG(
            reduceTransparency: false,
            increaseContrast: true,
            name: "banner-increase-contrast.png"
        )
        XCTAssertNotEqual(standard, increased)
    }

    func testT05_24_focusSampleRendersBothStates() {
        let idle = focusPNG(focused: false, name: "focus-glass-idle.png")
        let focused = focusPNG(focused: true, name: "focus-glass-focused.png")
        XCTAssertNotEqual(idle, focused)
    }

    func testT05_25_focusedGlassDiffersFromIdentity() {
        let idle = focusPNG(focused: false, name: "focus-glass-identity.png")
        let focused = focusPNG(focused: true, name: "focus-glass-regular.png")
        XCTAssertNotEqual(idle, focused)
    }

    func testT05_32_scrimSamplesRenderOnThreeBackdrops() {
        let samples: [(String, Color)] = [
            ("bright", .white),
            ("dark", .black),
            ("colorful", Color(red: 0.95, green: 0.15, blue: 0.45)),
        ]
        for (name, color) in samples {
            _ = SnapshotCanvas.png(
                ContrastBackdropSample(background: color, label: name),
                size: CGSize(width: 640, height: 360),
                scale: 2,
                name: "scrim-\(name).png"
            )
        }
    }

    func testT05_38_largestTypeStillRenders() {
        let view = VStack(spacing: SpacingToken.l) {
            ErrorStateView(failure: .serverUnreachable, attempts: 1, onRetry: {}, onSwitchServer: {})
            Button(action: {}) {
                Copy.text(.actionPlay)
            }
            .lineLimit(TruncationPolicy.playButtonLineLimit)
        }
        .environment(\.dynamicTypeSize, .accessibility5)
        .environment(\.legibilityWeight, .bold)
        let data = SnapshotCanvas.png(
            view,
            size: CGSize(width: 1600, height: 900),
            scale: 2,
            name: "error-largest-type.png"
        )
        XCTAssertFalse(data.isEmpty)
    }

    func testT05_45_lazyGridSignpostTrend() {
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        let metric = XCTOSSignpostMetric(
            subsystem: "org.glassfin.app",
            category: "DesignGrid",
            name: "BrowseGrid"
        )
        measure(metrics: [metric], options: options) {
            let poster = OSSignposter(subsystem: "org.glassfin.app", category: "DesignGrid")
            let interval = poster.beginInterval("BrowseGrid")
            let data = SnapshotCanvas.png(
                BrowseGridProbe(count: 2000),
                size: SnapshotCanvas.pointSize,
                scale: 1,
                name: "grid-2000.png"
            )
            XCTAssertFalse(data.isEmpty)
            poster.endInterval("BrowseGrid", interval)
        }
    }

    func testT05_47_cardStyleSamplesRender() {
        let item = DemoFixtures.posterVariants[1]
        _ = SnapshotCanvas.png(
            PosterCard(
                content: item,
                style: .poster,
                identifier: "snapshot.card.idle",
                isFocused: false,
                onSelect: {},
                onTogglePlayed: {},
                onToggleFavorite: {}
            ),
            size: CGSize(width: 280, height: 460),
            scale: 2,
            name: "card-idle.png"
        )
        _ = SnapshotCanvas.png(
            PosterCard(
                content: item,
                style: .poster,
                identifier: "snapshot.card.focused",
                isFocused: true,
                onSelect: {},
                onTogglePlayed: {},
                onToggleFavorite: {}
            ),
            size: CGSize(width: 280, height: 460),
            scale: 2,
            name: "card-focused.png"
        )
    }

    func testT05_49_interactiveProbeRenders() {
        _ = SnapshotCanvas.png(
            InteractiveGlassProbe(),
            size: CGSize(width: 640, height: 160),
            scale: 2,
            name: "interactive-probe.png"
        )
    }

    func testT05_51_segmentedSeasonPickerRenders() {
        _ = SnapshotCanvas.png(
            SeasonPickerHost(),
            size: CGSize(width: 800, height: 120),
            scale: 2,
            name: "season-picker.png"
        )
    }

    private var posterStrip: some View {
        HStack(alignment: .top, spacing: SpacingToken.s) {
            ForEach(DemoFixtures.posterVariants) { item in
                PosterFace(content: item, style: .poster, isFocused: item.id == "half")
            }
        }
    }

    private func galleryPNG(mode: GalleryMode, scale: CGFloat, name: String) -> Data {
        SnapshotCanvas.png(
            mode.apply(DesignSystemGallery(backdrop: Color(red: 0.85, green: 0.35, blue: 0.1))),
            size: SnapshotCanvas.pointSize,
            scale: scale,
            name: name
        )
    }

    private func bannerPNG(reduceTransparency: Bool, increaseContrast: Bool, name: String) -> Data {
        let banner = ZStack {
            Color.orange
            GlassBanner(message: .bannerOffline, systemImage: "wifi.slash", identifier: "snapshot.banner")
        }
        .environment(\.accessibilityReduceTransparency, reduceTransparency)
        .environment(\.colorSchemeContrast, increaseContrast ? .increased : .standard)
        return SnapshotCanvas.png(banner, size: CGSize(width: 800, height: 200), scale: 2, name: name)
    }

    private func focusPNG(focused: Bool, name: String) -> Data {
        SnapshotCanvas.png(
            FocusGlassSample(forcedFocus: focused),
            size: CGSize(width: 640, height: 160),
            scale: 2,
            name: name
        )
    }
}

private enum GalleryMode: String {
    case standard
    case reduceTransparency
    case increaseContrast
    case reduceMotion

    @ViewBuilder
    func apply<V: View>(_ view: V) -> some View {
        switch self {
        case .standard:
            view
        case .reduceTransparency:
            view.environment(\.accessibilityReduceTransparency, true)
        case .increaseContrast:
            view.environment(\.colorSchemeContrast, .increased)
        case .reduceMotion:
            view.environment(\.accessibilityReduceMotion, true)
        }
    }
}

@MainActor
private enum SnapshotCanvas {
    static let pointSize = CGSize(width: 1920, height: 1080)

    static func png<V: View>(
        _ view: V,
        size: CGSize,
        scale: CGFloat,
        name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Data {
        let hosted = view.frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: hosted)
        renderer.scale = scale
        renderer.proposedSize = ProposedViewSize(size)
        renderer.isOpaque = true
        let image = renderer.uiImage
        XCTAssertNotNil(image, "missing render for \(name)", file: file, line: line)
        XCTAssertEqual(image?.size.width ?? 0, size.width, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(image?.size.height ?? 0, size.height, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(image?.scale ?? 0, scale, accuracy: 0.01, file: file, line: line)
        let data = image?.pngData() ?? Data()
        XCTAssertFalse(data.isEmpty, file: file, line: line)
        write(data, name: name)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: name) { activity in
            activity.add(attachment)
        }
        return data
    }

    static func write(_ data: Data, name: String) {
        guard let directory = ProcessInfo.processInfo.environment["GLASSFIN_SCREENSHOT_DIR"], !directory.isEmpty else {
            return
        }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: folder.appendingPathComponent(name))
    }
}

private struct SeasonPickerHost: View {
    @State private var season = "1"

    var body: some View {
        SeasonPickerBar(seasons: ["1", "2", "3"], selection: $season)
    }
}
