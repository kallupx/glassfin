# tvOS UI test shards

The `test-tvos` check aggregates three matrix jobs. Each shard has its own
30-minute timeout, uses `-only-testing` to select complete UI test classes, and
disables XCTest parallel testing within its simulator. The workflow shuts down
all simulators before each shard starts. A failed or cancelled shard fails the
aggregate; `fail-fast: false` lets the other shards finish and upload diagnostics.
The existing path and Dependabot conditions still control whether tvOS runs.

Each runner builds its own tests. This keeps the existing build, signing,
fixture, result export and redaction flow without transferring compiled products
between runners. Shard 1 also runs the Release binary scan, macOS package tests
and all hosted tvOS unit tests. Shards 2 and 3 run only their assigned UI classes.

## Assignment and coverage guard

`scripts/ci/tvos-ui-shards.json` is the single source for both the Actions matrix
and the `xcodebuild -only-testing` arguments. Run:

```sh
python3 scripts/check-tvos-ui-shards.py --self-test
python3 scripts/check-tvos-ui-shards.py
python3 scripts/check-tvos-ui-shards.py --matrix
python3 scripts/check-tvos-ui-shards.py --shard 1
```

The guard scans every Swift file under `Apps/Shared/UITests` for `XCTestCase`
classes, including subclasses of locally declared test classes. It rejects
unassigned, duplicate and unknown classes, empty shards, and an empty discovery
result. It runs in Linux lint and again in each shard before any build. New UI
test classes must be assigned in the manifest. The scanner includes declarations
inside platform conditionals; a future iOS-only class will also need an assignment
or a corresponding discovery update. Keep the source directory aligned with the
UI test target in `project.yml` if that target's sources move.
Manifest and guard changes select tvOS in the path filter; changes to the shared
macOS runner script select both platforms.

## Measured balance

Class durations below come from the `app-test.log` files in the `tvos-results`
artifacts for runs [40863298450](https://github.com/kallupx/glassfin/actions/runs/40863298450)
and [40842906108](https://github.com/kallupx/glassfin/actions/runs/40842906108).
The streamed run logs contain only part of the build output, so the artifact logs
provide the complete XCTest class timings. Values are elapsed seconds rounded to
one decimal place.

| Shard | UI class | 40863298450 | 40842906108 |
| --- | --- | ---: | ---: |
| 1 | T06HomeUITests | 290.1 | 333.5 |
| 1 | T09SearchUITests | 69.7 | 72.4 |
| 1 | DevicePerformanceTests | 85.3 | 88.1 |
| 2 | T09SearchMVPTests | 295.0 | 318.8 |
| 2 | T04AuthUITests | 173.7 | 172.2 |
| 2 | WelcomeSmokeTests | 5.7 | 5.7 |
| 3 | T07LibraryUITests | 193.3 | 203.5 |
| 3 | DesignSystemFocusTests | 159.1 | 170.2 |
| 3 | T08PlaybackWiringUITests | 88.4 | 71.1 |
| 3 | T10SettingsUITests | 187.7 | 136.8 |
| **1 total** | | **445.1 (7m25s)** | **494.0 (8m14s)** |
| **2 total** | | **474.4 (7m54s)** | **496.7 (8m17s)** |
| **3 total** | | **628.4 (10m28s)** | **581.5 (9m42s)** |

Shard 1 has fewer UI seconds to leave room for its additional checks. These
totals exclude builds, simulator startup, hosted unit tests and result export.
The runs contain 89 and 88 UI tests respectively; timings will change as tests
are added. Rebalance whole classes using subsequent shard logs when needed.
Per-shard builds trade additional runner time for a smaller workflow change and
independent diagnostics. The optional `full-ui` job retains its existing full
suite run and timeout; this change targets the required `test-tvos` path.

No application code, test files or assertions are changed.
