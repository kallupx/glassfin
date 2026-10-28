import GlassfinCore
import SwiftUI
import UIKit
import XCTest

@testable import Glassfin

final class T09SearchSnapshotTests: XCTestCase {
    /// T09-31: the real search view with Movies, Series and Episodes, at both output sizes.
    @MainActor
    func testT09_31_groupedRowsAt1080And4K() async throws {
        let fixture = try await SearchSnapshotFixture()
        defer { fixture.cleanup() }
        XCTAssertEqual(fixture.feature.model.groups.map(\.id), [.movies, .series, .episodes])
        try await recordSearch(fixture, name: "T09-31-grouped")
    }

    /// T09-32: a successful empty Series group leaves no empty header between the other rows.
    @MainActor
    func testT09_32_emptyGroupAt1080And4K() async throws {
        let fixture = try await SearchSnapshotFixture(mode: .emptySeries)
        defer { fixture.cleanup() }
        XCTAssertEqual(fixture.feature.model.groups.map { $0.items.count }, [1, 0, 1])
        try await recordSearch(fixture, name: "T09-32-empty-group")
    }

    /// T09-33: empty-result copy includes a literal query, including Markdown punctuation.
    @MainActor
    func testT09_33_literalEmptyQueryAt1080And4K() async throws {
        let fixture = try await SearchSnapshotFixture(mode: .empty, term: "**xyz**")
        defer { fixture.cleanup() }
        XCTAssertTrue(fixture.feature.model.showsEmpty)
        try await recordSearch(fixture, name: "T09-33-empty")
    }

    /// T09-34: a pending query shows the real skeleton and no results from the previous query.
    @MainActor
    func testT09_34_loadingAt1080And4K() async throws {
        let fixture = try await SearchSnapshotFixture()
        defer { fixture.cleanup() }
        XCTAssertTrue(fixture.feature.model.hasContent)
        fixture.feature.model.setTerm("pending")
        XCTAssertTrue(fixture.feature.model.state.showsSkeleton)
        XCTAssertTrue(fixture.feature.model.groups.isEmpty)
        try await recordSearch(fixture, name: "T09-34-loading")
    }

    /// T09-35: the production poster button face shows both movie and series title/year.
    @MainActor
    func testT09_35_movieAndSeriesPostersAt1080And4K() async throws {
        let fixture = try await SearchSnapshotFixture()
        defer { fixture.cleanup() }
        let items = fixture.feature.model.groups.filter { $0.id != .episodes }.flatMap(\.items)
        XCTAssertEqual(items.map(\.searchCardTitle), ["Star film (2026)", "Star voyagers (2024)"])
        let cards = HStack(alignment: .top, spacing: CardMetrics.spacing) {
            ForEach(items) { item in
                SearchResultCard(feature: fixture.feature, item: item, style: .poster, focused: true, onSelect: {})
            }
        }
        try record(cards, name: "T09-35-posters")
    }

    /// T09-36: the production landscape face shows series, SxEy and episode name.
    @MainActor
    func testT09_36_episodeLandscapeAt1080And4K() async throws {
        let fixture = try await SearchSnapshotFixture()
        defer { fixture.cleanup() }
        let item = try XCTUnwrap(fixture.feature.model.groups.last?.items.first)
        XCTAssertEqual(item.searchCardTitle, "Star voyagers · S2E3 · The arrival")
        try record(
            SearchResultCard(feature: fixture.feature, item: item, style: .landscape, focused: true, onSelect: {}),
            name: "T09-36-episode")
    }

    /// T09-42: system search chrome and banner glass over content, with Reduce Transparency.
    @MainActor
    func testT09_42_searchGlassAndOpaqueBannerAt1080And4K() async throws {
        let fixture = try await SearchSnapshotFixture()
        defer { fixture.cleanup() }
        fixture.app.handle(.serverUnreachable)
        XCTAssertTrue(fixture.feature.model.hasContent)
        XCTAssertEqual(fixture.feature.model.bannerKey, AppErrorMessage.serverDownKey)
        var captures: [(String, Data)] = []
        for opaque in [false, true] {
            captures += try await searchCaptures(fixture, name: "T09-42-\(opaque ? "opaque" : "glass")", opaque: opaque)
        }
        let glass = try XCTUnwrap(captures.first { $0.0 == "T09-42-glass-1080-top.png" }?.1)
        let opaque = try XCTUnwrap(captures.first { $0.0 == "T09-42-opaque-1080-top.png" }?.1)
        XCTAssertNotEqual(glass, opaque)
        try compareReferences(captures)
    }

    /// T09-64: literal tags, entities and long graphemes retain the real card layout.
    @MainActor
    func testT09_64_literalMetadataLayoutAt1080And4K() async throws {
        let fixture = try await SearchSnapshotFixture(mode: .literal)
        defer { fixture.cleanup() }
        let items = fixture.feature.model.groups.flatMap(\.items)
        XCTAssertEqual(items.first?.name, "<b>Star</b> &amp; **film**")
        XCTAssertEqual(items.last?.seriesName?.count, MetadataPolicy.nameMax)
        let cards = HStack(alignment: .top, spacing: SpacingToken.l) {
            ForEach(items) { item in
                SearchResultCard(
                    feature: fixture.feature, item: item,
                    style: item.kind == .episode ? .landscape : .poster, focused: true, onSelect: {})
            }
        }
        try record(cards, name: "T09-64-literal")
    }

    @MainActor
    private func recordSearch(_ fixture: SearchSnapshotFixture, name: String) async throws {
        let captures = try await searchCaptures(fixture, name: name)
        try compareReferences(captures)
    }

    @MainActor
    private func searchCaptures(
        _ fixture: SearchSnapshotFixture, name: String, opaque: Bool = false
    ) async throws -> [(String, Data)] {
        var captures: [(String, Data)] = []
        for scale in [CGFloat(1), CGFloat(2)] {
            // Host the actual screen: ImageRenderer alone cannot capture UIKit's native searchable chrome.
            let view = SearchView(feature: fixture.feature)
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.colorScheme, .dark)
                .environment(
                    \.designAccessibilityOverride,
                    DesignAccessibilityValues(reduceTransparency: opaque, reduceMotion: true))
            let host = UIHostingController(rootView: view)
            host.overrideUserInterfaceStyle = .dark
            let size = CGSize(width: 1920, height: 1080)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previousKey = scene.windows.first { $0.isKeyWindow }
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            // Give UIKit's navigation/search presentation a run-loop turn to commit its first frame.
            try await Task.sleep(for: .milliseconds(600))
            host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            for position in ["top", "bottom"] {
                if position == "bottom" {
                    guard let scroll = verticalScroll(in: host.view) else { continue }
                    scroll.setContentOffset(
                        CGPoint(
                            x: 0,
                            y: max(
                                0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom
                            )),
                        animated: false)
                    try await Task.sleep(for: .milliseconds(100))
                    host.view.layoutIfNeeded()
                }
                let image = renderer.image { _ in
                    XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
                }
                let data = image.pngData() ?? Data()
                let filename = "\(name)-\(scale == 1 ? "1080" : "4k")-\(position).png"
                attach(data, name: filename, scale: scale, bitmap: image.cgImage)
                captures.append((filename, data))
            }
            window.isHidden = true
            window.rootViewController = nil
            previousKey?.makeKey()
        }
        return captures
    }

    @MainActor
    private func verticalScroll(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.contentSize.height > scroll.bounds.height + 1 { return scroll }
        return view.subviews.lazy.compactMap { self.verticalScroll(in: $0) }.first
    }

    @MainActor
    private func record<V: View>(_ view: V, name: String) throws {
        var captures: [(String, Data)] = []
        for scale in [CGFloat(1), CGFloat(2)] {
            let canvas =
                view
                .padding(SpacingToken.xl)
                .frame(width: 1920, height: 1080)
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.colorScheme, .dark)
                .environment(\.designAccessibilityOverride, DesignAccessibilityValues(reduceMotion: true))
            let renderer = ImageRenderer(content: canvas)
            renderer.proposedSize = ProposedViewSize(width: 1920, height: 1080)
            renderer.scale = scale
            renderer.isOpaque = true
            let image = try XCTUnwrap(renderer.uiImage)
            let data = image.pngData() ?? Data()
            let filename = "\(name)-\(scale == 1 ? "1080" : "4k").png"
            attach(data, name: filename, scale: scale, bitmap: image.cgImage)
            captures.append((filename, data))
        }
        try compareReferences(captures)
    }

    @MainActor
    private func attach(_ data: Data, name: String, scale: CGFloat, bitmap: CGImage?) {
        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(bitmap?.width, Int(1920 * scale))
        XCTAssertEqual(bitmap?.height, Int(1080 * scale))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["GLASSFIN_SCREENSHOT_DIR"], !folder.isEmpty {
            let directory = URL(fileURLWithPath: folder).appendingPathComponent("m09-\(platform)")
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: directory.appendingPathComponent(name))
            } catch { XCTFail("Could not write snapshot artifact: \(error)") }
        }
    }

    @MainActor
    private func compareReferences(_ captures: [(String, Data)]) throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__/T09SearchSnapshotTests/\(platform)")
        let missing = captures.filter {
            !FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.0).path)
        }
        // Both sizes are attached before recording is reported as skipped. Never accept a new baseline automatically.
        guard missing.isEmpty else {
            throw XCTSkip("M09 references require recording/review on macOS CI; rendered PNGs are attached")
        }
        for (name, actual) in captures {
            XCTAssertEqual(actual, try Data(contentsOf: directory.appendingPathComponent(name)), "Snapshot: \(name)")
        }
    }

    private var platform: String {
        #if os(tvOS)
            "tvos"
        #else
            "ios"
        #endif
    }
}

@MainActor
private struct SearchSnapshotFixture {
    enum Mode: Sendable { case results, emptySeries, empty, literal }

    let root: URL
    let app: AppState
    let feature: SearchFeature

    init(mode: Mode = .results, term: String = "star") async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        app = AppState(
            secureStore: InMemorySecureStore(), settings: InMemorySettingsStore(),
            path: StaticConnectivityPath(online: true), pinger: SearchSnapshotPinger(), cacheRoot: root,
            automaticPing: false, recentSearches: RecentSearchStore(directory: root.appendingPathComponent("history")))
        let session = UserSession(
            server: ServerInfo(
                id: "11111111111111111111111111111111", name: "Search fixture",
                url: URL(string: "https://media.example")!, version: SemVer(major: 12, minor: 2, patch: 0)),
            userID: "22222222222222222222222222222222", userName: "Ada", isAdministrator: false)
        try app.didSignIn(session, token: "snapshot-token")
        feature = SearchFeature(app: app, session: session, client: SearchSnapshotClient(mode: mode))
        feature.model.setTerm(term)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while feature.model.state.isLoading && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(feature.model.state.isLoading)
        XCTAssertNil(feature.model.blockingErrorKey)
    }

    func cleanup() {
        feature.model.onDisappear()
        try? FileManager.default.removeItem(at: root)
    }
}

private struct SearchSnapshotClient: JellyfinAPIClient {
    let mode: SearchSnapshotFixture.Mode

    func send(_ request: APIRequest) async throws(APIError) -> Data {
        let kind = request.query.first { $0.name == "includeItemTypes" }?.value ?? "Movie"
        let term = request.query.first { $0.name == "searchTerm" }?.value
        if term == "pending" {
            do { try await Task.sleep(for: .seconds(60)) } catch { throw .cancelled }
        }
        let item: [String: Any]
        switch kind {
        case "Series":
            item = [
                "Id": "cccccccccccccccccccccccccccccccc", "Type": kind, "Name": "Star voyagers", "ProductionYear": 2024,
            ]
        case "Episode":
            item = [
                "Id": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", "Type": kind, "Name": "The arrival",
                "SeriesName": mode == .literal ? "\u{202E}" + String(repeating: "👩🏽‍🚀", count: 201) : "Star voyagers",
                "ParentIndexNumber": 2, "IndexNumber": 3,
            ]
        default:
            item = [
                "Id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "Type": kind,
                "Name": mode == .literal ? "\u{0000}<b>Star</b> &amp; **film**" : "Star film", "ProductionYear": 2026,
            ]
        }
        let items = mode == .empty || (mode == .emptySeries && kind == "Series") ? [] : [item]
        do {
            return try JSONSerialization.data(withJSONObject: ["Items": items, "TotalRecordCount": items.count])
        } catch { throw .decoding }
    }
}

private struct SearchSnapshotPinger: ReachabilityPinging {
    func ping() async -> PingOutcome { .ok }
}
