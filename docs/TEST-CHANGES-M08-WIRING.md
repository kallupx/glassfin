# M08 playback wiring test audit

The wiring change adds two test files and preserves every existing assertion. The required M07/main merge also inherits the test files described below unchanged from that base. This PR adds:

- `Packages/GlassfinCore/Tests/CoreStateTests/T08PlaybackWiringTests.swift`: five tests covering detail Resume versus From beginning through PlaybackInfo and engine loading, Stopped payloads and idempotent dismissal, optimistic UserDataStore updates that preserve favorites, return focus identifiers, natural-end reporting before dismissal, track options, negative tick clamping, and startup failure.
- `Apps/Shared/UITests/T08PlaybackWiringUITests.swift`: five tvOS / three iOS tests covering the shared presentation host with the existing library fixtures and mock playback engine. They assert `playback.root`, Menu return to detail, From beginning focus restoration, episode selection, Home Play/Pause and card focus restoration, and localized startup errors.

The existing M07 debug scenarios retain their navigation-only episode behavior when no playback presentation action is installed. New `series-playback` and `series-playback-error` scenarios install the same presentation host used by the authenticated app. This preserves the M07 navigation assertions while exercising the new episode playback behavior separately. No real Jellyfin server is contacted.

Playback copy reuses the existing CoreModels String Catalog translations in English and Finnish. No user-facing text is introduced outside the catalogs.

The tvOS AVKit wrapper uses Apple's `playerViewControllerShouldDismiss(_:)` delegate to defer presentation dismissal until the coordinator has completed Stopped and the local update: https://developer.apple.com/documentation/avkit/avplayerviewcontrollerdelegate/playerviewcontrollershoulddismiss(_:)

Linux validation runs `swift test` for `Packages/GlassfinCore`, plus repository source, localization, formatting, lint and coverage checks. Apple builds and UI tests run only in GitHub Actions. While this PR targets `feat/m07-library-detail`, the PR workflow does not run for that base. After #23 merges, retarget to `main`, merge `origin/main` with a merge commit, and watch the resulting checks.

Known scope limits: mock UI tests validate presentation, report sequencing and focus rather than AV decoding or device playback performance. The existing M08a PoC codec, remux, pinning and reporting limits remain. Search playback and advanced playback features are outside this wiring change.

## M07/main synchronization and CI corrections

The required merge of `origin/feat/m07-library-detail` at `942f4f0` inherits main's merged #44 (`085582b`). PR #42 is not merged. The resumed task explicitly identified this updated main as the continuation point.

Inherited test files match the M07 base byte for byte:
- `Packages/GlassfinCore/Tests/CorePlaybackTests/DefaultAudioSelectionTests.swift` (added by #44).
- `Packages/GlassfinCore/Tests/CorePlaybackTests/FullPlaybackTests.swift` (added by #44).
- `Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift` (the base selects its preserved PoC configuration; assertions are untouched).

The first manual Apple run exposed a tvOS delegate conformance isolation error and iOS detail actions laid out outside the screen. The delegate conformance is now explicitly isolated to MainActor. Detail backdrop layout uses its displayed size, and the iOS action bar scrolls horizontally so Play and From beginning remain reachable. No test or assertion was weakened to fix these failures. The base's track menus, subtitle overlay, full negotiation and PoC regression path are retained.

After base synchronization: Linux `scripts/coverage-gate.sh` passes 687 tests with 10 skipped and zero failures; line coverage is 92.19% (10887/11809). Formatting, SwiftLint, source/design/catalog checks, debug-string checks, and test-target checks pass.

## Watchdog continuation: tvOS accessibility and focus

Diagnosed run `40782012438` from the completed tvOS job log and downloaded `tvos-results` xcresult exports (accessibility hierarchies and test activities). The player and localized error were present. The outer `home.playback` accessibility modifier replaced the child's `playback.root`, causing four root-existence assertions and the startup-error test to fail before checking its visible error. The return hierarchy also showed From beginning missing after its saved position became zero.

The player destination now owns a stable ZStack and the single `playback.root` accessibility container across loading, playback and error. Home's existing `home.playback` identifier/value belongs to the separate native media surface. Startup runs once for the stable destination. The detail action bar remembers that From beginning was offered, keeping its button mounted when playback resets progress to zero and focus temporarily leaves the screen.

No test file or assertion is changed by this correction. The original UI assertions remain the regression checks. The required merge of main `c87d897` brings the CI-only local Jellyfin E2E workflow change; no real server is used in this worktree.

The same main merge inherits `Apps/Shared/Tests/Logic/UITestStateResetTests.swift` and `scripts/ci/test_jellyfin_e2e.py` unchanged; their assertions are retained exactly. Validation of the correction: Linux `swift test --package-path Packages/GlassfinCore` passes all 687 tests (10 skipped, zero failures), plus formatting, SwiftLint and repository source/catalog checks.
