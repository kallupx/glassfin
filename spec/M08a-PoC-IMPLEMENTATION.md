# M08a-PoC implementation note

The normative PoC rules are [SPEC.md §3a](SPEC.md#3a-poc-tier-p0-poc-decided-27102026),
with [03-security.md](03-security.md) and [ADR M08-2](adr/M08-2.md). This file
records integration details, test traceability and validation gaps; it does not
define a competing specification. Follow-up 4 was rebased onto `abc2017`
(including #20 `a30a181`, #21 `dd38838` and #25 `abc2017`).

Implemented on 2026-10-27. This is the playback slice of the hands-on PoC. The
M04 sign-in, M06 Home and M07 detail implementations are separate work; this
change provides their playback entry point without depending on those branches.

## Connecting the detail view

Create one `PlaybackCoordinator` per active session with a
`PlaybackSessionProviding` adapter. The adapter supplies the server URL, user ID,
existing `ClientIdentity`, certificate trust/pin and the authenticated
CoreNetworking `JellyfinAPIClient`. Its `sessionExpired()` implementation must
clear credentials and invoke M04's existing S2.2 session-expired sign-in handling.
Recreate the coordinator when changing the server or authenticated user.

On Apple platforms, construct `URLSessionOriginClient(trust: session.trust)` and
pass that same origin client to `AVPlayerEngine` and the coordinator. Present
`PlaybackView(coordinator:engine:)` from the detail screen. `project.yml` already
includes `Apps/Shared/Sources` in both application targets.

- Every start fetches the user's item with Fields=MediaStreams, refetches once only if stream metadata is absent, and checks its default video codec before PlaybackInfo.
- `play(itemID:)` also reads `UserData.PlaybackPositionTicks` from that response.
- `play(itemID:choice: .resumeAt(ticks: savedTicks))` uses detail's saved position;
  the item request still verifies the video metadata.
- `play(itemID:choice: .startOver)` sends zero ticks.
- The observable state exposes loading, playing, paused, buffering, ended, a
  failure catalog key, and session expiry. Menu/dismiss stops the loader and
  attempts a Stopped report. Call `stop()` before releasing a coordinator.

## Playback implementation

`PlaybackDecision` provides the static profile and default-video preflight;
`VideoTranscodeReasons` provides the pure, locked query parser. `MediaURLBuilder`
enforces video copy, fMP4 segments and disabled subtitles. `PlaybackCoordinator`
serializes startup, one DirectPlay-to-DirectStream retry, reports and the media
401 session probe. The retry uses a new PlaySessionId and waits for Stopped.
`AVPlayerEngine` and `PlaybackView` adapt this to the native Apple player.

Both delivery methods use `PlaybackPreparation` and `AVPlayerMediaSession` with
prototype fallbacks disabled. `MediaURLValidation.hasNoUserInfo` is separate
from `MediaOrigin.matches`: it checks URLComponents.user/password for nil before
any credential stripping, URL wrapping, playlist delivery or transport fetch.
This implements the Follow-up 4 security decision, including empty user/password
fields. The loader rechecks mutable requests and the URLSession adapter checks
again before creating its request. The HLS rewriter checks the master base URL
and every variant, segment, init segment and key URI. Server-generated segment
query tokens retain the ADR's accepted-risk behavior; RFC 6454 origin identity
and its documenting test are unchanged.

## Differences resolved against merged main

- Removed the provisional `h265` alias. Only `h264` and `hevc`, matched without
  case sensitivity, pass video preflight, as required by SPEC §3a / Q8P-21.
- The prior T08-2-14 test let the playback resolver strip URL userinfo. Its query
  stripping assertions remain, while userinfo now rejects playback under the
  explicit Follow-up 4 decision. The low-level redaction utility is unchanged.
- Rebase conflicts preserve main's 12.2 startup worker readiness, bounded refresh
  retries, persisted library path verification/repair, idle-worker restart and
  redacted diagnostics. These now apply to the PoC's Movies/Shows libraries,
  codec probing and two-season/four-episode completion checks. All 16 combined
  Python mocks pass. Main's chunked bounded-body implementation is retained.
- The former duplicated playback rules in this note are replaced by references
  to the merged specification. The implementation audit found no further
  contradictions with the merged PoC codec, profile, reason-parser, retry,
  pinning, string, reporting or token rules. Native validation remains pending.

## Complete test-plan mapping (updated Follow-up 4)

Authoritative plans re-read on 2026-10-27: `/workspace/jellyfin-tvos/test/TESTPLAN-M08a-PoC.md`
(T08P-01–99) and `TESTPLAN-PoC-ACCEPTANCE.md` (TPOC-01–82). Every ID appears below.
L denotes locally run Linux model/unit coverage, I denotes opt-in live tests
(skipped without GLASSFIN_INTEGRATION), and K denotes a script. A Linux model
counterpart does not establish an X/U/S/M result. Pending portions are explicit;
this table is traceability, not a claim of PoC acceptance.

### T08P

| Plan ID | Matching tests/scripts | Evidence and remaining validation |
| --- | --- | --- |
| T08P-01 | [`testT08P_01_70_deviceProfileShapeAndVideoCopyURL`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackPoCTests.swift) | L profile shape. |
| T08P-02 | [`testT08P_02_playbackInfoRequestAndParsing`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackPoCTests.swift) | L request/auth/DTO. |
| T08P-03 | [`testT08P_03_firstMediaSourceUsedInURLAndReports`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L first-source model; AVPlayer X pending. |
| T08P-04 | [`testT08P_04_47_preparationErrorsFailBeforeEngineLoad`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L server-error model; U focus pending. |
| T08P-05 | [`testT08P_05_seedMediaPlaybackDecisions`](../Packages/GlassfinCore/Tests/IntegrationTests/DockerIntegrationTests.swift) | I gated: all three live servers not run locally. |
| T08P-06 | [`testT08P_06_07_08_10_12_14_16_profileDecisionMatrix`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackPoCTests.swift) | L method model; decoded X/U pending. |
| T08P-07 | [`testT08P_06_07_08_10_12_14_16_profileDecisionMatrix`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackPoCTests.swift) | L method model; decoded HEVC/audio X/U pending. |
| T08P-08 | [`testT08P_06_07_08_10_12_14_16_profileDecisionMatrix`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackPoCTests.swift)<br>[`testT08P_08_10_70_hlsLoadsWithVideoCopyAndReportsDirectStream`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L carrier/report model; decoded X/U pending. |
| T08P-09 | [`testT08P_05_seedMediaPlaybackDecisions`](../Packages/GlassfinCore/Tests/IntegrationTests/DockerIntegrationTests.swift) | I gated: fetched HLS/session flags. |
| T08P-10 | [`testT08P_06_07_08_10_12_14_16_profileDecisionMatrix`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackPoCTests.swift)<br>[`testT08P_08_10_70_hlsLoadsWithVideoCopyAndReportsDirectStream`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L carrier/report model; real audio X/U pending. |
| T08P-11 | [`testT08P_05_seedMediaPlaybackDecisions`](../Packages/GlassfinCore/Tests/IntegrationTests/DockerIntegrationTests.swift) | I gated: copied video/audio conversion. |
| T08P-12 | [`testT08P_06_07_08_10_12_14_16_profileDecisionMatrix`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackPoCTests.swift)<br>[`testT08P_05_seedMediaPlaybackDecisions`](../Packages/GlassfinCore/Tests/IntegrationTests/DockerIntegrationTests.swift) | L method + I gated; decoded HEVC X/U pending. |
| T08P-13 | [`testT08P_13_14_unsupportedPreflightMakesZeroPlaybackRequests`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L precheck; X/U deadline/focus pending. |
| T08P-14 | [`testT08P_06_07_08_10_12_14_16_profileDecisionMatrix`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackPoCTests.swift)<br>[`testT08P_13_14_unsupportedPreflightMakesZeroPlaybackRequests`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L codec/decision order; see 82–99. |
| T08P-15 | [`testT08P_15_supportedPlaybackAfterUnsupportedError`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L recovery; U dismissal/focus pending. |
| T08P-16 | [`testT08P_06_07_08_10_12_14_16_profileDecisionMatrix`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackPoCTests.swift) | L container decision; real HLS DirectPlay X pending. |
| T08P-17 | [`testT08P_17_directPlayFailureRetriesRemuxOnce`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_17_startupLoaderAndPreparationFailureRetry`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_17_failureBeforeReadyRetriesWithoutPlayingReport`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_17_56_retryWaitsForStoppedAndCanBeDismissed`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_17_retryKeepsBackwardSeekPosition`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_17_56_stopDuringRetryDiscardsLatePlaybackInfo`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_17_56_cancellingStartupCancelsPendingRetry`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_17_retryRequiresNewPlaySessionID`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L coordinator: engine/loader/preparation/timeout failures, audio conversion, session IDs, report order, backward seek and dismissal; native AVPlayer X pending. No first-frame watchdog existed in this slice; the timeout event is injected. |
| T08P-18 | — | Pending native player UI/snapshots. |
| T08P-19 | [`testT08P_19_56_engineStatesAndRepeatedPlay`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L state/report model; native controls X/U pending. |
| T08P-20 | — | Pending native seek/ranges. |
| T08P-21 | — | Pending real HLS seek. |
| T08P-22 | — | Pending Menu/dismissal/focus journey. |
| T08P-23 | [`testT08P_23_31_endAndErrorReportStoppedExactlyOnce`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L end/report model; UserData/automatic dismissal X/U/I pending. |
| T08P-24 | — | Pending explicit unknown-duration scenario (removed former unrelated ID annotation). |
| T08P-25 | [`testT08P_25_27_29_reportingSequenceAndFields`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L report shape/order only: native first-frame timing pending; current engine emits readyToPlay. |
| T08P-26 | [`testT08P_26_progressTimerUsesClockAndCancels`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L injected clock, six ticks; macOS-server run pending. |
| T08P-27 | [`testT08P_25_27_29_reportingSequenceAndFields`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L immediate progress; native timing X pending. |
| T08P-28 | — | Pending Q8P-07 Ping decision. |
| T08P-29 | [`testT08P_25_27_29_reportingSequenceAndFields`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L stop payload/timer cancellation. |
| T08P-30 | [`testT08P_30_73_reportingRetriesOnceAndContinuesPlayback`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_30_transientRetryCanRecover`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L one transient retry/recovery only; reconnect queue pending. |
| T08P-31 | [`testT08P_23_31_endAndErrorReportStoppedExactlyOnce`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_31_initialRemuxFailureNeverRetries`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L failed/remux stop payload; real segment failure X pending. |
| T08P-32 | [`testT08P_32_73_reportHTTPFailuresRedactAndKeepHeaderOnlyAuth`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackPoCTests.swift) | L real HTTPClient + mocked transport auth/redaction. |
| T08P-33 | — | Pending optimistic UserData/Home refresh and live resume position. |
| T08P-34 | [`testT08P_05_seedMediaPlaybackDecisions`](../Packages/GlassfinCore/Tests/IntegrationTests/DockerIntegrationTests.swift) | I gated: active item/session flags only; dashboard/PlayMethod U pending. |
| T08P-35 | — | Pending explicit post-sign-out report discard test. |
| T08P-36 | [`testT08P_36_resumeTicksAndSaturation`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackPoCTests.swift)<br>[`testT08P_36_37_resumeAndStartOver`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L ticks/resume model; real seek X/U pending. |
| T08P-37 | [`testT08P_36_37_resumeAndStartOver`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L start-over model; U journey pending. |
| T08P-38 | — | Pending dedicated DirectStream resume/server-position test. |
| T08P-39 | — | Pending Home direct-resume U journey. |
| T08P-40 | — | Pending prompt/navigation U journey. |
| T08P-41 | — | Pending re-sign-in/live resume U journey. |
| T08P-42 | [`testT08P_42_43_45_mediaUnauthorizedChecksMeExactlyOnce`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_42_44_startupMedia401AndReport401`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_42_retry401NeverStartsThirdAttempt`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_42_44_stopped401PreventsRemuxRetry`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L origin/engine/report/retry 401 policy; real loader X pending. |
| T08P-43 | [`testT08P_42_43_45_mediaUnauthorizedChecksMeExactlyOnce`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_43_56_dismissalDuringStoppedStillChecksSession`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L duplicate 401/probe/session expiry; sign-in UI X/U pending. |
| T08P-44 | [`testT08P_44_playbackInfo401ExpiresSession`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_42_44_startupMedia401AndReport401`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_42_44_stopped401PreventsRemuxRetry`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L PlaybackInfo direct expiry + report probe policy; Q8P-09 remains open. |
| T08P-45 | [`testT08P_42_43_45_mediaUnauthorizedChecksMeExactlyOnce`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L DirectStream unauthorized event; actual AVPlayer segment mapping X pending. |
| T08P-46 | — | Pending permission-specific UI. |
| T08P-47 | [`testT08P_04_47_preparationErrorsFailBeforeEngineLoad`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L no POST retry/generic error only; AppError distinctions/Try again UI pending. |
| T08P-48 | — | Pending buffering/reconnect UI/timeouts. |
| T08P-49 | — | Pending network recovery. |
| T08P-50 | — | Pending offline preflight/banner. |
| T08P-51 | — | Pending poor-network scenario. |
| T08P-52 | — | Pending injected 15-second API timeout/UI. |
| T08P-53 | — | Pending playlist/byte-range timeout bound (Q8P-12). |
| T08P-54 | [`testT08P_54_crossOriginHLSIsRejected`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_54_87_resolverAndTrustRejections`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L origin/downgrade policy; AVPlayer X pending. |
| T08P-55 | [`testT08P_55_pinnedDirectPlayUsesLoader`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L pinned carrier/trust; decoded X/U pending. |
| T08P-56 | [`testT08P_43_56_dismissalDuringStoppedStillChecksSession`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_56_stopDuringStartupDiscardsLateResponse`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_56_cancelledPlayLeavesIdle`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_19_56_engineStatesAndRepeatedPlay`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_17_56_retryWaitsForStoppedAndCanBeDismissed`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_17_56_stopDuringRetryDiscardsLatePlaybackInfo`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_17_56_cancellingStartupCancelsPendingRetry`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L stop/cancel/stale-response/retry-dismissal model; rapid native cycles X/U pending. |
| T08P-57 | — | Pending native focus/Info panel. |
| T08P-58 | — | Pending caller-specific return focus. |
| T08P-59 | — | Pending error-dialog focus. |
| T08P-60 | — | Pending VoiceOver errors/loading labels. |
| T08P-61 | — | Manual device VoiceOver; not run. |
| T08P-62 | [`testT08P_62_catalogKeysHaveBothTranslations`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackPoCTests.swift) | L exact key/copy/en-fi catalog checks; remaining app error strings require module integration. |
| T08P-63 | — | Pending Finnish U/S. |
| T08P-64 | — | Pending English S. |
| T08P-65 | — | Pending first-frame signposts/optional device measurement. |
| T08P-66 | — | Pending long 4K memory run. |
| T08P-67 | — | Pending CPU measurement. |
| T08P-68 | — | Pending native 10-cycle memory check. |
| T08P-69 | [`testT08P_69_71_directURLHasNoCredentialOrFallback`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackPoCTests.swift) | L app-built URL/header carrier policy in Debug/Release; actual media X pending. |
| T08P-70 | [`testT08P_01_70_deviceProfileShapeAndVideoCopyURL`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackPoCTests.swift)<br>[`testT08P_70_88_masterAndVariantUseLoaderAndSegmentsStayOnOrigin`](../Packages/GlassfinCore/Tests/CorePlaybackTests/MediaLoaderSecurityTests.swift)<br>[`testT08P_08_10_70_hlsLoadsWithVideoCopyAndReportsDirectStream`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L master/variant loader auth + segment URI model in Debug/Release; macOS server U pending. |
| T08P-71 | [`testT08P_69_71_directURLHasNoCredentialOrFallback`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackPoCTests.swift)<br>[`testT08P_71_loaderFailureNeverUsesCredentialFallback`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L forced loader failure, no credential fallback in Debug/Release. |
| T08P-72 | [`check-release-binary.sh`](../scripts/check-release-binary.sh) | K configured binary scanner; Apple Release binary not available locally. |
| T08P-73 | [`testT08P_32_73_reportHTTPFailuresRedactAndKeepHeaderOnlyAuth`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackPoCTests.swift)<br>[`testT08P_30_73_reportingRetriesOnceAndContinuesPlayback`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_73_74_playerAndReportingLogRedaction`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L report HTTP failure/redaction in Debug/Release; native logger X pending. |
| T08P-74 | [`testT08P_73_74_playerAndReportingLogRedaction`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L PlayerLogSink redaction in Debug/Release; AVPlayer error/access-log X pending. |
| T08P-75 | [`ci-grep.sh`](../scripts/ci-grep.sh) | K ci-grep passed; SwiftLint custom_rules require unavailable SourceKit. |
| T08P-76 | [`redact_artifacts.py`](../scripts/redact_artifacts.py) | K redactor self-test only; pre-upload reject-on-secret scan and all-artifact proof pending. |
| T08P-77 | — | Pending native macOS server-log evidence. |
| T08P-78 | — | Pending Now Playing/title cleaner integration. |
| T08P-79 | [`testT08P_13_14_unsupportedPreflightMakesZeroPlaybackRequests`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L zero negotiation/stream precheck model; macOS-server app/job evidence X/U pending. |
| T08P-80 | [`testT08P_05_seedMediaPlaybackDecisions`](../Packages/GlassfinCore/Tests/IntegrationTests/DockerIntegrationTests.swift) | I gated DTS reason/session checks; decoded macOS U pending. |
| T08P-81 | [`testT08P_05_seedMediaPlaybackDecisions`](../Packages/GlassfinCore/Tests/IntegrationTests/DockerIntegrationTests.swift) | I gated exact ContainerNotSupported reason set; decoded macOS U pending. |
| T08P-82 | [`testT08P_82_VideoCodecNotSupported`](../Packages/GlassfinCore/Tests/CorePlaybackTests/VideoTranscodeReasonsTests.swift)<br>[`testT08P_82_VideoProfileNotSupported`](../Packages/GlassfinCore/Tests/CorePlaybackTests/VideoTranscodeReasonsTests.swift)<br>[`testT08P_82_VideoRangeTypeNotSupported`](../Packages/GlassfinCore/Tests/CorePlaybackTests/VideoTranscodeReasonsTests.swift)<br>[`testT08P_82_VideoCodecTagNotSupported`](../Packages/GlassfinCore/Tests/CorePlaybackTests/VideoTranscodeReasonsTests.swift)<br>[`testT08P_82_VideoLevelNotSupported`](../Packages/GlassfinCore/Tests/CorePlaybackTests/VideoTranscodeReasonsTests.swift)<br>[`testT08P_82_VideoResolutionNotSupported`](../Packages/GlassfinCore/Tests/CorePlaybackTests/VideoTranscodeReasonsTests.swift)<br>[`testT08P_82_VideoBitDepthNotSupported`](../Packages/GlassfinCore/Tests/CorePlaybackTests/VideoTranscodeReasonsTests.swift)<br>[`testT08P_82_VideoFramerateNotSupported`](../Packages/GlassfinCore/Tests/CorePlaybackTests/VideoTranscodeReasonsTests.swift)<br>[`testT08P_82_RefFramesNotSupported`](../Packages/GlassfinCore/Tests/CorePlaybackTests/VideoTranscodeReasonsTests.swift)<br>[`testT08P_82_AnamorphicVideoNotSupported`](../Packages/GlassfinCore/Tests/CorePlaybackTests/VideoTranscodeReasonsTests.swift)<br>[`testT08P_82_InterlacedVideoNotSupported`](../Packages/GlassfinCore/Tests/CorePlaybackTests/VideoTranscodeReasonsTests.swift)<br>[`testT08P_82_VideoBitrateNotSupported`](../Packages/GlassfinCore/Tests/CorePlaybackTests/VideoTranscodeReasonsTests.swift)<br>[`testT08P_82_UnknownVideoStreamInfo`](../Packages/GlassfinCore/Tests/CorePlaybackTests/VideoTranscodeReasonsTests.swift)<br>[`testT08P_82_VideoRotationNotSupported`](../Packages/GlassfinCore/Tests/CorePlaybackTests/VideoTranscodeReasonsTests.swift) | L all 14 blocking values alone and mixed. |
| T08P-83 | [`testT08P_83_ignoredReasons`](../Packages/GlassfinCore/Tests/CorePlaybackTests/VideoTranscodeReasonsTests.swift) | L ignored/container/audio/subtitle/unknown reasons. |
| T08P-84 | [`testT08P_84_emptyMissingAndEncodedCommas`](../Packages/GlassfinCore/Tests/CorePlaybackTests/VideoTranscodeReasonsTests.swift) | L empty/missing/encoded comma behavior; missing URL decisions also in profileDecisionMatrix. |
| T08P-85 | [`testT08P_85_malformedInputsAreDeterministic`](../Packages/GlassfinCore/Tests/CorePlaybackTests/VideoTranscodeReasonsTests.swift) | L deterministic malformed/large/repeated input tests; no wall-clock 10-ms performance assertion. |
| T08P-86 | [`testT08P_86_reasonAndParameterCaseAreSignificant`](../Packages/GlassfinCore/Tests/CorePlaybackTests/VideoTranscodeReasonsTests.swift) | L exact case-sensitive query name/reason tests. |
| T08P-87 | [`testT08P_54_87_resolverAndTrustRejections`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L pinned HLS block/key; native dialog/focus/snapshots X/U/S pending. |
| T08P-88 | [`testT08P_70_88_masterAndVariantUseLoaderAndSegmentsStayOnOrigin`](../Packages/GlassfinCore/Tests/CorePlaybackTests/MediaLoaderSecurityTests.swift) | L loader/origin/downgrade segment/init URI checks in Debug/Release; AVPlayer X pending. |
| T08P-89 | [`testT08P_89_queryVideoReasonsBlockBeforeStreamRequest`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L video-reason block: zero stream/player/Playing; native X pending. |
| T08P-90 | [`testT08P_90_jsonBodyReasonsAreIgnored`](../Packages/GlassfinCore/Tests/CorePlaybackTests/VideoTranscodeReasonsTests.swift)<br>[`testT08P_90_nonQueryReasonTextAndOtherQueryValuesAreIgnored`](../Packages/GlassfinCore/Tests/CorePlaybackTests/VideoTranscodeReasonsTests.swift) | L query-only parsing in Debug/Release; no stored/forwarded unrelated query values. |
| T08P-91 | — | Pending scenario-specific URL-canary/redaction matrix; general redaction tests are 73/74. |
| T08P-92 | [`testT08P_92_bothAttemptsFailWithExactlyTwoStreams`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_92_remuxPlaylistFailureEndsChain`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L two failures: exactly 2 PlaybackInfo/streams, both Failed Stopped, no third attempt; native X pending. |
| T08P-93 | [`testT08P_93_pinnedDirectPlayFailureNeverNegotiatesRemux`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L pinned DirectPlay failure: self-signed key, one negotiation/stream/Failed Stopped; pinned native TLS X pending. |
| T08P-94 | [`testT08P_94_defaultVideoSelectionIgnoresIndexHints`](../Packages/GlassfinCore/Tests/CorePlaybackTests/VideoTranscodeReasonsTests.swift)<br>[`testT08P_94_95_96_97_defaultVideoPrecheck`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L first IsDefault video, both orders and conflicting index hint; native X pending. |
| T08P-95 | [`testT08P_94_95_96_97_defaultVideoPrecheck`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L first video fallback, ignores default audio, both orders. |
| T08P-96 | [`testT08P_94_95_96_97_defaultVideoPrecheck`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L empty/audio-only streams: generic error, no refetch/negotiation/player; native focus X pending. |
| T08P-97 | [`testT08P_94_95_96_97_defaultVideoPrecheck`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L case-insensitive canonical codec names; h265/H265 and avc rejected per merged SPEC §3a. |
| T08P-98 | [`testT08P_98_missingStreamsRefetchExactlyOnce`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L item refetch exactly once with Fields=MediaStreams; success/missing/empty/unsupported outcomes; HTTP-mock X pending. |
| T08P-99 | [`testT08P_99_retryVideoReasonBlocksBeforeStreamOrPlayer`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L retry video reason: unsupported key, no remux stream/player/job, no third attempt; native X pending. |

### TPOC

| Plan ID | Matching tests/scripts | Evidence and remaining validation |
| --- | --- | --- |
| TPOC-01 | — | Pending merged-main CI/recorded SHA. |
| TPOC-02 | [`testTPOC_02_seedConfigurationAndNonAdminUser`](../Packages/GlassfinCore/Tests/IntegrationTests/DockerIntegrationTests.swift)<br>[`PoCBootstrapTests.test_TPOC_02_non_admin_random_password_is_private`](../scripts/test_jellyfin_bootstrap.py)<br>[`test_TPOC_02_resume_threshold_and_quick_connect_preserve_configuration`](../scripts/test_jellyfin_bootstrap.py)<br>[`test_TPOC_02_library_paths_and_offline_metadata`](../scripts/test_jellyfin_bootstrap.py)<br>[`test_TPOC_02_scan_waits_for_probing_episodes_and_idle_task`](../scripts/test_jellyfin_bootstrap.py)<br>[`test_TPOC_02_configuration_failures_are_not_ignored`](../scripts/test_jellyfin_bootstrap.py)<br>[`test_TPOC_02_scan_requires_both_seasons_and_all_four_episodes`](../scripts/test_jellyfin_bootstrap.py) | Python mocks passed + I gated seed/config/user/library checks; native macOS/bootstrap/version evidence pending. |
| TPOC-03 | — | Pending cross-module green CI on same SHA. |
| TPOC-04 | — | Pending clean tvOS simulator setup. |
| TPOC-05 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-06 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-07 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-08 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-09 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-10 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-11 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-12 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-13 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-14 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-15 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-16 | [`testT08P_05_seedMediaPlaybackDecisions`](../Packages/GlassfinCore/Tests/IntegrationTests/DockerIntegrationTests.swift) | I gated HLS/session/reason checks; native U journey pending. |
| TPOC-17 | [`testT08P_05_seedMediaPlaybackDecisions`](../Packages/GlassfinCore/Tests/IntegrationTests/DockerIntegrationTests.swift) | I gated DTS video-copy/audio-transcode/reasons; native U journey pending. |
| TPOC-18 | [`testT08P_13_14_unsupportedPreflightMakesZeroPlaybackRequests`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_15_supportedPlaybackAfterUnsupportedError`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L precheck/recovery; native U and no-transcode server evidence pending. |
| TPOC-19 | [`testT08P_05_seedMediaPlaybackDecisions`](../Packages/GlassfinCore/Tests/IntegrationTests/DockerIntegrationTests.swift) | I gated optional HEVC remux; native U pending. |
| TPOC-20 | [`testT08P_25_27_29_reportingSequenceAndFields`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L report model; native controls/server-position U/I pending. |
| TPOC-21 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-22 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-23 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-24 | [`testTPOC_02_seedConfigurationAndNonAdminUser`](../Packages/GlassfinCore/Tests/IntegrationTests/DockerIntegrationTests.swift) | I gated two-season seed prerequisite only; U season picker pending. |
| TPOC-25 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-26 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-27 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-28 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-29 | [`testT08P_36_37_resumeAndStartOver`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L resume model; native U accuracy pending. |
| TPOC-30 | [`testT08P_36_37_resumeAndStartOver`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L start-over model; native Home refresh U pending. |
| TPOC-31 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-32 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-33 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-34 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-35 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-36 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-37 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-38 | [`testTPOC_02_seedConfigurationAndNonAdminUser`](../Packages/GlassfinCore/Tests/IntegrationTests/DockerIntegrationTests.swift) | I gated seed has S02E01 only; cross-season Next Up/focus U pending. |
| TPOC-39 | [`testTPOC_02_seedConfigurationAndNonAdminUser`](../Packages/GlassfinCore/Tests/IntegrationTests/DockerIntegrationTests.swift) | I gated season/episode distribution only; picker U pending. |
| TPOC-40 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-41 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-42 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-43 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-44 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-45 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-46 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-47 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-48 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-49 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-50 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-51 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-52 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-53 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-54 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-55 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-56 | [`testT08P_42_43_45_mediaUnauthorizedChecksMeExactlyOnce`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L DirectPlay 401/session policy only; revoke/live U pending. |
| TPOC-57 | [`testT08P_42_43_45_mediaUnauthorizedChecksMeExactlyOnce`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L DirectStream 401/session policy only; segment/revoke U pending. |
| TPOC-58 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-59 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-60 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-61 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-62 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-63 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-64 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-65 | [`testTPOC_65_catalogCompleteness`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackPoCTests.swift) | L both catalogs en/fi completeness. |
| TPOC-66 | — | Pending native simulator journey/cross-module integration; no matching playback-slice test. |
| TPOC-67 | [`testT08P_73_74_playerAndReportingLogRedaction`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L report/player redaction only; full app/artifact/recording scan pending. |
| TPOC-68 | [`testT08P_71_loaderFailureNeverUsesCredentialFallback`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`check-release-binary.sh`](../scripts/check-release-binary.sh) | L Release no-fallback policy; K scanner configured, Apple Release binary/U proof pending. |
| TPOC-69 | — | Optional manual Apple TV checklist; not run. |
| TPOC-70 | — | Optional manual Apple TV checklist; not run. |
| TPOC-71 | — | Optional manual Apple TV checklist; not run. |
| TPOC-72 | — | Optional manual Apple TV checklist; not run. |
| TPOC-73 | — | Optional manual Apple TV checklist; not run. |
| TPOC-74 | — | Optional manual Apple TV checklist; not run. |
| TPOC-75 | — | Optional manual Apple TV checklist; not run. |
| TPOC-76 | — | Optional manual Apple TV checklist; not run. |
| TPOC-77 | — | Optional manual Apple TV checklist; not run. |
| TPOC-78 | [`testT08P_55_pinnedDirectPlayUsesLoader`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift)<br>[`testT08P_54_87_resolverAndTrustRejections`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | L pinned carrier and remux blocking only; native TLS/focus U pending. |
| TPOC-79 | [`PoCBootstrapTests.test_TPOC_02_non_admin_random_password_is_private`](../scripts/test_jellyfin_bootstrap.py) | Python private random viewer-password test only; admin/per-run/CI masking/full scan evidence pending. |
| TPOC-80 | — | Pending pre-upload reject-on-secret scanner; redact_artifacts self-test alone is not this row. |
| TPOC-81 | — | Pending per-journey xcresult + recording + redacted API/session logs. |
| TPOC-82 | — | Pending mock-only single-season focusable picker; two-season seed is intentionally not used. |

## Follow-up 4 security traceability

The plans under `/workspace/jellyfin-tvos/test` were checked again. They have
no dedicated userinfo rejection row. T08-2-52/53 are in merged main's plan but
absent from that external snapshot; T08-2-52 documents origin comparison, not
playback rejection. The supplemental cases are therefore recorded as gaps
related to the existing origin/token rows. All new userinfo tests below run
in both Debug and Release.

| ID / gap | Matching coverage | Scope |
| --- | --- | --- |
| T08P-14/97 | `PlaybackPoCDecisionTests.testT08P_06_07_08_10_12_14_16_profileDecisionMatrix`, `PlaybackCoordinatorTests.testT08P_94_95_96_97_defaultVideoPrecheck` | Canonical codecs still accept mixed case; h265/H265 now reject before negotiation/media. |
| T08-2-14 | `ADRM08PrototypeTests.testT08_2_14_headerPathStripsCredentialQueriesIgnoringCase` | Query stripping remains covered; userinfo playback stripping is superseded by rejection. |
| T08P-70/88; T08-2-50 | `MediaLoaderSecurityTests.testT08P_70_88_masterAndVariantUseLoaderAndSegmentsStayOnOrigin`, existing cross-origin URI tests | Existing header, segment-query-token and origin/downgrade regressions retained. |
| T08-2-52/53 (merged plan) | `MediaOriginTests`, `MediaFailurePrecedenceTests` | Existing origin/userinfo documentation and loader failure precedence retained unchanged. |
| Gap: userinfo segment/key rejection (related T08P-88 / T08-2-50) | [`MediaUserInfoSecurityTests.testUserInfoSegmentsAndKeysRejectServerPlaylistBeforeDelivery`](../Packages/GlassfinCore/Tests/CorePlaybackTests/MediaUserInfoSecurityTests.swift) | Reject complete fetched playlists with credential-bearing media, map, part or key URLs; no bytes delivered; mock log contains only the clean playlist request. |
| Gap: userinfo variant rejection (related T08P-70 / T08-2-50) | [`MediaUserInfoSecurityTests.testUserInfoVariantPlaylistsRejectServerMasterBeforeDelivery`](../Packages/GlassfinCore/Tests/CorePlaybackTests/MediaUserInfoSecurityTests.swift) | Plain/scheme-relative variants, audio rendition and I-frame URI attributes reject before handoff. |
| Gap: userinfo TranscodingUrl / resolved URL (related T08P-54/69/70) | [`MediaUserInfoSecurityTests.testUserInfoTranscodingURLsAndServerURLsAreRejected`](../Packages/GlassfinCore/Tests/CorePlaybackTests/MediaUserInfoSecurityTests.swift), `testUserInfoInitialAndResolvedURLsNeverReachTransportOrPlayer`, `testUserInfoRedirectNeverReachesTransport`, [`PlaybackCoordinatorTests.testUserInfoTranscodingURLFailsBeforeMediaRequest`](../Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift) | Builders, initial/master URL, absolute/scheme-relative TranscodingUrl, resolver redirects and planner block; initial failures send zero media requests, redirects send only the clean first request. |
| Gap: loader request credentials (related T08P-69/70) | [`MediaUserInfoSecurityTests.testUserInfoLoaderRequestsAreRejectedEvenAfterMutation`](../Packages/GlassfinCore/Tests/CorePlaybackTests/MediaUserInfoSecurityTests.swift), `testAtSignInPathAndQueryDoesNotRejectSafePlayback` | Direct wrapper/planner and mutable request bypass attempts reject with an empty mock request log; harmless path/query @ still works. Request-log assertions inspect URLComponents.user/password directly. |

The matrix includes nonempty, empty and percent-encoded user/password fields:
`user:password@`, `user@`, `:password@`, `@`, `:@`, `user:@`, `%75ser:%70w@`.

## Generated media and bootstrap

`scripts/generate-playback-media.sh MEDIA_DIRECTORY [FFMPEG_PATH]` has no Docker
or network dependency (`FFMPEG` and `GLASSFIN_MEDIA_DIR` are also accepted).
It produces Movies/F1–F6 at 160×90 and 12 fps using deterministic testsrc/sine,
bitexact muxing and single-thread ultrafast encoders. F1 MP4 H.264/AAC and F3 MKV
H.264/AAC are about 60 seconds; F2 HEVC/E-AC-3 (`hvc1`), F4 H.264/DTS, F5
MPEG-2/AAC and F6 HEVC/AC-3 are six seconds. Season 1 has three 60-second
H.264/AAC episodes; Season 2 has one six-second S02E01. Paths use
`Shows/Glassfin Test Show (2026)/Season 01` and `Season 02`; local NFOs fix 2026
air dates. TPOC-24/38/39 use this two-season seed; TPOC-82 remains mock-only.
All synthetic media is CC0 and remains uncommitted.

Bootstrap accepts `--server-url` / `GLASSFIN_SERVER_URL` and `--media-dir` /
`GLASSFIN_SERVER_MEDIA_DIR` (a path visible to the server). It reads/updates
`/System/Configuration`, changes only `MinResumeDurationSeconds=0` and
`QuickConnectAvailable=true`, preserves the 5/90 resume percentages, creates
both offline-metadata libraries and waits for video probing and scan completion.
The Docker wrapper exports generated `GLASSFIN_TEST_USERNAME` and
`GLASSFIN_TEST_PASSWORD` alongside the admin credentials. A native caller can
supply those variables or receive generated credentials through
`GLASSFIN_TEST_CREDENTIALS_FILE` (mode 0600). No password/token is printed.
Live tests require `GLASSFIN_INTEGRATION=1`; they fetch HLS bytes and inspect
`/Sessions` for copied video and the expected audio conversion.

## Remaining validation and full M08a work

Apple compilation, device playback, Menu/focus behavior, seek accuracy and
HDR/display matching require Xcode/tvOS hardware. Linux checks do not establish
those results. Live Jellyfin checks require Docker and the configured server
matrix. The previous ADR measurement checklist remains applicable.

TODO (M08a full scope): runtime device/display capabilities, track selection,
subtitle rendering, trickplay, media segments, next-up, buffering timeout UI,
Ping and reconnect delivery of failed Stopped reports.
Video transcoding is deliberately excluded from this PoC.

## Local verification (Follow-up 4)

- Linux Swift 6.4.1 `swift build`, `swift test` and `swift test -c release` passed.
  Debug: 253 tests; Release: 252 tests; each has seven gated live-server skips
  and zero failures. Coverage's native test run passed 253 tests with seven skips.
- `scripts/coverage-gate.sh`: 92.95% line coverage (4180/4497), threshold 80%.
- All lint commands from `ci.yml` passed: SwiftLint 0.65.1, strict recursive
  swift-format, license checks and self-test, source greps, entitlements,
  debug-string/credential-construction checks and self-test, artifact-redactor
  self-test. SwiftLint warns that custom_rules require prohibited SourceKit;
  `ci-grep.sh` passed independently. Path filter and shell syntax also passed.
- All 16 combined bootstrap Python tests passed, including 12.2 recovery and
  the two-season/four-episode scan requirements. `git diff --check` passed.
- `MediaOrigin.swift` and `MediaOriginTests.swift` have no diff from merged main.
  Main's chunked body reader/appender and failure precedence remain intact.

Live-server tests are gated off. Apple compilation, actual AVPlayer/TLS behavior,
UI/device journeys, the three-version live matrix and Release app binary scans
were not run on Linux. The model tests do not establish simulator acceptance.

## Open questions

- Test-plan gap: assign dedicated IDs for the new userinfo rejection cases.
- Q8P-04: audio output preference/channel policy; current profile keeps AAC/EAC3
  and current video-copy URL chooses AAC for audio conversion.
- Q8P-07: whether remux requires Ping; Q8P-09: report-401/auth handling and pending
  report policy; Q8P-12: media timeout bound. These existing questions remain
  outside this credential check.
- Native AVPlayer decoding, first-frame timing/watchdog, focus/VoiceOver,
  simulator recordings, three-version live matrix and artifact/binary evidence
  remain runner validation. The complete mapping marks the specific gaps.
