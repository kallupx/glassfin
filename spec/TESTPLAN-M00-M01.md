# Test plan – M00 (infra and CI) and M01 (GlassfinCore)

**Author:** Tester · 21 Oct 2026 · Basis: spec/SPEC.md, 00-infra-ci.md, 01-core.md
**Environment:** the Tester has Linux (no Xcode, no Swift, no Docker at the time of writing). Everything runs in CI; the Tester reads artifacts and reviews tests and code in `kallupx/glassfin`.

## Open questions before testing
| # | Question | Who | Why |
|---|---|---|---|
| Q1 | Package name. Resolved in v1.2: `GlassfinCore` everywhere (SPEC §1 and M00/M01). Targets and CI greps use that name. | Specification | One name everywhere, otherwise grep checks and schemes diverge. |
| Q2 | `.xcresult` does not open on Linux (`xcresulttool` is macOS-only). CI must also export: JUnit XML, screenshots as PNG, coverage as text/JSON (`xccov view --report --json`), and logs of failed tests. The shipping CI uploads the redacted text export and does not upload the xcresult bundle. | Coder | Otherwise M00's criterion "the Tester can open the artifacts on Linux" is not met. |
| Q3 | What does a negative ticks value produce: an error, zero, or a negative Duration? Resolved in SPEC v1.2: a negative position becomes 0 with one warning. `RunTimeTicks` ≤ 0 means unknown duration and no progress bar. A negative value is never sent to the server. | Specification | The M01 criterion requires a test, and the expected result is now specified. |
| Q4 | WebSocket backoff: is jitter added, and does the delay reset after a successful connection? Tests need an injected `Clock`. Resolved in SPEC v1.2: full jitter `random(0, min(30 s, 1 s · 2^n))`, and the counter resets only after 10 s of a stable connection. Reconnect immediately in the foreground. | Specification / Coder | Otherwise the test is slow or nondeterministic. |
| Q5 | Integration test server (SPEC §6.10). Recommendation was option (b): Docker containers 10.10.7 / 10.11.x / 12.x on a Linux runner. That is now `integration.yml` (`workflow_dispatch`): pinned images `10.10.7`, `10.11.11`, and `12.2`. | User | Without this, M01's integration criterion is not testable. |

## M00 – test cases
| ID | Test | Steps | Expected | Evidence |
|---|---|---|---|---|
| T00-01 | Clean build | A pull request with empty tvOS and iOS apps and the core | `ci.yml` green, the jobs that should run did run | Actions run status |
| T00-02 | Path filter, draft | A draft pull request that changes only `spec/**` or `*.md` | Only `lint` runs. `test-tvos`, `test-ios`, and `full-ui` are skipped | Job list |
| T00-02b | Path filter, ready | A ready pull request that changes only `spec/**` or `*.md` | `lint` and `full-ui` run. `test-tvos` and `test-ios` are skipped (v1.3.3: `full-ui` is not path-filtered) | Job list |
| T00-03 | Path filter, positive | A pull request that changes `Packages/**` | `test-tvos` and `test-ios` run | Job list |
| T00-04 | iOS gate | A pull request that changes only `Apps/tvOS/**` | `test-tvos` and `test-ios` both run (v1.3.3: they share the macOS path gate). A push to `main` does not run them | Job list |
| T00-05 | Concurrency | Two pushes to the same pull request in a row | The first run is cancelled | Run history |
| T00-06 | Cache | The same pull request runs twice | The second run is a cache hit (SPM and DerivedData), and the duration drops | Logs and duration |
| T00-07 | `needs: lint` | A pull request with an intentional SwiftLint error | `lint` fails, macOS jobs do not start | Job list |
| T00-08 | Lint blocks merge | The same pull request | Branch protection blocks the merge | Pull-request view |
| T00-09 | CI greps | Separate test branches: `NSAllowsArbitraryLoads`, `X-Emby-Token`, `api_key=`, `print(` | Each fails the `lint` job with a clear message | Logs |
| T00-10 | license-check, negative | A test branch plus `kingslay/FFmpegKit` | `license-check` fails | Logs |
| T00-11 | license-check, positive | Clean main | Passes | Logs |
| T00-12 | Units on both platforms | A pull request that changes `Packages/**`, or `workflow_dispatch` | Text results from both the tvOS and iOS simulators | Artifacts |
| T00-13 | Smoke test + screenshot | A ready pull request or a push to main (`full-ui`) | XCUITest launches the app, the first view is visible, PNG in the artifact | Tester opens the PNG |
| T00-14 | Artifacts on Linux | Download the run's artifacts | JUnit, PNGs, and coverage open without macOS (see Q2). Retention is 14 days. xcresult is not in the upload | Tester |
| T00-15 | Timeouts and runners | Review the workflow | macOS 25 min, Linux lint 10 min, `permissions: contents: read`, `runs-on` only `ubuntu-latest` or `xcode-27`, no `self-hosted`, no `xlarge` | Review |
| T00-16 | Minute tracking | The first 10 runs, while the repo was private | macOS minutes recorded, forecast ≤ 200 min/month or an escalation proposal. On the public repo, standard-runner minutes are free; this row is historical | Coder's report |
| T00-17 | License files | Repository root | `LICENSE` and `THIRD_PARTY_LICENSES` exist, and dependencies match `Package.resolved` | Review |
| T00-18 | Secrets | `release.yml` (when it exists) | No `pull_request` trigger, the key is deleted in an `always()` step, no echo. Concurrency `cancel-in-progress: true` | Review + Security |
| T00-19 | Draft vs ready | A draft pull request that changes `Packages/**`, then mark it ready | The draft runs `lint`, `test-tvos`, and `test-ios`, and skips `full-ui`. Marking it ready starts `full-ui`. The `full-ci` label starts `full-ui` on the draft | Job list |
| T00-20 | Artifact retention | Review `ci.yml` | Every `upload-artifact` sets `retention-days: 14` | Review |

## M01 – test cases
| ID | Test | Expected |
|---|---|---|
| T01-01 | Import boundary | Core does not import SwiftUI or UIKit without an `#if os(...)` adapter (CI grep fails on a test branch) |
| T01-02 | Auth header before login | Exactly `MediaBrowser Client="Glassfin", Device="…", DeviceId="…", Version="…"`, no Token field |
| T01-03 | Auth header when signed in | The same plus `Token="…"`; field order and quotes match |
| T01-04 | Special characters in the device name | A device name with `"`, `,`, non-ASCII letters, and emoji → the header stays valid (escape or sanitize) |
| T01-05 | No header and query together | Media and image URLs have only `ApiKey`, no Authorization header; API requests have no `ApiKey` |
| T01-06 | DeviceId is stable | Generated once; the same value after restart (mock SecureStore); `-uitest-reset` changes it |
| T01-07 | Endpoint matrix | For every P0 endpoint, 6 cases: 200, 401, 404, 500, timeout, and malformed JSON → the correct `APIError` variant, no crash |
| T01-08 | 401 handling | 401 produces `unauthorized`; a network error never produces it (K10) |
| T01-09 | Quick Connect route | Initiate uses POST (12.x); it also works on 10.10 |
| T01-10 | Ticks ↔ Duration | 0, 1 tick, 10,000,000 (1 s), > 24 h, the `Int64.max` boundary, negative (see Q3), round-trip without loss |
| T01-11 | Mappers | Every DTO → domain mapper with a 12.x and a 10.10 fixture; missing optional fields (nil overview, no images, no trickplay) do not crash |
| T01-12 | Unknown enum | An unknown `Type` string → `.other(String)`; an unknown `MediaSegmentType` → `.unknown` |
| T01-13 | Token is not in UserSession | `UserSession` does not contain the token; `description` or `dump` does not leak it (also Security S requirements) |
| T01-14 | WebSocket backoff | Drops → delays with full jitter up to 30 s (injected clock); success resets the delay after 10 s stable (Q4) |
| T01-15 | WebSocket events | A mock socket sends `UserDataChanged` and `LibraryChanged` → events arrive on the stream; `KeepAlive` does not produce a UI event; an unknown type is ignored |
| T01-16 | ServerShuttingDown / Restarting | Does not sign the user out; moves to the reconnect state |
| T01-17 | Cancellation | A cancelled `Task` → the request is cancelled, no leak, no error toast (important for M09 K6) |
| T01-18 | Concurrency | Swift 6 strict concurrency `complete` with no warnings (build log) |
| T01-19 | Coverage | Core ≥ 80% line coverage |
| T01-20 | Integration | Login, UserViews, Resume, and PlaybackInfo on 12.x; the same on 10.10.7 and 10.11.x (see Q5). `workflow_dispatch` of `integration.yml` |
| T01-30 | Docker matrix | The same three pinned Jellyfin versions in `scripts/docker-integration.sh` |

## Approval
A module is acceptable when every acceptance criterion in the spec and the P0 tests above are green in CI, open questions Q1–Q5 are resolved or consciously left open, and there are no open critical bugs.
