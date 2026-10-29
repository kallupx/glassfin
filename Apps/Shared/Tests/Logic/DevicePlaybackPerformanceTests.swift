import AVFoundation
import GlassfinCore
import UIKit
import XCTest

/// Real AVPlayer/loader/decoder, in-memory API and media origin. No network is used.
@MainActor
final class DevicePlaybackPerformanceTests: XCTestCase {
    func testP5_nativeFirstFrameFromMockOrigin() throws {
        let bytes = try fixture()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(
            metrics: [
                XCTClockMetric(), XCTMemoryMetric(), XCTCPUMetric(),
                XCTOSSignpostMetric(
                    subsystem: "org.glassfin.app", category: "DevicePerformance", name: "playback.firstFrame"),
            ], options: options
        ) {
            runCycle(bytes)
        }
    }

    func testP12_P13_tenNativePlayStopCyclesFromMockOrigin() throws {
        let bytes = try fixture()
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric(), XCTCPUMetric()], options: options) {
            for _ in 0..<10 { runCycle(bytes) }
        }
    }

    private func fixture() throws -> Data {
        guard let url = Bundle(for: Self.self).url(forResource: "PerfFixture", withExtension: "mp4") else {
            throw XCTSkip("Run scripts/prepare-perf-fixture.sh before xcodegen generate; see DEVICE-MEASUREMENT.md")
        }
        let bytes = try Data(contentsOf: url)
        XCTAssertFalse(bytes.isEmpty)
        return bytes
    }

    private func runCycle(_ bytes: Data) {
        let frame = expectation(description: "Native first video frame ready for display")
        let stopped = expectation(description: "Native player stopped")
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            XCTFail("The hosted app must have a window scene for native frame presentation")
            return
        }
        let run = NativePerformanceRun(bytes: bytes, frame: frame, scene: scene)
        run.start()
        XCTAssertEqual(XCTWaiter.wait(for: [frame], timeout: 15), .completed)
        Task {
            await run.stop()
            stopped.fulfill()
        }
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 5), .completed)
        XCTAssertNil(run.engine.player)
    }
}

@MainActor
private final class NativePerformanceRun {
    let engine: AVPlayerEngine
    private let playback: PlaybackCoordinator
    private let layer = AVPlayerLayer()
    private let window: UIWindow
    private weak var previousWindow: UIWindow?
    private var observation: NSKeyValueObservation?
    private var frame: XCTestExpectation?
    private var task: Task<Void, Never>?

    init(bytes: Data, frame: XCTestExpectation, scene: UIWindowScene) {
        self.frame = frame
        let origin = PerformanceMediaOrigin(bytes: bytes)
        engine = AVPlayerEngine(origin: origin)
        let client = MockAPIClient { _ throws(APIError) in
            Data(
                """
                {"PlaySessionId":"performance","MediaSources":[{
                "Id":"22222222222222222222222222222222","Container":"mp4",
                "SupportsDirectPlay":true,"MediaStreams":[{"Type":"Video","Codec":"h264"}]}],
                "MediaStreams":[{"Type":"Video","Codec":"h264"}]}
                """.utf8)
        }
        let session = MockPlaybackSession(
            serverURL: URL(string: "https://performance.invalid")!,
            userID: "11111111111111111111111111111111",
            identity: ClientIdentity(deviceName: "Fixture", deviceID: "fixture", version: "1"), apiClient: client)
        playback = PlaybackCoordinator(session: session, engine: engine, origin: origin)
        previousWindow = scene.windows.first(where: \.isKeyWindow)
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1280, height: 720)
        let controller = UIViewController()
        window.rootViewController = controller
        layer.frame = window.bounds
        controller.view.layer.addSublayer(layer)
        window.makeKeyAndVisible()
        observation = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, change in
            guard change.newValue == true else { return }
            Task { @MainActor [weak self] in
                guard let self, let frame = self.frame else { return }
                self.frame = nil
                self.playback.noteFirstFrameReady()
                frame.fulfill()
            }
        }
    }

    func start() {
        task = Task {
            await playback.play(itemID: "33333333333333333333333333333333", choice: .startOver)
            layer.player = engine.player
        }
    }

    func stop() async {
        task?.cancel()
        await playback.stop()
        observation = nil
        layer.player = nil
        window.isHidden = true
        window.rootViewController = nil
        previousWindow?.makeKeyAndVisible()
    }
}

private struct PerformanceMediaOrigin: MediaOriginClient {
    let bytes: Data

    func fetch(_ request: OriginMediaRequest) async throws(APIError) -> OriginMediaResponse {
        let start = Int(min(Int64(bytes.count), max(0, request.range?.start ?? 0)))
        let end = Int(min(Int64(bytes.count), (request.range?.end ?? Int64(bytes.count - 1)) + 1))
        return OriginMediaResponse(
            status: request.range == nil ? 200 : 206, contentType: "video/mp4",
            body: request.method == "HEAD" ? Data() : bytes.subdata(in: start..<max(start, end)),
            totalLength: Int64(bytes.count))
    }
}
