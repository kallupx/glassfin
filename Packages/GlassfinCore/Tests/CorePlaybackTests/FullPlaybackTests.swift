import CoreModels
import CoreNetworking
import Foundation
import XCTest

@testable import CorePlayback

final class RuntimeProfileTests: XCTestCase {
    private func profile(_ capabilities: PlaybackCapabilities = .init(), convertASS: Bool = true) throws -> [String:
        Any]
    {
        try jsonBody(
            JSONEncoder().encode(
                RuntimeDeviceProfile(
                    capabilities: capabilities, maxBitrate: 120_000_000,
                    convertASS: convertASS)))
    }

    func testNativeContainersAndConditionalCodecs() throws {
        for av1 in [true, false] {
            for opus in [true, false] {
                let value = try profile(.init(av1: av1, verifiedOpus: opus))
                let direct = try XCTUnwrap((value["DirectPlayProfiles"] as? [[String: Any]])?.first)
                XCTAssertEqual(direct["Container"] as? String, "mp4,m4v,mov")
                XCTAssertEqual((direct["VideoCodec"] as? String)?.contains("av1"), av1)
                XCTAssertEqual((direct["AudioCodec"] as? String)?.contains("opus"), opus)
                for codec in ["aac", "ac3", "eac3", "alac", "flac", "mp3"] {
                    XCTAssertTrue((direct["AudioCodec"] as? String)?.contains(codec) == true)
                }
            }
        }
    }

    func testSDRDisplayExcludesEveryHDRRange() throws {
        let codecs = try XCTUnwrap(try profile()["CodecProfiles"] as? [[String: Any]])
        let hevc = try XCTUnwrap(codecs.first { $0["Codec"] as? String == "hevc" })
        let conditions = try XCTUnwrap(hevc["Conditions"] as? [[String: Any]])
        XCTAssertEqual(conditions.first { $0["Property"] as? String == "VideoRangeType" }?["Value"] as? String, "SDR")
    }

    func testHDRAndDolbyVisionRequireTheirOwnDisplayCapabilities() throws {
        for hdr10 in [false, true] {
            for hlg in [false, true] {
                for dv in [false, true] {
                    let value = PlaybackCapabilities(hdr10: hdr10, hlg: hlg, dolbyVision: dv)
                    let ranges = Set(value.videoRanges.split(separator: "|").map(String.init))
                    XCTAssertEqual(ranges.contains("HDR10"), hdr10)
                    XCTAssertEqual(ranges.contains("HLG"), hlg)
                    XCTAssertEqual(ranges.contains("DOVI"), dv)
                    XCTAssertEqual(ranges.contains("DOVIWithHDR10"), dv && hdr10)
                    XCTAssertEqual(ranges.contains("DOVIWithSDR"), dv)
                }
            }
        }
    }

    func testCodecLevelAndBitDepthConstraints() throws {
        let codecs = try XCTUnwrap(
            try profile(.init(h264Level: 42, hevcLevel: 150))["CodecProfiles"] as? [[String: Any]])
        for (name, level, depth) in [("h264", "42", "8"), ("hevc", "150", "10")] {
            let codec = try XCTUnwrap(codecs.first { $0["Codec"] as? String == name })
            let conditions = try XCTUnwrap(codec["Conditions"] as? [[String: Any]])
            XCTAssertEqual(conditions.first { $0["Property"] as? String == "VideoLevel" }?["Value"] as? String, level)
            XCTAssertEqual(
                conditions.first { $0["Property"] as? String == "VideoBitDepth" }?["Value"] as? String, depth)
        }
    }

    func testTranscodingWireShapeAndNoHEVCWithoutDecoder() throws {
        let value = try profile(.init(hevc: false))
        let transcode = try XCTUnwrap((value["TranscodingProfiles"] as? [[String: Any]])?.first)
        XCTAssertEqual(transcode["Protocol"] as? String, "hls")
        XCTAssertEqual(transcode["Container"] as? String, "mp4")
        XCTAssertEqual(transcode["VideoCodec"] as? String, "h264")
        XCTAssertEqual(transcode["AudioCodec"] as? String, "eac3,ac3,aac")
        XCTAssertEqual(transcode["MaxAudioChannels"] as? String, "8")
        XCTAssertEqual(transcode["BreakOnNonKeyFrames"] as? Bool, true)
        XCTAssertEqual(value["MaxStreamingBitrate"] as? Int, 120_000_000)
    }

    func testSubtitleDeliveryAndASSDefault() throws {
        for convert in [true, false] {
            let subs = try XCTUnwrap(try profile(convertASS: convert)["SubtitleProfiles"] as? [[String: String]])
            for codec in ["pgssub", "dvdsub"] {
                XCTAssertTrue(subs.contains { $0["Format"] == codec && $0["Method"] == "Encode" })
            }
            XCTAssertTrue(subs.contains { $0["Format"] == "ass" && $0["Method"] == (convert ? "External" : "Encode") })
            XCTAssertTrue(subs.contains { $0["Format"] == "vtt" && $0["Method"] == "Hls" })
            XCTAssertTrue(subs.contains { $0["Format"] == "mov_text" && $0["Method"] == "Embed" })
        }
    }
}

final class FullStreamSelectionTests: XCTestCase {
    func testDecisionTable() throws {
        let rows: [(String, String, Bool, String?, PlaybackAttempt, PlayMethod?)] = [
            ("mp4", "h264", true, nil, .automatic, .directPlay),
            ("mkv", "h264", false, "/master.m3u8?VideoCodec=copy", .automatic, .directStream),
            ("mkv", "hevc", false, "/master.m3u8?TranscodeReasons=AudioCodecNotSupported", .automatic, .directStream),
            ("avi", "mpeg4", false, "/master.m3u8?TranscodeReasons=VideoCodecNotSupported", .automatic, .transcode),
            ("mp4", "av1", true, nil, .automatic, .directPlay),
            ("mp4", "h264", true, "/master.m3u8", .directStream, .directStream),
            ("mp4", "h264", true, "/master.m3u8", .transcode, .transcode),
            ("mkv", "hevc", false, nil, .automatic, nil),
            ("mkv", "hevc", false, "", .transcode, nil),
        ]
        for (container, video, direct, url, attempt, expected) in rows {
            let info = try JSONDecoder().decode(
                PlaybackInfoResponseDTO.self,
                from: playbackFixture(
                    container: container, video: video, direct: direct, transcodingURL: url))
            let source = try XCTUnwrap(info.MediaSources?.first)
            if let expected {
                XCTAssertEqual(try PlaybackStreamSelection.decide(source: source, attempt: attempt).method, expected)
            } else {
                XCTAssertThrowsError(try PlaybackStreamSelection.decide(source: source, attempt: attempt))
            }
        }
    }

    func testNegotiatedURLPreservesCodecsAndBurnInWithoutCredentials() throws {
        let server = try XCTUnwrap(URL(string: "https://server.example/jellyfin"))
        let url = try MediaURLBuilder.negotiatedHLS(
            server: server,
            transcodingURL:
                "/master.m3u8?VideoCodec=hevc&AudioCodec=eac3&SubtitleMethod=Encode&SubtitleStreamIndex=8&ApiKey=fixture"
        )
        XCTAssertFalse(MediaCredentialQuery.contains(url))
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first { $0.name == "VideoCodec" }?.value, "hevc")
        XCTAssertEqual(query.first { $0.name == "AudioCodec" }?.value, "eac3")
        XCTAssertEqual(query.first { $0.name == "SubtitleMethod" }?.value, "Encode")
        XCTAssertEqual(query.first { $0.name == "SubtitleStreamIndex" }?.value, "8")
        XCTAssertEqual(url.path, "/jellyfin/master.m3u8")
        for path in [
            "https://other.example/master.m3u8", "http://server.example/master.m3u8",
            "https://user@server.example/master.m3u8",
        ] {
            XCTAssertThrowsError(try MediaURLBuilder.negotiatedHLS(server: server, transcodingURL: path))
        }
    }
}

final class FullTrackMappingTests: XCTestCase {
    func testSparseIndexesTypesCaseAndDeliveryMapping() throws {
        let streams = try fullStreams()
        let tracks = PlaybackTrack.map(streams)
        XCTAssertEqual(tracks.map(\.id), [2, 5, 8, 10, 12, 15])
        XCTAssertEqual(tracks.map(\.delivery), [.embedded, .embedded, .externalVTT, .burnIn, .externalVTT, .embedded])
        XCTAssertEqual(PlaybackTrack.map(streams, convertASS: false).first { $0.id == 12 }?.delivery, .burnIn)
    }

    func testLanguagePreferencesAndSubtitleModes() throws {
        let tracks = PlaybackTrack.map(try fullStreams())
        for (mode, expected) in [("Always", 8), ("None", -1), ("OnlyForced", 10), ("Smart", 10)] {
            let user = try JSONDecoder().decode(
                PlaybackUserConfigurationDTO.self,
                from: JSONSerialization.data(withJSONObject: [
                    "AudioLanguagePreference": "fi", "SubtitleLanguagePreference": "fin", "SubtitleMode": mode,
                ]))
            let selection = PlaybackTrackSelection.defaults(tracks: tracks, user: user)
            XCTAssertEqual(selection.audio, 5)
            XCTAssertEqual(selection.subtitle, expected)
        }
        XCTAssertEqual(PlaybackTrackSelection.defaults(tracks: tracks, user: nil).audio, 2)
        XCTAssertNil(PlaybackTrackSelection.defaults(tracks: tracks, user: nil).subtitle)
    }

    func testMissingDuplicateAndMaliciousTrackMetadata() throws {
        let data = Data(
            """
            [{"Index":3,"Type":"Audio","DisplayTitle":"A\\u202eB\\u0001"},
             {"Index":3,"Type":"Audio"},{"Type":"Audio"},{"Index":-1,"Type":"Subtitle"},{"Index":7,"Type":"Data"}]
            """.utf8)
        let tracks = PlaybackTrack.map(try JSONDecoder().decode([MediaStreamDTO].self, from: data))
        XCTAssertEqual(tracks.count, 1)
        XCTAssertEqual(tracks.first?.title, "AB")
    }

    func testNativeMappingUsesMetadataInsteadOfStreamIndexAndRejectsAmbiguity() throws {
        let tracks = PlaybackTrack.map(try fullStreams())
        let track = try XCTUnwrap(tracks.first { $0.id == 5 })
        let options = [
            NativeTrackOption(title: "English", language: "en"), NativeTrackOption(title: "Finnish", language: "fi"),
        ]
        XCTAssertEqual(NativeTrackMapping.optionIndex(for: track, options: options, peers: tracks), 1)
        let duplicates = [
            NativeTrackOption(title: "Finnish", language: "fi"), NativeTrackOption(title: "Commentary", language: "fi"),
        ]
        XCTAssertNil(NativeTrackMapping.optionIndex(for: track, options: duplicates, peers: tracks))
        XCTAssertNil(NativeTrackMapping.optionIndex(for: track, options: [], peers: tracks))
    }

    func testWebVTTCJKOverlapsAndLiteralMarkup() throws {
        let cues = try WebVTT.parse(
            Data(
                """
                WEBVTT

                cue-id
                00:01.000 --> 00:03.000 align:center
                日本語 中文 한국어

                00:00:02.000 --> 00:00:04.000
                <b>literal</b>
                """.utf8))
        XCTAssertEqual(WebVTT.text(at: .seconds(2), cues: cues), "日本語 中文 한국어\n<b>literal</b>")
        XCTAssertEqual(WebVTT.text(at: .seconds(4), cues: cues), "")
    }

    func testSubtitleLimitsAndMalformedCues() throws {
        XCTAssertThrowsError(try WebVTT.parse(Data(repeating: 65, count: WebVTT.maximumBytes + 1)))
        XCTAssertThrowsError(try WebVTT.parse(Data("not vtt".utf8)))
        XCTAssertThrowsError(try WebVTT.parse(Data([0xff])))
        XCTAssertTrue(try WebVTT.parse(Data("WEBVTT\n\n00:03.000 --> 00:01.000\nbad".utf8)).isEmpty)
        XCTAssertTrue(try WebVTT.parse(Data("WEBVTT\n\n1e300:00:00.000 --> 1e301:00:00.000\nbad".utf8)).isEmpty)
    }
}

private func fullStreams() throws -> [MediaStreamDTO] {
    try JSONDecoder().decode(
        [MediaStreamDTO].self,
        from: Data(
            """
            [{"Index":0,"Type":"Video","Codec":"hevc"},
             {"Index":2,"Type":"Audio","Codec":"aac","Language":"eng","IsDefault":true},
             {"Index":5,"Type":"AUDIO","Codec":"eac3","Language":"fin"},
             {"Index":8,"Type":"Subtitle","Codec":"subrip","Language":"fin","IsExternal":true},
             {"Index":10,"Type":"Subtitle","Codec":"pgssub","Language":"fin","IsForced":true},
             {"Index":12,"Type":"Subtitle","Codec":"ass","Language":"eng"},
             {"Index":15,"Type":"Subtitle","Codec":"mov_text","Language":"eng"}]
            """.utf8))
}

@MainActor
final class FullPlaybackCoordinatorTests: XCTestCase {
    private struct Rig {
        let playback: PlaybackCoordinator
        let client: FullPlaybackClient
        let engine: FullTrackEngine
        let origin: MockPlaybackOrigin
        let session: MockPlaybackSession
    }

    private func rig(
        direct: Bool = true, reasons: String = "", noCredential: Bool = false,
        clock: any GlassfinClock = SystemGlassfinClock(), capabilities: PlaybackCapabilities = .init()
    ) throws -> Rig {
        let client = FullPlaybackClient(
            streams: try fullStreams(), direct: direct, reasons: reasons, noCredential: noCredential)
        let session = MockPlaybackSession(
            serverURL: try XCTUnwrap(URL(string: "https://server.example/jellyfin")), userID: pocUserID,
            identity: ClientIdentity(deviceName: "TV", deviceID: "fixture", version: "1", token: "fixture-token"),
            apiClient: client)
        let engine = FullTrackEngine()
        let origin = MockPlaybackOrigin()
        let playback = PlaybackCoordinator(
            session: session, engine: engine, origin: origin, timer: ManualPlaybackTimer(),
            configuration: .init(capabilities: capabilities), clock: clock)
        return Rig(playback: playback, client: client, engine: engine, origin: origin, session: session)
    }

    private func settle(_ condition: () async -> Bool) async {
        for _ in 0..<1000 {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("Playback operation did not complete")
    }

    private func start(_ rig: Rig) async {
        await rig.playback.play(itemID: pocItemID, choice: .startOver)
        await settle { rig.playback.state == .playing }
    }

    func testFullRuntimeProfileAndUserPreferencesAreUsedByDefault() async throws {
        let rig = try rig(capabilities: .init(av1: true, hdr10: true))
        await start(rig)
        let calls = await rig.client.calls
        let body = try jsonBody(calls.first { $0.path.hasSuffix("PlaybackInfo") }?.body)
        XCTAssertEqual(body["AudioStreamIndex"] as? Int, 5)
        XCTAssertEqual(body["SubtitleStreamIndex"] as? Int, -1)
        XCTAssertEqual(body["MaxStreamingBitrate"] as? Int, 20_000_000)
        let profile = try XCTUnwrap(body["DeviceProfile"] as? [String: Any])
        XCTAssertEqual(profile["Name"] as? String, "Glassfin AVPlayer")
        XCTAssertEqual(rig.playback.selection.audio, 5)
        XCTAssertTrue(rig.engine.selections.contains { $0.0 == 5 && $0.1 == .audio })
        await rig.playback.stop()
    }

    func testThreeAttemptFallbackFlagsPositionAndReportMethods() async throws {
        let rig = try rig()
        await start(rig)
        rig.engine.base.position = .seconds(42)
        rig.engine.base.emit(.failed(.network))
        await settle { rig.engine.base.loads.count == 2 && rig.playback.state == .playing }
        rig.engine.base.emit(.failed(.network))
        await settle { rig.engine.base.loads.count == 3 && rig.playback.state == .playing }
        let calls = await rig.client.calls
        let bodies = try calls.filter { $0.path.hasSuffix("PlaybackInfo") }.map { try jsonBody($0.body) }
        XCTAssertEqual(bodies.count, 3)
        XCTAssertEqual(bodies.compactMap { $0["EnableDirectPlay"] as? Bool }, [true, false, false])
        XCTAssertEqual(bodies.compactMap { $0["AllowVideoStreamCopy"] as? Bool }, [true, true, false])
        XCTAssertEqual(bodies.compactMap { $0["StartTimeTicks"] as? Int64 }, [0, 420_000_000, 420_000_000])
        XCTAssertEqual(rig.engine.base.loads.map(\.start), [.zero, .seconds(42), .seconds(42)])
        let reports = try calls.filter { $0.path == "/Sessions/Playing" }.map { try jsonBody($0.body) }
        XCTAssertEqual(reports.compactMap { $0["PlayMethod"] as? String }, ["DirectPlay", "DirectStream", "Transcode"])
        rig.engine.base.emit(.failed(.network))
        await settle { rig.playback.state == .failed(localizedKey: PlaybackCopy.couldNotPlayKey) }
        let finalCalls = await rig.client.calls
        XCTAssertEqual(finalCalls.filter { $0.path.hasSuffix("PlaybackInfo") }.count, 3)
    }

    func testUnsupportedVideoNegotiatesTranscodeInsteadOfPoCRejection() async throws {
        let rig = try rig(direct: false, reasons: "VideoCodecNotSupported")
        await start(rig)
        XCTAssertEqual(rig.playback.playMethod, .transcode)
        XCTAssertEqual(rig.playback.transcodeReasons, ["VideoCodecNotSupported"])
        XCTAssertNil(rig.playback.failure)
        await rig.playback.stop()
    }

    func testNativeEmbeddedSwitchDoesNotReloadAndReportsSelection() async throws {
        let rig = try rig()
        await start(rig)
        await rig.playback.selectTrack(id: 2, kind: .audio)
        await rig.playback.selectTrack(id: 15, kind: .subtitle)
        let calls = await rig.client.calls
        XCTAssertEqual(calls.filter { $0.path.hasSuffix("PlaybackInfo") }.count, 1)
        XCTAssertEqual(rig.engine.base.loads.count, 1)
        let report = try jsonBody(calls.last { $0.path.hasSuffix("/Progress") }?.body)
        XCTAssertEqual(report["AudioStreamIndex"] as? Int, 2)
        XCTAssertEqual(rig.playback.diagnostics?.sourceAudio, "aac")
        XCTAssertEqual(report["SubtitleStreamIndex"] as? Int, 15)
        await rig.playback.stop()
    }

    func testExternalTextIsBoundedAndCanBeTurnedOffWithoutReload() async throws {
        let rig = try rig()
        await start(rig)
        await rig.playback.selectTrack(id: 8, kind: .subtitle)
        XCTAssertEqual(WebVTT.text(at: .seconds(1), cues: rig.playback.subtitleCues), "日本語 中文 한국어")
        let subtitleCalls = await rig.client.calls.filter { $0.path.hasSuffix("Stream.vtt") }
        XCTAssertEqual(subtitleCalls.count, 1)
        XCTAssertEqual(subtitleCalls.first?.maximumResponseBytes, WebVTT.maximumBytes)
        XCTAssertFalse(subtitleCalls.first?.path.contains("?") == true)
        await rig.playback.selectTrack(id: nil, kind: .subtitle)
        XCTAssertEqual(rig.playback.selection.subtitle, -1)
        XCTAssertTrue(rig.playback.subtitleCues.isEmpty)
        XCTAssertEqual(rig.engine.base.loads.count, 1)
        await rig.playback.stop()
    }

    func testBurnInAndTurningItOffRenegotiateSameSourceAtSamePosition() async throws {
        let rig = try rig()
        await start(rig)
        rig.engine.base.position = .seconds(37)
        await rig.playback.selectTrack(id: 10, kind: .subtitle)
        await settle { rig.playback.state == .playing }
        XCTAssertEqual(rig.playback.playMethod, .transcode)
        await rig.playback.selectTrack(id: nil, kind: .subtitle)
        await settle { rig.playback.state == .playing }
        let bodies = try await rig.client.calls.filter { $0.path.hasSuffix("PlaybackInfo") }.map {
            try jsonBody($0.body)
        }
        XCTAssertEqual(bodies.count, 3)
        XCTAssertEqual(bodies[1]["SubtitleStreamIndex"] as? Int, 10)
        XCTAssertEqual(bodies[2]["SubtitleStreamIndex"] as? Int, -1)
        XCTAssertEqual(bodies[1]["MediaSourceId"] as? String, pocSourceID)
        XCTAssertEqual(bodies[1]["StartTimeTicks"] as? Int64, 370_000_000)
        XCTAssertEqual(rig.engine.base.loads.map(\.start), [.zero, .seconds(37), .seconds(37)])
        await rig.playback.stop()
    }

    func testPausedServerSwitchKeepsPauseStateAndPosition() async throws {
        let rig = try rig()
        await start(rig)
        rig.engine.base.position = .seconds(23)
        rig.playback.pause()
        await settle { rig.playback.state == .paused }
        await rig.playback.selectTrack(id: 10, kind: .subtitle)
        await settle { rig.playback.state == .paused && rig.engine.base.loads.count == 2 }
        XCTAssertEqual(rig.engine.base.loads.last?.start, .seconds(23))
        XCTAssertEqual(rig.playback.selection.subtitle, 10)
        await rig.playback.stop()
    }

    func testHLSWithAvailableEmbeddedAudioSwitchesNatively() async throws {
        let rig = try rig(direct: false)
        await start(rig)
        await rig.playback.selectTrack(id: 2, kind: .audio)
        XCTAssertEqual(rig.engine.base.loads.count, 1)
        XCTAssertEqual(rig.playback.selection.audio, 2)
        let calls = await rig.client.calls
        XCTAssertEqual(calls.filter { $0.path.hasSuffix("PlaybackInfo") }.count, 1)
        await rig.playback.stop()
    }

    func testSystemNativeMenuSelectionUpdatesProgress() async throws {
        let rig = try rig()
        await start(rig)
        rig.engine.base.emit(.trackChanged(kind: .audio, id: 2))
        await settle { rig.playback.selection.audio == 2 }
        await settle { await rig.client.calls.contains { $0.path.hasSuffix("/Progress") } }
        let calls = await rig.client.calls
        let report = try jsonBody(calls.last { $0.path.hasSuffix("/Progress") }?.body)
        XCTAssertEqual(report["AudioStreamIndex"] as? Int, 2)
        await rig.playback.stop()
    }

    func testAudioInRemuxAndUnmappedNativeTrackRenegotiate() async throws {
        for direct in [false, true] {
            let rig = try rig(direct: direct)
            await start(rig)
            // Let subsequent initial audio selection succeed; only this live selection is unmappable.
            rig.engine.failNextSelection = true
            rig.engine.nativeSelectionWorks = true
            await rig.playback.selectTrack(id: 2, kind: .audio)
            await settle { rig.playback.state == .playing && rig.engine.base.loads.count == 2 }
            let calls = await rig.client.calls
            let body = try jsonBody(calls.last { $0.path.hasSuffix("PlaybackInfo") }?.body)
            XCTAssertEqual(body["AudioStreamIndex"] as? Int, 2)
            XCTAssertEqual(body["MediaSourceId"] as? String, pocSourceID)
            await rig.playback.stop()
        }
    }

    func testPinnedHLSAndMissingServerCredentialFailBeforePlaylistFetch() async throws {
        for pinned in [false, true] {
            let rig = try rig(direct: false, noCredential: !pinned)
            if pinned { rig.session.trust = .pinnedSelfSigned(fingerprintSHA256: "fixture") }
            await rig.playback.play(itemID: pocItemID, choice: .startOver)
            if pinned {
                XCTAssertEqual(rig.playback.failure, .hlsSegmentsBypassPinnedTrust)
            } else {
                XCTAssertEqual(rig.playback.failure, .couldNotPlay)
            }
            let requests = await rig.origin.requests
            XCTAssertTrue(requests.isEmpty)
            XCTAssertTrue(rig.engine.base.loads.isEmpty)
        }
    }

    func testFirstFrameDeadlineFallsBackAnd401DoesNotRetry() async throws {
        let clock = FullPlaybackClock()
        let rig = try rig(clock: clock)
        rig.engine.base.automaticallyPlaying = false
        await rig.playback.play(itemID: pocItemID, choice: .startOver)
        await settle { await clock.isWaiting }
        await clock.advance()
        await settle { rig.engine.base.loads.count == 2 }
        rig.engine.base.emit(.failed(.unauthorized))
        await settle { rig.playback.state == .failed(localizedKey: PlaybackCopy.couldNotPlayKey) }
        await settle { await rig.client.calls.filter { $0.path == "/Users/Me" }.count == 2 }
        let calls = await rig.client.calls
        XCTAssertEqual(calls.filter { $0.path.hasSuffix("PlaybackInfo") }.count, 2)
        XCTAssertEqual(calls.filter { $0.path == "/Users/Me" }.count, 2)
        XCTAssertEqual(rig.session.expirationCount, 0)
    }

    func testSubtitleDownloadHasTotalDeadline() async throws {
        let clock = FullPlaybackClock()
        let api = PlaybackAPI(client: SlowSubtitleClient())
        let task = Task {
            do {
                _ = try await api.subtitles(itemID: pocItemID, mediaSourceID: pocSourceID, index: 8, clock: clock)
                XCTFail("Expected the subtitle deadline")
            } catch {
                XCTAssertEqual(error as? APIError, .timeout)
            }
        }
        await settle { await clock.isWaiting }
        await clock.advance()
        await task.value
    }

    func testASSSettingRenegotiatesBetweenBurnInAndConversion() async throws {
        let previous = UserDefaults.standard.object(forKey: PlaybackPreferenceKeys.convertASS)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: PlaybackPreferenceKeys.convertASS)
            } else {
                UserDefaults.standard.removeObject(forKey: PlaybackPreferenceKeys.convertASS)
            }
        }
        let rig = try rig()
        await start(rig)
        await rig.playback.selectTrack(id: 12, kind: .subtitle)
        await rig.playback.setASSConversion(false)
        await settle { rig.playback.state == .playing }
        XCTAssertEqual(rig.playback.playMethod, .transcode)
        XCTAssertTrue(rig.playback.subtitleCues.isEmpty)
        let burningCalls = await rig.client.calls
        let burnBody = try jsonBody(burningCalls.last { $0.path.hasSuffix("PlaybackInfo") }?.body)
        XCTAssertEqual(burnBody["AllowVideoStreamCopy"] as? Bool, false)
        await rig.playback.setASSConversion(true)
        await settle { rig.playback.state == .playing }
        XCTAssertEqual(rig.playback.playMethod, .directPlay)
        XCTAssertFalse(rig.playback.subtitleCues.isEmpty)
        await rig.playback.stop()
    }

    func testInitialASSConversionAndPreferenceDefaults() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FullPlaybackTests"))
        defer { defaults.removePersistentDomain(forName: "FullPlaybackTests") }
        defaults.removePersistentDomain(forName: "FullPlaybackTests")
        XCTAssertTrue(PlaybackPreferences.configuration(defaults: defaults).convertASS)
        XCTAssertEqual(PlaybackPreferences.configuration(defaults: defaults).remoteBitrate, 20_000_000)
        PlaybackPreferences.setASSConversion(false, defaults: defaults)
        XCTAssertFalse(PlaybackPreferences.configuration(defaults: defaults).convertASS)
        let rig = try rig()
        await start(rig)
        await rig.playback.selectTrack(id: 12, kind: .subtitle)
        XCTAssertEqual(rig.engine.base.loads.count, 1)
        XCTAssertFalse(rig.playback.subtitleCues.isEmpty)
        await rig.playback.stop()
    }
}

@MainActor
private final class FullTrackEngine: PlaybackEngine, PlaybackTrackSelecting {
    let base = MockPlaybackEngine()
    var nativeSelectionWorks = true
    var failNextSelection = false
    var selections: [(Int?, PlaybackTrack.Kind)] = []
    var events: AsyncStream<PlaybackEngineEvent> { base.events }
    var position: Duration { base.position }
    var canSeek: Bool { base.canSeek }
    func load(_ carrier: ResourceLoaderCarrier, startAt: Duration) async throws(APIError) {
        try await base.load(carrier, startAt: startAt)
    }
    func play() { base.play() }
    func pause() { base.pause() }
    func stop() { base.stop() }
    func seek(to position: Duration) async { await base.seek(to: position) }
    func selectNativeTrack(_ track: PlaybackTrack?, kind: PlaybackTrack.Kind, peers: [PlaybackTrack]) async -> Bool {
        selections.append((track?.id, kind))
        if failNextSelection {
            failNextSelection = false
            return false
        }
        return nativeSelectionWorks
    }
}

private actor FullPlaybackClient: JellyfinAPIClient {
    var calls: [APIRequest] = []
    let streams: [MediaStreamDTO]
    let direct: Bool
    let reasons: String
    let noCredential: Bool
    private var count = 0
    init(streams: [MediaStreamDTO], direct: Bool, reasons: String, noCredential: Bool) {
        self.streams = streams
        self.direct = direct
        self.reasons = reasons
        self.noCredential = noCredential
    }
    func send(_ request: APIRequest) async throws(APIError) -> Data {
        calls.append(request)
        if request.path == "/Users/Me" {
            return Data("{\"Configuration\":{\"AudioLanguagePreference\":\"fi\",\"SubtitleMode\":\"None\"}}".utf8)
        }
        if request.path.hasSuffix("Stream.vtt") {
            return Data("WEBVTT\n\n00:00.000 --> 00:03.000\n日本語 中文 한국어".utf8)
        }
        if request.path.contains("/Sessions/") { return Data() }
        do {
            // DTOs are intentionally decode-only, so fixtures retain their original JSON shape.
            let rawStreams = try JSONSerialization.jsonObject(
                with: Data(
                    """
                    [{"Index":0,"Type":"Video","Codec":"mpeg4"},
                     {"Index":2,"Type":"Audio","Codec":"aac","Language":"eng","IsDefault":true},
                     {"Index":5,"Type":"Audio","Codec":"eac3","Language":"fin"},
                     {"Index":8,"Type":"Subtitle","Codec":"subrip","Language":"fin","IsExternal":true},
                     {"Index":10,"Type":"Subtitle","Codec":"pgssub","Language":"fin","IsForced":true},
                     {"Index":12,"Type":"Subtitle","Codec":"ass","Language":"eng"},
                     {"Index":15,"Type":"Subtitle","Codec":"mov_text","Language":"eng"}]
                    """.utf8))
            if request.path.hasSuffix("PlaybackInfo") {
                count += 1
                let body = try jsonBody(request.body)
                let subtitle = body["SubtitleStreamIndex"] as? Int
                let profile = body["DeviceProfile"] as? [String: Any]
                let subtitleProfiles = profile?["SubtitleProfiles"] as? [[String: String]] ?? []
                let burn =
                    subtitle == 10
                    || (subtitle == 12
                        && subtitleProfiles.contains { $0["Format"] == "ass" && $0["Method"] == "Encode" })
                let copy = body["AllowVideoStreamCopy"] as? Bool ?? true
                let credential = noCredential ? "" : "&ApiKey=server-fixture"
                let url =
                    "/master.m3u8?VideoCodec=\(copy && !burn ? "copy" : "hevc")&AudioCodec=eac3&TranscodeReasons=\(reasons)\(credential)"
                return try JSONSerialization.data(withJSONObject: [
                    "PlaySessionId": "full-session-\(count)",
                    "MediaSources": [
                        [
                            "Id": pocSourceID, "Container": direct ? "mp4" : "mkv",
                            "SupportsDirectPlay": direct && !burn && body["EnableDirectPlay"] as? Bool == true,
                            "SupportsDirectStream": true, "SupportsTranscoding": true,
                            "TranscodingUrl": url, "MediaStreams": rawStreams,
                        ]
                    ],
                ])
            }
            return try JSONSerialization.data(withJSONObject: ["MediaStreams": rawStreams])
        } catch { throw .decoding }
    }
}

private actor FullPlaybackClock: GlassfinClock {
    private var continuation: CheckedContinuation<Void, any Error>?
    var isWaiting: Bool { continuation != nil }
    nonisolated func now() -> Duration { .zero }
    func sleep(for duration: Duration) async throws {
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

private struct SlowSubtitleClient: JellyfinAPIClient {
    func send(_ request: APIRequest) async throws(APIError) -> Data {
        do { try await Task.sleep(for: .seconds(60)) } catch { throw .cancelled }
        return Data()
    }
}
