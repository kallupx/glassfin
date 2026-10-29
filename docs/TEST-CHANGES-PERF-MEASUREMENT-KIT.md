# Performance measurement test additions

No test file or assertion inherited from main is changed. All existing assertions
in this kit's new test files are preserved. No baseline or acceptance threshold is
weakened. New test files:

- `Apps/Shared/UITests/DevicePerformanceTests.swift`: P1 mock Home launch (launch,
  clock, signpost metrics), P3/P11 tvOS focus/browse (clock, app CPU, app memory,
  signpost metrics). Three measured iterations; fixtures are the existing mock Home.
- `Apps/Shared/Tests/Logic/DevicePlaybackPerformanceTests.swift`: P5 native first
  frame (clock, CPU, memory, actual coordinator signpost), P12/P13 ten native
  play/stop cycles (clock, CPU, memory). Real AVPlayerEngine/resource loader and
  AVPlayerLayer display readiness; API and byte origin stay in memory. Requires
  generated 12-second H.264 fixture. Missing fixture explicitly skips these two
  tests; CI and the device runner generate it before XcodeGen, so they must run.

The native benchmarks use the hosted app process, including XCTest overhead.
They are decoder/lifecycle regression measurements, not LAN startup, full-length
4K memory, or proof that retained growth is below 20 MB. See the runbook for those
acceptance procedures. No absolute device budgets are asserted on simulators.

`project.yml` adds the generated fixture as an optional test bundle resource to
both existing hosted unit-test targets. Both Debug test actions pass the existing
`-uitest-mock-server` argument so hosted app startup cannot restore a saved
server session while benchmarks run. Run/Profile/Archive actions are unchanged.
`scripts/macos-ci.sh` prepares it before
project generation. Test suites remain in their existing schemes and therefore
run in the regular tvOS/iOS CI jobs. Existing synthetic performance tests remain
intact. Source-check assertions and artifact redaction rules remain intact.

The kit is rebased onto `085582b` (PR #44). Its existing full-playback and default
audio-selection tests and assertions are preserved. Conflict resolution keeps
main's track state/cleanup and playback negotiation, and classifies the new
first-frame interval from the negotiated PlayMethod. Full M08a track selection
also gets a fixed-name application/handoff interval. Neither instrument changes
negotiation, playback state, selected tracks, fallback policy, or rendering.

Main subsequently advanced to `f5f63e3` (M07), and the kit is rebased onto that
commit too. All M07 test files/assertions are inherited unchanged. The new
`DevicePerformanceTests` file adds `testP3_P11_mockTwoThousandItemGrid` without
changing its existing assertions: it verifies the fixture total, retains focus
while scrolling down/up through lazy pages, and collects clock/app CPU/app memory
and focus-update metrics. The fixture uses the existing Debug-only M07 host.
M07 grid focus, artwork loading, and thumbnail decoding now share the kit's fixed
measurement scopes; no paging, cache, decode, or UI behavior changes.

The generated Docker performance library uses two episodes per series so that
watching episode 1 produces an actual Next Up episode. Counts remain 5,000 movies
and 500 series, with 1,000 episodes; generation is verified with a small local
fixture without contacting a server. No test assertion changes are involved.
The runbook generates a separate ten-minute LAN input for resume/seek/longer
playback scenarios. The default native benchmark fixture remains twelve seconds;
`prepare-perf-fixture.sh` accepts an output path and duration for this purpose.
The runbook uses 4,997 ordinary movies plus three generated playback samples
for exactly 5,000 movies. The new offline `prepare-perf-playback.sh` generates
H.264 MP4 with two AAC/two mov_text tracks, H.264 MKV with two AAC/external SRT
tracks, and MPEG-2 MKV intended for video transcoding. A short local generation
and ffprobe verify the streams; negotiated playback still needs owner/device
evidence. None of these files contain personal media or credentials.

The final rebase also includes main's `c87d897` CI-only change. Its new opt-in
native Jellyfin E2E job is outside this task's mocks/Docker-only server scope,
so the PR uses ordinary tvOS/iOS CI without `full-ci`. The queued opt-in job was
cancelled before any step ran. Regular tvOS runs the identical suite as the
optional duplicate full-ui job; no tests, assertions, selectors, or workflow
conditions are changed by this kit to exclude test coverage.

The tvOS failure in CI run `40784493490` is confined to the new
`DevicePerformanceTests.testP3_P11_mockTwoThousandItemGrid` benchmark. The
`gh run view --log-failed` output ends during the Release build; the uploaded
`tvos-results/app-test.log` and exported xcresult identify the sole failure as
the focused-card existence assertion at the original line 77, during XCTest's
unmeasured warm-up traversal. The screen recording shows Movie 1 regaining focus
shortly after that immediate query, before another remote press. The three
measured traversals and every other test passed. This is an asynchronous
scroll/focus synchronization defect in the new benchmark, not evidence of a
main-branch infrastructure timeout.

The benchmark now captures the starting card's identity and waits up to ten
seconds for that same card to exist and regain focus after all twelve Down and
twelve Up presses. A new assertion requires the wait to complete; the original
focused-card assertion remains unchanged. No extra remote presses or focus
assignment can conceal lost focus. The fixture count, three measured iterations,
metrics, existing assertions, and acceptance thresholds remain intact. Clock,
CPU, and memory measurements include this synchronization overhead and remain
UI automation trends rather than raw focus latency or device acceptance proof.
No production focus behavior changes are required.

## M08/main merge synchronization

The kit merges main `589c5cf` (PR #51) with a merge commit. No test file or
assertion is edited during conflict resolution. The two M08 wiring test files
are inherited byte for byte from main; the existing performance tests remain
unchanged. Main's `docs/TEST-CHANGES-M08-WIRING.md` describes those additions.

`PlaybackView.swift` retains the MainActor AVKit delegate and deferred dismissal
through the shared host while preserving first-frame observation and seek
measurement. `PlaybackCoordinator.swift` retains request/track options, Stopped
sequencing, and return focus while measuring both playback entry points. The
shared destination remains the sole `playback.root` accessibility container,
starts playback once, and preserves `detail.startOver` focus restoration.

The device runbook now uses the connected Home/detail/episode playback routes
for Docker trials. No physical-device or server playback result is claimed.

Merge validation: Linux `swift test --package-path Packages/GlassfinCore` passes
687 tests (10 skipped, zero failures). Source/catalog, debug-only string,
unit-test target, and full Swift formatting checks pass. Apple validation runs
only in GitHub Actions.
