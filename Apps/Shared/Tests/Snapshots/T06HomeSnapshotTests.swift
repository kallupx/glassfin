import GlassfinCore
import SwiftUI
import UIKit
import XCTest

@testable import Glassfin

@MainActor
final class T06HomeSnapshotTests: XCTestCase {
    // T06-70: canonical spec/TESTPLAN-M06.md.
    func testT06_70_homeDefaultAndOpaqueBannerAt1080And4K() async throws {
        let secure = InMemorySecureStore()
        let settings = InMemorySettingsStore()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppState(
            secureStore: secure, settings: settings, path: StaticConnectivityPath(online: true),
            pinger: SnapshotPinger(), cacheRoot: root, automaticPing: false)
        let server = ServerInfo(
            id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", name: "1", url: URL(string: "https://media.example")!,
            version: SemVer(major: 10, minor: 11, patch: 0))
        let session = UserSession(
            server: server, userID: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", userName: "1", isAdministrator: false)
        try app.didSignIn(session, token: "snapshot-token")
        let model = HomeViewModel(
            library: HomeMockLibrary(mode: "all"), userData: app.userData, snapshots: app.snapshots,
            responses: app.responses, app: app, clock: SystemGlassfinClock(), signposter: app.signposter,
            scope: app.scope)
        await model.load()
        app.handle(.serverUnreachable)
        for reduceTransparency in [false, true] {
            for scale in [CGFloat(1), CGFloat(2)] {
                let view = HomeView(
                    model: model, app: app, session: session, imageLoader: HomeMockImages(),
                    onDetail: { _ in }, onPlay: { _ in }
                )
                .environment(
                    \.designAccessibilityOverride,
                    DesignAccessibilityValues(reduceTransparency: reduceTransparency))
                let renderer = ImageRenderer(content: view.frame(width: 1920, height: 1080))
                renderer.proposedSize = ProposedViewSize(width: 1920, height: 1080)
                renderer.scale = scale
                let data = try XCTUnwrap(renderer.uiImage?.pngData())
                XCTAssertFalse(data.isEmpty)
                let name = "home-\(reduceTransparency ? "opaque" : "default")-\(scale == 1 ? "1080" : "4k").png"
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
                attachment.name = name
                attachment.lifetime = .keepAlways
                add(attachment)
                if let folder = ProcessInfo.processInfo.environment["GLASSFIN_SCREENSHOT_DIR"] {
                    let directory = URL(fileURLWithPath: folder, isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try data.write(to: directory.appendingPathComponent(name))
                }
            }
        }
    }
}

private struct SnapshotPinger: ReachabilityPinging {
    func ping() async -> PingOutcome { .ok }
}
