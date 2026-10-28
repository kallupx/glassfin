# M06 PoC follow-ups: merge onto main

Date: 2026-10-28. Branch before the merge: `280bdfe9b986d372a57a5f40fdbca33656eb1a38`. Main merged as the second parent: `b70aea11eb3272086bcb27a7062116993ee49125` (squash merge of #22).

## Conflict resolution and scope

- Kept main's `AuthRootView.swift`, `HomeMocks.swift`, `HomeRootView.swift` and `HomeView.swift` verbatim. All other app and package sources, build configuration, workflows and scripts also match main.
- Kept this branch's `T06HomeUITests.swift` byte-for-byte from `280bdfe`, including all five PoC scenarios (T06-05, T06-30, T06-40, T06-42, T06-43), helper failures, timing limits, focus assertions and the async `XCTWaiter.fulfillment` fix. No test was deleted, skipped, renamed or relaxed.
- Kept main's `T04AuthUITests.swift` verbatim. Relative to the old branch, this restores the DEBUG `notify` import, unique approval notification registration, its success assertion, token cleanup, the `-uitest-qc-approval` launch argument, and the `notify_set_state` success assertion after the code screenshot. All existing code-display and Home-arrival assertions remain. `AuthRootView` retains main's matching notify-based approval reader instead of reverting to the branch's fixed two-second approval delay. This synchronization came from #13 and is unrelated to the Home follow-ups.
- Updated `TEST-COVERAGE-M06.md` to distinguish retained test sources from unavailable fixture/app behavior. The diff against main contains only the Home UI tests and documentation; no M06 app implementation is duplicated.

## Known tvOS prerequisites preserved as failures

The instruction to retain main's app code removes branch-only test hooks and app fixes. The retained tests still require them:

- T06-30 navigates to Next Up item 5 (`id: 25`), but main's fixture returns only four Next Up cards (`id: 21...24`). The fifth-card requirement and geometry assertion remain unchanged. Main's conditional default-focus preference also remains unchanged; the focus-memory behavior needs an Apple run after the fixture is supplied.
- T06-42 and T06-43 launch with `-uitest-home-network-controls` and require `home.test.resumeRequests` after the initial load. Main has no `HomeMockControls`/`HomeMockPath`, no request counter, no connectivity injection for this argument, and no Play/Pause network toggle. Both tests call `XCTFail` when the counter is missing; they do not silently pass or skip.
- T06-42 additionally requires `home.playback.blocked` and the existing localized offline-playback key. Main's playback guard returns without displaying that feedback. That assertion remains unchanged.

These are known limitations of the requested test/doc-only scope. A passing Linux package suite does not establish that these tvOS UI tests pass. No Apple SDK, UI execution or Release binary scan is available in this Linux environment.

## Validation

- `swift test` in `Packages/GlassfinCore` passed on Linux with Swift 6.4.1: 496 cases, eight existing live-integration skips, zero failures.
- `bash scripts/coverage-gate.sh` passed with the same test counts and 91.44% line coverage (8,051 / 8,805 lines; threshold 80%).
- SwiftLint 0.65.1 and strict recursive `swift-format` passed. The SwiftLint release archive matched the SHA-256 pinned in CI. The static executable skipped custom rules because it prohibits SourceKit access; the dynamic executable passed without that warning after selecting the installed Swift toolchain's SourceKit library via command-local `LINUX_SOURCEKIT_LIB` and `LD_LIBRARY_PATH`.
- License checks and self-test, `ci-grep` (including image pipeline, design system and catalogs), entitlements, DEBUG-only string check and self-test, unit-test target check and self-test, image-pipeline self-test, artifact-redactor self-test, all 33 Python bootstrap/HLS tests, shell syntax checks and the 22-case Docker script self-test passed.
- `git diff --check` passed. Byte comparisons confirmed main's app/package sources, auth UI tests, configuration, workflows and scripts were preserved, and `T06HomeUITests.swift` was unchanged from the pre-merge branch. No new package tests were added or modified.
