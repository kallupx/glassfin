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

- `play(itemID:)` fetches the user's item to read `UserData.PlaybackPositionTicks`.
- `play(itemID:choice: .resumeAt(ticks: savedTicks))` uses detail's existing data.
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
conversion reasons or a missing server fallback fail before engine loading.

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
M08b's loopback proxy is still needed for that case.

Reports use CoreNetworking, preserve ordering, clamp outbound positions and
retry transient failures once. A media/report 401 stops playback and attempts
Stopped before exactly one `/Users/Me` probe. Only a second 401 expires the
session; no playback retry is made. The probe survives cancellation of the
engine event task. AVPlayer URIs and error comments, and reporting diagnostics,
pass through `PlaybackLog`/`MediaLogRedactor`.

## Tests and generated media

`PlaybackPoCTests.swift` covers T08a-PoC-01 (HTTP request/parsing), 02 (decisions),
03 (profile/video-copy URL), 05 (tick boundaries), 09 (DirectPlay carrier), and
10 (catalog keys/translations). `PlaybackCoordinatorTests.swift` covers 03
(HLS), 04 (report ordering/retry), 05 (resume/start-over), 06 (errors/origins/trust),
07 (401 paths), 08 (redaction), 11 (injected clock), 12 (startup cancellation),
13 (terminal reports), and 15 (states/repeated play). Assertions use catalog keys.

T08a-PoC-14 in `Tests/IntegrationTests` checks the five generated fixtures with
live PlaybackInfo and URL construction only, gated by `GLASSFIN_INTEGRATION=1`.
`scripts/docker-integration.sh` invokes `scripts/generate-playback-media.sh` and
waits for all five movies to be scanned. The generator can also run alone with
a temporary media directory. All clips are synthetic lavfi test patterns and
sine waves dedicated to the public domain under CC0; no media is committed.

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

- Debug build and `swift test`: passed.
- Coverage gate: 166 tests, 6 live-server tests skipped, zero failures;
  line coverage 93.73% (4034/4304), above the 80% threshold.
- Release build: passed.
- swift-format, source greps, debug-string checks, license checks, entitlements
  and artifact-redactor self-tests: passed.
- CI-pinned SwiftLint 0.65.1: passed; it warned that `custom_rules` was skipped
  because SourceKit access was prohibited. Source greps independently passed.
- Generated all five fixtures and checked codecs, HEVC `hvc1` and approximately
  three-second durations with ffprobe; missing-encoder failure also checked.
- Docker and Xcode are unavailable in this worktree environment; live Jellyfin
  integration and Apple compilation/device checks were not run.
