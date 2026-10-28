# M09 MVP tests after merging main

This branch supersedes PR #41, whose base branch was deleted after M09 merged
as `87540f9` (PR #24). Merge `origin/main` at `4f81fed` into `test/m09-mvp`
with a merge commit, retaining main's changes from PRs #33, #40 and #43.

## Test files

The four test files originally added by #41 are retained without changes:

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
removed or weakened during the merge. The files above match one of the merge
parents exactly; only the four new MVP test files differ from main in the PR.

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
