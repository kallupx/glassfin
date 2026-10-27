# M08a-PoC implementation

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

- Every start fetches the user's item and checks its default video codec before PlaybackInfo.
- `play(itemID:)` also reads `UserData.PlaybackPositionTicks` from that response.
- `play(itemID:choice: .resumeAt(ticks: savedTicks))` uses detail's saved position;
  the item request still verifies the video metadata.
- `play(itemID:choice: .startOver)` sends zero ticks.
- The observable state exposes loading, playing, paused, buffering, ended, a
  failure catalog key, and session expiry. Menu/dismiss stops the loader and
  attempts a Stopped report. Call `stop()` before releasing a coordinator.

## Codec and security choices

The static profile accepts MP4/MOV/M4V/HLS, H.264/HEVC and AAC/AC-3/E-AC-3. Other
containers use server HLS with fMP4; unsupported audio becomes AAC. The
TranscodingProfile's H.264/HEVC list describes compatible source/output codecs,
not permission to encode video: every HLS URL enforces `VideoCodec=copy` and
`SegmentContainer=mp4`. Unsupported source video, missing codec metadata, video
conversion reasons fail before engine loading. Missing server fallback URLs use the generic
playback error. The unsupported format uses its own catalog key in English and Finnish.
MPEG-2 (`mpeg2video`) is the canonical unsupported fixture; VC-1 is an additional
unit case. DTS and TrueHD request audio conversion with video copy; HEVC/AC-3 remuxes.

The pure `VideoTranscodeReasons` parser reads only the `TranscodeReasons` URL query
parameter; the DTO has no JSON-body reasons property. Exactly the 14 locked Q8P-05
video reasons block playback, including reference frames, interlacing, anamorphic
video and unknown video stream info. Other/unknown reasons are ignored. The
PlaybackInfo request keeps transcoding enabled so audio conversion can run.

`SubtitleStreamIndex=-1`, an empty SubtitleProfiles list, disabled manifest
subtitles and disabled native legible selection prevent subtitle burn-in. No
audio/subtitle selection UI is provided.

Both DirectPlay and HLS use the existing `PlaybackPreparation` and
`AVPlayerMediaSession` resource loader. The coordinator never enables the
prototype's header-key or query-token fallbacks, in Debug or Release. HLS
playlists/keys use Authorization; server-written segment credentials retain the
ADR M08-2 accepted risk. Absolute cross-origin URLs and HTTPS downgrades are
rejected before fetching. Pinned self-signed HLS stays blocked by the existing
planner because AVPlayer fetches its segments outside the app's trust delegate;
the error uses the distinct `hlsSegmentsBypassPinnedTrust` case and localized key.
It is raised before requesting a stream. DirectPlay retains the loader pin.
The error dialog focuses its sole OK action and dismissal returns to the caller.
Release also rejects query-token construction in the general media URL builder,
and the planner discards any supplied fallback URL. Test doubles live in test
targets so 401, logging and credential-policy tests execute in Release.

Reports use CoreNetworking, preserve ordering, clamp outbound positions and
retry transient failures once. A media/report 401 stops playback and attempts
Stopped before exactly one `/Users/Me` probe. Only a second 401 expires the
session; no playback retry is made. The probe survives cancellation of the
engine event task. AVPlayer URIs and error comments, and reporting diagnostics,
pass through `PlaybackLog`/`MediaLogRedactor`.

## Tests and generated media

Plan IDs are from Testaaja's TESTPLAN-M08a-PoC and TESTPLAN-PoC-ACCEPTANCE.
The latter's journey IDs below identify model/server portions only; simulator
navigation, actual decoded playback and Siri Remote focus are separate validation.
Function suffixes below follow `testT08P_<IDs>_` unless a full name is given.

| Plan ID | Test function suffix or full test name |
| --- | --- |
| T08P-01, 70 | `deviceProfileShapeAndVideoCopyURL` |
| T08P-02 | `playbackInfoRequestAndParsing` |
| T08P-03 | `firstMediaSourceUsedInURLAndReports` |
| T08P-04, 47 | `preparationErrorsFailBeforeEngineLoad` |
| T08P-05, 09, 11, 12, 34; TPOC-16, 17, 19 (server) | `testT08P_05_seedMediaPlaybackDecisions` (live Jellyfin) |
| T08P-06, 07, 08, 10, 12, 14, 16 | `profileDecisionMatrix` |
| T08P-08, 10, 70 | `hlsLoadsWithVideoCopyAndReportsDirectStream` (also TrueHD and HEVC/AC-3) |
| T08P-13, 14; TPOC-18 (model) | `unsupportedPreflightMakesZeroPlaybackRequests` (MPEG-2 and VC-1) |
| T08P-14 | `VideoTranscodeReasonsTests.testT08P_14_*` (one test per blocking reason, ignored values, empty/missing query, encoded commas, ignored JSON, default video selection); `queryVideoReasonsBlockBeforeStreamRequest` |
| T08P-15; TPOC-18 (model recovery) | `supportedPlaybackAfterUnsupportedError` |
| T08P-19, 24, 56 | `engineStatesAndRepeatedPlay` |
| T08P-23, 31 | `endAndErrorReportStoppedExactlyOnce` |
| T08P-25, 27, 29; TPOC-20 (report model) | `reportingSequenceAndFields` |
| T08P-26 | `progressTimerUsesClockAndCancels` (six 10-second ticks) |
| T08P-30 (retry only), 73 | `reportingRetriesOnceAndContinuesPlayback`, `transientRetryCanRecover` |
| T08P-32, 73 | `reportHTTPFailuresRedactAndKeepHeaderOnlyAuth` (real HTTPClient, mocked transport) |
| T08P-36 | `resumeTicksAndSaturation` |
| T08P-36, 37; TPOC-29, 30 (model) | `resumeAndStartOver` |
| T08P-42, 43, 45; TPOC-56, 57 (policy) | `mediaUnauthorizedChecksMeExactlyOnce` |
| T08P-44 | `playbackInfo401ExpiresSession` |
| T08P-42, 44 | `startupMedia401AndReport401` |
| T08P-43, 56 | `dismissalDuringStoppedStillChecksSession` |
| T08P-54 | `crossOriginHLSIsRejected` |
| T08P-54, 55 | `resolverAndTrustRejections` |
| T08P-55 | `pinnedDirectPlayUsesLoader` |
| T08P-56 | `stopDuringStartupDiscardsLateResponse`, `cancelledPlayLeavesIdle` |
| T08P-62 | `catalogKeysHaveBothTranslations` (locks exact unsupported/pinned copy and asserts the UI's catalog keys) |
| T08P-69, 71 | `directURLHasNoCredentialOrFallback` |
| T08P-70 | `testT08P_70_masterAndVariantUseLoaderAndSegmentsStayOnOrigin` (master/variant Authorization, preserved server segment credentials, origin/downgrade rejection) |
| T08P-71; TPOC-68 (Release policy) | `loaderFailureNeverUsesCredentialFallback` |
| T08P-73, 74; TPOC-67 (redaction model) | `playerAndReportingLogRedaction` |
| TPOC-02 | `BootstrapTests.test_TPOC_02_*` (five Python API mocks); `testTPOC_02_seedConfigurationAndNonAdminUser` (live) |
| TPOC-65 | `testTPOC_65_catalogCompleteness` |

The Release suite also runs the existing ADR loader/redactor/security tests.
The source lint rejects credential URL construction outside Debug guards.

`scripts/generate-playback-media.sh MEDIA_DIRECTORY [FFMPEG_PATH]` has no Docker
or network dependency (`FFMPEG` and `GLASSFIN_MEDIA_DIR` are also accepted).
It produces Movies/F1–F6 at 160×90 and 12 fps using deterministic testsrc/sine,
bitexact muxing and single-thread ultrafast encoders. F1 MP4 H.264/AAC and F3 MKV
H.264/AAC are about 60 seconds; F2 HEVC/E-AC-3 (`hvc1`), F4 H.264/DTS, F5
MPEG-2/AAC and F6 HEVC/AC-3 are six seconds. Three six-second H.264/AAC episodes
use Jellyfin's `Shows/Glassfin Test Show (2024)/Season 01/... S01E01.mp4` naming.
There is one season, per the final task scope (the acceptance plan's two-season
journey is not seeded here). All synthetic media is CC0 and remains uncommitted.

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
automatic fallback, Ping and reconnect delivery of failed Stopped reports.
Video transcoding is deliberately excluded from this PoC.

## Local verification (Linux, Swift 6.4.1)

- Rebased the original PoC onto `a40ded9` (#19), keeping its loader and redaction fixes.
  The post-rebase Debug build and 194 tests passed (6 gated live tests skipped).
- Final Debug and Release builds passed. Debug: 222 tests, 7 gated live tests
  skipped, zero failures. Release: 221 tests, the same 7 skipped, zero failures.
  The 401, loader/origin, log-redaction and no-fallback tests execute in Release.
- Coverage gate: 92.69% (4047/4366 lines), above the 80% requirement.
- Five Python bootstrap API-mock tests passed; they run in the existing lint job.
- swift-format, SwiftLint 0.65.1, source greps, Debug-only/credential-builder
  checks, license checks, entitlements, artifact-redactor self-test, Python
  compilation, shell syntax and `git diff --check` passed. SwiftLint reports
  that its custom_rules need unavailable SourceKit; the source grep passes.
- ffprobe confirmed all nine files' codecs, durations, channels and F2's `hvc1`
  tag. Two successive generated sets had identical SHA-256 hashes; generation
  took about 3–5 seconds and the complete seed is about 5.6 MB.

Docker and Xcode are not installed in this environment; live-server tests are
skipped, and no Apple build, simulator journey, device measurement or Release
app binary scan is claimed. No poc-acceptance CI job is added; that remains a
follow-up PR.

T08P-61 is device/manual only; TPOC-69–77 are the optional device checklist.
Other Apple-only portions include native playback/seek and focus (T08P-18–23,
38–41, 57–60), VoiceOver, locale snapshots (63–64), simulator/device metrics
(65–68), and Now Playing metadata (78). The model/security portions listed
above do not establish those UI/device results. Pending implementation from
the original PoC includes automatic fallback (17), Ping (28), reconnect delivery
of failed Stopped (30), permission UI (46), buffering/reconnect timeouts
(48–52), and integration of Home refresh/resume (33). The final one-season seed
also does not cover TPOC-24/38/39's second-season journey.
