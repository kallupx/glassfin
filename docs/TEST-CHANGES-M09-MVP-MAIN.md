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

`swift test --package-path Packages/GlassfinCore` passes: 590 total tests,
580 passed, 10 opt-in server skips, zero failures. The coverage gate also
passes with 92.27% line coverage (9034/9791; minimum 80%). SwiftLint,
strict swift-format, source/catalog/security checks and CI script tests pass.
