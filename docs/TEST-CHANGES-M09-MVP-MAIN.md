# M09 MVP tests after merging main

This branch supersedes PR #41, whose base branch was deleted after M09 merged
as `87540f9` (PR #24). Merge `origin/main` at `4f81fed` into `test/m09-mvp`
with a merge commit, retaining main's changes from PRs #33, #40 and #43.

## Test files

The four test files originally added by #41 are retained:

- `Packages/GlassfinCore/Tests/CoreModelsTests/T09MVPCardTests.swift` (4 tests).
- `Packages/GlassfinCore/Tests/CoreStateTests/T09MVPTests.swift` (3 tests).
- `Apps/Shared/UITests/T09SearchMVPTests.swift` (17 tests on tvOS; 11 on iOS).
- `Apps/Shared/Tests/Snapshots/T09SearchSnapshotTests.swift` (8 tests).

These 32 test methods supplement 24 plan rows. The complete mapping and known
limits are in [TEST-COVERAGE-M09-MVP.md](TEST-COVERAGE-M09-MVP.md).

The merge imports the following test files verbatim from main:

- `Apps/Shared/UITests/T06HomeUITests.swift`.
- `Packages/GlassfinCore/Tests/CoreAPITests/ClientPinTests.swift`.
- `Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift`.
- `Packages/GlassfinCore/Tests/CoreStateTests/PinFailureTests.swift`.
- `Packages/GlassfinCore/Tests/CoreStateTests/PinForgetRecoveryTests.swift`.
- `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift`.
- `Packages/GlassfinCore/Tests/CoreStateTests/T04AuthTests.swift`.

No test conflict required resolution, and no existing assertion was edited,
removed or weakened during the merge. At the merge commit, these files match
one of the merge parents exactly; only the four new MVP test files differ
from main in the PR.

## Apple compiler follow-up

The first replacement-PR CI run (`40751504583`) passed both Release builds
and core package tests but could not compile the app-hosted snapshot tests.
`T09SearchSnapshotTests.swift` needs an explicit `self.verticalScroll(in:)`
inside its lazy `compactMap` closure to satisfy Swift's capture rules.
Add only that `self.` qualification to the traversal helper. No test method,
assertion, expected value, timeout, skip condition or reference comparison is
changed. The other three MVP test files remain byte-for-byte identical to #41.

## Apple UI and rendering follow-up

CI run `40756344642` compiled the tests and exposed seven failing tvOS UI
methods and one snapshot assertion. The iOS job reached the UI suite before
its 40-minute timeout; it did not stall during a build.

Production fixes preserve each row header's own accessibility identifier by
assigning the row identifier to its horizontal scroll view, restore focus to
a surviving result when the remembered card disappears, and keep the retry
action beside the visible banner instead of below lazy offscreen rows.
Search scrolling can dismiss the phone keyboard, and compact tabs stay
expanded while Search is selected so other tabs remain reachable.

Two test helpers change without editing any test assertion or expected value:

- `T09SearchMVPTests.swift`: the tab helper enters a selected tvOS tab's content
  with Down when focus is still in the native tab strip. On iOS it dismisses
  the keyboard with the scroll gesture before switching away from Search.
  Tests still assert actual keyboard focus, query retention and tab content.
- `T09SearchSnapshotTests.swift`: the window renderer waits for the native
  navigation/search presentation and scrolling to commit to the screen.
  A single `Task.yield()` captured an incomplete first frame, making glass
  and opaque images identical. The inequality, dimensions, semantic checks,
  reference comparisons and missing-reference skip remain unchanged.

The two core MVP files remain byte-for-byte identical to #41. No test method,
assertion, expected value or reference baseline is removed or weakened.

## Conflict resolution

Keep main's throwing certificate-pin lookup and search-host error handling.
Retain #41's DEBUG fixtures, search header identifiers, snapshot access to the
production card, optional year labels and episode context labels. Retain the
MVP coverage mapping without reverting main's security changes.

Only mock-backed tests run locally. Opt-in server tests remain skipped;
macOS builds, simulator UI tests and snapshot rendering run in GitHub Actions.

## Linux validation

After merging main at `c87d897`, `swift test --package-path Packages/GlassfinCore`
passes: 689 total tests, 679 passed, 10 opt-in server skips, zero failures.
The coverage gate also passes with 91.83% line coverage
(10781/11740; minimum 80%). SwiftLint,
strict swift-format, source/catalog/security checks and CI script tests pass.

## Watchdog restart: run 40766696774 and main c87d897

Merge `origin/main` at `c87d897` with merge commit `8cfdb4c`, retaining
M07, M08a and the local Jellyfin E2E workflow. No test conflicts occurred.

The run's `--log-failed` output stops during dependency compilation; the
downloaded readable xcresult exports and `app-test.log` artifacts provide
the actual failures. Release builds and package tests passed. All eight
snapshot methods completed their render/semantic checks and skipped only
the missing reference comparison. Four UI methods failed:

- tvOS T09-03 and T09-12: after selecting a recent query or returning to a
  tab, the native field's accessibility value includes its dictation hint
  while keyboard focus is elsewhere. The query itself remains intact.
- iOS T09-12: swiping the content did not dismiss the keyboard; the Home
  tab remained covered and XCUITest reported an invalid hit point.
- iOS T09-56: the banner inherited the outer `search.root` identifier,
  replacing `search.banner` in the accessibility hierarchy.

Move the root identifier onto the scroll content before adding the banner
inset. Handle native iOS search submission by ending focus without clearing
the query, so the tab bar becomes reachable.

Only `Apps/Shared/UITests/T09SearchMVPTests.swift` changes in this follow-up.
Its tvOS setup returns to the native keyboard before the T09-03 value check
and after entering Search through the tab helper. A missing keyboard/focus
adds an explicit setup failure. Its iOS tab helper submits through the
native keyboard and waits for that keyboard to close before switching tabs.
Every existing assertion, exact expected value and assertion timeout remains
unchanged. No hint stripping, relaxed matching, disabled test or new skip is
introduced. Snapshot and core MVP test files are unchanged in this restart.

The following test files are imported verbatim from main by the merge:

- `Apps/Shared/Tests/Logic/T07ArtworkTests.swift`.
- `Apps/Shared/Tests/Logic/UITestStateResetTests.swift`.
- `Apps/Shared/UITests/T07LibraryUITests.swift`.
- `Packages/GlassfinCore/Tests/CoreModelsTests/T07MetadataTests.swift`.
- `Packages/GlassfinCore/Tests/CoreNetworkingTests/T07ImageTests.swift`.
- `Packages/GlassfinCore/Tests/CorePlaybackTests/DefaultAudioSelectionTests.swift`.
- `Packages/GlassfinCore/Tests/CorePlaybackTests/FullPlaybackTests.swift`.
- `Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift`.
- `Packages/GlassfinCore/Tests/CoreStateTests/PinFailureTests.swift`.
- `Packages/GlassfinCore/Tests/CoreStateTests/Support.swift`.
- `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift`.
- `Packages/GlassfinCore/Tests/CoreStateTests/T02FoundationTests.swift`.
- `Packages/GlassfinCore/Tests/CoreStateTests/T04AuthTests.swift`.
- `Packages/GlassfinCore/Tests/CoreStateTests/T07DetailTests.swift`.
- `Packages/GlassfinCore/Tests/CoreStateTests/T07LibraryTests.swift`.
- `Packages/GlassfinCore/Tests/CoreStateTests/T07ScreenLifecycleTests.swift`.
- `Packages/GlassfinCore/Tests/CoreStateTests/T07SecurityStateTests.swift`.

Restart validation after merging main: 689 core tests, 679 passed, 10 opt-in
server skips, zero failures. The coverage gate passes at 91.83% (10781/11740).
SwiftLint, recursive strict swift-format, source/catalog/security checks,
debug-only string checks and unit-test target checks pass.

## Run 40795729762, attempt 2: native tvOS field values

The downloaded `tvos-results/app-test.log` and readable xcresult export
identify two assertion failures, not a hang. All 80 UI tests completed in
1524.268 seconds, ending at 02:15:29 UTC on 2026-10-29. T09-03 read
`previous, Hold \u{FFFC} to dictate`; T09-12 read
`star, Hold \u{FFFC} to dictate`. Returning focus to the keyboard did not
remove the native accessibility instruction. Both tests reached their final
assertions; the remaining 78 UI tests passed. The entire job finished with
`failure`, not a timeout, after approximately 38 minutes.

The same `xcode-27` runner class passed tvOS on PRs #51 (run 40788831426,
36m43s), #42 (40776213907, 31m23s), and #32 (40776036687, 33m11s).
Current main is already an ancestor of this branch at `c87d897`. Raw
xcresult bundles are intentionally excluded from CI uploads; the JSON,
JUnit and failed-test exports are included and were inspected.

### Test/assertion changes

T09-03 and T09-12 now compare the complete native accessibility value with
the exact expected query, optionally followed by precisely
`, Hold \u{FFFC} to dictate` on tvOS. The helper does not strip arbitrary
text or accept substring/prefix matches. Wrong, missing, extra or reordered
query characters still fail equality. The iOS comparison is unchanged.
Both tvOS cases additionally type `s` after checking the retained query
and assert the exact raw field values `previouss` and `stars`. These checks
prove that the actual retained input is still editable and contains no
dictation instruction. All existing result, recent, focus, banner and
keyboard assertions remain in place. No test is disabled or newly skipped.

All explicit M09 UI waits already had finite timeouts, and remote focus
loops have finite attempt counts. Enable XCTest timeouts in both app and
iOS package invocations in `scripts/macos-ci.sh`, with a default and
maximum allowance of 180 seconds per test. This also bounds native
automation/idle waits. Enable unbuffered test output to expose the active
test in streamed logs. The existing 40-minute job deadline is unchanged.
See Apple's [execution time allowance documentation](https://developer.apple.com/documentation/xctest/xctestcase/executiontimeallowance).

The M09 core tests also used `SuspendingClock.waitForSleeps`, whose
continuation could previously wait forever if an expected sleep never
arrived. Replace that observer wait with a cancellation-aware poll and a
three-second deadline that records an XCTest failure at the caller.
Existing callers and assertions are unchanged, including those in older
core suites. This latent hang was not the cause of the recorded CI failure.

Local validation: 689 Linux package tests, 679 passed and 10 opt-in server
skips, with zero failures; coverage 91.78% (10775/11740). SwiftLint, strict
swift-format and all lint-job repository scripts pass. Two temporary
negative probes (removed after execution) confirmed that a missing clock
sleep and a cancelled clock wait both record failures promptly: two failures
in 0.034 seconds with a 30 ms deadline for the missing-sleep case.
