# PoC acceptance: F3/F4 AVPlayer journeys (UI tests)

This document maps the UI tests in `Apps/Shared/UITests/TPOCPlaybackAcceptanceUITests.swift` to the
PoC acceptance rows for the F3 and F4 fixtures. The canonical rows live in
`spec/TESTPLAN-PoC-ACCEPTANCE.md` (J3) and `spec/TESTPLAN-M08a-PoC.md`.

## Fixtures

| Fixture | Definition (SPEC.md) | Seed file (`scripts/generate-playback-media.sh`) |
| --- | --- | --- |
| F3 | MKV, H.264 + AAC, about 60 s. The server remuxes to HLS; video and audio are copied. | `Movies/Glassfin Remux (2024).mkv` |
| F4 | MKV, H.264 + DTS. Video is copied, audio is transcoded; it must play. | `Movies/Glassfin DTS (2024).mkv` |

The tests find each movie by its media (container `mkv`, video `h264`, audio `aac` or `dts`) through the
admin API, so they do not depend on titles. No new media fixture is added; the existing seed is reused.

## Test mapping

### `testTPOC_16_f3RemuxPlaysAsDirectStreamWithOnlyContainerReason` (TPOC-16)

| Step | Assertion | Rows |
| --- | --- | --- |
| Reset the F3 item's user data, launch without `-uitest-*` flags, sign in with the non-admin user | Home appears | TPOC-07 path |
| Movies tab → `library.item.<F3>` → `detail.play` | No placeholder (`detail.playback.pending`, `library.playback.pending`, `home.playback`) | TPOC-13 path |
| Poll `/Sessions` for the test user's session on the F3 item | `PlayMethod == DirectStream`, `IsVideoDirect == true`, `IsAudioDirect == true` | T08P-08 |
| Same session | `TranscodeReasons == [ContainerNotSupported]` | T08P-81 |
| Poll `/Sessions` up to 25 s | `PositionTicks` advances by at least 2 s | T08P-09 |
| Throughout | No alert and no "could not be played" / "format isn't supported" text | TPOC-16 "plays" |
| Menu | `detail.root` is shown again | TPOC-16 exit |

### `testTPOC_17_f4DtsPlaysWithAudioOnlyTranscodeAndNoError` (TPOC-17)

| Step | Assertion | Rows |
| --- | --- | --- |
| Reset, launch, sign in, Movies tab → `library.item.<F4>` → `detail.play` | As for TPOC-16 | TPOC-07, TPOC-13 path |
| Poll `/Sessions` | `PlayMethod == DirectStream`, `IsVideoDirect == true`, `IsAudioDirect == false` | T08P-10 |
| Same session | `AudioCodec` is `aac` or `eac3` | TESTPLAN-M08a Appendix A |
| Same session | No Q8P-05 video reason, at least one `Audio*` reason, nothing else except `ContainerNotSupported` | T08P-80, TPOC-17 |
| Until the item ends (about 6 s, 25 s limit) | Server `UserData.Played == true`; the player closes itself to `detail.root` | T08P-11 |
| Throughout | No alert and no failure text at any point | TPOC-17 "no error at any point" |

The app reports an audio-only transcode as `DirectStream` (see `PlaybackStreamSelection.swift` and
`PlaybackReporter.swift`), so both rows expect `DirectStream`.

## Running

The tests are tvOS only and skip with a clear reason when the live-server variables are missing, so the
default `test-tvos` job is unaffected. They need the native macOS Jellyfin server from TPOC-02, seeded by
`scripts/jellyfin_bootstrap.py`, and a clean simulator (TPOC-04: erase the simulator; `-uitest-reset`
cannot be used because it also enables the mock server).

| Variable (prefix with `TEST_RUNNER_` for xcodebuild) | Source |
| --- | --- |
| `GLASSFIN_POC_SERVER_URL` | `GLASSFIN_SERVER_URL`, for example `http://127.0.0.1:8096` |
| `GLASSFIN_POC_USERNAME`, `GLASSFIN_POC_PASSWORD` | The non-admin test user (`GLASSFIN_TEST_CREDENTIALS_FILE`) |
| `GLASSFIN_POC_ADMIN_USERNAME`, `GLASSFIN_POC_ADMIN_PASSWORD` | `GLASSFIN_USERNAME`, `GLASSFIN_PASSWORD` |

```sh
xcrun simctl erase "$SIMULATOR_UDID"
TEST_RUNNER_GLASSFIN_POC_SERVER_URL="$GLASSFIN_SERVER_URL" \
TEST_RUNNER_GLASSFIN_POC_USERNAME="$TEST_USER" TEST_RUNNER_GLASSFIN_POC_PASSWORD="$TEST_PASSWORD" \
TEST_RUNNER_GLASSFIN_POC_ADMIN_USERNAME="$GLASSFIN_USERNAME" \
TEST_RUNNER_GLASSFIN_POC_ADMIN_PASSWORD="$GLASSFIN_PASSWORD" \
xcodebuild test -project Glassfin.xcodeproj -scheme Glassfin-tvOS \
  -destination "id=$SIMULATOR_UDID" \
  -only-testing:Glassfin-tvOSUITests/TPOCPlaybackAcceptanceUITests
```

Passwords come only from the environment (TPOC-79). Screenshots are taken only on playback screens, never on
the credentials form, and the admin client never puts a token in a URL (TPOC-80, 03-security S5).

## What is still needed outside test code

These tests cannot pass on this branch alone. They will fail with a specific message at the first missing
piece. Each item needs app or CI changes, which this PR deliberately does not make:

1. **M07 library grid and detail (#23).** The journey uses `library.item.<id>`, `detail.root` and
   `detail.play`, which land with `feat/m07-library-detail`.
2. **M08 player adapter.** Detail Play and Home Play still open placeholders (`detail.playback.pending`,
   `home.playback`, `TODO(M08)` in `HomeRootView.swift`). `PlaybackView` must be presented from `detail.play`
   (and from Home) for any player journey to run.
3. **Live-server reset without mocks.** `-uitest-reset` also turns on the mock server
   (`LaunchConfiguration.swift`, `HomeMockLaunch`). The tests rely on a simulator erase; a reset-only flag
   would let one simulator run journeys back to back.
4. **CI job.** No workflow job starts the native macOS Jellyfin server, runs the bootstrap and passes the
   `TEST_RUNNER_GLASSFIN_POC_*` variables to the tvOS UI tests. Until one exists these tests skip in CI.
5. **Optional identifiers.** Assertions use server state plus the absence of alerts. A `playback.root`
   identifier and a `playback.error` element carrying the catalog key would make failures easier to read.
6. **Risk: ATS in the test runner.** The runner calls `http://127.0.0.1:8096` directly. If ATS blocks it,
   the UI test target needs `NSAllowsLocalNetworking` in its generated Info.plist (project.yml change).
