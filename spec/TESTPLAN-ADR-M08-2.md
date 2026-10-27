# Test plan – ADR M08-2 prototype (media token and self-signed media, no UI)

**Author:** Testaaja · 2026-10-22 · **Based on:** spec/08-playback.md ("Starting playback" item 3, ADR M08-2, and redirects and the resolved URL), 03-security.md (S1.5, S4.3, S4.4, S4.6, S5), 01-core.md (auth header), 02-state-errors-performance.md, SPEC.md §8 R3, all v1.3.3 (2026-10-22). **Updated 2026-10-22:** 08's "Clarifications v1.3.3" are taken into account (reference `08 T1.3.3`).
**Goal:** the prototype resolves S1.5 (token for media without the URL) and R3 (media from a self-signed server). The ADR gets a **separate result for three cases**: 1 direct play, 2 server HLS transcoding and 3 custom loopback remux. **v1.3.3:** Queue C resolves cases 1 and 2. Case 3 moves to M08b, and the ADR records only the planned token-free model for it. The ADR is recorded before the M08a playback path is implemented (08 HK).
**Work queue:** Queue C, no UI (SPEC §3). Focus and Siri Remote tests are therefore mostly N/A (T08-2-40).
**Environment:** Testaaja runs Linux. AVPlayer works only on the macOS simulator or a device. Simulator tests run against an in-test mock HTTP(S) server. The mock serves a small MP4 plus an HLS playlist and segments, some of which require the header and some `ApiKey`. The self-signed certificate is created at runtime with `openssl`. Linux Docker tests only URL and token construction plus `PlaybackInfo` and `TranscodingUrl`, not playback. Real transcoding and playback are verified on a device or a local server before M08a is merged (08 T1.3.3).
**Assertions:** tests assert on the error type / state (e.g. `tlsUntrusted`, `insecureRedirect`, `failed`) or on the String Catalog key, never on a hardcoded user-facing string. Expected UI texts are given in English (dev language) with the Finnish localization in parentheses.

**References:** `08 ADR (a)/(b)/(c)` = options · `08 ADR T1/T2/T3` = prototype cases 1–3 · `08 ADR metrics` · `08 ADR order` = default order · `08 Redirect` = "Redirects and the resolved URL" · `08 k2` = item 2 of starting playback · `08 HK` = acceptance criteria · `Sx.y` = 03-security.md · `02 Pn`. (Short codes k, HK and T1.3.3 are kept as reference codes.)
**Run:** **L** = Linux `swift test` (only pure parts such as the URL builder, playlist rewriting and the redactor; ⚠️ Linux build unverified) · **X** = macOS XCTest (mock HTTP(S) server, AVPlayer in the simulator) · **U** = macOS XCUITest · **S** = snapshot · **I** = Linux Docker integration · **K** = review or CI lint · **M** = manual device test.
**🔒** = raised to Turvallisuus.

## Setup
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T08-2-01 | Test environment: in-test mock HTTP(S) server (static MP4 and HLS master, variant and segments; some require the `Authorization` header, some `ApiKey`), HTTP mode and HTTPS mode with a self-signed certificate created at runtime with `openssl` | The mock records every request (path, headers, query), and the tests are reproducible without an external server. The environment is documented in the ADR | 08 T1.3.3/Q8-2-01, 08 ADR metrics | X |

## Case 1 – direct play (`/Videos/{id}/stream?static=true`)
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T08-2-48 | 🔒 Runtime test certificate | No private key or certificate is in the repo (gitleaks or secret scan), and it does not end up in artifacts | 08 T1.3.3/Q8-2-01, S5.5 | K |
| T08-2-02 | (b) `AVAssetResourceLoaderDelegate` and `glassfin-media://`, whole file | Playback starts. The mock server sees range requests from the app's URLSession with the `Authorization` header, and there is no `ApiKey` in the URL | 08 ADR (b), 08 ADR T1 | X |
| T08-2-03 | (b) seek to start, middle and end, and ±10 s | Each seek sends a new byte-range request, and playback continues. P7 ≤ 1.0 s (A15) / ≤ 2.0 s (oldest) on device | 08 ADR metrics, 02 P7 | X, M |
| T08-2-04 | (b) start: Play → first frame (signpost `playback.firstFrame`) | P5 ≤ 1.5 s / ≤ 2.5 s on device, LAN. On the simulator trend only | 08 ADR metrics, 02 P5 | X, M |
| T08-2-05 | (a) `AVURLAssetHTTPHeaderFieldsKey` on tvOS 26 (`macos-26`) and 27 (`xcode-27`) | The ADR records whether the header is sent on all requests (mock log). The risk of an undocumented key and App Store approval is also recorded | 08 ADR (a) ⚠️, S1.5 | X |
| T08-2-06 | (c) `ApiKey` fallback | The URL has `ApiKey` and the request has no `Authorization` header, i.e. header and query are never used in the same request | 08 ADR (c), 01 Auth Media, S1.5.3 | X, L |
| T08-2-07 | Choice in the default order | Case 1 is tried in the order (b) → (a) → (c), and the choice with its rationale is recorded in the ADR | 08 ADR order | K |
| T08-2-08 | 🔒 On header paths (a) and (b), the server request log after playback | The mock server log contains no `ApiKey` or `api_key` parameter and no token in the URL. A real Jellyfin server's logs are checked on a device or a local server before M08a is merged | 08 ADR metrics, 08 T1.3.3 | X, M |
| T08-2-09 | 🔒 Self-signed server and pinned fingerprint, (b) | Playback succeeds, because pinning is done in the app's URLSession | 08 ADR metrics (T1), S4.4, R3 | X, M |
| T08-2-10 | 🔒 Self-signed server, but the certificate changed after pinning | Playback does not start (`tlsUntrusted`). The token is kept, and the user is not signed out | S4.4, S2.2 | X |
| T08-2-11 | 🔒 Self-signed server without a user-approved pin | The connection is cancelled, and no token is sent | S4.4 | X |
| T08-2-12 | HTTP LAN IP (`http://192.168.x.x:8096`), (b) and (c) | AVPlayer plays with the `NSAllowsLocalNetworking` setting without `NSAllowsArbitraryLoads` (⚠️ device check) | S4.1, S4.3 ⚠️ | X, M |

## Case 2 – server HLS transcoding (`TranscodingUrl`)
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T08-2-13 | Relative `TranscodingUrl` and a base URL with a subpath (`https://host/jellyfin`) | The absolute URL is correct, and the subpath is kept | 08 k2, S4.5 | L, X |
| T08-2-14 | 🔒 `TranscodingUrl` already contains `ApiKey`, `api_key`, `apikey` or `API_KEY` | On the header path the parameter is removed regardless of case, and header and query are never used at the same time | 08 k2, SPEC v1.3.1 S5 | L, X |
| T08-2-15 | (b) master and variant playlists with the `glassfin-media://` scheme against the mock HLS | The playlists are fetched with the app's URLSession with the header. The ADR records whether the delegate intercepts media segments on tvOS 26 and 27 (according to a forum report it does not; the mock log shows who fetches the segments) | 08 ADR (b) ⚠️ limitation, 08 ADR T2, 08 T1.3.3 | X, M |
| T08-2-16 | Playlist URL rewriting: relative and absolute URIs, `#EXT-X-MEDIA` (audio and subtitles) and `#EXT-X-KEY` | Playback and tracks work. The ADR records which URI types go through (b) and which get `ApiKey` (c) | 08 ADR (b) Other risks, S1.5.3 (subtitle streams) | L, X |
| T08-2-17 | Case 2 segments | The `ApiKey` fallback (c) for segments is accepted as a risk only if redaction (T08-2-26…27) and the redirect rule (T08-2-31…36) are in place | 08 ADR T2, S4.6 Accepted risk | K |
| T08-2-18 | Start with transcoding (the signpost starts from the `PlaybackInfo` response) | P6 ≤ 4 s / ≤ 6 s on a real transcoding server on device before M08a is merged. With the mock HLS on the simulator only a functional test | 08 ADR metrics, 02 P6, 08 T1.3.3 | X, M |
| T08-2-19 | Seeking with transcoding | PB1 ≤ 3 s. Which limit applies to case 2 in the ADR is open (Q8-2-04) | 08 PB1, 08 ADR metrics | X, M |
| T08-2-20 | 🔒 Self-signed server and case 2 | The ADR records whether the media plays. If the segments are fetched over AVPlayer's own unpinned connection, the result is recorded as a known limitation (the metric requires only cases 1 and 3) | 08 ADR metrics, S4.4 ⚠️ risk | X, M |

## Case 3 – custom loopback remux (`127.0.0.1` HLS), moved to M08b
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T08-2-21 | Case 3 in the ADR | The ADR records only the planned token-free loopback model: the source is fetched with the app's URLSession with the header and pinning, and AVPlayer's URL contains no token. Implementation and tests move to M08b | 08 ADR T3, 08 T1.3.3/Q8-2-01 | K |
| T08-2-22 | 🔒 Self-signed server and case 3 | **Moved to M08b (v1.3.3)**, not in Queue C's scope. Kept as a basis for the M08b test plan | 08 ADR T3, 08 T1.3.3/Q8-2-01 | – |
| T08-2-23 | Case 3 start and seeking | **Moved to M08b (v1.3.3)**, not in Queue C's scope. Kept as a basis for the M08b test plan | 08 ADR T3, 08 T1.3.3/Q8-2-01 | – |
| T08-2-24 | 🔒 Loopback server listening socket (`127.0.0.1` only) | **Moved to M08b (v1.3.3)**, not in Queue C's scope. Kept as a basis for the M08b test plan | 08 ADR T3, 08 T1.3.3/Q8-2-01 | – |
| T08-2-25 | `http://127.0.0.1` for AVPlayer without `NSAllowsArbitraryLoads` | **Moved to M08b (v1.3.3)**, not in Queue C's scope. Kept as a basis for the M08b test plan | 08 ADR T3, 08 T1.3.3/Q8-2-01 | – |

## Redaction and logs
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T08-2-26 | 🔒 The `Logger` wrapper receives a media URL with `ApiKey=abc`, `api_key=`, `Token=`, `apikey=` or `API_KEY=` | The log gets `<redacted>`, also in error messages and `URLError.failingURL`. Regressions: T01-26 and T01-32 | S5.1, S5.2, SPEC v1.3.1 | L, X |
| T08-2-27 | 🔒 Fallback (c) in use, Diagnostics plus `AVPlayerItem.errorLog()` and `accessLog()` events whose URI contains `ApiKey` | Everything read from the log events goes through URI redaction before the Logger or diagnostics, so URLs are visible only redacted | S1.5.3, S5.1, 03 T1.3.3/Q8-2-07 | X |
| T08-2-28 | 🔒 URLs are not logged | The playback path code has no log call that interpolates a media URL (lint and review) | 08 k2 ("**URLs are not logged**"), S5.4 | K |
| T08-2-29 | 🔒 `ApiKey` in the source code | Appears only in `MediaURLBuilder` (CI grep, regression T01-25) | S1.5.3, 01 HK | K |
| T08-2-30 | 🔒 Prototype test artifacts (JUnit, logs) | The artifact scan has no hits for the patterns `ApiKey=` and `Token="` | S5.5, 00 Artifacts | K |

## Redirects and the resolved URL (S4.6)
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T08-2-31 | 🔒 Direct play: resolution | `MediaURLBuilder` does `HEAD /Videos/{id}/stream` with the app's URLSession, and only the final URL is given to AVPlayer (the mock checks the `AVURLAsset`'s URL) | 08 Redirect, S4.6, 08 HK | X |
| T08-2-32 | 🔒 HLS: resolution | The master playlist `GET` resolves, and the final URL is given to AVPlayer | 08 Redirect, S4.6 | X |
| T08-2-33 | 🔒 `ApiKey` URL and a cross-origin redirect (different host, port `8096 → 8080` or scheme) | `insecureRedirect`, and the URL is not given to AVPlayer (`completionHandler(nil)`) | S4.6, 08 HK, SPEC v1.3.1 | X |
| T08-2-34 | 🔒 HTTPS → HTTP redirect, also on LAN and also on the header path | Rejected, and the user gets an error | S4.6 | X |
| T08-2-35 | 🔒 Same-origin HTTPS → HTTPS redirect, and six consecutive redirects | In the first, playback starts and `ApiKey` is kept. The sixth consecutive redirect → error | S4.6, 08 HK | X |
| T08-2-36 | 🔒 The (b) path's own URLSession request is redirected to a cross-origin address | `Authorization` is removed from the new request or the redirect is rejected | S4.6 | X |
| T08-2-50 | 🔒 The resource loader's playlist has a relative URI, an absolute URI pointing to another origin (variant, segment or `#EXT-X-KEY`) and an `http://` URI in an HTTPS playlist | The relative one is resolved against the playlist's origin and works. Cross-origin and HTTPS → HTTP URIs are rejected, and no request is made to them | 03 T1.3.3/Q8-2-06, S4.6 | X |
| T08-2-37 | 🔒 `HEAD /Videos/{id}/stream` on Docker servers 10.10.7, 10.11.11 and 12.2 | Each answers 2xx/3xx. If one returns 405, the expected result is open (Q8-2-05) | S4.6 ("HEAD is in OpenAPI 12.2.0"), SPEC §2 | I |

## Network, errors and cancellation
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T08-2-38 | A resource loader request ends in a timeout or 503 | `loadingRequest` finishes with an error, playback does not get stuck and the state becomes `failed`. The token is kept | 02 §3, S2.2 | X |
| T08-2-39 | 🔒 A resource loader media request returns 401, and the check `GET /Users/Me` returns 200 | Playback is stopped, and the mock verifies exactly one `/Users/Me` call. The user **stays signed in**, the token stays in the Keychain and a playback error is shown | 03 T1.3.3/Q8-2-09, S2.2 | X |
| T08-2-49 | 🔒 A resource loader media request returns 401, and the check `GET /Users/Me` returns 401 | Playback is stopped. The user is signed out per S2.2: the token is removed, and the sign-in view is shown with the message "Session expired, please sign in again" (fi: "Istunto päättyi, kirjaudu uudelleen") only once | 03 T1.3.3/Q8-2-09, S2.2, 02 §3 | X |
| T08-2-40 | Playback is left with Menu in the native `AVPlayerViewController` (no custom UI) | The resource loader's URLSession tasks are cancelled, and no requests are made after leaving. No focus trap appears, and Menu returns to the test view | 02 §1, 08 Playback view | X, U |
| T08-2-41 | Poor network (3G profile) and a 10 s network outage on the (b) path | The observation is recorded in the ADR: buffering and recovery. The acceptance limit is M08a's PB12, not an ADR metric | 02 §3 Poor network, 08 PB12 | X, M |

## Other risks evaluated in the ADR, resolutions and platforms
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T08-2-42 | AirPlay on the (b) path | The ADR records whether AirPlay works with the custom scheme | 08 ADR (b) Other risks, S1.5.3 | M |
| T08-2-43 | HDR and DV matching on the (b) path: test media 2 and 3, a 4K HDR display and a 1080p SDR display | The ADR records whether `appliesPreferredDisplayCriteriaAutomatically` works and whether the display mode switches correctly | 08 ADR (b) Other risks, 08 PB10 | M |
| T08-2-44 | Memory on the (b) path and 10 play–stop cycles | P12 (≤ 400 MB / ≤ 300 MB) and P13 (growth < 20 MB) are recorded. These are M08a limits, not ADR metrics | 02 P12, P13, 08 HK | X, M |
| T08-2-45 | iOS simulator: the same `MediaURLBuilder` and resource loader | Unit tests pass in the `test-ios` job. Whether iOS belongs in the ADR results is open (Q8-2-10) | 08 Player abstraction, 11 Policy | X |
| T08-2-47 | Linux Docker (10.10.7, 10.11.11 and 12.2): `POST /Items/{id}/PlaybackInfo` with a DeviceProfile and `TranscodingUrl` handling | The response parses. The media URL and `TranscodingUrl` are built correctly on the base URL (also with a subpath). A pre-existing `ApiKey` is removed on the header path, and API calls carry no `ApiKey`. Playback is not tested | 08 T1.3.3/Q8-2-01, 08 k1–k2, S1.5 | I |
| T08-2-46 | ADR M08-2 document | The measured result for cases 1 and 2 and the planned model for case 3, the chosen order, the metrics and the accepted risk are recorded. Turvallisuus has reviewed the ADR before M08a | 08 HK, 03 HK S1.5, SPEC §3 | K |

## Open questions
| # | Question | Spec wording | For |
|---|---|---|---|
| Q8-2-01 | **Resolved (Spesifikaatio 2026-10-22)**: Queue C covers cases 1 and 2. The simulator uses an in-test mock HTTP(S) server (MP4 + HLS) and a runtime `openssl` certificate. Linux Docker tests URL and token construction and `PlaybackInfo`. Real playback is verified before M08a is merged (08 T1.3.3). Tests T08-2-01, T08-2-47 and T08-2-48. | 00: "`integration.yml` (Linux, Docker)" · 08: "No token is visible in the server logs on header paths." | Koodari, Spesifikaatio |
| Q8-2-02 | **Resolved (Spesifikaatio 2026-10-22)**: case 3 moves to M08b, and the ADR records only the planned model (T08-2-21…25). | 08: "3. **Custom loopback remux (M08b):** local `127.0.0.1` HLS" · SPEC §3: "Queue C: ADR M08-2 prototype … no UI" | Spesifikaatio |
| Q8-2-03 🔒 | **Resolved for M08b (Turvallisuus 2026-10-22):** bind only to `127.0.0.1`/`::1` on a random port, 128-bit path token with constant-time comparison, only GET and HEAD for media IDs known to the session, no Jellyfin token in the URL, and shutdown when playback ends or the app goes to the background (03 T1.3.3). Moves to the M08b test plan (T08-2-24) | 08: "local `127.0.0.1` HLS that fetches the source with the app's URLSession" | Turvallisuus |
| Q8-2-04 | Which seek limit applies to case 2: P7 (direct play only) or PB1's ≤ 3 s? | 08 ADR: "start P5/P6, seek P7" · 02: "P7 … direct play LAN" · PB1: "with transcoding (≤ 3 s)" | Spesifikaatio |
| Q8-2-05 🔒 | Do 10.10.7 and 10.11.x support the `HEAD /Videos/{id}/stream` call? What happens on a 405 response (GET + Range, or playback rejected)? | S4.6: "For direct play `HEAD /Videos/{id}/stream` is used (HEAD is in OpenAPI 12.2.0)" | Tutkija, Turvallisuus |
| Q8-2-06 🔒 | **Resolved (Turvallisuus 2026-10-22):** S4.6 applies to everything the resource loader fetches (playlists, variants, segments and keys). Relative URIs are resolved against the playlist's origin, and an absolute URI pointing to another origin as well as HTTPS → HTTP are rejected (03 T1.3.3). Test T08-2-50 | 08: "HLS: the master playlist `GET`" · S4.6: "The server or a proxy can still redirect segment requests elsewhere" | Turvallisuus |
| Q8-2-07 🔒 | **Resolved (Turvallisuus 2026-10-22):** the system log cannot be redacted. Everything read from `errorLog()` and `accessLog()` events goes through URI redaction before the Logger or diagnostics (03 T1.3.3). Test T08-2-27 | S5.1: "The ban covers the console, `os_log`, crash reports and diagnostics." · S5.2: "Logging goes through a single `Logger` wrapper" | Turvallisuus |
| Q8-2-08 | **Partially resolved:** real transcoding and playback are verified on a device or a local server before M08a is merged (08 T1.3.3). Open: who measures the P5, P6 and P7 values, and on which devices (A15, A12, A8)? | 02: "absolute targets are confirmed on device … (Koodari or the user, because Testaaja has no device)" | Koodari, user |
| Q8-2-09 🔒 | **Resolved (Turvallisuus 2026-10-22):** a media 401 alone does not sign out. Playback is stopped and `GET /Users/Me` is run. Only its 401 signs out; otherwise a playback error is shown (03 T1.3.3). Tests T08-2-39 and T08-2-49 | S2.2: "401 from any authenticated request (from the configured server) → the token is removed locally" | Turvallisuus, Spesifikaatio |
| Q8-2-10 | Does the ADR cover iOS (AirPlay and PiP on iOS), or only tvOS? | 08: "`PlaybackCoordinator` is UI-independent, so iOS uses it as is." (the ADR does not mention iOS) | Spesifikaatio |
| Q8-2-11 🔒 | Who decides on the App Store acceptability of option (a), and on what basis? A simulator test does not prove it. | 08 (a): "App Store acceptability is unverified" | Turvallisuus, user |
| Q8-2-12 | **Resolved (Spesifikaatio 2026-10-22)**: all module files and SPEC.md are now v1.3.3 (2026-10-22). | SPEC.md line 1 and line 3 | Spesifikaatio |
