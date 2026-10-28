# MVP integration canary

This draft canary must never merge into `main`. The current revision is rebuilt
from `085582bdcc5154753beeb48cf1d2d4d122dcc365`, which squash-merged #44.
The user explicitly authorized this refresh and a push with `--force-with-lease`.
The previous head `f1d6a6221890f5f287aa0e459f0b505b84fbe359` is retained in the
local backup ref `backup/integration-mvp-before-refresh-20261028T201105Z`. Its complete resolution log is archived below.

## Refreshed inputs

Fetched on 2026-10-28. Merge the following immutable heads in order with merge
commits. #44 is already in the baseline and is not merged again as a branch.

| Order | PR | Branch | Fetched head |
| --- | --- | --- | --- |
| 1 | #23 | `feat/m07-library-detail` | `942f4f04fd7dda85928f3acfcb31ead7d2653316` |
| 2 | #32 | `test/poc-m07-followups` | `dc7c29646c32eef57cbee8cb757ed4b09436d440` |
| 3 | #46 | `test/m09-mvp` | `a34000aa15ad75dcba876dfa0d8641180f18bdab` |
| 4 | #42 | `feat/m08a-trickplay-segments` | `ff6c54344e1d498d4da2a00cba8151c2a135b397` |
| 5 | #51 | `feat/m08-player-wiring` | `190daf207a740597f1edc1383419a9df521c1f73` |
| 6 | #47 | `testaaja/poc-acceptance-f3-f4` | `af146244dba27443ce8321835f9272ecdf5f2416` |

#47 contributes gated acceptance tests. No credentials are supplied and no live
server is used. #50 is excluded because its native Jellyfin process is outside
the user's mocks-or-Docker-only constraint. #49 device measurement tooling and
unrelated dependency/CI-security PRs are outside this MVP feature combination.

## Current merge resolutions

### 1. Library and detail (#23)

No textual conflicts against current main. Retain the source branch's union of
M07 and merged #44 DTOs, catalog keys and track UI.

### 2. M07 follow-ups (#32)

No textual conflicts. Retain all current missing-pin, metadata, transport and
security test coverage unchanged.

## Current validation and findings

Pending the refreshed combined Linux suite and GitHub Actions. Apple builds and
tests run only in GitHub Actions. Existing assertions must remain unchanged;
all integration-authored test edits are audited in
[TEST-CHANGES-INTEGRATION-MVP.md](TEST-CHANGES-INTEGRATION-MVP.md).

## Historical first pass (superseded)

The following archive describes the original baseline, inputs, fixes and known
limits. Current inputs and validation above take precedence. In particular, #51
now supplies playback wiring that was absent in the first pass.

### MVP integration canary

This branch combines the MVP work before the owning pull requests merge. It is a
canary only and must never be merged into `main`.

#### Inputs

Fetched on 2026-10-28. Baseline: `4f81fedff7271eca4897404951678dd704e4026f`.
The branches below are merged in this order with merge commits.

| Order | Branch | Owning PR | Fetched head |
| --- | --- | --- | --- |
| 1 | `feat/m07-library-detail` | #23 | `45de3ecfcf4636c05d1c1322a545d1409d0c9544` |
| 2 | `test/poc-m07-followups` | #32 | `c73873c8cb86569b1ea4a3b53ca2839f75da59c3` |
| 3 | `test/m09-mvp` | M09 tests | `dab9808e2b51890d5c227737da6e52ad672d2a90` |
| 4 | `feat/m08a-transcode-tracks` | #44 | `d26ada8d69ba7bc517fd06537ffc275a6734fcb5` |
| 5 | `feat/m08a-trickplay-segments` | #42 | `98332624d11a44471deceaf4dd91c262ea3a61f9` |

During the initial merge pass, M09 advanced to
`c0de9727dfa475308d4e27db48904b9406d885fb` (replacement PR #46), merging the
same `origin/main` baseline. After completing the five merges in order, merge
that updated head as well. This avoids rewriting any merge history.

PR #32 also advanced to `be800fc5a53d55b0cf76ca4e0c687263c4e74186`
during validation. It incorporates current #23 and the same recording-transport
signature correction found by the canary. Merge that head after the initial
sequence; all five remote source heads are then ancestors of the canary.

#### Merge resolutions

##### 1. Library and item detail (#23)

No textual conflicts. Git merged the branch automatically.

##### 2. M07 follow-up tests (#32)

No textual conflicts. Git merged the branch automatically, including the library
and detail UI follow-ups.

##### 3. M09 MVP tests

The test branch also carries older copies of production files. Resolve those
against the current M07 implementation as follows; all incoming test files and
assertions are retained unchanged.

| File | Conflict | Resolution |
| --- | --- | --- |
| `Apps/Shared/Sources/DesignSystem/Copy.swift` | Older M09 copy omits M07 copy cases and resources (two hunks). | Keep the M07 library/detail catalog keys and resource mappings. |
| `Apps/Shared/Sources/DesignSystem/Panels.swift` | M09 has the original fixed hero action bar. | Keep M07's optional custom action content and fallback action bar. |
| `Apps/Shared/Sources/DesignSystem/Shell.swift` | M09 lacks library/overflow closures and duplicates overflow accessibility modifiers (two hunks). | Keep M07's closures and apply identifiers once to the fallback container. |
| `Apps/Shared/Sources/GlassfinRootView.swift` | Older root omits the library debug host. | Keep M07's debug-host routing and the existing Search debug route. |
| `Apps/Shared/Sources/HomeRootView.swift` | Older tab shell omits library-session fallback and content closures. | Keep M07's library list fallback and real library/overflow destinations, with Search retained. |
| `Apps/Shared/Sources/Search/SearchUITestSupport.swift` | Add/add: M09 expands the original fixture (six hunks). | Keep M09's request counters, offline/error/refresh/image fixtures, isolated recents and tab container. |
| `Apps/Shared/Sources/Search/SearchView.swift` | Add/add: older host API versus M07 error handling; new M09 card/header behavior (six hunks). | Keep the throwing feature factory and retry/error host; add M09 header IDs, internal card visibility for snapshots, contextual titles and two-line title height. |
| `Packages/GlassfinCore/Sources/CoreModels/SearchModels.swift` | Add/add: M09 adds contextual titles and SeriesName cleaning (two hunks). | Retain both additions alongside the existing sanitization. |
| `Packages/GlassfinCore/Sources/CoreNetworking/HTTPClient.swift` | M09 references the former bounded transport class name. | Keep M07's `BoundedRequestDownload`, separate from its library image downloader. |
| `Packages/GlassfinCore/Sources/CoreState/AuthFlow.swift` | M09's older nonthrowing factory suppresses pin errors (three hunks). | Keep the throwing factory and validated `certificatePin(for:url:)` lookup; corrupted pins must fail closed. |
| `Packages/GlassfinCore/Sources/CoreState/ViewModels.swift` | M09 restores old inline Library/Series view models. | Keep M07's implementations in their separate files; do not duplicate the types. |
| `docs/M09-TEST-MAPPING.md` | Add/add: original mapping versus supplemented coverage (seven hunks). | Keep the M09 MVP mapping with its new entry points and explicit Apple/device limits. |

Semantic merge conflict: M09 also restored
`Packages/GlassfinCore/Sources/CoreNetworking/BoundedResponseDownload.swift`
without a textual conflict. It duplicates the transport renamed to
`BoundedRequestDownload.swift` by M07 and collides with M07's library image type
in `LibraryImages.swift`. Omit the obsolete restored file; keep both current M07
download implementations and all their tests. M09 should retain the rename when
rebasing onto #23/main.

##### 4. Transcoding and tracks (#44)

| File | Conflict | Resolution |
| --- | --- | --- |
| `Packages/GlassfinCore/Sources/CoreModels/DTOs.swift` | M07 person/studio DTO declarations and #44 playback user configuration are appended at the same location. | Retain all three complete DTO types. |

Semantic merge conflict in the same file: both branches independently add
`MediaStreamDTO.Channels`. Retain a single declaration with the same `Int?` type,
plus all M07 technical metadata and #44 track/delivery fields. The owning branches
must union these fields when they merge.

##### 5. Trickplay, segments and next episode (#42)

| File | Conflict | Resolution |
| --- | --- | --- |
| `Apps/Shared/Resources/Localizable.xcstrings` | Track strings and playback feature strings occupy the same insertion point, producing interleaved key/value conflicts. | Merge complete catalog entries by key, keeping M07, M09, #44 and #42 entries with both translated `en` and `fi` values. Shared entries agree; sort keys without altering translations. |
| `Apps/Shared/Sources/DesignSystem/Copy.swift` | M07 keys and #42 playback keys, then #44 and #42 resource mappings, overlap (two hunks). | Union all distinct cases and mappings. |
| `Apps/Shared/Sources/PlaybackView.swift` | #44 track menus/subtitle overlay and #42 playback companion/feature overlay modify the same view and representable (three hunks). | Pass both companion and track menus to the native controller, render both overlays, and update both transport menus and companion gesture/contextual-action state. Retain #42's initializer, lifecycle and return-focus callback. |

##### M09 head refresh (#46)

No textual conflicts when merging `c0de972` after the initial ordered sequence.
The update contributes its main-sync test audit and coverage documentation.

##### M07 follow-up head refresh (#32)

No textual conflicts when merging `be800fc` after validation. Its transport mock
matches the integration correction exactly; only its test-audit document is new
to the combined tree.

#### Integration fixes

The first combined Linux build failed in
`Packages/GlassfinCore/Sources/CoreState/RetryingClient.swift:82` with an invalid
redeclaration of `trackCancellation(_:)`. The M09 branch restored a second,
identical method already supplied by M07. Keep one implementation; its locking
and cancellation semantics are unchanged. This is an integration-only failure;
M09/#46 should avoid restoring the older duplicate when adopting M07.

Also remove the obsolete transport file described in the M09 resolution above.
No test implementation or assertion was changed for either correction.

The next Linux build exposed a failure that also affects #32 against current
#23: `T07FilterTransport` in
`Packages/GlassfinCore/Tests/CoreServicesTests/T07FilterEncodingTests.swift:55`
does not conform to `RequestTransport`. Its `data(for:)` predates the required
`maximumBytes: Int?` argument. Add that argument to the mock method only. The
test `testT07_79_specialCharacterGenresAreEncodedAndRoundTripWithoutChangingThePath`
and every assertion remain unchanged. PR #32 should take this signature fix.
See [TEST-CHANGES-INTEGRATION-MVP.md](TEST-CHANGES-INTEGRATION-MVP.md).
Status: #32 has independently adopted the same fix in `be800fc`, now included.

##### Apple CI: M09 snapshot compilation

Run `40752037758`, head `290118b`: Linux lint/coverage passes; the tvOS Release
app builds and all 742 macOS package tests pass (10 opt-in skips). The tvOS app
test build then fails in
`Apps/Shared/Tests/Snapshots/T09SearchSnapshotTests.swift:179:48`:
`implicit use of 'self' in closure; use 'self.' to make capture semantics explicit`.
The lazy `compactMap` closure recursively calls the instance's
`verticalScroll(in:)` helper. Qualify it as `self.verticalScroll(in:)`.

This is a real source/test compile failure, not a runner hang, and would also
affect M09 PR #46 independently. The eight M09 snapshot test methods cannot run
until their target compiles. The integration applies that one-token qualification
and changes no assertion, reference, recording or skip behavior. See the test
audit for the exact edit. A new push starts CI for the corrected head.

#### Validation

Only mocks or the repository's Docker test server may be used. Apple builds and
tests run only in GitHub Actions. Linux `swift test` must pass before each push.
CI results and any failures affecting the owning PRs are reported in the draft
canary pull request and the final integration report.

- Linux `swift test --package-path Packages/GlassfinCore`: 732 tests, 722 passed,
  10 opt-in server skips, zero failures.
- `bash scripts/coverage-gate.sh`: the same 732 tests, zero failures; line
  coverage 91.68% (11327/12355), minimum 80%.
- Strict `swift-format`, SwiftLint, source/catalog/security checks, entitlements,
  debug-only strings, unit-test targets, license checks and redaction self-test
  pass. Local SwiftLint warns that its SourceKit-dependent custom rule is
  unavailable; `ci-grep.sh` independently enforces the no-print check.
- Python bootstrap/HLS probe tests: 33 passed. Docker script self-test: 22 passed.
  No Docker server or real server was started.

#### Product integration limits

These are static findings, separate from test failures. They are not fixed by
resolving textual conflicts and need explicit feature integration work.

| File / entry point | Finding | Owning work and proposed fix |
| --- | --- | --- |
| `Packages/GlassfinCore/Sources/CoreState/LibrarySession.swift`, `Apps/Shared/Sources/Library/LibraryFeatureAssembly.swift`, `Apps/Shared/Sources/PlaybackView.swift` | Production code does not assign `LibrarySession.onPlayback`; the only assignment is in the DEBUG library host. Library/detail actions set an intent but do not present M08 playback. | #23 with #44/#42: assemble an authenticated playback coordinator and engine, present `PlaybackView`, connect next episode and user-data updates, and return focus through the library session. |
| `Apps/Shared/Sources/Search/SearchView.swift`, `SearchItemDetail` | Search retains its standalone text-only detail destination and the Q9-12 TODO even with M07 present. | #23 and M09/#46: route validated search selections to M07 detail/episode destinations while retaining query, results and focus. |
| `Apps/Shared/Sources/SettingsView.swift` | The shell defaults to `.poc`; #44's ASS conversion and remote-bitrate controls remain hidden until a production playback configuration is supplied. | #44 with the shell/playback assembly: pass the intended production configuration and validate preferences alongside #42 segment/autoplay controls. |

Physical-device playback, remote/Siri input, performance and reviewed snapshot
baselines remain outside Linux validation. Opt-in server tests are intentionally
skipped. Full CI may validate compilation and mock-backed behavior without
closing these product gaps.
