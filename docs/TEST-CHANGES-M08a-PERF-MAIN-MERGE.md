# M08a merge of main after PRs #32 and #49

## Scope

Merge `origin/main` at `290a287` into `feat/m08a-trickplay-segments` using a merge commit. The only conflict resolution is in `Apps/Shared/Sources/PlaybackView.swift`. It preserves main's first-frame observation and native seek measurement alongside the branch's scrub gestures, transport visibility, native Skip actions, Next Up overlay, and shared dismissal lifecycle.

## Test changes

No test file, test helper, or assertion was authored, edited, removed, disabled, or weakened for this merge resolution. The existing PB7 cancellation and focus-return test remains unchanged.

The merge imports the following test files verbatim from main:

- `Apps/Shared/Tests/Logic/DevicePlaybackPerformanceTests.swift`
- `Apps/Shared/UITests/DevicePerformanceTests.swift`
- `Packages/GlassfinCore/Tests/CoreModelsTests/T07TechnicalRowTests.swift`
- `Packages/GlassfinCore/Tests/CoreServicesTests/T07FilterEncodingTests.swift`
- `Packages/GlassfinCore/Tests/CoreStateTests/PinFailureTests.swift`
- `Packages/GlassfinCore/Tests/CoreStateTests/T07PoCFollowupTests.swift`

It also imports `Tests/Fixtures/m07-subtitles.json` and `Tests/Fixtures/m07-technical-items.json` verbatim. The six test files and two fixtures were compared byte-for-byte with `origin/main`. Every other pre-merge test file remains byte-for-byte unchanged from the branch parent.

The imported additions are documented by main's existing [M07 follow-up audit](TEST-CHANGES-M07-POC-FOLLOWUPS.md) and [performance measurement audit](TEST-CHANGES-PERF-MEASUREMENT-KIT.md).

## Validation

Linux Swift 6.4.1 package tests passed through `scripts/coverage-gate.sh`, which invokes `swift test --enable-code-coverage --build-system native` in `Packages/GlassfinCore`: 731 tests executed, 721 passed, 10 integration tests skipped, zero failures. Line coverage is 91.71% (11,505 / 12,545), above the unchanged 80% threshold.

SwiftLint 0.65.1 with in-process SourceKit, recursive strict swift-format, ci-grep, license, entitlements, debug-only strings, unit-test-target guards, and artifact-redaction self-tests passed. The bootstrap, HLS probe, and CI helper Python suites passed (41 tests total), as did shell syntax checks and the Docker integration script self-test (22 cases). The Docker self-test uses stubs and does not start a server.

Apple builds and tests run only in GitHub Actions; their final counts and CI results are recorded in PR #42.

Only mocks are used locally. No real Jellyfin server or credentials are used. Physical-device performance and playback acceptance remain outside this merge validation.

## Subsequent main merge and CI follow-up

During CI monitoring the branch advanced to merge commit `35910ad`, importing main's HTTP 503 handling from PR #52 at `ad426ca`. Its `ServerStartingPlaybackTests.swift` and `ServerStartingTests.swift` are imported verbatim; their upstream audit is [TEST-CHANGES-503.md](TEST-CHANGES-503.md). No existing branch test or assertion is changed.

The unchanged PB7 UI test caught a tvOS crash after Cancel followed by Menu. The exported crash report shows `NSKVODeallocate` during layer teardown. The production fix invalidates first-frame observation before replacing or detaching the native player and before dismantling its controller, and observes readiness only while a player is attached. First-frame instrumentation and native seek instrumentation remain active for real playback. No test changes are needed: the original PB7 dismissal and focus assertions remain the regression check.

Linux validation after the additional main merge: 740 tests executed, 730 passed, 10 integration tests skipped, zero failures; coverage 91.77% (11,624 / 12,667 lines). The final CI results for the follow-up commit are recorded in PR #42.

## Merge of main's matching KVO fix

Main subsequently imported the same native-player observation lifecycle fix through PR #53 at `3954aca`. Merging it into the branch after `fb3710e` conflicts only around M08a's additional scrub/Skip methods in `PlaybackView.swift`. The resolution retains the pre-merge file byte-for-byte: it already contains main's first-frame observation invalidation, player-attachment guard and delegate teardown, together with M08a's scrub gestures, segment actions and transport visibility callback. The resulting playback source has no semantic changes, and no test file or assertion changes are required.

Validation after the M09 main merge at `fb3710e`: 747 Linux tests executed, 737 passed, 10 integration tests skipped, zero failures; coverage 91.84% (11,651 / 12,686 lines). The matching KVO merge does not change package or app source content. Its repeated Linux coverage gate also passes: 747 tests executed, 737 passed, 10 skipped, zero failures; coverage 91.81% (11,647 / 12,686 lines). The small coverage variation reflects the repeated run, with no source changes. Its final CI status is recorded in PR #42.
