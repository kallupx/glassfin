# Apple TV P1–P15 measurement runbook

Use this with [SPEC §3a](../spec/SPEC.md#3a-poc-tier-p0-poc-decided-27102026)
and [M02 performance targets and clarifications](../spec/02-state-errors-performance.md#4-performance-requirements-measurable-targets).
Device measurements are an MVP release requirement, explicitly outside PoC
acceptance. No device numbers have been collected by this PR.

## Start here: a repeatable smoke benchmark

On the owner's Mac, install the Xcode version required by `project.yml` and the
package manifest, select it with `xcode-select`, accept its license, and install
the tvOS platform. Install XcodeGen and ffmpeg (`brew install xcodegen ffmpeg`).
Pair the Apple TV in Xcode → Window → Devices and Simulators; enable Developer
Mode on the Apple TV if requested. Use a tvOS version supported by that Xcode
and record the actual versions, rather than assuming the spec's platform claims.
Sign into Xcode → Settings → Accounts with the owner's Apple Developer team.

```bash
git switch feat/perf-measurement-kit
git pull --ff-only
xcrun xctrace list devices
# Substitute the paired Apple TV identifier and the owner's team identifier.
bash scripts/device-measurement.sh APPLE_TV_UDID DEVELOPMENT_TEAM
```

The runner generates a CC0 12-second H.264/320×180/30 fps fixture, regenerates
`Glassfin.xcodeproj`, and runs only the new performance classes on the Apple TV.
It explicitly overrides the repository's unsigned CI settings with automatic
Apple Development signing for the app and test runners. Let Xcode register the
device/provision profiles; a signing failure must be resolved in the owner's
account. The device must be unlocked, reachable, and available to Xcode.
Results are in `artifacts/device-perf/<UTC timestamp>.xcresult`. Open the bundle
in Xcode, select a test, and inspect its Performance metrics and each iteration.
No credentials or server are needed. Both Debug test actions pass the existing
`-uitest-mock-server` flag to isolate hosted app startup from saved sessions.
Tests do not use the owner's saved session.

The equivalent `xcodebuild test` command, signing overrides, and exact
`-only-testing` selectors are in [the runner](../scripts/device-measurement.sh).
To run just one test, replace its selectors with, for example:
`-only-testing:Glassfin-tvOSUnitTests/DevicePlaybackPerformanceTests/testP5_nativeFirstFrameFromMockOrigin`.
Use `-test-iterations 10` for more samples; record that each P1/P5 test also has
three measured iterations internally. Do not merge different tests' samples.
A missing generated fixture skips the native tests. Treat that as incomplete:
run `scripts/prepare-perf-fixture.sh` **before** `xcodegen generate` and rerun.

The smoke suite measures:

- P1: the existing signed-in mock Home, application launch, clock, and Home-row
  signpost. Each iteration terminates the app; this is process-cold, with warm
  filesystem/OS caches, not a reboot or a purged-cache measurement.
- P3/P11: real Siri Remote focus changes in mock Home and the M07 2,000-item
  paged grid; clock, app CPU, app memory, and focus-update signposts. The grid
  test checks the reported total and scrolls through several lazily loaded pages,
  rather than preloading every item. Mock artwork does not model LAN downloads.
- P5: the production PlaybackCoordinator → AVPlayerEngine → resource loader →
  native AVPlayerLayer first-frame readiness, with an in-memory API/byte origin.
  It is a native decoding regression, excluding LAN and server latency.
- P12/P13: ten native play → first-frame → stop cycles in one process and one
  measured block. Memory includes the hosted XCTest process. This short, small
  fixture does not establish full-length/4K peak memory or retained-growth limits.

Simulator CI runs these same classes automatically in the normal tvOS/iOS jobs;
iOS omits the Siri Remote test. Metrics are trends, with no device-budget
assertions. Absolute device targets require the separate scenarios below.

## Install the build for acceptance measurements

For local Xcode installation, regenerate the project, select `Glassfin-tvOS`,
select the paired Apple TV, and set the owner's development team and automatic
signing. The runner's `CODE_SIGNING_ALLOWED=YES`, `CODE_SIGNING_REQUIRED=YES`,
`CODE_SIGN_STYLE=Automatic`, and `CODE_SIGN_IDENTITY=Apple Development` overrides
are needed because the project defaults are for unsigned CI. Launch once to
complete first-install setup, then stop the debugger. For comparable release
numbers, use a signed **Release** build, disable coverage, diagnostics such as
Address Sanitizer, and view debugging, and record optimization and signing.
Do not add UI-test launch arguments to acceptance runs.

For TestFlight, the owner archives a signed Release build using an App Store
profile, uploads through Organizer, assigns the build to a test group, installs
TestFlight on Apple TV, and selects the exact version/build. No mock arguments
or generated test media are present in the Release app. XCTest cannot target a
TestFlight installation: use the signed development build for automation.
If profiling/attachment is unavailable for the distributed build, collect
manual visible timings there and reproduce in the signed Release development
build for Instruments. Label the two distributions separately. The repo does
not configure TestFlight credentials or enable MetricKit collection.

## Prepare a dedicated LAN Docker server

Never use a personal/production Jellyfin server or library. Use Docker Desktop
on the owner's Mac, or a Docker host on the same private LAN. The existing
`scripts/docker-integration.sh` is an isolated, automatically removed localhost
server: it is useful for protocol regression, but Apple TV cannot reach its
`127.0.0.1` binding. For a persistent device-only test fixture:

```bash
# Ten-minute LAN media supports resume, ±30-second seeks, and five-minute playback runs.
bash scripts/prepare-perf-fixture.sh "$HOME/glassfin-perf-input.mp4" 600
# A new empty directory, outside the checkout. Hard links keep storage small.
python3 scripts/prepare-perf-library.py "$HOME/glassfin-perf-media" \
  --video "$HOME/glassfin-perf-input.mp4" --movies 4997
# Three dedicated playback samples bring the movie total to exactly 5,000.
bash scripts/prepare-perf-playback.sh "$HOME/glassfin-perf-media/movies" 600
mkdir -p "$HOME/glassfin-perf-config"
docker run -d --name glassfin-device-perf \
  -p 8096:8096 \
  -v "$HOME/glassfin-perf-config:/config" \
  -v "$HOME/glassfin-perf-media:/media:ro" \
  jellyfin/jellyfin:12.2@sha256:357724bf0ae27a672c7cbaa899db2d9abeb13dbd8657ccce750258a4c059d037
```

Finish the startup wizard in the local Docker server's web UI. Add Movies at
`/media/movies` and Shows at `/media/shows`, enable local NFO/artwork, and disable
online metadata/artwork providers. Create a dedicated non-admin measurement
user. Wait for the scan and verify **5,000 movies and 500 series** (two episodes
per series, 1,000 episodes total), poster display, DirectPlay support, and idle
server CPU. The movie total is 4,997 ordinary items plus the three playback
samples below. In the Docker web player, seek an ordinary movie to 60 seconds,
then stop to populate Continue Watching. Mark episode 1 of a series watched to
populate Next Up with episode 2. Before each P14/P15 trial, restore the selected
synthetic items' watched/progress state in the Docker server's web UI so trials
begin from the same state. Sign into the same test user on Apple TV
using the Docker host's private LAN address. Record a server alias, image digest,
fixture counts, and settings; do not put the address or credentials in results.
Docker port 8096 is for this private test LAN; stop it with
`docker stop glassfin-device-perf` after measuring. Preserve the dedicated data
folders for repeat runs; do not point these commands at personal data.

The three named playback samples are deterministic, ten-minute inputs:

| Sample | Purpose and required verification |
|---|---|
| Perf Native Tracks | H.264 MP4, two AAC stereo tones (440/880 Hz), and two embedded mov_text subtitle tracks. P5/P7 and P9 DirectPlay: verify PlayMethod is DirectPlay; switch between the two distinguishable tones/subtitle samples and confirm continuous playback. |
| Perf Server Remux | Copied H.264/two AAC tracks in MKV, with two external SRT files for server VTT conversion. P9 HLS: verify PlayMethod is DirectStream and segments are HLS; record native selection versus renegotiation/reload. A reload does not pass P9's no-restart target. |
| Perf Video Transcode | MPEG-2 video in MKV, outside the runtime DirectPlay profile. P6: use full M08a and verify Diagnostics reports Transcode with video encoding. DirectStream/video-copy output is not P6. Record server CPU/encoding startup separately. |

Audio/subtitle language tags are `eng` and `fin`; fixture titles and subtitle
samples are English. The helpers generate files only and do not contact a
server. The owner must verify the actual negotiated PlayMethod/codec in the
player diagnostics and Docker server dashboard: generation/ffprobe output is
not proof of a server/device playback result. M08 connects Home, detail, and
episode playback to the native player. The samples are low-resolution/low-bitrate inputs;
record that scope rather than treating them as 4K stress measurements.

The small seed is for UI scale, cache, and startup repeatability. For representative
playback memory/bitrate runs, generate a separate synthetic long-form fixture,
record the generation command, duration, codec, resolution, frame rate, and bitrate,
and add it to this Docker library. For example, ffmpeg `testsrc2=size=1920x1080:rate=30`
with `-t 300 -c:v libx264 -pix_fmt yuv420p -b:v 15M -movflags +faststart` produces
a five-minute 1080p video. Use a separately recorded HEVC/4K fixture when testing
that path. Small-file native benchmark results cannot stand in for that scenario.
For P6/P9, use a caller configured for full M08a (the coordinator default after
PR #44), rather than the explicitly limited `.poc` configuration. M08 routes
Home Play/Pause, detail Resume/From beginning, and episode actions through the
shared playback presentation host. Use those routes with the Docker test server.

## Capture and repeat consistently

Copy [PERF-RESULTS-TEMPLATE.md](PERF-RESULTS-TEMPLATE.md) for each build/device/network
combination. Record commit, build, device model/chip, actual OS/Xcode, display mode
(60 Hz for P3), glass/accessibility settings, LAN versus Wi-Fi 5, fixture, cache
state, and server load. Measure A15, A12 glass, and the oldest supported device
available. Apply the spec's oldest column only to its oldest device; record A12
separately because it has no explicit target column. Unsupported/unavailable
hardware is an unmeasured limit, never a pass.

Use Instruments on the Mac, select the paired Apple TV and Glassfin, and add
**os_signpost / Points of Interest**, **App Launch**, **Animation Hitches**,
**Time Profiler**, and **Allocations/VM Tracker** as appropriate. Save a reusable
Instruments template. For cold launch, select launch/record, rather than attaching
after startup. Filter custom intervals to subsystem `org.glassfin.app`, category
`DevicePerformance`; the older category `Performance` contains model timings.
Capture memory and hitches in separate runs when profiler overhead is material.
Launch without a debugger for the timing/memory pass. Keep raw `.trace` and
`.xcresult` locally; record sanitized filenames and selected numeric values.

Run one separate warm-up for warm scenarios. Collect at least **20 valid trials**
per latency scenario, and 3 runs of each memory/hitch scenario. Preserve all raw
values, including failures. Compute median and nearest-rank p95 by sorting n
samples and taking index `ceil(0.95*n)` (1-based). P2 explicitly gates p95; for the
other latency rows report median/p95/max and use max for the conservative target
comparison. Report sample count and failures; do not drop slow successes. Exclude
intervals marked `cancelled` from success statistics, but count and explain them.
Intervals are closed on errors/cancellation with this fixed marker, never with
an error string. A missing begin/end pair is missing evidence.

For true rendered endpoints, use the Instruments render timeline or a 60 fps
screen recording/external camera with the remote action and TV visible. Frame
counts × 1000/60 give milliseconds with roughly one-frame resolution. `onAppear`,
image-state assignment, first-frame-ready, and timeControlStatus are proxies;
report their names and verify visible behavior instead of calling them GPU
presentation timestamps. App-init markers omit pre-main work; App Launch supplies
that part. Cold cache runs use a fresh dedicated install/test user cache and
re-login **before** recording; warm runs revisit the same content. Never include
interactive login in signed-in P1.

## P1–P15 procedures and evidence

Targets below are **A15 / oldest**, from M02. Timings are milliseconds unless noted.

| ID | Target | Start → end and repeatable procedure | Evidence and current limits |
|---|---|---|---|
| P1 | ≤1500 / ≤3000 | Signed in, LAN; force quit, record launch → first Home row visible. Repeat warm disk and separately purged-cache cases. | App Launch plus `DevicePerformance:launch.homeRowVisible`; marker begins at app init and ends at row `onAppear`. Also `launch.interactive` ends at first accepted Home focus. Confirm pixels/focus; old `Performance:launch.homeFirstRow` starts at model reload, omitting startup. |
| P2 | p95 ≤1000 / ≤2000 | Launch or return to Home → all sections loaded successfully. Use a stale Home (>60 s away) for return/refetch; also record cached return separately. | `home.load` covers actual Home load through all successful sections; `Performance:home.sections` is the existing model interval. On launch, measure from the P1 start timestamp to `home.load` end to include assembly/auth restoration. On return, include navigation → load start gap and confirm UI. Failed sections are not successful samples. |
| P3 | 60 fps, hitch <5 / <10 ms/s | Record 30 s of repeated left/right across Home rows, then 30 s up/down through a **2,000-item library grid**, same input cadence. | Animation Hitches: total hitch ms / captured seconds, FPS, trace. `browse.focusUpdate` covers only synchronous focus state handling, not animation/input latency. Mock tests cover Home rows and the M07 paged 2,000-item grid, using the existing `-uitest-library grid` fixture. The production library grid is available; profile the dedicated Docker library for acceptance. |
| P4 | cache ≤100/≤200; LAN ≤500/≤800 | Image demand → poster pixels visible. Revisit same row for cache; fresh cache for LAN. Capture 20 posters per path. | `poster.ready` spans load + decode → SwiftUI image assignment; nested completed `poster.cacheBytes` or `poster.networkBytes` identifies source. `image.decode` covers ImageIO worker decode; it is not total appearance latency. Correlate pixels. Cache-miss probes are marked cancelled. |
| P5 | ≤1500 / ≤2500 | Play confirmation → first visible video frame, DirectPlay on LAN; repeat same codec/resolution/bitrate. | `playback.firstFrame` starts at coordinator entry, includes metadata/PlaybackInfo/preparation, ends only when the presentation surface signals first-frame readiness. Native mock benchmark uses AVPlayerLayer. Product adapter uses AVPlayerViewController. M08 connects Home/detail/episode actions to this instrumented native player; use the Docker fixture for LAN trials. |
| P6 | ≤4000 / ≤6000 | Video transcode: capture both Play → first frame and PlaybackInfo response → first frame (M02 clarification). Record server startup cost separately. | Full M08a now supports video transcode. `playback.transcodeFirstFrame` begins after PlaybackInfo selects Transcode and ends on native first-frame readiness; measure Play → response separately to report total startup. `playback.directStreamFirstFrame` is video-copy DirectStream, not P6. M08 supplies the shared Home/detail/episode playback route for Docker LAN trials. Explicit `.poc` configurations do not transcode. |
| P7 | ≤1000 / ≤2000 | DirectPlay LAN; confirm a seek +30 s, then −30 s → visible moving video/audio resumed. Use long synthetic media. | `playback.seekResume`: explicit engine seek starts before AVPlayer seek; tvOS AVKit delegate starts at scrub confirmation and returns the unchanged target. End is playing status (after explicit seek completion). Confirm resumed motion; paused/cancelled seeks do not establish a success. Available through the M08 native playback route; validate against the Docker fixture. |
| P8 | cached ≤150 / ≤300 | Scrub over cached sprite tiles → correct preview visible. Repeat across 20 tiles. | Trickplay absent in PoC; blocked. Existing `Performance:playback.trickplay` only wraps the generic model hook. Once implemented, use cached tile request/visible image endpoints and video evidence. |
| P9 | ≤1000 / ≤2000; no restart | Switch audio then subtitles in DirectPlay and HLS, 20 changes each; confirm audible/visible result and continuous playback. | Full M08a supplies native transport menus and subtitle rendering. `DevicePerformance:playback.trackApply` spans a valid changed selection through native/model application or player-load handoff after renegotiation; it excludes the final progress report on native changes. This is not an audible/rendered endpoint. Record native versus reload paths separately; a playback restart fails the no-restart target even if its interval is short. Existing `Performance:playback.trackSwitch` is only the generic model hook. M08 supplies the shared playback route for full UI trials; explicit `.poc` configurations keep track selection disabled. |
| P10 | after debounce ≤500 / ≤1000 | Type a fixed synthetic query with results; last edit → 300 ms debounce → first results. Repeat different fixed queries on LAN. | `Performance:search.results` begins after debounce and ends after search/model update. Verify visible first results and record 300 ms separately. Search is implemented outside PoC; requires connected search UI and the dedicated test server. |
| P11 | browse ≤250 / ≤200 MB | Browse the full fixture for 5 min: rows, grid, detail, back; sample baseline and peak physical footprint. | XCTMemoryMetric(application:) for mock trends; Instruments physical footprint for acceptance (including image caches). Record memory warnings. Library grid/detail navigation is available after M07; browse the dedicated Docker fixture for acceptance rather than substituting short mock runs. |
| P12 | AVPlayer ≤400/≤300; remux ≤500/≤400 MB | Play long synthetic fixture for 5 min; sample steady/peak footprint separately for DirectPlay, server DirectStream, and on-device remux. | Native mock metric is a short decoder test. Use `playback.lifetime` to align active playback with memory. Server DirectStream is video-copy server output; on-device FFmpeg remux is future scope, so that variant is N/A. M08 supplies the playback UI route; device memory evidence is still required. |
| P13 | growth <20 MB on both | One process: warm once; stop on Home, wait 10 s, record baseline. Ten × (play 30 s → stop → Home → wait 10 s); record post-cycle footprint at each identical idle point, final minus baseline. | XCTMemoryMetric gives peak/growth trend, not proof of retained bytes. Confirm in Allocations/VM Tracker, excluding the warm-up and without relaunching; inspect retained objects. Native ten-cycle test is short lifecycle regression only. M08 supplies the Home playback/return journey; verify retained memory on device. |
| P14 | ≤2000 on both | Stop/finish a synthetic partially watched item → correct Home progress/played badge and Continue Watching membership. Include server report + refresh + rendering. | `home.watchedProjection` isolates store projection only. Start full measurement at stop action / `playback.lifetime` end; end at correct pixels. Existing M06 tests cover model/store refresh. M08 waits for Stopped and the local user-data update before dismissal; measure the complete return-to-Home journey against Docker. |
| P15 | ≤5000 on both | On a second client of the same Docker server/test user, toggle a fixed item's watched state. Record request/action → Apple TV badge/membership change. Repeat 20 times. | Use a synchronized dual-screen recording or aligned clocks. `home.remoteApply` starts only at received event application, not at second-client action; `home.watchedProjection` covers later model projection. Existing WebSocket tests do not prove network-to-pixels latency. Confirm the visible item really changes and no manual refresh occurs. |

## Existing tooling inventory and interpretation

- `CoreState/Performance.swift`: complete P1–P15 budget/name catalog, production
  OSSignposter, recording/no-op implementations; memory entries are events, not
  memory samplers. `BrowseInstrumentation` is a helper, not a wired scrolling FPS
  monitor. Linux instrumentation is a no-op.
- `HomeViewModel`, `AppState`, `SearchViewModel`, and the generic `PlayerViewModel`
  already emit model intervals. M07 provides library grid/detail navigation and its deterministic 2,000-item
  Debug grid. The production `PlaybackCoordinator` (full M08a
  by default, with an explicit `.poc` configuration) and
  `AVPlayerEngine` are separate from that generic player model. This kit adds
  scopes at the production coordinator, native presentation, image decoder,
  image pipeline, and app/Home UI boundaries without replacing existing names.
- `T02FoundationTests.testT02_18_signpostNamesBudgetsAndRecording` and
  `T02_33_AppleSignpostMetricTests` include synthetic signpost tests;
  `DesignSystemSnapshotTests.testT05_45_lazyGridSignpostTrend` renders a grid
  snapshot, rather than measuring real focus/scroll hitches. M06/M09 tests cover
  state, image sizing/decoding, caching, and event propagation.
- `ci.yml` runs lint/Linux tests and path-selected macOS tvOS/iOS tests through
  `scripts/macos-ci.sh`. These ordinary jobs run the complete mock performance
  suite. `integration.yml` is manually dispatched Docker protocol testing.
  There is no job literally named `poc-acceptance`. Main's opt-in `jellyfin-e2e`
  job (`scripts/ci/jellyfin-e2e.py`) starts native loopback Jellyfin for F3/F4
  acceptance tests when available; it does not implement every PoC journey or
  measure P1–P15. It runs on `workflow_dispatch` or the `full-ci` label. This
  Docker-only measurement workflow uses the ordinary PR jobs and leaves that
  label off. The optional `full-ui` job duplicates the regular tvOS suite; its
  absence does not remove any XCTest assertions from the ordinary tvOS job.
- `generate-playback-media.sh`, `jellyfin_bootstrap.py`, and
  `docker-integration.sh` seed/probe a small throwaway library, not the full
  performance library. `prepare-perf-library.py` creates the 5,000/500 offline
  synthetic library; `prepare-perf-playback.sh` adds explicit track/remux/transcode
  inputs. File generation is not proof that Jellyfin indexed or negotiated them.
- `export_xcresult.py` exports test/coverage/screenshot review files, not the
  complete per-iteration performance data. Keep the local result bundle for
  Xcode's performance report. `redact_artifacts.py` and artifact scanning remain
  in place. Never upload raw result bundles or traces from authenticated runs;
  manually review sanitized numeric summaries for addresses, tokens, names, and IDs.
- There is no MetricKit subscriber. M02 leaves crash reporting to a pre-TestFlight
  decision. This kit adds no background sampling, telemetry, uploads, or third-party
  reporting; signposts use fixed names and fixed completed/cancelled outcomes only.

Apple references: [XCTest signpost metrics](https://developer.apple.com/documentation/xctest/xctossignpostmetric),
[first-frame display readiness](https://developer.apple.com/documentation/avkit/avplayerviewcontroller/isreadyfordisplay),
and [AVKit scrub navigation delegate](https://developer.apple.com/documentation/avkit/avplayerviewcontrollerdelegate/playerviewcontroller(_:timetoseekafterusernavigatedfrom:to:)).
