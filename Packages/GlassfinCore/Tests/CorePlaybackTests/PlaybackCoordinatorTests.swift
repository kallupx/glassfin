import CoreModels
import CoreNetworking
import CorePlayback
import Foundation
import XCTest

@MainActor
final class PlaybackCoordinatorTests: XCTestCase {
    private struct Rig {
        let coordinator: PlaybackCoordinator
        let session: MockPlaybackSession
        let engine: MockPlaybackEngine
        let timer: ManualPlaybackTimer
        let client: PoCAPIClient
        let origin: MockPlaybackOrigin
    }

    private func rig(
        data: Data? = nil, itemData: Data? = nil,
        originResponse: OriginMediaResponse = OriginMediaResponse(status: 200),
        handler: (@Sendable (APIRequest) async throws(APIError) -> Data)? = nil,
        log: any GlassfinLog = SilentLog()
    ) throws -> Rig {
        let fixture = try data ?? playbackFixture()
        let itemFixture = try itemData ?? playbackItemFixture(from: fixture)
        let client = PoCAPIClient { request throws(APIError) in
            if request.method == "GET", request.path.contains("/Items/") { return itemFixture }
            if let handler { return try await handler(request) }
            if request.path.hasSuffix("/PlaybackInfo") { return fixture }
            return Data()
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

    /// T08P-13/14, TPOC-18 (model): unsupported metadata causes zero negotiation or stream requests.
    func testT08P_13_14_unsupportedPreflightMakesZeroPlaybackRequests() async throws {
        for codec in ["mpeg2video", "vc1"] {
            let rig = try rig(itemData: playbackItemFixture(from: playbackFixture(video: codec)))
            await rig.coordinator.play(itemID: pocItemID, choice: .startOver)
            XCTAssertEqual(rig.coordinator.state, .failed(localizedKey: PlaybackCopy.unsupportedVideoKey))
            let calls = await rig.client.calls
            XCTAssertEqual(calls.count, 1)
            XCTAssertEqual(calls.first?.method, "GET")
            XCTAssertFalse(calls.contains { $0.path.hasSuffix("PlaybackInfo") || $0.path.hasPrefix("/Sessions/") })
            let originRequests = await rig.origin.requests
            XCTAssertTrue(originRequests.isEmpty)
            XCTAssertTrue(rig.engine.loads.isEmpty)
            XCTAssertFalse(rig.timer.isRunning)
        }
    }

    func testT08P_89_queryVideoReasonsBlockBeforeStreamRequest() async throws {
        let metadata = try playbackItemFixture(from: playbackFixture())
        let rig = try rig(
            data: playbackFixture(
                container: "mkv", direct: false,
                transcodingURL: "/master.m3u8?TranscodeReasons=AudioCodecNotSupported%2CRefFramesNotSupported"),
            itemData: metadata)
        await rig.coordinator.play(itemID: pocItemID, choice: .startOver)
        XCTAssertEqual(rig.coordinator.failure, .unsupportedVideo)
        XCTAssertTrue(rig.engine.loads.isEmpty)
        let requests = await rig.origin.requests
        XCTAssertTrue(requests.isEmpty)
        let calls = await rig.client.calls
        XCTAssertEqual(calls.filter { $0.path.hasSuffix("PlaybackInfo") }.count, 1)
        XCTAssertFalse(calls.contains { $0.path == "/Sessions/Playing" })
    }

    /// T08P-03: the second source must never replace the selected first source.
    func testT08P_03_firstMediaSourceUsedInURLAndReports() async throws {
        var fixture = try jsonBody(playbackFixture())
        var sources = try XCTUnwrap(fixture["MediaSources"] as? [[String: Any]])
        var second = sources[0]
        second["Id"] = pocItemID
        sources.append(second)
        fixture["MediaSources"] = sources
        let rig = try rig(data: JSONSerialization.data(withJSONObject: fixture))
        await started(rig)
        let url = try XCTUnwrap(rig.engine.loads.first?.carrier.originURL)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first { $0.name == "mediaSourceId" }?.value, pocSourceID)
        await rig.coordinator.stop()
        for call in await rig.client.calls where call.path.hasPrefix("/Sessions/") {
            XCTAssertEqual(try jsonBody(call.body)["MediaSourceId"] as? String, pocSourceID)
        }
    }

    /// T08P-55: pinned DirectPlay keeps the trust policy and header through the loader.
    func testT08P_55_pinnedDirectPlayUsesLoader() async throws {
        let rig = try rig()
        let trust = ServerTrustClass.pinnedSelfSigned(fingerprintSHA256: String(repeating: "a", count: 64))
        rig.session.trust = trust
        await started(rig)
        let carrier = try XCTUnwrap(rig.engine.loads.first?.carrier)
        XCTAssertEqual(carrier.trust, trust)
        XCTAssertEqual(carrier.authorizationHeader, try rig.session.identity.authorizationHeader())
        XCTAssertEqual(carrier.assetURL.scheme, "glassfin-media")
        await rig.coordinator.stop()
    }

    /// T08P-71, TPOC-68 (policy): force loader failure; never load a query/header fallback.
    func testT08P_71_loaderFailureNeverUsesCredentialFallback() async throws {
        let rig = try retryRig()
        rig.engine.loadError = .network
        await rig.coordinator.play(itemID: pocItemID, choice: .startOver)
        XCTAssertEqual(rig.coordinator.failure, .couldNotPlay)
        XCTAssertTrue(rig.engine.loads.isEmpty)
        let calls = await rig.client.calls
        XCTAssertEqual(calls.filter { $0.path.hasSuffix("PlaybackInfo") }.count, 2)
        let requests = await rig.origin.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertFalse(requests.contains { MediaCredentialQuery.contains($0.url) })
        if !HeaderFieldsKeyPolicy.isAllowedInCurrentBuild {
            let server = try XCTUnwrap(URL(string: "https://server.example"))
            XCTAssertNil(MediaURLBuilder.queryCredentialFallback(strippedURL: server, token: "secret"))
            let options = MediaOpenOptions(
                trust: .publiclyTrusted, headerFieldsKeyAvailable: true,
                apiKeyFallbackURL: try XCTUnwrap(URL(string: "https://server.example/stream?ApiKey=server-secret")))
            XCTAssertFalse(options.headerFieldsKeyAvailable)
            let plan = MediaOpenPlanner.plan(
                delivery: .directFile, resolvedURL: server,
                authorizationHeader: "test-header", options: options)
            XCTAssertTrue(plan.measuredFallbacks.isEmpty)
        }
    }

    /// T08P-15, TPOC-18 (model only): an unsupported error must not poison the next start.
    func testT08P_15_supportedPlaybackAfterUnsupportedError() async throws {
        let rig = try rig(itemData: playbackItemFixture(from: playbackFixture(video: "mpeg2video")))
        await rig.coordinator.play(itemID: pocItemID, choice: .startOver)
        XCTAssertEqual(rig.coordinator.failure, .unsupportedVideo)
        let supported = try playbackFixture()
        let metadata = try playbackItemFixture(from: supported)
        await rig.client.setHandler { request throws(APIError) in
            if request.method == "GET" { return metadata }
            if request.path.hasSuffix("PlaybackInfo") { return supported }
            return Data()
        }
        await started(rig)
        XCTAssertNil(rig.coordinator.failure)
        XCTAssertEqual(rig.engine.loads.count, 1)
        await rig.coordinator.stop()
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

    /// T08P-25/T08P-27/T08P-29: ordered start, periodic and immediate progress, stop; complete identity fields.
    func testT08P_25_27_29_reportingSequenceAndFields() async throws {
        let rig = try rig()
        await started(rig)
        rig.engine.position = .seconds(10)
        await rig.timer.fire()
        rig.engine.position = .seconds(20)
        await rig.timer.fire()
        rig.coordinator.pause()
        await settle {
            let calls = await rig.client.calls
            return rig.coordinator.state == .paused && calls.count >= 6
        }
        await rig.coordinator.seek(to: .seconds(30))
        await settle { (await rig.client.calls).count >= 7 }
        rig.coordinator.resume()
        await settle {
            let calls = await rig.client.calls
            return rig.coordinator.state == .playing && calls.count >= 8
        }
        await rig.coordinator.stop()
        let calls = await rig.client.calls
        XCTAssertEqual(
            calls.filter { $0.method != "GET" || $0.path == "/Users/Me" }.map(\.path),
            [
                "/Items/\(pocItemID)/PlaybackInfo", "/Sessions/Playing",
                "/Sessions/Playing/Progress", "/Sessions/Playing/Progress", "/Sessions/Playing/Progress",
                "/Sessions/Playing/Progress", "/Sessions/Playing/Progress", "/Sessions/Playing/Stopped",
            ])
        let reports = try calls.filter { $0.path.hasPrefix("/Sessions/") }.map { try jsonBody($0.body) }
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

    /// T08P-36/T08P-37: resume from UserData, explicit ticks, negative clamp and start over.
    func testT08P_36_37_resumeAndStartOver() async throws {
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

    /// T08P-04/T08P-47: PlaybackInfo errors, malformed info and unsupported codecs never load the player.
    func testT08P_04_47_preparationErrorsFailBeforeEngineLoad() async throws {
        for error in [APIError.server(status: 500), .network, .tls, .timeout, .decoding] {
            let rig = try rig(handler: { _ throws(APIError) in throw error })
            await rig.coordinator.play(itemID: pocItemID, choice: .startOver)
            XCTAssertEqual(rig.coordinator.state, .failed(localizedKey: PlaybackCopy.couldNotPlayKey))
            XCTAssertTrue(rig.engine.loads.isEmpty)
            XCTAssertEqual(rig.session.expirationCount, 0)
            let calls = await rig.client.calls
            XCTAssertEqual(calls.count, 2)
        }
        let metadata = try playbackItemFixture(from: playbackFixture())
        for body in [
            #"{"MediaSources":[],"ErrorCode":"NotAllowed"}"#,
            #"{"MediaSources":[],"ErrorCode":"NoCompatibleStream"}"#,
            #"{"MediaSources":[],"ErrorCode":"RateLimitExceeded"}"#,
            #"{"MediaSources":[]}"#,
        ] {
            let rig = try rig(data: Data(body.utf8), itemData: metadata)
            await rig.coordinator.play(itemID: pocItemID, choice: .startOver)
            XCTAssertEqual(rig.coordinator.state, .failed(localizedKey: PlaybackCopy.couldNotPlayKey))
            XCTAssertTrue(rig.engine.loads.isEmpty)
            XCTAssertEqual(rig.session.expirationCount, 0)
            let calls = await rig.client.calls
            XCTAssertEqual(calls.filter { $0.path.hasSuffix("PlaybackInfo") }.count, 1)
            XCTAssertFalse(calls.contains { $0.path == "/Sessions/Playing" })
        }
    }

    /// T08P-54: absolute cross-origin and downgrade URLs are refused before any fetch.
    func testT08P_54_crossOriginHLSIsRejected() async throws {
        for url in ["https://evil.example/master.m3u8?ApiKey=secret", "http://server.example/master.m3u8"] {
            let rig = try rig(data: playbackFixture(container: "mkv", direct: false, transcodingURL: url))
            await rig.coordinator.play(itemID: pocItemID, choice: .startOver)
            XCTAssertEqual(rig.coordinator.failure, .insecureRedirect)
            XCTAssertEqual(rig.coordinator.state, .failed(localizedKey: PlaybackCopy.couldNotPlayKey))
            XCTAssertTrue(rig.engine.loads.isEmpty)
            let requests = await rig.origin.requests
            XCTAssertTrue(requests.isEmpty)
        }
    }

    /// T08P-42/T08P-43/T08P-45: duplicate media 401s stop once, probe once, never retry PlaybackInfo.
    func testT08P_42_43_45_mediaUnauthorizedChecksMeExactlyOnce() async throws {
        for remux in [false, true] {
            for meError in [APIError.unauthorized, .network, .server(status: 500), .forbidden] {
                try await checkMediaUnauthorized(meError: meError, remux: remux)
            }
            try await checkMediaUnauthorized(meError: nil, remux: remux)
        }
    }

    private func checkMediaUnauthorized(meError: APIError?, remux: Bool) async throws {
        let data = try playbackFixture(
            container: remux ? "mkv" : "mp4", direct: !remux,
            transcodingURL: remux ? "/master.m3u8" : nil)
        let rig = try rig(
            data: data,
            handler: { request throws(APIError) in
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
            calls.filter { $0.method != "GET" || $0.path == "/Users/Me" }.map(\.path),
            [
                "/Items/\(pocItemID)/PlaybackInfo", "/Sessions/Playing", "/Sessions/Playing/Stopped", "/Users/Me",
            ])
        XCTAssertEqual(try jsonBody(calls.first { $0.path.hasSuffix("/Stopped") }?.body)["Failed"] as? Bool, true)
        XCTAssertFalse(rig.timer.isRunning)
        XCTAssertEqual(rig.engine.loads.count, 1)
    }

    /// T08P-44: authenticated PlaybackInfo 401 maps directly to S2.2, never a retry loop.
    func testT08P_44_playbackInfo401ExpiresSession() async throws {
        let rig = try rig(handler: { _ throws(APIError) in throw .unauthorized })
        await rig.coordinator.play(itemID: pocItemID, choice: .startOver)
        XCTAssertEqual(rig.coordinator.state, .sessionExpired)
        XCTAssertEqual(rig.session.expirationCount, 1)
        let count = await rig.client.calls.count
        XCTAssertEqual(count, 2)
        XCTAssertTrue(rig.engine.loads.isEmpty)
    }

    /// T08P-43/T08P-56: repeated dismissal cannot cancel the pending auth check after a media 401.
    func testT08P_43_56_dismissalDuringStoppedStillChecksSession() async throws {
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
        let paths = await rig.client.calls.filter { $0.method != "GET" || $0.path == "/Users/Me" }.map(\.path)
        XCTAssertEqual(
            paths,
            [
                "/Items/\(pocItemID)/PlaybackInfo", "/Sessions/Playing", "/Sessions/Playing/Stopped", "/Users/Me",
            ])
    }

    /// T08P-23/T08P-31: terminal events send Stopped once, with Failed true only for an error.
    func testT08P_23_31_endAndErrorReportStoppedExactlyOnce() async throws {
        for event in [PlaybackEngineEvent.ended, .failed(.network)] {
            let rig = try rig(data: playbackFixture(container: "mkv", direct: false, transcodingURL: "/master.m3u8"))
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

    /// T08P-30/T08P-73: one transient retry, logging redacted, playback survives reporting outages.
    func testT08P_30_73_reportingRetriesOnceAndContinuesPlayback() async throws {
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
            calls.filter { $0.method != "GET" || $0.path == "/Users/Me" }.map(\.path),
            [
                "/Items/\(pocItemID)/PlaybackInfo", "/Sessions/Playing", "/Sessions/Playing",
                "/Sessions/Playing/Progress", "/Sessions/Playing/Progress",
                "/Sessions/Playing/Stopped", "/Sessions/Playing/Stopped",
            ])
        XCTAssertEqual(sink.messages.filter { $0.hasPrefix("Playback report failed:") }.count, 6)
    }

    /// T08P-08/T08P-10/T08P-70: HLS remux and audio conversion stay video copy through the loader.
    func testT08P_08_10_70_hlsLoadsWithVideoCopyAndReportsDirectStream() async throws {
        for (video, audio) in [("h264", "aac"), ("h264", "dts"), ("h264", "truehd"), ("hevc", "ac3")] {
            let rig = try rig(
                data: playbackFixture(
                    container: "mkv", video: video, audio: audio, direct: false,
                    transcodingURL:
                        "/Videos/abc/master.m3u8?ApiKey=secret&VideoCodec=h264&TranscodeReasons=ContainerNotSupported%2CAudioCodecNotSupported%2CSubtitleCodecNotSupported"
                ))
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

    /// T08P-54/T08P-87: resolver failures and pinned HLS terminate before engine load.
    func testT08P_54_87_resolverAndTrustRejections() async throws {
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
        XCTAssertEqual(rig.coordinator.state, .failed(localizedKey: PlaybackCopy.pinnedHLSKey))
        let pinnedRequests = await rig.origin.requests
        XCTAssertTrue(pinnedRequests.isEmpty)
    }

    /// T08P-73/T08P-74: captured report/player diagnostics redact all credential spellings.
    func testT08P_73_74_playerAndReportingLogRedaction() {
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

    /// T08P-26: the production scheduler requests 10 seconds on the injected clock.
    func testT08P_26_progressTimerUsesClockAndCancels() async {
        let clock = PoCClock()
        let timer = PlaybackProgressTimer(clock: clock)
        var ticks = 0
        timer.start { ticks += 1 }
        await settle { await clock.pendingCount == 1 }
        let requested = await clock.requested
        XCTAssertEqual(requested, [.seconds(10)])
        for expected in 1...6 {
            await clock.advance()
            await settle { ticks == expected }
            await settle { await clock.pendingCount == 1 }
        }
        let durations = await clock.requested
        XCTAssertEqual(durations, Array(repeating: .seconds(10), count: 7))
        timer.cancel()
        await settle { await clock.pendingCount == 0 }
        XCTAssertEqual(ticks, 6)
    }

    /// T08P-56: stopping an in-flight PlaybackInfo prevents stale engine creation.
    func testT08P_56_stopDuringStartupDiscardsLateResponse() async throws {
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

    /// T08P-56: cancellation also leaves loading when the caller cancels its play task.
    func testT08P_56_cancelledPlayLeavesIdle() async throws {
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

    /// T08P-30: recovery after one retry, and permanent reporting errors are not retried.
    func testT08P_30_transientRetryCanRecover() async throws {
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

    /// T08P-42/T08P-44: media-probe and engine-load 401s share the single session check.
    func testT08P_42_44_startupMedia401AndReport401() async throws {
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
            let paths = await rig.client.calls.filter { $0.method != "GET" || $0.path == "/Users/Me" }.map(\.path)
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
        let paths = await rig.client.calls.filter { $0.method != "GET" || $0.path == "/Users/Me" }.map(\.path)
        XCTAssertEqual(
            paths,
            [
                "/Items/\(pocItemID)/PlaybackInfo", "/Sessions/Playing", "/Sessions/Playing/Stopped", "/Users/Me",
            ])
    }

    /// T08P-19/T08P-56: buffering, duplicate ready, repeated play and a negative resume warning.
    func testT08P_19_56_engineStatesAndRepeatedPlay() async throws {
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
        let paths = await rig.client.calls.filter { $0.method != "GET" || $0.path == "/Users/Me" }.map(\.path)
        XCTAssertEqual(paths.filter { $0 == "/Sessions/Playing" }.count, 2)
        XCTAssertEqual(paths.filter { $0 == "/Sessions/Playing/Stopped" }.count, 2)
        XCTAssertEqual(
            sink.messages.filter { $0.contains("PlaybackPositionTicks") && $0.contains(pocItemID) }.count, 1)
    }
    private func retryRig(audio: String = "aac", retryData: Data? = nil) throws -> Rig {
        let first = try playbackFixture()
        let second =
            try retryData
            ?? playbackFixture(
                audio: audio, direct: true, transcodingURL: "/master.m3u8?TranscodeReasons=DirectPlayError",
                playSessionID: "remux-session")
        return try rig(handler: { request throws(APIError) in
            if request.path.hasSuffix("PlaybackInfo") {
                let direct = (try? jsonBody(request.body)["EnableDirectPlay"] as? Bool) ?? true
                return direct ? first : second
            }
            return Data()
        })
    }

    private func assertAttempts(_ rig: Rig, info: Int, streams: Int, file: StaticString = #filePath, line: UInt = #line)
        async
    {
        let calls = await rig.client.calls
        let requests = await rig.origin.requests
        let negotiations = calls.filter { $0.path.hasSuffix("PlaybackInfo") }
        XCTAssertEqual(negotiations.count, info, file: file, line: line)
        XCTAssertEqual(requests.count, streams, file: file, line: line)
        for (index, call) in negotiations.enumerated() {
            let body = try? jsonBody(call.body)
            XCTAssertEqual(body?["EnableDirectPlay"] as? Bool, index == 0, file: file, line: line)
            XCTAssertEqual(body?["AllowVideoStreamCopy"] as? Bool, true, file: file, line: line)
            XCTAssertEqual(body?["EnableTranscoding"] as? Bool, true, file: file, line: line)
        }
    }

    /// T08P-17: failed item/loader/timeout events share one video-copy retry, with optional audio conversion.
    func testT08P_17_directPlayFailureRetriesRemuxOnce() async throws {
        for error in [APIError.network, .timeout, .server(status: 500)] {
            for audio in ["aac", "dts"] {
                let rig = try retryRig(audio: audio)
                await started(rig, choice: .resume)
                rig.engine.position = .seconds(20)
                rig.engine.emit(.failed(error))
                rig.engine.emit(.failed(error))
                await settle { rig.engine.loads.count == 2 && rig.coordinator.state == .playing && rig.timer.isRunning }
                XCTAssertNil(rig.coordinator.failure)
                await assertAttempts(rig, info: 2, streams: 2)
                let carrier = try XCTUnwrap(rig.engine.loads.last?.carrier)
                let query = URLComponents(url: carrier.originURL, resolvingAgainstBaseURL: false)?.queryItems
                XCTAssertEqual(query?.first { $0.name == "VideoCodec" }?.value, "copy")
                XCTAssertEqual(query?.first { $0.name == "AudioCodec" }?.value, audio == "aac" ? "copy" : "aac")
                XCTAssertEqual(rig.engine.loads.last?.start, .seconds(20))
                let info = await rig.client.calls.filter { $0.path.hasSuffix("PlaybackInfo") }
                XCTAssertEqual(try jsonBody(info.last?.body)["StartTimeTicks"] as? Int64, 200_000_000)
                await rig.coordinator.stop()
                let reports = try await rig.client.calls.filter { $0.path.hasPrefix("/Sessions/") }.map {
                    try jsonBody($0.body)
                }
                XCTAssertEqual(
                    reports.compactMap { $0["PlaySessionId"] as? String },
                    ["play-session", "play-session", "remux-session", "remux-session"])
                XCTAssertEqual(
                    reports.compactMap { $0["PlayMethod"] as? String },
                    ["DirectPlay", "DirectPlay", "DirectStream", "DirectStream"])
                XCTAssertEqual(reports.compactMap { $0["Failed"] as? Bool }, [false, true, false, false])
            }
        }
    }

    func testT08P_17_startupLoaderAndPreparationFailureRetry() async throws {
        for failure in ["loader", "http", "redirect"] {
            let rig = try retryRig()
            if failure == "loader" {
                rig.engine.loadErrors = [.network, nil]
            } else {
                let response =
                    failure == "http"
                    ? OriginMediaResponse(status: 500)
                    : OriginMediaResponse(status: 302, location: URL(string: "https://evil.example/media"))
                await rig.origin.setResponses([response, OriginMediaResponse(status: 200)])
            }
            await started(rig, choice: .resume)
            await assertAttempts(rig, info: 2, streams: 2)
            XCTAssertEqual(rig.engine.loads.last?.start, .milliseconds(12_500))
            let calls = await rig.client.calls
            XCTAssertEqual(
                calls.filter { $0.method == "POST" }.map(\.path),
                [
                    "/Items/\(pocItemID)/PlaybackInfo", "/Sessions/Playing/Stopped",
                    "/Items/\(pocItemID)/PlaybackInfo", "/Sessions/Playing",
                ])
            let stopped = try jsonBody(calls.first { $0.path.hasSuffix("Stopped") }?.body)
            XCTAssertEqual(stopped["Failed"] as? Bool, true)
            XCTAssertEqual(stopped["PositionTicks"] as? Int64, 125_000_000)
            await rig.coordinator.stop()
        }
    }

    func testT08P_17_failureBeforeReadyRetriesWithoutPlayingReport() async throws {
        let rig = try retryRig()
        rig.engine.automaticallyReady = false
        rig.engine.automaticallyPlaying = false
        await rig.coordinator.play(itemID: pocItemID, choice: .startOver)
        rig.engine.automaticallyReady = true
        rig.engine.automaticallyPlaying = true
        rig.engine.emit(.failed(.timeout))
        await settle { rig.engine.loads.count == 2 && rig.timer.isRunning }
        let reports = try await rig.client.calls.filter { $0.path == "/Sessions/Playing" }.map { try jsonBody($0.body) }
        XCTAssertEqual(reports.compactMap { $0["PlaySessionId"] as? String }, ["remux-session"])
        await rig.coordinator.stop()
    }

    func testT08P_92_bothAttemptsFailWithExactlyTwoStreams() async throws {
        for startupFailure in [false, true] {
            let rig = try retryRig()
            if startupFailure {
                rig.engine.loadError = .network
                await rig.coordinator.play(itemID: pocItemID, choice: .startOver)
            } else {
                await started(rig)
                rig.engine.emit(.failed(.network))
                await settle { rig.engine.loads.count == 2 && rig.timer.isRunning }
                rig.engine.emit(.failed(.server(status: 500)))
                rig.engine.emit(.failed(.network))
                await settle { rig.coordinator.failure == .couldNotPlay }
            }
            XCTAssertEqual(rig.coordinator.state, .failed(localizedKey: PlaybackCopy.couldNotPlayKey))
            await assertAttempts(rig, info: 2, streams: 2)
            XCTAssertEqual(rig.engine.loadAttempts.count, 2)
            let stopped = try await rig.client.calls.filter { $0.path.hasSuffix("Stopped") }.map {
                try jsonBody($0.body)
            }
            XCTAssertEqual(stopped.compactMap { $0["PlaySessionId"] as? String }, ["play-session", "remux-session"])
            XCTAssertEqual(stopped.compactMap { $0["Failed"] as? Bool }, [true, true])
            XCTAssertFalse(rig.timer.isRunning)
        }
    }

    func testT08P_92_remuxPlaylistFailureEndsChain() async throws {
        for status in [404, 500] {
            let rig = try retryRig()
            await rig.origin.setResponses([OriginMediaResponse(status: 500), OriginMediaResponse(status: status)])
            await rig.coordinator.play(itemID: pocItemID, choice: .startOver)
            XCTAssertEqual(rig.coordinator.failure, .couldNotPlay)
            await assertAttempts(rig, info: 2, streams: 2)
            XCTAssertTrue(rig.engine.loads.isEmpty)
        }
    }

    func testT08P_93_pinnedDirectPlayFailureNeverNegotiatesRemux() async throws {
        for loaderFailure in [false, true] {
            let rig = try retryRig()
            rig.session.trust = .pinnedSelfSigned(fingerprintSHA256: String(repeating: "a", count: 64))
            if loaderFailure {
                rig.engine.loadError = .network
                await rig.coordinator.play(itemID: pocItemID, choice: .startOver)
            } else {
                await started(rig)
                rig.engine.emit(.failed(.network))
                await settle { rig.coordinator.failure == .hlsSegmentsBypassPinnedTrust }
            }
            XCTAssertEqual(rig.coordinator.state, .failed(localizedKey: "playback.selfSignedRemuxBlocked"))
            await assertAttempts(rig, info: 1, streams: 1)
            let calls = await rig.client.calls
            XCTAssertEqual(try jsonBody(calls.last?.body)["Failed"] as? Bool, true)
        }
    }

    func testT08P_99_retryVideoReasonBlocksBeforeStreamOrPlayer() async throws {
        let retry = try playbackFixture(
            container: "mkv", direct: false,
            transcodingURL: "/master.m3u8?TranscodeReasons=ContainerNotSupported,VideoCodecNotSupported",
            playSessionID: "remux-session")
        let rig = try retryRig(retryData: retry)
        await started(rig)
        rig.engine.emit(.failed(.network))
        await settle { rig.coordinator.failure == .unsupportedVideo }
        XCTAssertEqual(rig.coordinator.state, .failed(localizedKey: "playback.unsupportedVideoFormat"))
        await assertAttempts(rig, info: 2, streams: 1)
        XCTAssertEqual(rig.engine.loadAttempts.count, 1)
        let calls = await rig.client.calls
        XCTAssertEqual(calls.filter { $0.path.hasSuffix("Stopped") }.count, 1)
        XCTAssertEqual(try jsonBody(calls.first { $0.path.hasSuffix("Stopped") }?.body)["Failed"] as? Bool, true)
    }

    func testT08P_31_initialRemuxFailureNeverRetries() async throws {
        let rig = try rig(data: playbackFixture(container: "mkv", direct: false, transcodingURL: "/master.m3u8"))
        await started(rig)
        rig.engine.emit(.failed(.network))
        await settle { rig.coordinator.failure == .couldNotPlay }
        let calls = await rig.client.calls
        XCTAssertEqual(calls.filter { $0.path.hasSuffix("PlaybackInfo") }.count, 1)
        let streams = await rig.origin.requests
        XCTAssertEqual(streams.count, 1)
        XCTAssertEqual(rig.engine.loadAttempts.count, 1)
    }

    func testT08P_17_56_retryWaitsForStoppedAndCanBeDismissed() async throws {
        for dismiss in [false, true] {
            let first = try playbackFixture()
            let remux = try playbackFixture(
                direct: false, transcodingURL: "/master.m3u8", playSessionID: "remux-session")
            let gate = PoCRequestGate()
            let rig = try rig(handler: { request throws(APIError) in
                if request.path.hasSuffix("Stopped"), (try? jsonBody(request.body)["Failed"] as? Bool) == true {
                    await gate.wait()
                }
                if request.path.hasSuffix("PlaybackInfo") {
                    return (try? jsonBody(request.body)["EnableDirectPlay"] as? Bool) == false ? remux : first
                }
                return Data()
            })
            await started(rig)
            rig.engine.emit(.failed(.network))
            await settle { await gate.isWaiting }
            await assertAttempts(rig, info: 1, streams: 1)
            XCTAssertFalse(rig.timer.isRunning)
            if dismiss { await rig.coordinator.stop() }
            await gate.release()
            if dismiss {
                await settle { rig.coordinator.state == .idle }
                await assertAttempts(rig, info: 1, streams: 1)
            } else {
                await settle { rig.engine.loads.count == 2 && rig.timer.isRunning }
                let paths = await rig.client.calls.filter { $0.method == "POST" }.map(\.path)
                XCTAssertEqual(
                    paths,
                    [
                        "/Items/\(pocItemID)/PlaybackInfo", "/Sessions/Playing",
                        "/Sessions/Playing/Stopped", "/Items/\(pocItemID)/PlaybackInfo", "/Sessions/Playing",
                    ])
                await rig.coordinator.stop()
            }
        }
    }

    func testT08P_42_retry401NeverStartsThirdAttempt() async throws {
        let rig = try retryRig()
        await started(rig)
        await rig.origin.setResponses([OriginMediaResponse(status: 401)])
        rig.engine.emit(.failed(.network))
        await settle { (await rig.client.calls).last?.path == "/Users/Me" }
        await settle { rig.coordinator.failure == .couldNotPlay }
        await assertAttempts(rig, info: 2, streams: 2)
        XCTAssertEqual(rig.engine.loadAttempts.count, 1)
        XCTAssertEqual(rig.session.expirationCount, 0)
    }

    func testT08P_42_44_stopped401PreventsRemuxRetry() async throws {
        let fixture = try playbackFixture()
        let rig = try rig(handler: { request throws(APIError) in
            if request.path.hasSuffix("PlaybackInfo") { return fixture }
            if request.path.hasSuffix("Stopped") { throw .unauthorized }
            return Data()
        })
        await started(rig)
        rig.engine.emit(.failed(.network))
        await settle { rig.coordinator.failure == .couldNotPlay }
        await assertAttempts(rig, info: 1, streams: 1)
        let calls = await rig.client.calls
        XCTAssertEqual(calls.filter { $0.path == "/Users/Me" }.count, 1)
        XCTAssertEqual(calls.filter { $0.path.hasSuffix("Stopped") }.count, 1)
    }

    func testT08P_17_retryKeepsBackwardSeekPosition() async throws {
        let rig = try retryRig()
        await started(rig, choice: .resume)
        await rig.coordinator.seek(to: .seconds(3))
        rig.engine.emit(.failed(.network))
        await settle { rig.engine.loads.count == 2 && rig.timer.isRunning }
        XCTAssertEqual(rig.engine.loads.last?.start, .seconds(3))
        await rig.coordinator.stop()
    }

    func testT08P_17_56_stopDuringRetryDiscardsLatePlaybackInfo() async throws {
        let first = try playbackFixture()
        let remux = try playbackFixture(direct: false, transcodingURL: "/master.m3u8", playSessionID: "remux-session")
        let gate = PoCRequestGate()
        let rig = try rig(handler: { request throws(APIError) in
            if request.path.hasSuffix("PlaybackInfo") {
                if (try? jsonBody(request.body)["EnableDirectPlay"] as? Bool) == false {
                    await gate.wait()
                    return remux
                }
                return first
            }
            return Data()
        })
        await started(rig)
        rig.engine.emit(.failed(.network))
        await settle { await gate.isWaiting }
        await rig.coordinator.stop()
        await gate.release()
        await settle { rig.coordinator.state == .idle }
        await assertAttempts(rig, info: 2, streams: 1)
        XCTAssertEqual(rig.engine.loadAttempts.count, 1)
        XCTAssertFalse(rig.timer.isRunning)
    }

    func testT08P_17_56_cancellingStartupCancelsPendingRetry() async throws {
        for cancelAtStopped in [false, true] {
            let first = try playbackFixture()
            let remux = try playbackFixture(
                direct: false, transcodingURL: "/master.m3u8", playSessionID: "remux-session")
            let gate = PoCRequestGate()
            let rig = try rig(handler: { request throws(APIError) in
                if cancelAtStopped && request.path.hasSuffix("Stopped") { await gate.wait() }
                if request.path.hasSuffix("PlaybackInfo") {
                    if (try? jsonBody(request.body)["EnableDirectPlay"] as? Bool) == false {
                        await gate.wait()
                        return remux
                    }
                    return first
                }
                return Data()
            })
            rig.engine.loadErrors = [.network, nil]
            let task = Task { await rig.coordinator.play(itemID: pocItemID, choice: .startOver) }
            await settle { await gate.isWaiting }
            task.cancel()
            await gate.release()
            await task.value
            XCTAssertEqual(rig.coordinator.state, .idle)
            await assertAttempts(rig, info: cancelAtStopped ? 1 : 2, streams: 1)
            XCTAssertEqual(rig.engine.loadAttempts.count, 1)
            XCTAssertFalse(rig.timer.isRunning)
        }
    }

    func testT08P_17_retryRequiresNewPlaySessionID() async throws {
        let rig = try retryRig(retryData: playbackFixture(direct: false, transcodingURL: "/master.m3u8"))
        rig.engine.loadError = .network
        await rig.coordinator.play(itemID: pocItemID, choice: .startOver)
        XCTAssertEqual(rig.coordinator.failure, .couldNotPlay)
        await assertAttempts(rig, info: 2, streams: 1)
    }

    func testT08P_94_95_96_97_defaultVideoPrecheck() async throws {
        let audio: [String: Any] = ["Type": "Audio", "Codec": "aac", "IsDefault": true]
        let cases: [([[String: Any]], PlaybackFailure?)] =
            [
                (
                    [
                        ["Type": "Video", "Codec": "mpeg2video"],
                        ["Type": "Video", "Codec": "h264", "IsDefault": true],
                    ], nil
                ),
                (
                    [
                        ["Type": "Video", "Codec": "h264"],
                        ["Type": "Video", "Codec": "mpeg2video", "IsDefault": true],
                    ], .unsupportedVideo
                ),
                (
                    [audio, ["Type": "Video", "Codec": "mpeg2video"], ["Type": "Video", "Codec": "h264"]],
                    .unsupportedVideo
                ),
                ([audio, ["Type": "Video", "Codec": "h264"], ["Type": "Video", "Codec": "mpeg2video"]], nil),
                ([audio, ["Type": "Subtitle", "Codec": "srt"]], .couldNotPlay), ([], .couldNotPlay),
            ]
            + ["H264", "Hevc", "HEVC", "h264", "H265", "h265", "MPEG2VIDEO", "Vc1", "avc"].map { codec in
                (
                    [["Type": "Video", "Codec": codec]],
                    ["MPEG2VIDEO", "Vc1", "avc"].contains(codec) ? .unsupportedVideo : nil
                )
            }
        for (streams, expected) in cases {
            let metadata = try JSONSerialization.data(withJSONObject: ["MediaStreams": streams])
            let rig = try rig(itemData: metadata)
            await rig.coordinator.play(itemID: pocItemID, choice: .startOver)
            if let expected {
                XCTAssertEqual(rig.coordinator.failure, expected)
                XCTAssertTrue(rig.engine.loads.isEmpty)
                let requests = await rig.origin.requests
                XCTAssertTrue(requests.isEmpty)
            } else {
                await settle { rig.coordinator.state == .playing }
            }
            let calls = await rig.client.calls
            XCTAssertEqual(calls.filter { $0.method == "GET" }.count, 1)
            XCTAssertEqual(calls.filter { $0.path.hasSuffix("PlaybackInfo") }.count, expected == nil ? 1 : 0)
            await rig.coordinator.stop()
        }
    }

    func testT08P_98_missingStreamsRefetchExactlyOnce() async throws {
        let supported = try playbackFixture()
        let valid = try playbackItemFixture(from: supported)
        let blocked = Data(#"{"MediaStreams":[{"Type":"Video","Codec":"mpeg2video"}]}"#.utf8)
        for (refetched, expected) in [
            (valid, nil), (Data("{}".utf8), PlaybackFailure.couldNotPlay),
            (Data(#"{"MediaStreams":[]}"#.utf8), .couldNotPlay), (blocked, .unsupportedVideo),
        ] {
            let count = PoCReportAttempts()
            let rig = try rig()
            await rig.client.setHandler { request throws(APIError) in
                if request.method == "GET" {
                    return await count.next("item") == 1 ? Data("{}".utf8) : refetched
                }
                if request.path.hasSuffix("PlaybackInfo") { return supported }
                return Data()
            }
            await rig.coordinator.play(itemID: pocItemID, choice: .startOver)
            if let expected {
                XCTAssertEqual(rig.coordinator.failure, expected)
                XCTAssertTrue(rig.engine.loads.isEmpty)
            } else {
                await settle { rig.coordinator.state == .playing }
            }
            let calls = await rig.client.calls
            let gets = calls.filter { $0.method == "GET" }
            XCTAssertEqual(gets.count, 2)
            for get in gets {
                XCTAssertEqual(get.path, "/Users/\(pocUserID)/Items/\(pocItemID)")
                XCTAssertTrue(get.query.contains { $0.name == "Fields" && $0.value == "MediaStreams" })
            }
            XCTAssertEqual(calls.filter { $0.path.hasSuffix("PlaybackInfo") }.count, expected == nil ? 1 : 0)
            await rig.coordinator.stop()
        }
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
