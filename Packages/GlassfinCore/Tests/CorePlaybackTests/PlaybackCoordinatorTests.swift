#if DEBUG
    import CoreModels
    import CoreNetworking
    import CorePlayback
    import CoreTestSupport
    import Foundation
    import XCTest

    @MainActor
    final class PlaybackCoordinatorTests: XCTestCase {
        private struct Rig {
            let coordinator: PlaybackCoordinator
            let session: MockPlaybackSession
            let engine: MockPlaybackEngine
            let timer: ManualPlaybackTimer
            let client: MockAPIClient
            let origin: MockPlaybackOrigin
        }

        private func rig(
            data: Data? = nil, originResponse: OriginMediaResponse = OriginMediaResponse(status: 200),
            handler: (@Sendable (APIRequest) async throws(APIError) -> Data)? = nil,
            log: any GlassfinLog = SilentLog()
        ) throws -> Rig {
            let fixture = try data ?? playbackFixture()
            let client: MockAPIClient
            if let handler {
                client = MockAPIClient(handler: handler)
            } else {
                client = MockAPIClient { request throws(APIError) in
                    if request.path.hasSuffix("/PlaybackInfo") { return fixture }
                    if request.path.contains("/Items/") {
                        return Data(#"{"UserData":{"PlaybackPositionTicks":125000000}}"#.utf8)
                    }
                    return Data()
                }
            }
            let session = MockPlaybackSession(
                serverURL: try XCTUnwrap(URL(string: "https://server.example/jellyfin")),
                userID: pocUserID,
                identity: ClientIdentity(deviceName: "TV", deviceID: "device", version: "1", token: "secret"),
                apiClient: client)
            let engine = MockPlaybackEngine()
            let timer = ManualPlaybackTimer()
            let origin = MockPlaybackOrigin(response: originResponse)
            let coordinator = PlaybackCoordinator(
                session: session, engine: engine, origin: origin, timer: timer, log: log)
            return Rig(
                coordinator: coordinator, session: session, engine: engine, timer: timer, client: client, origin: origin
            )
        }

        private func settle(
            _ condition: @MainActor () async -> Bool, file: StaticString = #filePath, line: UInt = #line
        ) async {
            // Yielding lets the event stream and mock HTTP actor drain; no wall-clock sleeps.
            for _ in 0..<2_000 {
                if await condition() { return }
                await Task.yield()
            }
            XCTFail("Playback events did not settle", file: file, line: line)
        }

        private func started(_ rig: Rig, choice: PlaybackStartChoice = .startOver) async {
            await rig.coordinator.play(itemID: pocItemID, choice: choice)
            await settle { rig.coordinator.state == .playing && rig.timer.isRunning }
        }

        /// T08a-PoC-04: ordered start, periodic and immediate progress, stop; complete identity fields.
        func testT08a_PoC_04_reportingSequenceAndFields() async throws {
            let rig = try rig()
            await started(rig)
            rig.engine.position = .seconds(10)
            await rig.timer.fire()
            rig.engine.position = .seconds(20)
            await rig.timer.fire()
            rig.coordinator.pause()
            await settle {
                let calls = await rig.client.calls
                return rig.coordinator.state == .paused && calls.count >= 5
            }
            await rig.coordinator.seek(to: .seconds(30))
            await settle { (await rig.client.calls).count >= 6 }
            rig.coordinator.resume()
            await settle {
                let calls = await rig.client.calls
                return rig.coordinator.state == .playing && calls.count >= 7
            }
            await rig.coordinator.stop()
            let calls = await rig.client.calls
            XCTAssertEqual(
                calls.map(\.path),
                [
                    "/Items/\(pocItemID)/PlaybackInfo", "/Sessions/Playing",
                    "/Sessions/Playing/Progress", "/Sessions/Playing/Progress", "/Sessions/Playing/Progress",
                    "/Sessions/Playing/Progress", "/Sessions/Playing/Progress", "/Sessions/Playing/Stopped",
                ])
            let reports = try calls.dropFirst().map { try jsonBody($0.body) }
            XCTAssertEqual(
                reports.map { $0["PositionTicks"] as? Int64 },
                [0, 100_000_000, 200_000_000, 200_000_000, 300_000_000, 300_000_000, 300_000_000])
            XCTAssertEqual(reports.map { $0["IsPaused"] as? Bool }, [false, false, false, true, true, false, false])
            for report in reports {
                XCTAssertEqual(report["ItemId"] as? String, pocItemID)
                XCTAssertEqual(report["MediaSourceId"] as? String, pocSourceID)
                XCTAssertEqual(report["PlaySessionId"] as? String, "play-session")
                XCTAssertEqual(report["PlayMethod"] as? String, "DirectPlay")
                XCTAssertEqual(report["CanSeek"] as? Bool, true)
            }
            XCTAssertEqual(reports.last?["Failed"] as? Bool, false)
            XCTAssertFalse(rig.timer.isRunning)
            XCTAssertEqual(rig.coordinator.state, .idle)
            await rig.timer.fire()
            let afterStop = await rig.client.calls.count
            XCTAssertEqual(afterStop, calls.count)
        }

        /// T08a-PoC-05: resume from UserData, explicit ticks, negative clamp and start over.
        func testT08a_PoC_05_resumeAndStartOver() async throws {
            let rig = try rig()
            await started(rig, choice: .resume)
            XCTAssertEqual(rig.engine.loads.last?.start, .milliseconds(12_500))
            let firstCalls = await rig.client.calls
            XCTAssertEqual(firstCalls.first?.path, "/Users/\(pocUserID)/Items/\(pocItemID)")
            let request = try XCTUnwrap(firstCalls.first { $0.path.hasSuffix("PlaybackInfo") })
            XCTAssertEqual(try jsonBody(request.body)["StartTimeTicks"] as? Int64, 125_000_000)
            await started(rig, choice: .resumeAt(ticks: 999_999_999))
            XCTAssertEqual(Ticks.ticks(from: try XCTUnwrap(rig.engine.loads.last?.start)), 999_999_999)
            await started(rig, choice: .resumeAt(ticks: -100))
            XCTAssertEqual(rig.engine.loads.last?.start, .zero)
            await started(rig, choice: .startOver)
            XCTAssertEqual(rig.engine.loads.last?.start, .zero)
            rig.engine.position = .seconds(-42)
            await rig.timer.fire()
            await rig.coordinator.seek(to: .seconds(-2))
            await rig.coordinator.stop()
            for call in await rig.client.calls {
                guard call.body != nil else { continue }
                let body = try jsonBody(call.body)
                if let ticks = body["PositionTicks"] as? Int64 { XCTAssertGreaterThanOrEqual(ticks, 0) }
                if let ticks = body["StartTimeTicks"] as? Int64 { XCTAssertGreaterThanOrEqual(ticks, 0) }
            }
        }

        /// T08a-PoC-06: PlaybackInfo errors, malformed info and unsupported codecs never load the player.
        func testT08a_PoC_06_preparationErrorsFailBeforeEngineLoad() async throws {
            for error in [APIError.server(status: 500), .network, .tls, .timeout, .decoding] {
                let rig = try rig(handler: { _ throws(APIError) in throw error })
                await rig.coordinator.play(itemID: pocItemID, choice: .startOver)
                XCTAssertEqual(rig.coordinator.state, .failed(localizedKey: PlaybackCopy.couldNotPlayKey))
                XCTAssertTrue(rig.engine.loads.isEmpty)
                XCTAssertEqual(rig.session.expirationCount, 0)
                let calls = await rig.client.calls
                XCTAssertEqual(calls.count, 1)
            }
            for data in [
                try playbackFixture(video: "vp9"), try playbackFixture(direct: false),
                Data(#"{"MediaSources":[],"ErrorCode":"NotAllowed"}"#.utf8),
            ] {
                let rig = try rig(data: data)
                await rig.coordinator.play(itemID: pocItemID, choice: .startOver)
                XCTAssertTrue(rig.engine.loads.isEmpty)
                XCTAssertEqual(rig.session.expirationCount, 0)
                if data != Data(#"{"MediaSources":[],"ErrorCode":"NotAllowed"}"#.utf8) {
                    XCTAssertEqual(rig.coordinator.state, .failed(localizedKey: PlaybackCopy.unsupportedVideoKey))
                }
            }
        }

        /// T08a-PoC-06: absolute cross-origin and downgrade URLs are refused before any fetch.
        func testT08a_PoC_06_crossOriginHLSIsRejected() async throws {
            for url in ["https://evil.example/master.m3u8?ApiKey=secret", "http://server.example/master.m3u8"] {
                let rig = try rig(data: playbackFixture(container: "mkv", direct: false, transcodingURL: url))
                await rig.coordinator.play(itemID: pocItemID, choice: .startOver)
                XCTAssertEqual(rig.coordinator.failure, .insecureRedirect)
                XCTAssertEqual(rig.coordinator.state, .failed(localizedKey: PlaybackCopy.insecureRedirectKey))
                XCTAssertTrue(rig.engine.loads.isEmpty)
                let requests = await rig.origin.requests
                XCTAssertTrue(requests.isEmpty)
            }
        }

        /// T08a-PoC-07: duplicate media 401s stop once, probe once, never retry PlaybackInfo.
        func testT08a_PoC_07_mediaUnauthorizedChecksMeExactlyOnce() async throws {
            for meError in [APIError.unauthorized, .network, .server(status: 500), .forbidden] {
                try await checkMediaUnauthorized(meError: meError)
            }
            try await checkMediaUnauthorized(meError: nil)
        }

        private func checkMediaUnauthorized(meError: APIError?) async throws {
            let data = try playbackFixture()
            let rig = try rig(handler: { request throws(APIError) in
                if request.path.hasSuffix("PlaybackInfo") { return data }
                if request.path == "/Users/Me", let meError { throw meError }
                return Data()
            })
            await started(rig)
            rig.engine.emit(.failed(.unauthorized))
            rig.engine.emit(.failed(.unauthorized))
            await settle { (await rig.client.calls).contains { $0.path == "/Users/Me" } }
            if meError == .unauthorized {
                await settle { rig.session.expirationCount == 1 }
                XCTAssertEqual(rig.coordinator.state, .sessionExpired)
            } else {
                await settle { rig.coordinator.failure == .couldNotPlay }
                XCTAssertEqual(rig.coordinator.state, .failed(localizedKey: PlaybackCopy.couldNotPlayKey))
                XCTAssertEqual(rig.session.expirationCount, 0)
            }
            let calls = await rig.client.calls
            XCTAssertEqual(
                calls.map(\.path),
                [
                    "/Items/\(pocItemID)/PlaybackInfo", "/Sessions/Playing", "/Sessions/Playing/Stopped", "/Users/Me",
                ])
            XCTAssertEqual(try jsonBody(calls[2].body)["Failed"] as? Bool, true)
            XCTAssertFalse(rig.timer.isRunning)
            XCTAssertEqual(rig.engine.loads.count, 1)
        }

        /// T08a-PoC-07: authenticated PlaybackInfo 401 maps directly to S2.2, never a retry loop.
        func testT08a_PoC_07_playbackInfo401ExpiresSession() async throws {
            let rig = try rig(handler: { _ throws(APIError) in throw .unauthorized })
            await rig.coordinator.play(itemID: pocItemID, choice: .startOver)
            XCTAssertEqual(rig.coordinator.state, .sessionExpired)
            XCTAssertEqual(rig.session.expirationCount, 1)
            let count = await rig.client.calls.count
            XCTAssertEqual(count, 1)
            XCTAssertTrue(rig.engine.loads.isEmpty)
        }

        /// T08a-PoC-07/12: repeated dismissal cannot cancel the pending auth check after a media 401.
        func testT08a_PoC_07_dismissalDuringStoppedStillChecksSession() async throws {
            let fixture = try playbackFixture()
            let gate = PoCRequestGate()
            let rig = try rig(handler: { request throws(APIError) in
                if request.path.hasSuffix("PlaybackInfo") { return fixture }
                if request.path.hasSuffix("Stopped") { await gate.wait() }
                if request.path == "/Users/Me" { throw .unauthorized }
                return Data()
            })
            await started(rig)
            rig.engine.emit(.failed(.unauthorized))
            await settle { await gate.isWaiting }
            await rig.coordinator.stop()
            await rig.coordinator.stop()
            await gate.release()
            await settle { rig.session.expirationCount == 1 }
            XCTAssertEqual(rig.coordinator.state, .sessionExpired)
            let paths = await rig.client.calls.map(\.path)
            XCTAssertEqual(
                paths,
                [
                    "/Items/\(pocItemID)/PlaybackInfo", "/Sessions/Playing", "/Sessions/Playing/Stopped", "/Users/Me",
                ])
        }

        /// T08a-PoC-13: terminal events send Stopped once, with Failed true only for an error.
        func testT08a_PoC_13_endAndErrorReportStoppedExactlyOnce() async throws {
            for event in [PlaybackEngineEvent.ended, .failed(.network)] {
                let rig = try rig()
                await started(rig)
                rig.engine.position = .seconds(3)
                rig.engine.emit(event)
                await settle { (await rig.client.calls).last?.path == "/Sessions/Playing/Stopped" }
                let calls = await rig.client.calls
                XCTAssertEqual(try jsonBody(calls.last?.body)["Failed"] as? Bool, event != .ended)
                XCTAssertEqual(try jsonBody(calls.last?.body)["PositionTicks"] as? Int64, 30_000_000)
                await rig.coordinator.stop()
                let after = await rig.client.calls.count
                XCTAssertEqual(after, calls.count)
            }
        }

        /// T08a-PoC-04/08: one transient retry, logging redacted, playback survives reporting outages.
        func testT08a_PoC_04_reportingRetriesOnceAndContinuesPlayback() async throws {
            let fixture = try playbackFixture()
            let sink = PoCLogCapture()
            let rig = try rig(
                handler: { request throws(APIError) in
                    if request.path.hasSuffix("PlaybackInfo") { return fixture }
                    throw .network
                }, log: sink)
            await started(rig)
            await rig.timer.fire()
            XCTAssertEqual(rig.coordinator.state, .playing)
            await rig.coordinator.stop()
            let calls = await rig.client.calls
            XCTAssertEqual(
                calls.map(\.path),
                [
                    "/Items/\(pocItemID)/PlaybackInfo", "/Sessions/Playing", "/Sessions/Playing",
                    "/Sessions/Playing/Progress", "/Sessions/Playing/Progress",
                    "/Sessions/Playing/Stopped", "/Sessions/Playing/Stopped",
                ])
            XCTAssertEqual(sink.messages.filter { $0.hasPrefix("Playback report failed:") }.count, 6)
        }

        /// T08a-PoC-03/09: HLS remux and audio conversion stay video copy through the loader.
        func testT08a_PoC_03_hlsLoadsWithVideoCopyAndReportsDirectStream() async throws {
            for audio in ["aac", "dts"] {
                let rig = try rig(
                    data: playbackFixture(
                        container: "mkv", audio: audio, direct: false,
                        transcodingURL: "/Videos/abc/master.m3u8?ApiKey=secret&VideoCodec=h264"))
                await started(rig)
                let carrier = try XCTUnwrap(rig.engine.loads.first?.carrier)
                XCTAssertEqual(carrier.segmentPolicy, .leaveServerURLs)
                XCTAssertEqual(carrier.assetURL.scheme, "glassfin-media")
                XCTAssertFalse(MediaCredentialQuery.contains(carrier.originURL))
                let requests = await rig.origin.requests
                XCTAssertEqual(requests.first?.method, "GET")
                XCTAssertEqual(requests.first?.authorizationHeader, try rig.session.identity.authorizationHeader())
                let calls = await rig.client.calls
                XCTAssertEqual(try jsonBody(calls.last?.body)["PlayMethod"] as? String, "DirectStream")
                await rig.coordinator.stop()
            }
        }

        /// T08a-PoC-06: resolver failures and pinned HLS terminate before engine load.
        func testT08a_PoC_06_resolverAndTrustRejections() async throws {
            for response in [
                OriginMediaResponse(status: 500),
                OriginMediaResponse(status: 302, location: URL(string: "https://evil.example/media")),
            ] {
                let rig = try rig(originResponse: response)
                await rig.coordinator.play(itemID: pocItemID, choice: .startOver)
                XCTAssertTrue(rig.engine.loads.isEmpty)
                XCTAssertEqual(rig.session.expirationCount, 0)
            }
            let rig = try rig(data: playbackFixture(container: "mkv", direct: false, transcodingURL: "/master.m3u8"))
            rig.session.trust = .pinnedSelfSigned(fingerprintSHA256: String(repeating: "a", count: 64))
            await rig.coordinator.play(itemID: pocItemID, choice: .startOver)
            XCTAssertTrue(rig.engine.loads.isEmpty)
            XCTAssertEqual(rig.coordinator.state, .failed(localizedKey: PlaybackCopy.couldNotPlayKey))
        }

        /// T08a-PoC-08: captured report/player diagnostics redact all credential spellings.
        func testT08a_PoC_08_playerAndReportingLogRedaction() {
            let sink = PoCLogCapture()
            let log = PlaybackLog(sink: sink)
            let secrets = [
                "query-secret", "legacy-secret", "token-secret", "header-secret", "quoted-secret", "two words",
            ]
            let diagnostics =
                "https://server/media?ApiKey=query-secret&" + "api" + "_key=legacy-secret&token=token-secret"
            log.error("Playback report failed \(diagnostics)\nAuthorization: header-secret\nToken=\"quoted-secret\"")
            PlayerLogSink.record([diagnostics, "Authorization: header-secret", "Token=\"quoted-secret\""], log: log)
            log.error("token=\"two words\"")
            XCTAssertEqual(sink.messages.count, 5)
            for message in sink.messages {
                for secret in secrets { XCTAssertFalse(message.contains(secret)) }
                XCTAssertTrue(message.contains("<redacted>"))
            }
        }

        /// T08a-PoC-11: the production scheduler requests 10 seconds on the injected clock.
        func testT08a_PoC_11_progressTimerUsesClockAndCancels() async {
            let clock = PoCClock()
            let timer = PlaybackProgressTimer(clock: clock)
            var ticks = 0
            timer.start { ticks += 1 }
            await settle { await clock.pendingCount == 1 }
            let requested = await clock.requested
            XCTAssertEqual(requested, [.seconds(10)])
            await clock.advance()
            await settle { ticks == 1 }
            await settle { await clock.pendingCount == 1 }
            timer.cancel()
            await settle { await clock.pendingCount == 0 }
            XCTAssertEqual(ticks, 1)
        }

        /// T08a-PoC-12: stopping an in-flight PlaybackInfo prevents stale engine creation.
        func testT08a_PoC_12_stopDuringStartupDiscardsLateResponse() async throws {
            let gate = PoCRequestGate()
            let fixture = try playbackFixture()
            let rig = try rig(handler: { _ in
                await gate.wait()
                return fixture
            })
            let load = Task { await rig.coordinator.play(itemID: pocItemID, choice: .startOver) }
            await settle { await gate.isWaiting }
            await rig.coordinator.stop()
            await gate.release()
            await load.value
            XCTAssertEqual(rig.coordinator.state, .idle)
            XCTAssertTrue(rig.engine.loads.isEmpty)
            let requests = await rig.origin.requests
            XCTAssertTrue(requests.isEmpty)
        }

        /// T08a-PoC-12: cancellation also leaves loading when the caller cancels its play task.
        func testT08a_PoC_12_cancelledPlayLeavesIdle() async throws {
            let gate = PoCRequestGate()
            let fixture = try playbackFixture()
            let rig = try rig(handler: { _ in
                await gate.wait()
                return fixture
            })
            let load = Task { await rig.coordinator.play(itemID: pocItemID, choice: .startOver) }
            await settle { await gate.isWaiting }
            load.cancel()
            await gate.release()
            await load.value
            XCTAssertEqual(rig.coordinator.state, .idle)
            XCTAssertTrue(rig.engine.loads.isEmpty)
        }

        /// T08a-PoC-04: recovery after one retry, and permanent reporting errors are not retried.
        func testT08a_PoC_04_transientRetryCanRecover() async throws {
            let fixture = try playbackFixture()
            for error in [APIError.network, .timeout, .server(status: 503), .forbidden] {
                let attempts = PoCReportAttempts()
                let rig = try rig(handler: { request throws(APIError) in
                    if request.path.hasSuffix("PlaybackInfo") { return fixture }
                    let attempt = await attempts.next(request.path)
                    if attempt == 1 { throw error }
                    return Data()
                })
                await started(rig)
                await rig.timer.fire()
                await rig.coordinator.stop()
                let calls = await rig.client.calls
                let count = error == .forbidden ? 1 : 2
                XCTAssertEqual(calls.filter { $0.path == "/Sessions/Playing" }.count, count)
                XCTAssertEqual(calls.filter { $0.path == "/Sessions/Playing/Progress" }.count, count)
                XCTAssertEqual(calls.filter { $0.path == "/Sessions/Playing/Stopped" }.count, count)
                XCTAssertEqual(rig.session.expirationCount, 0)
            }
        }

        /// T08a-PoC-07: media-probe and engine-load 401s share the single session check.
        func testT08a_PoC_07_startupMedia401AndReport401() async throws {
            let fixture = try playbackFixture()
            for origin401 in [true, false] {
                let rig = try rig(
                    originResponse: OriginMediaResponse(status: origin401 ? 401 : 200),
                    handler: { request throws(APIError) in
                        if request.path.hasSuffix("PlaybackInfo") { return fixture }
                        if request.path == "/Users/Me" { return Data() }
                        throw .unauthorized
                    })
                if !origin401 { rig.engine.loadError = .unauthorized }
                await rig.coordinator.play(itemID: pocItemID, choice: .startOver)
                XCTAssertEqual(rig.coordinator.state, .failed(localizedKey: PlaybackCopy.couldNotPlayKey))
                let paths = await rig.client.calls.map(\.path)
                XCTAssertEqual(
                    paths,
                    [
                        "/Items/\(pocItemID)/PlaybackInfo", "/Sessions/Playing/Stopped", "/Users/Me",
                    ])
                XCTAssertEqual(rig.session.expirationCount, 0)
            }
            let rig = try rig(handler: { request throws(APIError) in
                if request.path.hasSuffix("PlaybackInfo") { return fixture }
                if request.path == "/Users/Me" { return Data() }
                throw .unauthorized
            })
            await rig.coordinator.play(itemID: pocItemID, choice: .startOver)
            await settle { (await rig.client.calls).last?.path == "/Users/Me" }
            let paths = await rig.client.calls.map(\.path)
            XCTAssertEqual(
                paths,
                [
                    "/Items/\(pocItemID)/PlaybackInfo", "/Sessions/Playing", "/Sessions/Playing/Stopped", "/Users/Me",
                ])
        }

        /// T08a-PoC-15: buffering, duplicate ready, repeated play and a negative resume warning.
        func testT08a_PoC_15_engineStatesAndRepeatedPlay() async throws {
            let sink = PoCLogCapture()
            let rig = try rig(log: sink)
            XCTAssertEqual(rig.coordinator.state, .idle)
            await started(rig, choice: .resumeAt(ticks: -1))
            rig.engine.emit(.ready)
            rig.engine.emit(.buffering)
            await settle { rig.coordinator.state == .buffering }
            rig.engine.emit(.playing)
            await settle { rig.coordinator.state == .playing }
            await started(rig, choice: .startOver)
            await rig.coordinator.stop()
            let paths = await rig.client.calls.map(\.path)
            XCTAssertEqual(paths.filter { $0 == "/Sessions/Playing" }.count, 2)
            XCTAssertEqual(paths.filter { $0 == "/Sessions/Playing/Stopped" }.count, 2)
            XCTAssertEqual(
                sink.messages.filter { $0.contains("PlaybackPositionTicks") && $0.contains(pocItemID) }.count, 1)
        }
    }

    private actor PoCRequestGate {
        private var continuation: CheckedContinuation<Void, Never>?
        var isWaiting: Bool { continuation != nil }
        func wait() async { await withCheckedContinuation { continuation = $0 } }
        func release() {
            continuation?.resume()
            continuation = nil
        }
    }

    private actor PoCReportAttempts {
        private var counts: [String: Int] = [:]
        func next(_ path: String) -> Int {
            counts[path, default: 0] += 1
            return counts[path, default: 0]
        }
    }

    private actor PoCClock: GlassfinClock {
        private var continuation: CheckedContinuation<Void, any Error>?
        private(set) var requested: [Duration] = []
        var pendingCount: Int { continuation == nil ? 0 : 1 }
        nonisolated func now() -> Duration { .zero }
        func sleep(for duration: Duration) async throws {
            requested.append(duration)
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await withCheckedThrowingContinuation { continuation = $0 }
            } onCancel: {
                Task { await self.cancel() }
            }
        }
        func advance() {
            continuation?.resume()
            continuation = nil
        }
        private func cancel() {
            continuation?.resume(throwing: CancellationError())
            continuation = nil
        }
    }

    private final class PoCLogCapture: GlassfinLog, @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String] = []
        var messages: [String] { lock.withLock { entries } }
        func warning(_ message: String) { record(message) }
        func debug(_ message: String) { record(message) }
        func error(_ message: String) { record(message) }
        private func record(_ message: String) { lock.withLock { entries.append(message) } }
    }
#endif
