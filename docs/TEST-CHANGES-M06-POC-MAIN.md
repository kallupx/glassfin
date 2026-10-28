# M06 PoC follow-ups: main merge and app hooks

Date: 2026-10-28. Branch: `test/poc-m06-followups`, PR #33. This app follow-up starts at `9071de5`, after the merges described below. Main advanced to `3a07600` during validation; a final merge incorporates that CI caching change after app commit `13c9168`.

## App changes after CI run 40695296939

The full-ui job exposed three missing prerequisites in main. This follow-up supplies app code for the unchanged acceptance tests:

- T06-30: `HomeMockLibrary.nextUp(limit:)` supplies up to `HomePolicy.rowLimit` cards, matching Resume and including the fifth Next Up card (`id: 25`). Each tvOS row keeps its own remembered focus preference even while inactive; initial focus still uses the existing first eligible row task.
- T06-42 and T06-43: inside the existing DEBUG mock/reset launch path, `-uitest-home-network-controls` creates `HomeMockControls` and injects `HomeMockPath` into the real `AppState`. The path provides an initially online, lock-protected `AsyncStream<Bool>` consumed by `AppState.startPathUpdates()`. Play/Pause on a Home card toggles that path. No focus assignment, timer, direct connectivity mutation or direct test-triggered refresh is used. Recovery reaches the existing Home connectivity observer and `model.reconnect()`.
- The DEBUG-only `home.test.resumeRequests` accessibility value reads the actual mock Resume service call count and is exposed only when Home has a fetch and no sections are loading. Context-menu Play continues through the production playback guard, including when the network controls are enabled.
- Production offline playback now displays the existing localized `AppErrorMessage.playbackOfflineKey` as nonfocusable `home.playback.blocked` feedback and clears it on recovery. The connectivity banner and retained cards continue to use the normal app state. This implements T06-42's clear playback-block message requirement in `spec/TESTPLAN-M06.md` and the M02 offline behavior.

All mock path/control types, launch argument handling, remote interception and request diagnostics are inside `#if DEBUG`. Controls require the existing mock/reset launch configuration plus the explicit network-controls argument. Release has the real focus-memory and playback-feedback fixes but no network test controls. No credentials, tokens, environment secrets or external service configuration were added.

## Exact test-file change inventory for the Home app follow-up

**This app follow-up changes no test files relative to `9071de5`. Exact list: none.** No assertion, timing bound, fixture expectation, test name, skip condition or test target was changed. `Apps/Shared/UITests/T06HomeUITests.swift` remains byte-identical to `9071de5` and the pre-merge `280bdfe` version. No package tests were added or modified.

The original PR-local test changes relative to main are still confined to `Apps/Shared/UITests/T06HomeUITests.swift`: the five retained PoC scenarios T06-05, T06-30, T06-40, T06-42 and T06-43 and their bounded remote/counter helpers. The app fixes supply their required fixtures and behavior; none of those tests was relaxed to accommodate main.

## Merge history and inherited tests

Branch before the main merge: `280bdfe9b986d372a57a5f40fdbca33656eb1a38`. Merge `836c286113500d6f21b5989e54635adf678526d3` incorporates `b70aea11eb3272086bcb27a7062116993ee49125` (M06 #22). Merge `9071de5` incorporates `eaf26b5ba0208ad2d8e7453495d411404a4ec6b7` (M10 Settings #28). Both are merge commits; no history was rebased or force-pushed.

The final merge incorporates `3a07600ef158548965cdd4bc30cd3488d239112f` (CI SwiftPM SourcePackages caching, #36) without conflicts. Its upstream changes affect only `.github/workflows/ci.yml`, `.gitignore` and `scripts/macos-ci.sh`; no app, package or test sources change. The main ancestry and merged shell syntax were checked again before pushing.

Those merges initially preserved all main app code, removing the earlier branch-only Home hooks. CI run 40695296939 then failed T06-30 on the absent fifth Next Up card and T06-42/T06-43 on the absent request counter. The app implementation above supersedes that earlier test/doc-only scope.

`T04AuthUITests.swift` was inherited verbatim from main. Relative to `280bdfe`, this includes #13's notify-based Quick Connect approval handshake, its registration/state assertions and cleanup, and #28's unconditional notify import plus Settings cancellation flow: removal of the Home-root wait and subsequent Settings-tab activation after sign-out cancellation, while retaining the sign-out-button wait. These are upstream changes, with no PR-local auth test edits. T10 tests and all other main tests remain unchanged relative to main.

## Validation of the app follow-up

- Linux Swift 6.4.1: `bash scripts/coverage-gate.sh` ran `swift test --enable-code-coverage --build-system native` in `Packages/GlassfinCore`: 503 cases, 495 passed, eight existing live-integration skips, zero failures. Line coverage: 91.68% (8,093 / 8,827; threshold 80%).
- SwiftLint 0.65.1 passed using the dynamic executable and the installed toolchain's SourceKit library. Its release archive SHA-256 matches CI's pin. Strict recursive `swift-format` passed.
- License checks and self-test, `ci-grep` (including image pipeline, design system and string catalogs), entitlements, DEBUG-only source check and self-test, unit-test target check and self-test, image-pipeline self-test, artifact-redactor self-test, all 33 Python bootstrap/HLS tests, shell syntax checks and the 22-case Docker script self-test passed.
- A temporary copy of the actual `HomeMocks.swift`, replacing only its SwiftUI import with Foundation, passed Swift 6 strict-concurrency type checking with warnings as errors against the built core modules. The check includes the exact existential path-injection expression from `AuthAssembly`.
- A temporary executable using that same mock source and the built core modules passed checks for the Next Up count, limit and fifth ID, empty/down fixtures, actual `AppState` path drop/recovery, playback-block keys, automatic refetch through `onReconnect`, and retained model content/remembered IDs. This does not exercise SwiftUI's connectivity observer or rendered focus.
- `git diff --check` passed. The test-file inventory is empty relative to `9071de5`.

Linux cannot execute tvOS Focus Engine, SwiftUI UI tests or an Apple Release binary scan. These results do not claim an Apple UI pass; the pushed app changes require macOS CI verification of T06-30, T06-42 and T06-43.

## CI run 40705232914 investigation and playback fix

This follow-up starts at `6b36f66df70793000ce4b34b02f8487f826d27af`. The refreshed `origin/main` remains `3a07600ef158548965cdd4bc30cd3488d239112f`, already included by that merge commit.

- `test-tvos` failed because SwiftPM timed out downloading the `openapi-generator.artifactbundle.zip` binary artifact from the LePips/openapi-generator v0.8.0 release. Package resolution failed before the Release app could be produced. The later package, app unit and 44 UI tests passed. This is an infrastructure failure, with no evidence of an app build error or Release marker leak.
- `test-ios` has a real unit-test failure in the uploaded `ios-results/package-test.log`, although the console log stops during the Release build. `testT08P_92_bothAttemptsFailWithExactlyTwoStreams` failed its two unchanged assertions at lines 849 and 850: only the direct-play session's failed Stopped report was visible when both direct-play and remux reports were expected. Its Release build and binary marker scan passed, as did all 40 app unit tests and 23 UI tests.
- `lint`, `full-ui` and `dependabot-macos` passed. The mixed infrastructure and code failures require a code fix and a new CI run, rather than treating both failed jobs as infrastructure-only.

`PlaybackCoordinator.fail` previously published `failure` before awaiting the final Stopped report. It now awaits that report before publishing the reason and checks the generation so completion of an older failure cannot overwrite a newly started playback. Engine shutdown, timer cancellation, immediate failed UI state, serialized reporting and the existing authorization handling remain intact. This production fix adds no UI-test hooks or Release markers; the Home controls retain their existing DEBUG guards.

### Exact test-file changes in this CI follow-up

Relative to `6b36f66`, the complete list is:

- `Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift`: add `testT08P_92_failureWaitsForStoppedAndCannotOverwriteNewPlayback`. A continuation gates the remux Stopped response. The test checks that the final reason stays unpublished while reporting is suspended and that completing the report cannot overwrite a replacement playback. It covers both ordinary failure completion and replacement playback without wall-clock sleeps. No existing test, assertion, timeout, fixture, skip or target is changed.

The new regression test fails against the original coordinator with two `XCTAssertNil` failures while Stopped is suspended. All existing tests, including `testT08P_92_bothAttemptsFailWithExactlyTwoStreams`, retain their original assertions. `Apps/Shared/UITests/T06HomeUITests.swift` is unchanged in this follow-up; the original PR-local UI-test inventory above still applies.

### Local validation of the CI follow-up

- All 50 `PlaybackCoordinatorTests` pass with the production fix, including the original failing case and the new regression test.
- Linux Swift 6.4.1, `bash scripts/coverage-gate.sh`: 504 tests, 496 passed, eight existing live-integration skips, zero failures; 91.68% line coverage (8,094 / 8,829; threshold 80%).
- SwiftLint 0.65.1 and strict recursive `swift-format` pass. SwiftLint uses the dynamic executable with the installed Swift toolchain library; its archive checksum matches the CI pin.
- License checks and self-test; `ci-grep` including design-system, image-pipeline and string-catalog checks; entitlements; DEBUG-only string and unit-test-target checks with self-tests; image-pipeline and artifact-redaction self-tests; all 33 Python bootstrap/HLS tests; shell syntax; and the 22-case Docker script self-test pass.
- `git diff --check` passes. The exact test-file inventory relative to `6b36f66` contains only the additive regression in `PlaybackCoordinatorTests.swift` listed above.

Apple Release builds, binary marker scans and simulator suites require the new macOS CI run. The earlier iOS Release scan passed, and no DEBUG/UI-test hook code is changed in this follow-up.
