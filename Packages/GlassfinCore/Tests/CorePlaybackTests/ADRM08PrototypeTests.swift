import CoreModels
import CoreNetworking
import CorePlayback
import Foundation
import Synchronization
import XCTest

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

#if os(macOS)
    import Network
    import Security
#endif

/// ADR M08-2. Each `T08-2-xx` id is in the test name. Device timings stay nil.
final class ADRM08PrototypeTests: XCTestCase {
    private let itemID = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    private let sourceID = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    private let token = "session-token"
    private let segmentSecret = "segment-secret"

    /// T08-2-01. Cases 1 and 2 only. Case 3 is M08b. Linux Docker does not play media.
    func testT08_2_01_prototypeCoversCasesOneAndTwo() {
        XCTAssertEqual(ADRM08Prototype.prototypeCases, [1, 2])
        XCTAssertEqual(ADRM08Prototype.case3Owner, "M08b")
        XCTAssertFalse(ADRM08Prototype.simulatorServer.isEmpty)
        XCTAssertEqual(
            ADRM08Prototype.linuxDockerScope,
            "URL construction, token placement, and PlaybackInfo only."
        )
        XCTAssertFalse(ADRM08Prototype.prototypeCases.contains(3))
    }

    /// T08-2-02. The loader asks the origin for a range with Authorization and no credential query.
    /// First-frame playback is not asserted: this run does not decode an MP4.
    func testT08_2_02_resourceLoaderRequestsRangeWithAuthorizationAndNoApiKey() async throws {
        let origin = mediaURL("https://media.example/Videos/\(itemID)/stream?static=true")
        let asset = try XCTUnwrap(MediaAssetScheme.wrap(origin))
        XCTAssertEqual(asset.scheme, MediaAssetScheme.name)
        let header = try playbackHeader()
        let request = try XCTUnwrap(
            ResourceLoadPlanner.originRequest(
                assetURL: asset,
                authorizationHeader: header,
                trust: .publiclyTrusted,
                range: HTTPByteRange(start: 0, end: 1),
                allowedHost: "media.example"
            )
        )
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.authorizationHeader, header)
        XCTAssertEqual(request.range?.headerValue, "bytes=0-1")
        XCTAssertEqual(HTTPByteRange(start: 8, end: nil).headerValue, "bytes=8-")
        XCTAssertFalse(leaked(request.url.absoluteString))
        XCTAssertNil(
            ResourceLoadPlanner.originRequest(
                assetURL: asset,
                authorizationHeader: header,
                trust: .publiclyTrusted,
                range: nil,
                allowedHost: "other.example"
            )
        )
        let response = OriginMediaResponse(
            status: 206,
            contentType: "video/mp4",
            body: Data([0, 1]),
            totalLength: 2
        )
        let reply = try XCTUnwrap(PlayerResponseBuilder.build(origin: response, requestURL: request.url))
        XCTAssertEqual(reply.contentTypeUTI, "public.mpeg-4")
        XCTAssertEqual(ContentRangeHeader.totalLength(of: "bytes 0-1/99"), 99)
        XCTAssertNil(ContentRangeHeader.totalLength(of: "bytes 0-1/*"))
        XCTAssertNil(ContentRangeHeader.totalLength(of: nil))
        let missing = OriginMediaResponse(status: 404)
        XCTAssertNil(PlayerResponseBuilder.build(origin: missing, requestURL: request.url))
        let roundTrip = try XCTUnwrap(MediaAssetScheme.unwrap(asset))
        XCTAssertEqual(roundTrip.absoluteString, origin.absoluteString)
        #if os(macOS)
            try await assertLocalHTTPFetchSeesAuthorizationWithoutCredentialQuery()
        #endif
    }

    /// T08-2-03. Scrub timing is a device measurement. No sample was recorded.
    func testT08_2_03_scrubTimingIsUnmeasured() {
        assertUnmeasuredDeviceLimits()
        XCTAssertEqual(PrototypeMeasurements.directPlayScrubLimitLAN, .milliseconds(1_000))
    }

    /// T08-2-04. First-frame timing is a device measurement. No sample was recorded.
    func testT08_2_04_firstFrameTimingIsUnmeasured() {
        assertUnmeasuredDeviceLimits()
        XCTAssertEqual(PrototypeMeasurements.directPlayStartLimitLAN, .milliseconds(1_500))
        XCTAssertEqual(PrototypeMeasurements.directPlayStartLimitOldest, .milliseconds(2_500))
    }

    /// T08-2-05. The header-key fallback uses the undocumented asset key.
    /// Segment behavior on tvOS 26 and 27 was not measured. Q8-2-11 stays open.
    func testT08_2_05_headerKeyFallbackUsesTheUndocumentedAssetKey() throws {
        let plan = try directPlan(trust: .publiclyTrusted, headerKey: true, apiKey: false)
        guard case .assetHeaderFields(let carrier) = plan.measuredFallbacks.first else {
            return XCTFail("header key fallback missing")
        }
        XCTAssertEqual(carrier.headerFieldsKey, ResolvedMediaURL.httpHeaderFieldsKey)
        XCTAssertTrue(plan.findings.contains(.headerFieldsKeyIsUndocumentedFallback))
        XCTAssertTrue(plan.findings.contains(.headerFieldsKeyDoesNotApplyPin))
        let described = String(describing: carrier)
        XCTAssertFalse(leaked(described), "header carrier description leaked a credential")
        XCTAssertNil(PrototypeMeasurements.recordedFirstFrame)
        let checklist = ADRM08Prototype.deviceChecklist.joined(separator: " ")
        XCTAssertTrue(checklist.contains("tvOS 26 and 27"))
    }

    /// T08-2-06. Query fallback carries ApiKey and refuses an Authorization header on the same URL.
    func testT08_2_06_queryFallbackNeverCombinesHeaderAndCredentialQuery() throws {
        let stripped = mediaURL("https://media.example/Videos/\(itemID)/stream?static=true")
        let fallback = try XCTUnwrap(MediaURLBuilder.queryCredentialFallback(strippedURL: stripped, token: token))
        XCTAssertTrue(MediaCredentialQuery.contains(fallback))
        XCTAssertNil(
            OriginMediaRequest(
                method: "GET",
                url: fallback,
                authorizationHeader: try playbackHeader(),
                trust: .publiclyTrusted
            )
        )
        let queryOnly = try XCTUnwrap(
            OriginMediaRequest(method: "GET", url: fallback, authorizationHeader: nil, trust: .publiclyTrusted)
        )
        XCTAssertNil(queryOnly.authorizationHeader)
        XCTAssertNil(MediaURLBuilder.queryCredentialFallback(strippedURL: fallback, token: token))
        XCTAssertNil(MediaURLBuilder.queryCredentialFallback(strippedURL: stripped, token: ""))
        XCTAssertNil(
            OriginMediaRequest(method: "GET", url: stripped, authorizationHeader: "", trust: .publiclyTrusted)
        )
        let prepared = try directPlayRequest()
        XCTAssertFalse(MediaCredentialQuery.contains(prepared.url))
        XCTAssertNotNil(prepared.authorizationHeader)
        XCTAssertFalse(prepared.usesAPIKeyQuery)
    }

    /// T08-2-07. Case 1 order is resource loader, then the header key, then a credential query.
    func testT08_2_07_caseOneOrderIsLoaderThenHeaderKeyThenQuery() throws {
        XCTAssertEqual(ADRM08Prototype.case1Order, ["resourceLoader", "assetHeaderFields", "apiKeyQuery"])
        let fallback = try queryFallback()
        let plan = try directPlan(trust: .publiclyTrusted, headerKey: true, apiKeyURL: fallback)
        XCTAssertEqual(plan.primary.kindName, "resourceLoader")
        XCTAssertEqual(plan.measuredFallbacks.map(\.kindName), ["assetHeaderFields", "apiKeyQuery"])
        let pinned = try directPlan(
            trust: .pinnedSelfSigned(fingerprintSHA256: fingerprint("ab")),
            headerKey: true,
            apiKeyURL: fallback
        )
        XCTAssertEqual(pinned.primary.kindName, "resourceLoader")
        XCTAssertTrue(pinned.measuredFallbacks.isEmpty)
        let unavailable = try directPlan(trust: .publiclyTrusted, headerKey: false, apiKey: false)
        XCTAssertTrue(unavailable.findings.contains(.headerFieldsKeyUnavailable))
        XCTAssertTrue(unavailable.findings.contains(.apiKeyFallbackDisabled))
        let blocked = MediaOpenPlanner.plan(
            delivery: .directFile,
            resolvedURL: mediaURL("https://media.example/v"),
            authorizationHeader: nil,
            options: MediaOpenOptions(trust: .publiclyTrusted, headerFieldsKeyAvailable: true)
        )
        XCTAssertEqual(blocked.primary, .blocked(.missingAuthorization))
        let unusable = MediaOpenPlanner.plan(
            delivery: .directFile,
            resolvedURL: mediaURL("ftp://media.example/v"),
            authorizationHeader: "header",
            options: MediaOpenOptions(trust: .publiclyTrusted, headerFieldsKeyAvailable: true)
        )
        XCTAssertEqual(unusable.primary, .blocked(.missingMediaURL))
    }

    /// T08-2-08. Plan text and the direct-play URL do not contain the token or a credential query.
    /// Jellyfin server logs are checked by the Docker test when integration is enabled.
    func testT08_2_08_planDescriptionAndURLOmitTheAccessToken() throws {
        let prepared = try directPlayRequest()
        let handoff = PlaybackHandoff.make(prepared)
        let fallback = try queryFallback()
        let direct = try directPlan(trust: .publiclyTrusted, headerKey: true, apiKeyURL: fallback)
        let hls = try hlsPlan(trust: .publiclyTrusted, headerKey: true, apiKeyURL: fallback)
        let blob = [
            prepared.url.absoluteString,
            prepared.description,
            handoff.description,
            direct.description,
            hls.description,
            String(describing: direct),
            String(describing: hls),
        ].joined(separator: "\n")
        XCTAssertFalse(leaked(blob), "plan text leaked a credential")
        XCTAssertFalse(handoff.usesAPIKeyQueryFallback)
        XCTAssertFalse(MediaCredentialQuery.contains(prepared.url))
        do {
            _ = try MediaURLBuilder.directPlay(
                server: mediaURL("https://media.example"),
                identity: playbackIdentity(),
                itemID: "not-an-id",
                mediaSourceID: sourceID,
                playSessionID: "play-1"
            )
            XCTFail("invalid item id was accepted")
        } catch let error {
            XCTAssertEqual(error, .invalidItemID)
        }
    }

    /// T08-2-09. Pinned direct play stays on the resource loader. The gate allows only the same leaf.
    func testT08_2_09_pinnedDirectPlayUsesTheResourceLoaderAndMatchingFingerprint() async throws {
        let pin = fingerprint("ab")
        let plan = try directPlan(trust: .pinnedSelfSigned(fingerprintSHA256: pin), headerKey: true, apiKey: true)
        guard case .resourceLoader(let carrier) = plan.primary else {
            return XCTFail("pinned direct play was not a resource loader")
        }
        XCTAssertEqual(carrier.assetURL.scheme, MediaAssetScheme.name)
        XCTAssertFalse(leaked(carrier.originURL.absoluteString))
        XCTAssertFalse(MediaCredentialQuery.contains(carrier.originURL))
        XCTAssertTrue(plan.measuredFallbacks.isEmpty)
        XCTAssertTrue(plan.findings.contains(.pinnedTrustAppliesOnlyToLoaderFetches))
        XCTAssertTrue(plan.findings.contains(.apiKeyDoesNotFixTLS))
        let spaced = spacedFingerprint(pin)
        XCTAssertEqual(PinnedTrustGate.normalizeFingerprint(spaced.uppercased()), pin)
        let trust = ServerTrustClass.pinnedSelfSigned(fingerprintSHA256: pin)
        XCTAssertEqual(PinnedTrustGate.decide(trust: trust, observedFingerprintSHA256: pin), .allowPinned)
        let publicVerdict = PinnedTrustGate.decide(trust: .publiclyTrusted, observedFingerprintSHA256: nil)
        XCTAssertEqual(publicVerdict, .performDefaultHandling)
        #if os(macOS)
            try await assertPinnedLeafAllowsFetchAndMismatchCancels()
        #endif
    }

    /// T08-2-10. A changed leaf is cancelled. The token stays, and this is not the 401 logout path.
    func testT08_2_10_pinMismatchCancelsWithoutClearingTheToken() {
        let trust = ServerTrustClass.pinnedSelfSigned(fingerprintSHA256: fingerprint("ab"))
        let verdict = PinnedTrustGate.decide(trust: trust, observedFingerprintSHA256: fingerprint("cd"))
        XCTAssertEqual(verdict, .cancel)
        XCTAssertNil(PinnedTrustGate.normalizeFingerprint("abcd"))
        XCTAssertEqual(PinnedTrustGate.decide(trust: .cleartext, observedFingerprintSHA256: fingerprint("ab")), .cancel)
        XCTAssertEqual(
            PinnedTrustGate.decide(trust: .unpinnedSelfSigned, observedFingerprintSHA256: fingerprint("ab")),
            .cancel
        )
        let outcome = ResourceLoaderFailurePolicy.outcome(status: nil, timedOut: false)
        XCTAssertEqual(outcome, LoaderOutcome(terminal: .failed, tokenCleared: false))
        XCTAssertFalse(LogoutPolicy.shouldLogOut(.tls))
        XCTAssertNotEqual(MediaStatusPolicy.decide(status: 495), .checkCurrentUser)
    }

    /// T08-2-11. Unpinned self-signed playback is blocked and does not open a loader, so no token is sent.
    func testT08_2_11_unpinnedSelfSignedSendsNoToken() throws {
        let direct = try directPlan(trust: .unpinnedSelfSigned, headerKey: true, apiKey: true)
        XCTAssertEqual(direct.primary, .blocked(.unpinnedSelfSigned))
        XCTAssertTrue(direct.measuredFallbacks.isEmpty)
        XCTAssertNil(direct.insufficientPinnedPlaylistFetch)
        XCTAssertFalse(leaked(direct.description), "blocked plan leaked a credential")
        let hls = try hlsPlan(trust: .unpinnedSelfSigned, headerKey: true, apiKey: true)
        XCTAssertEqual(hls.primary, .blocked(.unpinnedSelfSigned))
        XCTAssertTrue(hls.findings.contains(.apiKeyDoesNotFixTLS))
    }

    /// T08-2-12. Cleartext direct play still uses the loader. ATS allows local networking only.
    func testT08_2_12_cleartextDirectPlayUsesTheLoaderWithoutArbitraryLoads() throws {
        let plan = try directPlan(trust: .cleartext, headerKey: true, apiKey: false)
        XCTAssertEqual(plan.primary.kindName, "resourceLoader")
        XCTAssertTrue(plan.findings.contains(.cleartextHasNoCertificatePin))
        try assertLocalNetworkingPlists()
    }

    /// T08-2-13. A server mounted at /jellyfin keeps that prefix on a relative transcoding URL.
    func testT08_2_13_transcodingURLKeepsTheServerSubpath() throws {
        let resolved = try XCTUnwrap(
            MediaURLBuilder.resolveTranscodingURL(
                server: mediaURL("https://host/jellyfin"),
                transcodingURL: "/Videos/\(itemID)/master.m3u8?id=1"
            )
        )
        XCTAssertEqual(resolved.path, "/jellyfin/Videos/\(itemID)/master.m3u8")
        XCTAssertEqual(resolved.host, "host")
        XCTAssertTrue(resolved.query?.contains("id=1") == true)
    }

    /// T08-2-14. Credential query names are stripped without regard to case. Innocent items stay.
    func testT08_2_14_headerPathStripsCredentialQueriesIgnoringCase() async throws {
        let legacy = "api" + "_key"
        let raw = mediaURL(
            "https://user:\(segmentSecret)@media.example/v?ApiKey=\(segmentSecret)&\(legacy)=\(segmentSecret)"
                + "&apikey=\(segmentSecret)&API_KEY=\(segmentSecret)&Token=\(segmentSecret)"
                + "&secret=\(segmentSecret)&pw=\(segmentSecret)&accesstoken=\(segmentSecret)&playSessionId=keep"
        )
        XCTAssertTrue(MediaCredentialQuery.contains(raw))
        let stripped = MediaCredentialQuery.stripping(raw)
        XCTAssertFalse(leaked(stripped.absoluteString))
        XCTAssertNil(stripped.user)
        XCTAssertTrue(stripped.absoluteString.contains("playSessionId=keep"))
        XCTAssertTrue(MediaCredentialQuery.isCredentialName("API_KEY"))
        XCTAssertTrue(MediaCredentialQuery.isCredentialName(legacy))
        XCTAssertFalse(MediaCredentialQuery.isCredentialName("playSessionId"))
        let client = ScriptedOrigin([ok()])
        let log = CapturingLog()
        let resolver = PlaybackURLResolver(client: client, log: log)
        let resolution = try await resolver.resolve(
            start: raw,
            method: "GET",
            authorizationHeader: try playbackHeader(),
            trust: .publiclyTrusted
        )
        guard case .resolved(let final) = resolution else {
            return XCTFail("header resolve failed")
        }
        XCTAssertFalse(leaked(final.absoluteString))
        XCTAssertFalse(leaked(client.requests()[0].url.absoluteString))
        XCTAssertNotNil(client.requests()[0].authorizationHeader)
        let crafted = credentialAssetURL()
        XCTAssertNil(MediaAssetScheme.unwrap(crafted))
        XCTAssertNil(MediaAssetScheme.wrap(mediaURL("ftp://media.example/a")))
    }

    /// T08-2-15. The loader is documented to see playlists and keys, not segment bytes.
    /// A device trace on tvOS 26 and 27 was not run.
    func testT08_2_15_loaderSeesPlaylistsAndKeysOnly() throws {
        let plan = try hlsPlan(trust: .publiclyTrusted, headerKey: true, apiKey: false)
        XCTAssertEqual(plan.primary.kindName, "resourceLoader")
        XCTAssertTrue(plan.findings.contains(.resourceLoaderSeesPlaylistsAndKeysOnly))
        XCTAssertTrue(plan.findings.contains(.hlsSegmentBytesCannotBeServedByResourceLoader))
        XCTAssertTrue(plan.findings.contains(.headerFieldsKeySegmentBehaviorUnverified))
        let clear = try hlsPlan(trust: .cleartext, headerKey: false, apiKey: false)
        XCTAssertTrue(clear.findings.contains(.cleartextHasNoCertificatePin))
        XCTAssertTrue(clear.findings.contains(.hlsSegmentsStayOnServerURLs))
        XCTAssertNil(PrototypeMeasurements.recordedFirstFrame)
    }

    /// T08-2-16. Playlist and key URIs move to glassfin-media. Segments stay on the playlist origin.
    func testT08_2_16_playlistRewriteRejectsOtherOriginsAndDowngrades() throws {
        let base = mediaURL("https://media.example/jellyfin/videos/\(itemID)/master.m3u8")
        let playlist = """
            #EXTM3U
            #EXT-X-VERSION:7
            #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="en",URI="audio.m3u8"
            #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="s",NAME="en",URI="subs.m3u8"
            #EXT-X-STREAM-INF:BANDWIDTH=1000
            variant.m3u8
            #EXT-X-KEY:METHOD=AES-128,URI="key.key?ApiKey=\(segmentSecret)"
            #EXT-X-SESSION-KEY:METHOD=AES-128,URI="session.key"
            #EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=1000,URI="iframe.m3u8"
            #EXT-X-MAP:URI="init.mp4"
            #EXT-X-PART:URI="part.mp4"
            #EXT-X-PRELOAD-HINT:TYPE=PART,URI="next.mp4"
            seg-0.ts
            https://media.example/jellyfin/videos/\(itemID)/abs.ts?ApiKey=\(segmentSecret)

            """
        let rewrite = try XCTUnwrap(successRewrite(HLSPlaylistRewriter.rewrite(playlist: playlist, baseURL: base)))
        XCTAssertFalse(leaked(rewrite.description), "rewrite description contained a credential")
        XCTAssertGreaterThan(rewrite.rewritten, 0)
        XCTAssertGreaterThan(rewrite.untouchedSegments, 0)
        let wrapped = wrappedOrigins(in: rewrite.playlist)
        XCTAssertFalse(wrapped.isEmpty)
        for origin in wrapped {
            XCTAssertTrue(MediaOrigin.matches(origin, base))
            XCTAssertFalse(leaked(origin.absoluteString), "wrapped URI kept a credential")
        }
        XCTAssertTrue(rewrite.playlist.contains("https://media.example/jellyfin/videos/\(itemID)/seg-0.ts"))
        XCTAssertTrue(rewrite.playlist.contains("abs.ts?ApiKey="))
        let withBreaks = "\u{feff}" + playlist.replacingOccurrences(of: "\n", with: "\r\n")
        let crlf = HLSPlaylistRewriter.rewrite(playlist: withBreaks, baseURL: base)
        XCTAssertEqual(successRewrite(crlf)?.rewritten, rewrite.rewritten)
        let variantBase = mediaURL("https://media.example/jellyfin/videos/\(itemID)/variant.m3u8")
        let variantRewrite = HLSPlaylistRewriter.rewrite(playlist: "seg-1.ts\n", baseURL: variantBase)
        let variant = try XCTUnwrap(successRewrite(variantRewrite))
        XCTAssertTrue(variant.playlist.contains("https://media.example/jellyfin/videos/\(itemID)/seg-1.ts"))
        XCTAssertFalse(variant.playlist.contains("master.m3u8"))
        let cross = HLSPlaylistRewriter.rewrite(playlist: "#EXTM3U\nhttps://cdn.example/a.ts\n", baseURL: base)
        XCTAssertEqual(cross, .failure(.crossOrigin))
        let downgrade = HLSPlaylistRewriter.rewrite(
            playlist: "#EXTM3U\nhttp://media.example/jellyfin/videos/\(itemID)/a.ts\n",
            baseURL: base
        )
        XCTAssertEqual(downgrade, .failure(.httpsDowngrade))
        let broken = HLSPlaylistRewriter.rewrite(playlist: "http://[\n", baseURL: base)
        XCTAssertEqual(broken, .failure(.unresolvable))
        let rejected = OriginMediaResponse(
            status: 200,
            contentType: "application/vnd.apple.mpegurl",
            body: Data("#EXTM3U\nhttps://cdn.example/a.ts\n".utf8)
        )
        XCTAssertNil(PlayerResponseBuilder.build(origin: rejected, requestURL: base))
        let sniffed = OriginMediaResponse(status: 200, body: Data("#EXTM3U\nseg-0.ts\n".utf8))
        XCTAssertNotNil(PlayerResponseBuilder.build(origin: sniffed, requestURL: base))
        let audio = OriginMediaResponse(status: 200, contentType: "audio/mp4", body: Data([1]))
        let audioReply = try XCTUnwrap(PlayerResponseBuilder.build(origin: audio, requestURL: base))
        XCTAssertEqual(audioReply.contentTypeUTI, "public.mpeg-4")
        let binary = OriginMediaResponse(status: 200, contentType: "application/octet-stream", body: Data([1]))
        let binaryReply = try XCTUnwrap(PlayerResponseBuilder.build(origin: binary, requestURL: base))
        XCTAssertEqual(binaryReply.contentTypeUTI, "public.data")
        let movie = mediaURL("https://media.example/clip.mov")
        let movieReply = try XCTUnwrap(
            PlayerResponseBuilder.build(origin: OriginMediaResponse(status: 200, body: Data([1])), requestURL: movie)
        )
        XCTAssertEqual(movieReply.contentTypeUTI, "com.apple.quicktime-movie")
    }

    /// T08-2-17. A server-written segment credential stays only when redaction and S4.6 are both on.
    func testT08_2_17_segmentCredentialRequiresRedactionAndRedirectRules() {
        XCTAssertTrue(SegmentCredentialPolicy.mayLeaveServerCredential(redactionOn: true, redirectRulesOn: true))
        XCTAssertFalse(SegmentCredentialPolicy.mayLeaveServerCredential(redactionOn: false, redirectRulesOn: true))
        XCTAssertFalse(SegmentCredentialPolicy.mayLeaveServerCredential(redactionOn: true, redirectRulesOn: false))
        XCTAssertFalse(SegmentCredentialPolicy.mayLeaveServerCredential(redactionOn: false, redirectRulesOn: false))
    }

    /// T08-2-18. Transcode start timing is a device measurement. No sample was recorded.
    func testT08_2_18_transcodeStartTimingIsUnmeasured() {
        assertUnmeasuredDeviceLimits()
        XCTAssertEqual(PrototypeMeasurements.transcodeStartLimitLAN, .milliseconds(4_000))
    }

    /// T08-2-19. Case 2 scrub limit is unresolved (Q8-2-04). No sample was recorded.
    func testT08_2_19_caseTwoScrubLimitStaysUnresolved() {
        assertUnmeasuredDeviceLimits()
        XCTAssertTrue(PrototypeMeasurements.case2ScrubLimitUnresolved)
    }

    /// T08-2-20. Pinned HLS is blocked. Segments would bypass the pin. Loopback is M08b.
    func testT08_2_20_pinnedHLSIsBlockedUntilLoopbackExists() throws {
        let plan = try hlsPlan(
            trust: .pinnedSelfSigned(fingerprintSHA256: fingerprint("ab")),
            headerKey: true,
            apiKey: true
        )
        XCTAssertEqual(plan.primary, .blocked(.hlsSegmentsBypassPinnedTrust))
        XCTAssertTrue(plan.measuredFallbacks.isEmpty)
        XCTAssertNotNil(plan.insufficientPinnedPlaylistFetch)
        XCTAssertTrue(plan.findings.contains(.selfSignedHLSNeedsLoopbackProxy))
        XCTAssertTrue(plan.findings.contains(.serverApiKeyOnSegmentsIsAcceptedRisk))
        XCTAssertFalse(leaked(plan.description), "pinned HLS plan leaked a credential")
    }

    /// T08-2-21. The M08b player URL has a path token and no Jellyfin credential.
    /// The source fetch (header, pin, S4.6) is specified and not executed here.
    func testT08_2_21_loopbackPlayerURLOmitsTheJellyfinToken() throws {
        let pathToken = try XCTUnwrap(LoopbackPathToken.make(bytes: Array(repeating: 0xab, count: 16)))
        let url = try XCTUnwrap(LoopbackRemuxContract.playerURL(port: 9, pathToken: pathToken, mediaID: itemID))
        XCTAssertEqual(url.scheme, "http")
        XCTAssertEqual(url.host, "127.0.0.1")
        XCTAssertFalse(MediaCredentialQuery.contains(url))
        XCTAssertFalse(url.absoluteString.contains(token))
        XCTAssertEqual(LoopbackRemuxContract.owner, "M08b")
        XCTAssertNil(LoopbackRemuxContract.playerURL(port: 0, pathToken: pathToken, mediaID: itemID))
        XCTAssertNil(LoopbackRemuxContract.playerURL(port: 9, pathToken: "short", mediaID: itemID))
        XCTAssertNil(LoopbackRemuxContract.playerURL(port: 9, pathToken: pathToken, mediaID: "not-an-id"))
    }

    /// T08-2-22. Pinned case 3 is an M08b requirement. This prototype does not play loopback HLS.
    func testT08_2_22_pinnedLoopbackPlaybackIsNotInThisPrototype() {
        XCTAssertEqual(ADRM08Prototype.prototypeCases, [1, 2])
        XCTAssertEqual(LoopbackRemuxContract.owner, "M08b")
        XCTAssertFalse(ADRM08Prototype.prototypeCases.contains(3))
    }

    /// T08-2-23. Case 3 start and scrub numbers belong to M08b and were not measured.
    func testT08_2_23_loopbackDeviceTimingsAreUnmeasured() {
        assertUnmeasuredDeviceLimits()
        XCTAssertEqual(LoopbackRemuxContract.owner, "M08b")
    }

    /// T08-2-24. Bind is loopback only. The path token compare does not stop at the first difference.
    func testT08_2_24_loopbackBindsLoopbackHostsAndComparesTokensInConstantTime() throws {
        XCTAssertTrue(LoopbackRemuxContract.allowsBindHost("127.0.0.1"))
        XCTAssertTrue(LoopbackRemuxContract.allowsBindHost("::1"))
        XCTAssertFalse(LoopbackRemuxContract.allowsBindHost("192.168.1.5"))
        XCTAssertFalse(LoopbackRemuxContract.allowsBindHost("0.0.0.0"))
        XCTAssertFalse(LoopbackRemuxContract.allowsBindHost("localhost"))
        let bytes = [UInt8](repeating: 1, count: 16)
        let token = try XCTUnwrap(LoopbackPathToken.make(bytes: bytes))
        XCTAssertTrue(LoopbackPathToken.isValid(token))
        XCTAssertTrue(LoopbackPathToken.equals(token, token))
        var chars = Array(token)
        chars[0] = chars[0] == "0" ? "1" : "0"
        XCTAssertFalse(LoopbackPathToken.equals(token, String(chars)))
        XCTAssertFalse(LoopbackPathToken.equals(token, "ab"))
        XCTAssertFalse(LoopbackPathToken.equals("ab", token))
        XCTAssertNil(LoopbackPathToken.make(bytes: [1]))
        XCTAssertTrue(LoopbackRemuxContract.allows(method: "GET", mediaID: itemID, knownMediaIDs: [itemID]))
        XCTAssertTrue(LoopbackRemuxContract.allows(method: "HEAD", mediaID: itemID, knownMediaIDs: [itemID]))
        XCTAssertFalse(LoopbackRemuxContract.allows(method: "POST", mediaID: itemID, knownMediaIDs: [itemID]))
        XCTAssertFalse(LoopbackRemuxContract.allows(method: "GET", mediaID: sourceID, knownMediaIDs: [itemID]))
        XCTAssertFalse(LoopbackRemuxContract.allows(method: "GET", mediaID: "not-an-id", knownMediaIDs: ["not-an-id"]))
        XCTAssertEqual(LoopbackRemuxContract.allowedMethods, ["GET", "HEAD"])
    }

    /// T08-2-25. The loopback player URL is http on 127.0.0.1, and ATS does not allow arbitrary loads.
    func testT08_2_25_loopbackURLIsLocalHTTPWithoutArbitraryLoads() throws {
        let pathToken = try XCTUnwrap(LoopbackPathToken.make(bytes: Array(repeating: 0x11, count: 16)))
        let url = try XCTUnwrap(LoopbackRemuxContract.playerURL(port: 49_152, pathToken: pathToken, mediaID: itemID))
        XCTAssertEqual(url.scheme, "http")
        XCTAssertEqual(url.host, "127.0.0.1")
        XCTAssertEqual(url.port, 49_152)
        try assertLocalNetworkingPlists()
    }

    /// T08-2-26. Media logs replace credential queries, Authorization, and Token quotes with <redacted>.
    func testT08_2_26_mediaLogsReplaceCredentialsWithRedacted() throws {
        let legacy = "api" + "_key"
        let input =
            "https://media.example/v?ApiKey=\(segmentSecret)&\(legacy)=\(segmentSecret)"
            + "&Token=\(segmentSecret)&apikey=\(segmentSecret)&API_KEY=\(segmentSecret)"
        let redacted = MediaLogRedactor.redact(input)
        XCTAssertFalse(leaked(redacted, secret: segmentSecret), "media log kept a credential")
        XCTAssertTrue(redacted.contains("<redacted>"))
        let header = "Authorization: MediaBrowser Token=\"\(segmentSecret)\""
        let hiddenHeader = MediaLogRedactor.redact(header)
        XCTAssertFalse(leaked(hiddenHeader, secret: segmentSecret), "authorization log kept a credential")
        XCTAssertTrue(hiddenHeader.contains("<redacted>"))
        let failing = mediaURL("https://media.example/v?ApiKey=\(segmentSecret)")
        let error = URLError(.badURL, userInfo: [NSURLErrorFailingURLErrorKey: failing])
        let errorText = MediaLogRedactor.redact(urlError: error)
        XCTAssertFalse(leaked(errorText, secret: segmentSecret), "URLError log kept a credential")
        let sink = CapturingLog()
        let playback = PlaybackLog(sink: sink)
        playback.debug(input)
        playback.warning(header)
        playback.error("Token=\"\(segmentSecret)\"")
        let joined = sink.lines().joined(separator: "\n")
        XCTAssertFalse(leaked(joined, secret: segmentSecret), "playback log kept a credential")
        XCTAssertTrue(joined.contains("<redacted>"))
    }

    /// T08-2-27. Player log URIs use the same redactor. A live AVPlayerItem error log was not populated.
    func testT08_2_27_playerLogSinkRedactsErrorAndAccessURIs() {
        let sink = CapturingLog()
        PlayerLogSink.record(
            ["https://media.example/v?ApiKey=\(segmentSecret)", nil, "Token=\"\(segmentSecret)\""],
            log: sink
        )
        let joined = sink.lines().joined(separator: "\n")
        XCTAssertFalse(leaked(joined, secret: segmentSecret), "player log kept a credential")
        XCTAssertEqual(sink.lines().count, 2)
        XCTAssertTrue(joined.contains("<redacted>"))
    }

    /// T08-2-28. Playback log calls that mention a URL also run it through MediaLogRedactor.
    func testT08_2_28_playbackLogCallsRedactAbsoluteURLs() throws {
        let root = corePlaybackSources()
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var inspected = 0
        for file in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let row = String(line)
                let isLog = row.contains("log.debug(") || row.contains("log.warning(") || row.contains("log.error(")
                guard isLog else { continue }
                inspected += 1
                if row.contains("absoluteString") || row.contains("http") {
                    XCTAssertTrue(row.contains("MediaLogRedactor.redact"), "\(file.lastPathComponent):\(index + 1)")
                }
            }
        }
        XCTAssertGreaterThan(inspected, 0)
    }

    /// T08-2-29. CorePlayback constructs an ApiKey query item only in MediaURLBuilder.
    /// The socket regression stays T01-25.
    func testT08_2_29_apiKeyQueryItemIsOnlyBuiltInMediaURLBuilder() throws {
        let root = corePlaybackSources()
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var hits: [String] = []
        for file in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains("name: \"ApiKey\"") {
                hits.append(file.lastPathComponent)
            }
        }
        XCTAssertEqual(hits, ["MediaURLBuilder.swift"])
    }

    /// T08-2-30. A fake JUnit line loses ApiKey and Token values before it could be archived.
    func testT08_2_30_redactorClearsCredentialPatternsInArtifactText() {
        let legacy = "api" + "_key"
        let line = "failure ApiKey=\(segmentSecret) Token=\"\(segmentSecret)\" \(legacy)=\(segmentSecret)"
        let redacted = MediaLogRedactor.redact(line)
        XCTAssertFalse(leaked(redacted, secret: segmentSecret), "artifact text kept a credential")
        XCTAssertTrue(redacted.contains("<redacted>"))
    }

    /// T08-2-31. Direct play probes with HEAD and gives AVPlayer the final URL only.
    /// A 405 or 501 retries GET once (Q8-2-05).
    func testT08_2_31_directPlayHeadResolvesToTheFinalURL() async throws {
        let prepared = try directPlayRequest()
        let client = ScriptedOrigin([ok()])
        let preparation = PlaybackPreparation(client: client, log: CapturingLog())
        let opened = try await preparation.prepare(
            delivery: .directFile,
            initialURL: prepared.url,
            authorizationHeader: prepared.authorizationHeader,
            options: MediaOpenOptions(trust: .publiclyTrusted, headerFieldsKeyAvailable: true)
        )
        guard case .open(let plan) = opened else { return XCTFail("direct play did not open") }
        XCTAssertEqual(client.requests().map(\.method), ["HEAD"])
        guard case .resourceLoader(let carrier) = plan.primary else {
            return XCTFail("resolved direct play was not a loader")
        }
        let unwrapped = try XCTUnwrap(MediaAssetScheme.unwrap(carrier.assetURL))
        XCTAssertEqual(unwrapped.absoluteString, prepared.url.absoluteString)
        XCTAssertFalse(MediaCredentialQuery.contains(unwrapped))
        let retry = ScriptedOrigin([ok(405), ok()])
        let retried = try await PlaybackURLResolver(client: retry, log: SilentLog()).resolve(
            start: prepared.url,
            method: "HEAD",
            authorizationHeader: prepared.authorizationHeader,
            trust: .publiclyTrusted
        )
        guard case .resolved = retried else { return XCTFail("405 retry did not resolve") }
        XCTAssertEqual(retry.requests().map(\.method), ["HEAD", "GET"])
        let notImplemented = ScriptedOrigin([ok(501), ok(405)])
        let second = try await PlaybackURLResolver(client: notImplemented, log: SilentLog()).resolve(
            start: prepared.url,
            method: "HEAD",
            authorizationHeader: prepared.authorizationHeader,
            trust: .publiclyTrusted
        )
        XCTAssertEqual(second, .rejected(.transport(status: 405)))
        XCTAssertEqual(notImplemented.requests().map(\.method), ["HEAD", "GET"])
        let missing = try await PlaybackURLResolver(client: ScriptedOrigin([]), log: SilentLog()).resolve(
            start: prepared.url,
            method: "HEAD",
            authorizationHeader: nil,
            trust: .publiclyTrusted
        )
        XCTAssertEqual(missing, .rejected(.missingAuthorization))
        let empty = try await PlaybackURLResolver(client: ScriptedOrigin([]), log: SilentLog()).resolve(
            start: prepared.url,
            method: "HEAD",
            authorizationHeader: "",
            trust: .publiclyTrusted
        )
        XCTAssertEqual(empty, .rejected(.missingAuthorization))
    }

    /// T08-2-32. HLS resolves the master with GET and keeps only the final URL.
    func testT08_2_32_hlsGetResolvesTheMasterPlaylist() async throws {
        XCTAssertEqual(PlaybackTransportSelector.delivery(method: .directPlay, hasURL: false), .directFile)
        XCTAssertEqual(PlaybackTransportSelector.delivery(method: .directStream, hasURL: true), .serverHLS)
        XCTAssertEqual(PlaybackTransportSelector.delivery(method: .transcode, hasURL: true), .serverHLS)
        XCTAssertNil(PlaybackTransportSelector.delivery(method: .transcode, hasURL: false))
        let master = mediaURL("https://media.example/jellyfin/Videos/\(itemID)/master.m3u8")
        let client = ScriptedOrigin([ok(200, body: Data("#EXTM3U\n".utf8), type: "application/vnd.apple.mpegurl")])
        let opened = try await PlaybackPreparation(client: client).prepare(
            delivery: .serverHLS,
            initialURL: master,
            authorizationHeader: try playbackHeader(),
            options: MediaOpenOptions(trust: .publiclyTrusted, headerFieldsKeyAvailable: false)
        )
        guard case .open(let plan) = opened, case .resourceLoader(let carrier) = plan.primary else {
            return XCTFail("HLS did not open on the loader")
        }
        XCTAssertEqual(client.requests().map(\.method), ["GET"])
        XCTAssertEqual(carrier.originURL.absoluteString, master.absoluteString)
        XCTAssertEqual(carrier.segmentPolicy, .leaveServerURLs)
    }

    /// T08-2-33. A cross-origin redirect, including a port change, is not given to AVPlayer.
    func testT08_2_33_crossOriginRedirectIsRejectedBeforeTheNextFetch() async throws {
        let start = mediaURL("https://media.example:8096/Videos/\(itemID)/stream")
        let elsewhere = mediaURL("https://media.example:8080/Videos/\(itemID)/stream")
        let client = ScriptedOrigin([ok(302, location: elsewhere), ok()])
        let header = try playbackHeader()
        let resolution = try await PlaybackURLResolver(client: client, log: CapturingLog()).resolve(
            start: start,
            method: "HEAD",
            authorizationHeader: header,
            trust: .publiclyTrusted
        )
        XCTAssertEqual(resolution, .rejected(.insecureRedirect))
        XCTAssertEqual(client.requests().count, 1)
        let otherHost = mediaURL("https://cdn.example/Videos/\(itemID)/stream")
        let schemeChange = ScriptedOrigin([ok(302, location: otherHost)])
        let changed = try await PlaybackURLResolver(client: schemeChange, log: SilentLog()).resolve(
            start: start,
            method: "HEAD",
            authorizationHeader: header,
            trust: .publiclyTrusted
        )
        XCTAssertEqual(changed, .rejected(.insecureRedirect))
        XCTAssertEqual(schemeChange.requests().count, 1)
        let credential = mediaURL("https://media.example:8096/v?ApiKey=\(segmentSecret)")
        let queryClient = ScriptedOrigin([ok(302, location: elsewhere)])
        let query = try await PlaybackURLResolver(client: queryClient, log: SilentLog()).resolve(
            start: credential,
            method: "GET",
            authorizationHeader: header,
            trust: .publiclyTrusted,
            mode: .queryCredential
        )
        XCTAssertEqual(query, .rejected(.insecureRedirect))
        XCTAssertEqual(queryClient.requests().count, 1)
        XCTAssertEqual(queryClient.requests()[0].url.host, "media.example")
        XCTAssertNil(queryClient.requests()[0].authorizationHeader)
        let preparation = try await PlaybackPreparation(client: ScriptedOrigin([ok(302, location: elsewhere)])).prepare(
            delivery: .directFile,
            initialURL: start,
            authorizationHeader: header,
            options: MediaOpenOptions(trust: .publiclyTrusted, headerFieldsKeyAvailable: true)
        )
        XCTAssertEqual(preparation, .rejected(.insecureRedirect))
    }

    /// T08-2-34. HTTPS→HTTP is rejected on a LAN address and in header mode.
    func testT08_2_34_httpsDowngradeIsRejected() async throws {
        let start = mediaURL("https://192.168.1.20/Videos/\(itemID)/stream")
        let downgrade = mediaURL("http://192.168.1.20/Videos/\(itemID)/stream")
        let client = ScriptedOrigin([ok(302, location: downgrade), ok()])
        let resolution = try await PlaybackURLResolver(client: client, log: SilentLog()).resolve(
            start: start,
            method: "HEAD",
            authorizationHeader: try playbackHeader(),
            trust: .publiclyTrusted
        )
        XCTAssertEqual(resolution, .rejected(.insecureRedirect))
        XCTAssertEqual(client.requests().count, 1)
        XCTAssertTrue(MediaOrigin.isHTTPSDowngrade(start, downgrade))
    }

    /// T08-2-35. One same-origin redirect keeps ApiKey. The sixth redirect fails closed.
    func testT08_2_35_sameOriginRedirectKeepsApiKeyAndSixthHopFails() async throws {
        let start = mediaURL("https://media.example/v?ApiKey=\(segmentSecret)")
        let next = mediaURL("https://media.example/final")
        let client = ScriptedOrigin([ok(302, location: next), ok()])
        let resolution = try await PlaybackURLResolver(client: client, log: SilentLog()).resolve(
            start: start,
            method: "GET",
            authorizationHeader: "must-not-be-sent",
            trust: .publiclyTrusted,
            mode: .queryCredential
        )
        guard case .resolved(let final) = resolution else { return XCTFail("same-origin redirect failed") }
        XCTAssertTrue(final.absoluteString.contains("ApiKey="))
        let headerLeaked = final.absoluteString.contains("must-not-be-sent")
        XCTAssertFalse(headerLeaked, "resolved URL contained the authorization value")
        XCTAssertEqual(client.requests().count, 2)
        XCTAssertNil(client.requests()[0].authorizationHeader)
        XCTAssertNil(client.requests()[1].authorizationHeader)
        XCTAssertTrue(MediaCredentialQuery.contains(client.requests()[1].url))
        let already = mediaURL("https://media.example/final?ApiKey=kept")
        let kept = ScriptedOrigin([ok(302, location: already), ok()])
        _ = try await PlaybackURLResolver(client: kept, log: SilentLog()).resolve(
            start: start,
            method: "GET",
            authorizationHeader: nil,
            trust: .publiclyTrusted,
            mode: .queryCredential
        )
        XCTAssertEqual(kept.requests()[1].url.absoluteString, already.absoluteString)
        let relative = ScriptedOrigin([ok(302, location: mediaURL("/final")), ok()])
        let relativeResult = try await PlaybackURLResolver(client: relative, log: SilentLog()).resolve(
            start: mediaURL("https://media.example/v"),
            method: "GET",
            authorizationHeader: nil,
            trust: .publiclyTrusted,
            mode: .queryCredential
        )
        guard case .resolved(let relativeURL) = relativeResult else { return XCTFail("relative redirect failed") }
        XCTAssertEqual(relativeURL.path, "/final")
        var hops: [Result<OriginMediaResponse, APIError>] = []
        for index in 1...6 {
            hops.append(ok(302, location: mediaURL("https://media.example/h\(index)")))
        }
        let limited = ScriptedOrigin(hops)
        let tooMany = try await PlaybackURLResolver(client: limited, log: CapturingLog()).resolve(
            start: mediaURL("https://media.example/h0"),
            method: "GET",
            authorizationHeader: try playbackHeader(),
            trust: .publiclyTrusted
        )
        XCTAssertEqual(tooMany, .rejected(.tooManyHops))
        XCTAssertEqual(limited.requests().count, 6)
        let loop = ScriptedOrigin([ok(302, location: mediaURL("https://media.example/again"))])
        let looped = try await PlaybackURLResolver(client: loop, log: SilentLog()).resolve(
            start: mediaURL("https://media.example/again"),
            method: "GET",
            authorizationHeader: try playbackHeader(),
            trust: .publiclyTrusted
        )
        XCTAssertEqual(looped, .rejected(.loop))
        let upgradeClient = ScriptedOrigin([
            ok(302, location: mediaURL("https://media.example/up")),
            ok(),
        ])
        let upgraded = try await PlaybackURLResolver(client: upgradeClient, log: SilentLog()).resolve(
            start: mediaURL("http://media.example/up"),
            method: "GET",
            authorizationHeader: try playbackHeader(),
            trust: .cleartext
        )
        guard case .resolved(let secure) = upgraded else { return XCTFail("HTTP upgrade was rejected") }
        XCTAssertEqual(secure.scheme, "https")
        let bare = ScriptedOrigin([ok(302, location: mediaURL("https://media.example/next")), ok()])
        _ = try await PlaybackURLResolver(client: bare, log: SilentLog()).resolve(
            start: mediaURL("https://media.example/start"),
            method: "GET",
            authorizationHeader: nil,
            trust: .publiclyTrusted,
            mode: .queryCredential
        )
        XCTAssertFalse(MediaCredentialQuery.contains(bare.requests()[1].url))
    }

    /// T08-2-36. A loader fetch that is redirected off-origin does not send Authorization there.
    func testT08_2_36_loaderRedirectDropsTheOtherOrigin() async throws {
        let start = mediaURL("https://media.example/jellyfin/videos/\(itemID)/master.m3u8")
        let other = mediaURL("https://cdn.example/master.m3u8")
        let client = ScriptedOrigin([ok(302, location: other), ok()])
        let resolution = try await PlaybackURLResolver(client: client, log: CapturingLog()).resolve(
            start: start,
            method: "GET",
            authorizationHeader: try playbackHeader(),
            trust: .publiclyTrusted
        )
        XCTAssertEqual(resolution, .rejected(.insecureRedirect))
        XCTAssertEqual(client.requests().count, 1)
        XCTAssertEqual(client.requests()[0].url.host, "media.example")
        XCTAssertNotNil(client.requests()[0].authorizationHeader)
    }

    /// T08-2-38. Timeout and 503 fail the load and keep the token.
    func testT08_2_38_timeoutAndServerErrorDoNotClearTheToken() async throws {
        let timedOut = ResourceLoaderFailurePolicy.outcome(status: nil, timedOut: true)
        XCTAssertEqual(timedOut, LoaderOutcome(terminal: .failed, tokenCleared: false))
        let unavailable = ResourceLoaderFailurePolicy.outcome(status: 503, timedOut: false)
        XCTAssertEqual(unavailable, LoaderOutcome(terminal: .failed, tokenCleared: false))
        let success = ResourceLoaderFailurePolicy.outcome(status: 200, timedOut: false)
        XCTAssertEqual(success.terminal, .finished)
        XCTAssertFalse(success.tokenCleared)
        let waiting = ResourceLoaderFailurePolicy.outcome(status: 401, timedOut: false)
        XCTAssertEqual(waiting, LoaderOutcome(terminal: .awaitingSessionCheck, tokenCleared: false))
        XCTAssertEqual(MediaStatusPolicy.decide(status: 204), .bytes)
        XCTAssertEqual(MediaStatusPolicy.decide(status: 401), .checkCurrentUser)
        let client = ScriptedOrigin([ok(500)])
        let log = CapturingLog()
        let resolution = try await PlaybackURLResolver(client: client, log: log).resolve(
            start: mediaURL("https://media.example/v"),
            method: "GET",
            authorizationHeader: try playbackHeader(),
            trust: .publiclyTrusted
        )
        XCTAssertEqual(resolution, .rejected(.transport(status: 500)))
        XCTAssertFalse(leaked(log.lines().joined(separator: "\n")), "transport log leaked a credential")
        let noLocation = try await PlaybackURLResolver(client: ScriptedOrigin([ok(302)]), log: SilentLog()).resolve(
            start: mediaURL("https://media.example/v"),
            method: "GET",
            authorizationHeader: try playbackHeader(),
            trust: .publiclyTrusted
        )
        XCTAssertEqual(noLocation, .rejected(.transport(status: 302)))
    }

    /// T08-2-39. A media 401 logs out only when /Users/Me is also 401.
    func testT08_2_39_media401LogsOutOnlyWhenCurrentUserIs401() async {
        let success = await MediaUnauthorizedPolicy.decide(probe: ScriptedProbe(.success(())))
        XCTAssertEqual(success, .playbackError)
        let denied = await MediaUnauthorizedPolicy.decide(probe: ScriptedProbe(.failure(.unauthorized)))
        XCTAssertEqual(denied, .logOut)
        let network = await MediaUnauthorizedPolicy.decide(probe: ScriptedProbe(.failure(.network)))
        XCTAssertEqual(network, .playbackError)
        let server = await MediaUnauthorizedPolicy.decide(probe: ScriptedProbe(.failure(.server(status: 500))))
        XCTAssertEqual(server, .playbackError)
    }

    /// T08-2-40. Leaving playback cancels the fetch gate. Menu focus UI is not part of this queue.
    func testT08_2_40_cancelStopsTheFetchGate() {
        let gate = PlaybackFetchGate()
        XCTAssertFalse(gate.isCancelled)
        gate.cancel()
        XCTAssertTrue(gate.isCancelled)
    }

    /// T08-2-41. Poor-network playback was not run. No recovery sample was recorded.
    func testT08_2_41_poorNetworkBehaviorIsUnmeasured() {
        assertUnmeasuredDeviceLimits()
    }

    /// T08-2-42. AirPlay with the custom scheme was not run.
    func testT08_2_42_airPlayBehaviorIsUnmeasured() {
        assertUnmeasuredDeviceLimits()
    }

    /// T08-2-43. HDR and Dolby Vision display matching was not run.
    func testT08_2_43_hdrMatchingIsUnmeasured() {
        assertUnmeasuredDeviceLimits()
    }

    /// T08-2-44. Memory growth over play and stop cycles was not measured.
    func testT08_2_44_memoryGrowthIsUnmeasured() {
        assertUnmeasuredDeviceLimits()
        XCTAssertNil(PrototypeMeasurements.recordedMemoryGrowth)
    }

    /// T08-2-45. The same builder is shared. Whether the ADR result covers iOS is Q8-2-10.
    /// This package test is what the tvOS job runs on the macOS host. It is not a separate iOS ADR result.
    func testT08_2_45_sharedMediaURLBuilderDoesNotClaimAnIOSResult() throws {
        let prepared = try directPlayRequest()
        XCTAssertFalse(MediaCredentialQuery.contains(prepared.url))
        XCTAssertNotNil(prepared.authorizationHeader)
        XCTAssertTrue(prepared.url.path.contains("/Videos/\(itemID)/stream"))
        XCTAssertNil(PrototypeMeasurements.recordedFirstFrame)
    }

    /// T08-2-46. The prototype records cases, order, and the M08b contract.
    /// Security review of the ADR is the pull request, not this assertion.
    func testT08_2_46_prototypeRecordsCasesOrderAndTheLoopbackContract() {
        XCTAssertFalse(ADRM08Prototype.deviceChecklist.isEmpty)
        XCTAssertEqual(ADRM08Prototype.case1Order, ["resourceLoader", "assetHeaderFields", "apiKeyQuery"])
        XCTAssertEqual(ADRM08Prototype.prototypeCases, [1, 2])
        XCTAssertEqual(LoopbackRemuxContract.owner, ADRM08Prototype.case3Owner)
        XCTAssertTrue(LoopbackRemuxContract.listensOnEphemeralPort)
        XCTAssertTrue(LoopbackRemuxContract.stopsWhenPlaybackEnds)
        XCTAssertTrue(LoopbackRemuxContract.stopsWhenAppBackgrounds)
        XCTAssertTrue(ADRM08Prototype.deviceChecklist.joined(separator: " ").contains("pinned"))
    }

    private func assertUnmeasuredDeviceLimits() {
        XCTAssertNil(PrototypeMeasurements.recordedFirstFrame)
        XCTAssertNil(PrototypeMeasurements.recordedScrub)
        XCTAssertNil(PrototypeMeasurements.recordedTranscodeStart)
        XCTAssertNil(PrototypeMeasurements.recordedMemoryGrowth)
        XCTAssertTrue(PrototypeMeasurements.case2ScrubLimitUnresolved)
    }

    private func assertLocalNetworkingPlists() throws {
        for relative in ["Apps/tvOS/Info.plist", "Apps/iOS/Info.plist"] {
            let url = repositoryRoot().appendingPathComponent(relative)
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(text.contains("NSAllowsLocalNetworking"), relative)
            let arbitraryLoads = "NSAllows" + "ArbitraryLoads"
            XCTAssertFalse(text.contains(arbitraryLoads), relative)
        }
    }

    private func directPlayRequest() throws -> PreparedMediaRequest {
        try MediaURLBuilder.directPlay(
            server: mediaURL("https://media.example"),
            identity: playbackIdentity(),
            itemID: itemID,
            mediaSourceID: sourceID,
            playSessionID: "play-1"
        )
    }

    private func queryFallback() throws -> URL {
        try XCTUnwrap(
            MediaURLBuilder.queryCredentialFallback(
                strippedURL: mediaURL("https://media.example/Videos/\(itemID)/stream?static=true"),
                token: token
            )
        )
    }

    private func directPlan(trust: ServerTrustClass, headerKey: Bool, apiKey: Bool) throws -> MediaOpenPlan {
        try directPlan(trust: trust, headerKey: headerKey, apiKeyURL: apiKey ? queryFallback() : nil)
    }

    private func directPlan(trust: ServerTrustClass, headerKey: Bool, apiKeyURL: URL?) throws -> MediaOpenPlan {
        MediaOpenPlanner.plan(
            delivery: .directFile,
            resolvedURL: mediaURL("https://media.example/Videos/\(itemID)/stream?static=true"),
            authorizationHeader: try playbackHeader(),
            options: MediaOpenOptions(
                trust: trust,
                headerFieldsKeyAvailable: headerKey,
                apiKeyFallbackURL: apiKeyURL
            )
        )
    }

    private func hlsPlan(trust: ServerTrustClass, headerKey: Bool, apiKey: Bool) throws -> MediaOpenPlan {
        try hlsPlan(trust: trust, headerKey: headerKey, apiKeyURL: apiKey ? queryFallback() : nil)
    }

    private func hlsPlan(trust: ServerTrustClass, headerKey: Bool, apiKeyURL: URL?) throws -> MediaOpenPlan {
        MediaOpenPlanner.plan(
            delivery: .serverHLS,
            resolvedURL: mediaURL("https://media.example/jellyfin/Videos/\(itemID)/master.m3u8"),
            authorizationHeader: try playbackHeader(),
            options: MediaOpenOptions(
                trust: trust,
                headerFieldsKeyAvailable: headerKey,
                apiKeyFallbackURL: apiKeyURL
            )
        )
    }

    private func playbackIdentity() -> ClientIdentity {
        ClientIdentity(deviceName: "Glassfin CI", deviceID: "device-1", version: "0.1.0", token: token)
    }

    private func playbackHeader() throws -> String {
        try playbackIdentity().authorizationHeader()
    }

    private func leaked(_ text: String, secret: String? = nil) -> Bool {
        let secret = secret ?? token
        if text.contains(secret) { return true }
        if text.contains(segmentSecret) { return true }
        return text.contains("ApiKey=") && text.contains(segmentSecret)
    }

    private func fingerprint(_ byte: String) -> String {
        String(repeating: byte, count: 32)
    }

    private func spacedFingerprint(_ pin: String) -> String {
        pin.enumerated().map { index, character in
            index.isMultiple(of: 2) && index > 0 ? ":\(character)" : "\(character)"
        }.joined()
    }

    private func credentialAssetURL() -> URL {
        let encoded = "https://media.example/v?ApiKey=\(segmentSecret)".addingPercentEncoding(
            withAllowedCharacters: .alphanumerics
        )
        return mediaURL("\(MediaAssetScheme.name)://\(MediaAssetScheme.host)/\(encoded ?? "")")
    }

    private func corePlaybackSources() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        return url.appendingPathComponent("Sources/CorePlayback")
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }
}

private func mediaURL(_ string: String) -> URL {
    URL(string: string)!
}

private func ok(
    _ status: Int = 200,
    location: URL? = nil,
    body: Data = Data(),
    type: String? = nil
) -> Result<OriginMediaResponse, APIError> {
    .success(OriginMediaResponse(status: status, location: location, contentType: type, body: body))
}

private func successRewrite(_ result: Result<HLSRewrite, PlaylistURIRejection>) -> HLSRewrite? {
    if case .success(let value) = result { return value }
    return nil
}

private func wrappedOrigins(in playlist: String) -> [URL] {
    var origins: [URL] = []
    for token in playlist.split(whereSeparator: { $0 == "\"" || $0.isWhitespace || $0 == "," }) {
        guard let url = URL(string: String(token)), let origin = MediaAssetScheme.unwrap(url) else { continue }
        origins.append(origin)
    }
    return origins
}

private final class ScriptedOrigin: MediaOriginClient, Sendable {
    private struct State: Sendable {
        var steps: [Result<OriginMediaResponse, APIError>]
        var seen: [OriginMediaRequest]
    }

    private let state: Mutex<State>

    init(_ steps: [Result<OriginMediaResponse, APIError>]) {
        self.state = Mutex(State(steps: steps, seen: []))
    }

    func requests() -> [OriginMediaRequest] {
        state.withLock { $0.seen }
    }

    func fetch(_ request: OriginMediaRequest) async throws(APIError) -> OriginMediaResponse {
        let next = state.withLock { state -> Result<OriginMediaResponse, APIError>? in
            state.seen.append(request)
            return state.steps.isEmpty ? nil : state.steps.removeFirst()
        }
        guard let next else { throw APIError.network }
        switch next {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }
}

private final class CapturingLog: GlassfinLog, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    func warning(_ message: String) { append(message) }
    func debug(_ message: String) { append(message) }
    func error(_ message: String) { append(message) }

    func lines() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    private func append(_ message: String) {
        lock.lock()
        stored.append(message)
        lock.unlock()
    }
}

private final class ScriptedProbe: CurrentUserProbing, @unchecked Sendable {
    private let result: Result<Void, APIError>

    init(_ result: Result<Void, APIError>) {
        self.result = result
    }

    func currentUser() async throws(APIError) {
        switch result {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }
}

#if os(macOS)
    extension ADRM08PrototypeTests {
        fileprivate func assertLocalHTTPFetchSeesAuthorizationWithoutCredentialQuery() async throws {
            let server = LoopbackHTTPServer()
            let port = try await server.start()
            defer { server.stop() }
            let url = mediaURL("http://127.0.0.1:\(port)/Videos/stream?static=true")
            let client = URLSessionOriginClient(trust: .cleartext)
            let request = try XCTUnwrap(
                OriginMediaRequest(
                    method: "GET",
                    url: url,
                    authorizationHeader: try playbackHeader(),
                    range: HTTPByteRange(start: 0, end: 1),
                    trust: .cleartext
                )
            )
            let response = try await client.fetch(request)
            XCTAssertEqual(response.status, 200)
            XCTAssertEqual(response.body, Data("ok".utf8))
            let captured = server.captured
            XCTAssertTrue(captured.contains("Authorization:"))
            XCTAssertTrue(captured.contains("Range: bytes=0-1"))
            XCTAssertFalse(captured.contains("ApiKey="), "mock server saw a credential query")
        }

        fileprivate func assertPinnedLeafAllowsFetchAndMismatchCancels() async throws {
            let openssl = ["/usr/bin/openssl", "/opt/homebrew/bin/openssl", "/usr/local/bin/openssl"].first {
                FileManager.default.isExecutableFile(atPath: $0)
            }
            let binary = try XCTUnwrap(openssl, "openssl is required for the pinned leaf fetch")
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let cert = directory.appendingPathComponent("cert.pem")
            let key = directory.appendingPathComponent("key.pem")
            let request = Process()
            request.executableURL = URL(fileURLWithPath: binary)
            request.arguments = [
                "req", "-x509", "-newkey", "rsa:2048", "-keyout", key.path, "-out", cert.path,
                "-days", "1", "-nodes", "-subj", "/CN=127.0.0.1",
                "-addext", "subjectAltName=IP:127.0.0.1",
            ]
            request.standardOutput = FileHandle.nullDevice
            request.standardError = FileHandle.nullDevice
            try request.run()
            request.waitUntilExit()
            XCTAssertEqual(request.terminationStatus, 0, "openssl req failed")
            let der = try certificateDER(openssl: binary, cert: cert)
            let pin = leafPin(der)
            let started = try await startCertificateServer(openssl: binary, cert: cert, key: key)
            defer { started.process.terminate() }
            let url = mediaURL("https://127.0.0.1:\(started.port)/")
            let header = try playbackHeader()
            let trust = ServerTrustClass.pinnedSelfSigned(fingerprintSHA256: pin)
            let client = URLSessionOriginClient(trust: trust)
            let mediaRequest = try XCTUnwrap(
                OriginMediaRequest(method: "GET", url: url, authorizationHeader: header, trust: trust)
            )
            let response = try await client.fetch(mediaRequest)
            XCTAssertTrue((200..<400).contains(response.status), "pinned fetch status \(response.status)")
            let mismatch = ServerTrustClass.pinnedSelfSigned(fingerprintSHA256: fingerprint("cd"))
            let rejected = URLSessionOriginClient(trust: mismatch)
            let badRequest = try XCTUnwrap(
                OriginMediaRequest(method: "GET", url: url, authorizationHeader: header, trust: mismatch)
            )
            do {
                _ = try await rejected.fetch(badRequest)
                XCTFail("mismatched pin completed the fetch")
            } catch let error as APIError {
                let failed = error == .tls || error == .network || error == .cancelled
                XCTAssertTrue(failed, "mismatched pin produced \(error)")
            }
        }

        private func certificateDER(openssl: String, cert: URL) throws -> Data {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: openssl)
            process.arguments = ["x509", "-in", cert.path, "-outform", "DER"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            XCTAssertEqual(process.terminationStatus, 0, "openssl x509 failed")
            XCTAssertFalse(data.isEmpty)
            return data
        }

        private func leafPin(_ der: Data) -> String {
            let encoded: Data
            if let certificate = SecCertificateCreateWithData(nil, der as CFData) {
                encoded = SecCertificateCopyData(certificate) as Data
            } else {
                encoded = der
            }
            return CertificateFingerprint.sha256Hex(encoded)
        }

        private func startCertificateServer(
            openssl: String,
            cert: URL,
            key: URL
        ) async throws -> (process: Process, port: UInt16) {
            for _ in 0..<5 {
                let port = try await reservePort()
                let process = Process()
                process.executableURL = URL(fileURLWithPath: openssl)
                process.arguments = [
                    "s_server", "-accept", "127.0.0.1:\(port)", "-cert", cert.path, "-key", key.path,
                    "-www", "-naccept", "2",
                ]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try process.run()
                if await portAccepts(port, process: process) {
                    return (process, port)
                }
                process.terminate()
            }
            throw URLError(.cannotConnectToHost)
        }

        private func reservePort() async throws -> UInt16 {
            let listener = try NWListener(using: .tcp, on: .any)
            let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
                let once = ResumeOnce()
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        once.run { continuation.resume(returning: listener.port?.rawValue ?? 0) }
                    case .failed(let error):
                        once.run { continuation.resume(throwing: error) }
                    default:
                        break
                    }
                }
                listener.start(queue: .global())
            }
            listener.cancel()
            if port == 0 { throw URLError(.cannotConnectToHost) }
            return port
        }

        private func portAccepts(_ port: UInt16, process: Process) async -> Bool {
            let endpoint = NWEndpoint.Port(rawValue: port) ?? .any
            let deadline = Date().addingTimeInterval(3)
            while Date() < deadline {
                if !process.isRunning { return false }
                if await probe(endpoint) { return true }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return false
        }

        private func probe(_ port: NWEndpoint.Port) async -> Bool {
            let connection = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
            return await withCheckedContinuation { continuation in
                let once = ResumeOnce()
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        once.run {
                            connection.cancel()
                            continuation.resume(returning: true)
                        }
                    case .failed, .cancelled:
                        once.run { continuation.resume(returning: false) }
                    default:
                        break
                    }
                }
                connection.start(queue: .global())
            }
        }
    }

    private final class LoopbackHTTPServer: @unchecked Sendable {
        private let queue = DispatchQueue(label: "org.glassfin.loopback-http")
        private let lock = NSLock()
        private var listener: NWListener?
        private var buffer = Data()
        private var requestText = ""

        func start() async throws -> UInt16 {
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            return try await withCheckedThrowingContinuation { continuation in
                let once = ResumeOnce()
                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        once.run { continuation.resume(returning: listener.port?.rawValue ?? 0) }
                    case .failed(let error):
                        once.run { continuation.resume(throwing: error) }
                    default:
                        break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection)
                }
                listener.start(queue: queue)
            }
        }

        func stop() { listener?.cancel() }

        var captured: String {
            lock.lock()
            defer { lock.unlock() }
            return requestText
        }

        private func accept(_ connection: NWConnection) {
            connection.start(queue: queue)
            receive(connection)
        }

        private func receive(_ connection: NWConnection) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
                [weak self] data, _, isComplete, error in
                guard let self else { return }
                var ready = false
                if let data {
                    self.lock.lock()
                    self.buffer.append(data)
                    ready = self.buffer.range(of: Data([13, 10, 13, 10])) != nil
                    if ready {
                        self.requestText = String(decoding: self.buffer, as: UTF8.self)
                    }
                    self.lock.unlock()
                }
                if ready {
                    self.reply(connection)
                    return
                }
                if isComplete || error != nil {
                    connection.cancel()
                    return
                }
                self.receive(connection)
            }
        }

        private func reply(_ connection: NWConnection) {
            var payload = Data(
                "HTTP/1.1 200 OK\r\nContent-Type: video/mp4\r\nContent-Length: 2\r\nConnection: close\r\n\r\n".utf8
            )
            payload.append(Data("ok".utf8))
            connection.send(
                content: payload,
                completion: .contentProcessed { _ in
                    connection.cancel()
                })
        }
    }

    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false

        func run(_ body: () -> Void) {
            lock.lock()
            if fired {
                lock.unlock()
                return
            }
            fired = true
            lock.unlock()
            body()
        }
    }
#endif
