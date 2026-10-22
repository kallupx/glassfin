# Test plan – M00 (infra & CI) and M01 (AppCore)

**Author:** Testaaja · 2026-10-21 · Based on: spec/SPEC.md, 00-infra-ci.md, 01-core.md
**Environment:** Testaaja runs Linux (no Xcode, no Swift, no Docker at the moment). Everything runs in CI; Testaaja reads the artifacts and reviews tests/code in the `kallupx/glassfin` repo.
**Language:** Everything in the repo is English (code, comments, test names, commits, PRs, ADRs, README). The dev UI language is English (`Localizable.xcstrings`); Finnish is a localization. Tests must assert on the error type or the String Catalog key, never on a hardcoded user-facing string (see T00-20).

## Open questions before testing
> **Status 2026-10-21:** Q1 → `GlassfinCore`. Q2 → Koodari passed the artifact list to the agent. Q3 → Spesifikaatio v1.2: negative position → 0 + one log warning; RunTimeTicks ≤ 0 → duration unknown (no bar); negative PositionTicks is never sent. Q4 → v1.2: full jitter, 1 s × 2, max 30 s, reset only after the connection has been open for 10 s, injected `Clock`, reconnect immediately on returning to foreground. Q5 → the user confirmed the Docker integration server (spec v1.3 §6.10), in use after M01; only single-use credentials and test media.
| # | Question | For | Why |
|---|---|---|---|
| Q1 | Package name: `AppCore` (SPEC §1, M01) or `GlassfinCore` (M00)? Targets and CI greps refer to the name. | Spesifikaatio | One name everywhere, otherwise grep checks and schemes get crossed. |
| Q2 | `.xcresult` does not open on Linux (`xcresulttool` is macOS-only). CI must additionally export: JUnit XML, screenshots as PNG files, coverage as text/JSON (`xccov view --report --json`) and the logs of failed tests. | Koodari | Otherwise the M00 criterion "Testaaja can open the artifacts on Linux" is not met. |
| Q3 | What does a negative ticks value produce: an error, zero or a negative Duration? | Spesifikaatio | The M01 criterion requires a test, but the expected result is missing. |
| Q4 | WebSocket backoff: is jitter added, and does the delay reset after a successful connection? The tests require an injected `Clock` abstraction. | Spesifikaatio / Koodari | Otherwise the test is slow or non-deterministic. |
| Q5 | Integration test server (SPEC §6.10). I recommend option (b): Docker containers 10.10.7 / 10.11.x / 12.x on a Linux runner. It is the cheapest, and runs are reproducible. | User | Without this the M01 integration criterion cannot be tested. |

## M00 – test cases
| ID | Test | Steps | Expected | Verification |
|---|---|---|---|---|
| T00-01 | Clean build | PR with empty tvOS and iOS apps and core | `ci.yml` green, all jobs run | Actions run status |
| T00-02 | Path filter | PR that changes only `spec/**` or `*.md` | Only `lint` runs, macOS jobs are skipped | Job list |
| T00-03 | Path filter, positive | PR that changes `Packages/**` | `test-tvos` and `test-ios` run | Job list |
| T00-04 | iOS condition | PR that changes only `Apps/tvOS/**` | `test-ios` is skipped on the PR but runs on the main push | Job list |
| T00-05 | Concurrency | Two consecutive pushes to the same PR | The first run is cancelled | Run history |
| T00-06 | Cache | Same PR run twice | Cache hit on the second run (SPM and DerivedData), duration goes down | Logs and duration |
| T00-07 | `needs: lint` | PR with an intentional SwiftLint error | `lint` fails, macOS jobs do not start (0 macOS minutes) | Job list |
| T00-08 | Lint blocks merge | Same PR | Branch protection blocks the merge | PR view |
| T00-09 | CI greps | Separately in test branches: `NSAllowsArbitraryLoads`, `X-Emby-Token`, `api_key=`, `print(` | Each fails the `lint` job with a clear message | Logs |
| T00-10 | license-check, negative | Test branch + `kingslay/FFmpegKit` | `license-check` fails | Logs |
| T00-11 | license-check, positive | Clean main | Passes | Logs |
| T00-12 | Unit tests on both platforms | main push | JUnit reports from both the tvOS and the iOS simulator | Artifacts |
| T00-13 | Smoke test + screenshot | main push | XCUITest launches the app, the first view is visible, PNG as artifact | Testaaja opens the PNG |
| T00-14 | Artifacts on Linux | Download the run's artifacts | JUnit, PNGs and coverage open without macOS (see Q2) | Testaaja |
| T00-15 | Timeouts | Check the workflow | macOS 25 min, Linux 10 min, `permissions: contents: read` | Review |
| T00-16 | Minute tracking | First 10 runs | macOS minutes recorded, forecast ≤ 200 min/month or an escalation proposal | Koodari's report |
| T00-17 | License files | Repo root | `LICENSE` and `THIRD_PARTY_LICENSES` exist, dependencies match `Package.resolved` | Review |
| T00-18 | Secrets | `release.yml` (once it exists) | No `pull_request` trigger, the key is deleted in an `always()` step, no echo | Review + Turvallisuus |
| T00-19 | Test code does not end up in the release | Release build, `strings`/symbol search of the binary | `-uitest-mock-server`, `-uitest-reset` and MockAPIClient symbols are absent from the release binary (`#if DEBUG`) | CI check + Turvallisuus |
| T00-20 | String Catalog completeness | Lint script / XCTest over every `Localizable.xcstrings` in the repo; test branch where one key lacks its `fi` localization | Every key has both an `en` and a `fi` localization (non-empty); the test branch fails `lint`. No user-facing string literal outside the catalog | K/X: CI lint script + XCTest |

## M01 – test cases
| ID | Test | Expected |
|---|---|---|
| T01-01 | Import boundary | Core does not import SwiftUI or UIKit without an `#if os(...)` adapter (CI grep fails in a test branch) |
| T01-02 | Auth header before sign-in | Exactly `MediaBrowser Client="Glassfin", Device="…", DeviceId="…", Version="…"`, no Token field |
| T01-03 | Auth header when signed in | Same + `Token="…"`; field order and quoting match |
| T01-04 | Special characters in the device name | Device name contains `"`, `,`, non-ASCII letters (`ä`, `ö`) and emoji → the header stays valid (escaping or sanitizing) |
| T01-05 | Never header + query at the same time | Media and image URLs carry only `ApiKey`, no Authorization header; API requests carry no `ApiKey` |
| T01-06 | DeviceId is persistent | Generated once; same value after relaunch (mock SecureStore); `-uitest-reset` changes it |
| T01-07 | Endpoint matrix | For every P0 endpoint 6 cases: 200, 401, 404, 500, timeout and invalid JSON → the correct `APIError` variant, no crash |
| T01-08 | 401 handling | Only a server 401 produces the `unauthorized` state; network error, timeout, 5xx, 403 and TLS error never do (K10) |
| T01-09 | Quick Connect route | Initiate uses POST (12.x); also works on 10.10 |
| T01-10 | Ticks ↔ Duration | 0, 1 tick, 10 000 000 (1 s), > 24 h, `Int64.max` boundary, negative position → 0 + one warning; RunTimeTicks ≤ 0 → duration `nil`; reporting never sends a negative PositionTicks, round-trip conversion is lossless |
| T01-11 | Mappers | Every DTO → domain mapper with a 12.x and a 10.10 fixture; missing optional fields (nil overview, no images, no trickplay) do not crash |
| T01-12 | Unknown enum | Unknown `Type` string → `.other(String)`; unknown `MediaSegmentType` → `.unknown` |
| T01-13 | Token not in UserSession | `UserSession` does not contain the token; `description` or `dump` does not leak it (also Turvallisuus S requirements) |
| T01-14 | WebSocket backoff | Full jitter: the n-th delay ∈ [0, min(30, 2^n) s] (injected `Clock`, seeded randomness). Connection open < 10 s → the counter is NOT reset (flapping test). Open ≥ 10 s → reset. Reconnect immediately on returning to foreground. |
| T01-15 | WebSocket events | Mock socket sends `UserDataChanged` and `LibraryChanged` → the events arrive in the stream; `KeepAlive` produces no UI event; an unknown type is ignored |
| T01-16 | ServerShuttingDown / Restarting | Does not sign out; moves to the reconnect state |
| T01-17 | Cancellation | Cancelled `Task` → the request is cancelled, no leak, no error toast (important for M09 K6) |
| T01-18 | Concurrency | Swift 6 strict concurrency `complete` without warnings (build log) |
| T01-19 | Coverage | Core ≥ 80 % line coverage |
| T01-20 | Integration | Sign-in, UserViews, Resume and PlaybackInfo on 12.x; same on 10.10.7 and 10.11.11 in Docker containers (Q5 resolved, v1.3) |
| T01-30 | WebSocket auth (Docker) | Open `/socket` with only the `Authorization` header (no `ApiKey`/`api_key` query) on each version 10.10.7 / 10.11.11 / 12.2; wait for the first `KeepAlive`/`ForceKeepAlive` ≤ 10 s. Negative: wrong token → connection rejected, no logout on anything other than 401. If some version requires the query → exception for the group to decide |
| T01-31 | Keychain access group (Turvallisuus #1) | With a signed build the token is stored and read (no -34018); the access group is read from the Info.plist key `GlassfinKeychainAccessGroup` with the team prefix; updates use `SecItemUpdate`, the old value is kept if the write fails |
| T01-32 | Case-insensitive credential query (Turvallisuus #3) | `apikey=`, `ApiKey=`, `API_KEY=`, `Api_Key=` → `containsCredentialQuery` true and both redactors mask the value |
| T01-33 | Redirect port change (Turvallisuus #4) | `https://host:8096` → `https://host:8080` counts as cross-origin: `Authorization` is removed, the `ApiKey` URL is rejected |
| T01-21 | S4.6 cross-host redirect | Mock 302 to another host, port or scheme → the new request has no `Authorization` header |
| T01-22 | S4.6 HTTPS → HTTP | Mock 301 `https://` → `http://` → `insecureRedirect` error, the request is not made |
| T01-23 | S4.6 same-host + limit | Same-host redirect works (header kept), the 6th consecutive redirect → error, loop A→B→A → error |
| T01-24 | S4.6 + ApiKey | Cross-host redirect for a media URL with `ApiKey=` → the request is rejected (decision 2026-10-21); same for HTTPS→HTTP. Note: applies only to the app's own requests, not to AVPlayer |
| T01-25 | S1.5 ApiKey boundary | CI grep: `ApiKey` only in `MediaURLBuilder`; a test branch that uses it elsewhere → `lint` fails |
| T01-26 | S5.1 redaction | Logger receives a URL with `ApiKey=abc` → the log shows `ApiKey=<redacted>`; also error messages and `URLError.failingURL` |
| T01-28 | Header injection | CR/LF in the device name → rejected or stripped; other values URL-encoded; the header is never split in two |
| T01-29 | Artifact redaction | Test run with a known token → the token does not appear in JUnit, logs or screenshots (grep over artifacts) |
| T01-27 | S1.4 entitlements | CI check: Keychain access group only on the app and Top Shelf targets; a test branch where the iOS test target or a new extension has it → fails |

## Acceptance
The module can be accepted when all of the spec's acceptance criteria and the P0 tests above are green in CI, open questions Q1–Q5 are resolved or consciously recorded as open, and there are no open critical bugs.

## M03 – Security hardening (PR #5) – regression tests from Turvallisuus's review

> **Test note:** assert on the error type (`publicHTTPRejected`, `insecureRedirect`, …) or on the String Catalog key, never on a hardcoded user-facing string (Finnish or English). Error strings live in `Localizable.xcstrings` (dev language `en`, `fi` as localization), e.g. `AppError.swift` and `SessionTermination.swift`.

| ID | Test | Expected result |
|---|---|---|
| T03-01 | Certificate approval bound to the fingerprint: the user approves fingerprint B, the server presents C | `cancel`, C is not pinned, neither B nor C is written to the pin store (settings), A is kept |
| T03-02 | Same on the first approval (no previous pin), approved B ≠ presented C | `cancel` |
| T03-03 | Happy path: approved fingerprint == `leafHex` (also case/separator variants after normalization) | Pinned; the next connection with the same cert passes without asking |
| T03-04 | After pinning the certificate changes to D | Connection blocked, the user gets a new approval dialog with D's fingerprint |
| T03-05 | HTTP to a public IPv4: `http://203.0.113.5:8096`, `http://8.8.8.8` | `publicHTTPRejected`, no network request, no token/password |
| T03-06 | HTTP to a public IPv6: `http://[2001:db8::1]:8096`, `http://[2606:4700::1111]` | `publicHTTPRejected` |
| T03-07 | HTTP allowed private: 127.0.0.1, 10.0.0.5, 172.16.0.1, 172.31.255.254, 192.168.1.10, 169.254.1.1, 100.64.0.1, 100.127.255.254, `[::1]`, `[fe80::1]`, `[fd00::1]` | Allowed with the 🔓 marker |
| T03-08 | Edge cases: 172.15.0.1, 172.32.0.1, 100.63.255.255, 100.128.0.1, 192.169.0.1, IPv4-mapped `[::ffff:8.8.8.8]`, `[::ffff:192.168.1.1]` | Public ones rejected; a mapped address is evaluated with the IPv4 rules |
| T03-09 | Spoofing forms: `http://0x7f000001`, `http://2130706433`, `http://127.1`, `http://192.168.1.1.nip.io` | Not interpreted as a private IP (hostname → HTTPS required) |
| T03-10 | Redirect from private HTTP to a public HTTP IP | Rejected, Authorization is not sent |
| T03-11 | (PR #5: T03-28) Non-canonical numeric forms (Koodari's finding after 3057b64): `134744072`, `0x08080808`, `0177.0.0.1`, `010.0.0.1` (octal → 8.0.0.1), `127.1`, `127.0.1`, `0x7f.1`, `192.168.1.1.` (trailing dot), `192.168.001.010` | All rejected (`publicHTTPRejected` or invalid), none is accepted for HTTP as local |
| T03-12 | IPv6 special forms: `[::ffff:7f00:1]`, `[::ffff:808:808]`, `[::192.168.1.1]`, `[64:ff9b::808:808]` (NAT64), `[fe80::1%25en0]` (zone id) | Spec v1.3.2 S4.3: only `::ffff:`-mapped is evaluated with the IPv4 rules (7f00:1 → allowed, 808:808 → rejected); `::a.b.c.d` and NAT64 are always public → rejected (also `::192.168.1.1`); zone id handled consistently, no crash. In PR #5 as T03-29 |
