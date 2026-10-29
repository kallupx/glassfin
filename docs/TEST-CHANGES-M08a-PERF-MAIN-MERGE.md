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
