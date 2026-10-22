# Test plan – M04 (adding a server and signing in)

**Author:** Testaaja · 2026-10-22 · **Based on:** spec/04-auth.md, 03-security.md, 02-state-errors-performance.md, 01-core.md, 05-design-system.md, 00-infra-ci.md, SPEC.md, all v1.3.3 (2026-10-22). **Updated 2026-10-22 at 10:28:** 04's "Clarifications v1.3.3" are taken into account (reference `04 T1.3.3/Qx`).
**Environment:** Testaaja runs Linux. Mac tests run in CI (`test-tvos`, `test-ios`, `full-ui`), and Testaaja reads the artifacts (JUnit, PNG, coverage). Device tests are done by Koodari or the user (SPEC §8 R7).
**Work queue:** Queue A; M04 starts once PRs #5, #7 and #9 are merged (SPEC §3 "Parallel work queues").

**References:** `04 UC-Ax` = use case · `04 NV/Ax` = view in the screen-flow section · `04 NV/Focus` · `04 TLn` = operating logic item n · `04 HK` = acceptance criteria · `Sx.y` = 03-security.md · `02 §n` / `02 Pn` / `02 v1.3.2` = 02-state-errors-performance.md · `05 §n` · `01 Auth` = 01-core.md auth header section. (Short codes NV, TL, HK and T1.3.3 are kept as reference codes.)
**Run:** **L** = Linux `swift test` (only the GlassfinCore targets that do not depend on Apple frameworks; ⚠️ Linux build unverified, 00 `lint` item) · **X** = macOS XCTest · **U** = macOS XCUITest (`XCUIRemote`, mock server `-uitest-mock-server`) · **S** = snapshot (1080p + 4K) · **I** = Linux Docker integration (`integration.yml`, 10.10.7 / 10.11.11 / 12.2) · **K** = review or CI lint script · **M** = manual device test.
**🔒** = raised to Turvallisuus (traceable to 03-security.md).
**UI strings and assertions:** expected UI texts are given as the English dev-language string (`Localizable.xcstrings`) with the Finnish localization in parentheses. X and L tests assert on the error type / state (e.g. `publicHTTPRejected`, `invalidCredentials`, `.unsupportedServer`) or on the String Catalog key, never on a hardcoded string. U and S tests run in the `en` locale; the `fi` localization is covered by T00-20. Final English wording is owned by Spesifikaatio/Koodari in the catalog.

## A1 Welcome and first launch (UC-A1)
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T04-01 | Clean install (`-uitest-reset`) → app launch | A1 is shown: Glassfin logo and name over brand art or a static background, one `.glassProminent` button "Connect to Server" (fi: "Yhdistä palvelimeen"), which has the default focus | 04 NV/A1, 04 NV/Focus | U, S |
| T04-02 | Menu pressed on A1 | The app exits (system default), no crash and no state change | 04 NV/Focus | U |
| T04-03 | UC-A1 end to end with the Siri Remote only: A1 → A2 (HTTPS mock) → A3 → A4 → mock approves Quick Connect | Moves to home. Screenshots A1–A4 are in the artifacts | 04 HK UC-A1 | U |

## A2 Server address: input, normalization and errors
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T04-04 | A2 opens empty, and A2 is returned to with the field filled | When empty, the default focus is on the text field. When filled (navigating back) it is on the "Continue" (fi: "Jatka") button | 04 NV/Focus, 04 T1.3.3/Q4-05 | U |
| T04-05 | Focus order on A2: field ↔ "Continue", then Menu | All elements are reachable with up/down moves, there is no focus trap, and Menu returns to A1 | 04 NV/Focus | U |
| T04-06 | Input without scheme or port, e.g. `nas` (S4.3 allows HTTP), every attempt ends in connection refused | The mock records the exact order: 1) `https://nas` (443), 2) `https://nas:8920`, 3) `http://nas:8096`, 4) `http://nas` (80). Attempts are made sequentially | 04 NV/A2, 04 T1.3.3/Q4-02 | L, X |
| T04-07 | Scheme or port given: (a) `https://nas`, (b) `http://nas`, (c) `nas:8096`, (d) `https://nas:8096` | (a) only `https://nas`, and `https://` never changes to `http://`. (b) only `http://nas`. (c) `https://nas:8096` and then `http://nas:8096`, no other ports. (d) only `https://nas:8096` | 04 T1.3.3/Q4-02 | L, X |
| T04-08 | Reverse proxy subpath: `https://host/jellyfin` and `https://host/jellyfin/` (also schemeless `host/jellyfin`, where the subpath is kept in every attempt) | `GET https://host/jellyfin/System/Info/Public`, and the trailing `/` is removed. The subpath is kept in all later calls (sign-in, `/Users/Me`) | 04 HK, S4.5 | L, X, I |
| T04-09 | 🔒 Forbidden scheme: `ftp://h`, `file:///x`, `javascript:x`, `glassfin-media://x` | Inline error and no network request (mock: 0 requests) | S4.5 | L, X |
| T04-10 | 🔒 Credentials in the URL: `https://user:pass@host` | Userinfo is removed. It is not in the request, UserDefaults, the UI or the logs | S4.5 | L, X |
| T04-11 | 🔒 Public HTTP: `http://203.0.113.5:8096`, `http://8.8.8.8` | Error "Public addresses require HTTPS" (fi: "Julkiset osoitteet vaativat HTTPS:n") and a hint about a reverse proxy. No network request is made. Policy limits are in M03's T03-05…T03-12 regression; this tests the UI | 04 HK, S4.3 | U, X |
| T04-12 | 🔒 Schemeless public IP `203.0.113.5`, and HTTPS does not answer | HTTP attempts 3–4 are skipped (0 HTTP requests), and the result is the `publicHTTPRejected` message | S4.3, 04 T1.3.3/Q4-02 | X |
| T04-13 | 🔒 Schemeless public multi-label hostname (`jellyfin.example.com`), and HTTPS does not answer | S4.3 does not allow the host, so HTTP attempts are skipped and the result is `publicHTTPRejected` | S4.3, 04 T1.3.3/Q4-02 | X |
| T04-14 | 🔒 Schemeless HTTPS attempt 1 ends in a TLS error (`serverTrust`, self-signed certificate) | A2c opens. No further attempts are made, i.e. no fallback to HTTP (mock: 0 HTTP requests) | 04 T1.3.3/Q4-02, S4.4 | X |
| T04-15 | Server answers | `ServerName` and version are shown on A2 | 04 NV/A2 | U, S |
| T04-16 | 🔒 `ServerName` contains HTML (`<b>x</b>`), control characters or 500 characters | Shown as plain text without HTML rendering, and the layout does not break. The truncation limit is open (Q4-16) | S6.1 | X, S |
| T04-17 | DNS error, connection refused or timeout | Inline error "Server not found" (fi: "Palvelinta ei löytynyt"), and the loading state leaves the button | 04 NV/A2, 02 §3 | X, U |
| T04-18 | Response 200, but it is not Jellyfin: an HTML page, JSON without an `Id` or `ProductName` field, or an unparseable `Version` | Inline error "Not a Jellyfin server" (fi: "Ei Jellyfin-palvelin"). A valid response requires the fields `Id` and `ProductName` | 04 NV/A2, 04 T1.3.3/Q4-01, Q4-02 | X |
| T04-88 | 🔒 Valid Jellyfin response with `StartupWizardCompleted = false` | Sign-in does not continue. Message "Server setup is not complete. Finish setup in a web browser at <server URL>." (fi: "Palvelimen käyttöönotto on kesken. Viimeistele asennus selaimella osoitteessa …") with the entered server URL, and a "Try again" (fi: "Yritä uudelleen") button. No connection is made, the server is not saved, there is no in-app wizard and no admin user is created (P0; mock: no `/Startup/*` calls and no sign-in). Assert on the error type / catalog key | 01 endpoints, Spesifikaatio+Turvallisuus 2026-10-22 (Q4-14) | X, U |
| T04-92 | 🔒 On the T04-88 view, setup is completed on the server (mock switches to `StartupWizardCompleted = true`), then "Try again" | "Try again" re-runs the `/System/Info/Public` check (mock: exactly one new check), the server connects normally and the flow continues to A3. Before completion, "Try again" shows the same message again with no `/Startup/*` calls | Spesifikaatio 2026-10-22 (Q4-14) | X, U |
| T04-19 | Mock version 10.9.11 | Blocking view "Server version 10.9.11 is too old (requires ≥ 10.10.0)" (fi: "Palvelimen versio 10.9.11 on liian vanha (vaaditaan ≥ 10.10.0)"), `blockingError = .unsupportedServer` | 04 HK, 02 §3, 02 v1.3.2, 04 T1.3.3/Q4-01 | X, U |
| T04-20 | Version comparison limits: `10.9.11`, `10.9.99-rc1`, `10.10.0`, `10.10.0-rc1`, `10.10.7`, `10.11.11`, `12.2.0-beta`, `abc`, empty, `10.10`, `10`, `10.x` | Only the numeric `major.minor.patch` is compared, and the suffix is ignored: `10.9.x` → blocking view, `10.10.0-rc1` and newer → OK. Two-part `10.10` is accepted and parsed as `10.10.0` → OK. One-part (`10`) or non-numeric (`10.x`, `abc`, empty) is unparseable → `notJellyfin` ("Not a Jellyfin server" (fi: "Ei Jellyfin-palvelin")) | 04 T1.3.3/Q4-01, Spesifikaatio 2026-10-22 (Q4-19), 02 §3 | L |
| T04-21 | Loading state: `/System/Info/Public` answers with a 2 s delay | The loading state is shown in the button for the whole wait | 04 NV/A2 | U |
| T04-22 | A2 is left with Menu in the middle of the check | The request is cancelled (`.cancelled`), no error toast appears, and a late response does not move the user to A3 | 02 §1, 02 §3 `cancelled` | X, U |
| T04-23 | Poor network: every attempt hangs (mock does not answer), injected `Clock` | Each attempt is cut off at 5 s. "Server not found" arrives at the latest at 20 s, when the 4th attempt is skipped because of the cap. No crash on the 3G profile | 04 T1.3.3/Q4-02, 02 §3 Poor network | X, M |
| T04-24 | Device offline on A2 (`NetworkMonitor` mock) | Banner "No network connection" (fi: "Ei verkkoyhteyttä") appears ≤ 2 s and disappears ≤ 2 s after the connection returns | 02 §3 Offline | U |
| T04-84 | 🔒 Schemeless attempt 1 ends in a DNS error (NXDOMAIN) on a host for which S4.3 allows HTTP (`nas`) | The search stops immediately with "Server not found". No further attempts are made, including HTTP (mock: 1 request). Moving to the next attempt happens only on connection refused and timeout (T04-06), and a TLS error never leads to HTTP (T04-14) | 04 T1.3.3/Q4-02, 03 T1.3.3/Q4-03 | X |
| T04-85 | 🔒 `http://nas.home.arpa:8096`, `http://jellyfin.internal`, `http://media.lan`, also schemeless | The names are not local: `publicHTTPRejected`, with a hint to use an IP address or a `.local` name. No HTTP request is made. Schemeless, HTTPS is tried normally but HTTP attempts are skipped. No device test is needed for the suffixes | 04 T1.3.3/Q4-02, 03 T1.3.3/Q4-04, S4.3 | L, X |
| T04-86 | Schemeless HTTPS attempt 1 (443) returns 200 but not a Jellyfin response (e.g. a router HTML page), and attempt 2 (`https://host:8920`) is a valid Jellyfin | Attempt 1 is rejected (a 2xx that is not a valid Jellyfin response) and the search moves on to the next candidate. Attempt 2 wins and A2 shows its `ServerName`. Variant: attempt 2 also ends in connection refused/timeout and no HTTP candidate succeeds → "Not a Jellyfin server", because a candidate answered non-Jellyfin | 04 T1.3.3/Q4-02, Spesifikaatio+Turvallisuus 2026-10-22 (Q4-18) | X |
| T04-89 | 🔒 Captive portal on a public name: `jellyfin.example.com`, HTTPS 443 returns a 200 HTML page (not Jellyfin), and 8920 ends in refused | No HTTP attempts are made (mock: 0 HTTP requests), because S4.3 does not allow a public name. Nothing succeeds and a candidate (the captive portal) answered non-Jellyfin → "Not a Jellyfin server" (fi: "Ei Jellyfin-palvelin"). No token or credentials are sent | 04 T1.3.3/Q4-02, S4.3, Spesifikaatio+Turvallisuus 2026-10-22 (Q4-18) | X |

## A2b / A2c Unencrypted and self-signed server (UC-A5)
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T04-25 | 🔒 `http://192.168.1.10:8096` (private) | A2b warning "Connection is not encrypted" (fi: "Yhteys ei ole salattu"). Confirmation → A3 | 04 HK UC-A5, S4.2, S4.3 | U |
| T04-90 | 🔒 On device, `http://192.168.x.x:8096` (real LAN server) | The connection is established (A2b → A3), because `NSAllowsLocalNetworking = YES` allows HTTP to a private IP address | 03 T1.3.3/Q4-04, S4.1, S4.3 | M |
| T04-91 | 🔒 `Info.plist` check (lint script) | `NSAllowsLocalNetworking = YES` is set. `NSAllowsArbitraryLoads`, `NSExceptionDomains`/`NSExceptionAllowsInsecureHTTPLoads` and other ATS exceptions are absent, and a test branch that has one fails the `lint` job | 03 T1.3.3/Q4-04, S4.1, 00 `lint` | K |
| T04-26 | 🔒 A2b: user declines | No connection. The server is not saved to UserDefaults, and the view returns to A2 | 04 HK UC-A5 | U, X |
| T04-27 | 🔒 A2b and A2c open | Default focus is on "Cancel" (fi: "Peruuta"). "Continue Unencrypted" (fi: "Jatka salaamattomana") and certificate approval require a deliberate focus move. Select immediately after opening approves nothing | 04 T1.3.3/Q4-05 | U |
| T04-28 | 🔒 HTTP server after saving | The server row in Settings has a permanent 🔓 marker (tested once M10 exists) | S4.2, 10 P0 Account | U |
| T04-29 | 🔒 Self-signed certificate (mock challenge) | A2c shows the SHA-256 fingerprint, subject and validity. Approval pins exactly the leaf that was shown. Regressions: T03-01…T03-04 | 04 HK UC-A5, S4.4 | X, U, S |
| T04-30 | 🔒 A2c: user declines | No connection, and nothing is written to the pin store | 04 HK UC-A5, S4.4 | X, U |
| T04-31 | 🔒 The pinned certificate changes before the next launch | The connection is cut, and the warning shows the old and the new fingerprint. **The user is not signed out**, and the token is kept (TLS ≠ 401) | S4.4, S2.2 | X, U |
| T04-32 | 🔒 HTTPS and a CA-trusted certificate | No pinning: no pin fingerprint is stored in UserDefaults | S4.4 [AGREED] | X |

## A3 / A4 Quick Connect
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T04-33 | `GET /QuickConnect/Enabled` = true | A3: Quick Connect has the default focus, and the alternative is "Use Password" (fi: "Käytä salasanaa") | 04 NV/A3 | U, S |
| T04-34 | `Enabled` = false | Expected result is open: A3 with only the password option, or straight to A5 (Q4-06) | 04 NV/A3 | U |
| T04-35 | Starting Quick Connect | The mock verifies `POST /QuickConnect/Initiate` (not GET). When it is called (A3 or A4 view) is open (Q4-07) | 04 HK, S3.1, 01 endpoints | X |
| T04-36 | A4 is shown | Large 6-character `Code` and the instruction "Open Jellyfin on your phone or in a browser → User → Quick Connect → enter the code" (fi: "Avaa Jellyfin puhelimella tai selaimella → Käyttäjä → Quick Connect → syötä koodi") | 04 NV/A4 | U, S |
| T04-37 | 🔒 `Secret` on A4 | Not shown in the UI, not stored in UserDefaults or the Keychain, and does not appear in logs, JUnit or screenshots (redactor: `secret`) | S3.2, S5.2, S5.5 | X, K |
| T04-38 | Polling with an injected `Clock` | `GET /QuickConnect/Connect?secret=` is sent every 5 s. `Authenticated` = true → `POST /Users/AuthenticateWithQuickConnect {Secret}` → token to the Keychain → home | S3.1, S3.3, 04 NV/A4 | X |
| T04-39 | A4 is left with Menu, and the clock is advanced 60 s | Polling is cancelled, and no network request is made after leaving (mock client) | 04 HK, S3.3 | X, U |
| T04-40 | 5 minutes pass without approval | The polling task is cancelled. Whether the code is renewed automatically is open (Q4-08) | S3.3, 04 NV/A4 | X |
| T04-41 | Transient error while polling (timeout, 503) | Polling continues, and it does not result in a sign-out or the `unauthorized` state | 01 Scope 2 (SDK 3.1.0), S2.2 | X |
| T04-42 | App to background during A4 and back to foreground | Expected result is open (Q4-08) | S3.3 | U |
| T04-43 | `AuthenticateWithQuickConnect` returns 401 | `invalidCredentials`, no session-expiry flow. The message text is open (Q4-15) | S2.2, 02 v1.3.2 | X |
| T04-44 | Quick Connect on Docker servers 10.10.7, 10.11.11 and 12.2 (admin approves the code via the API) | Sign-in succeeds on all three versions, and `Initiate` is POST | 04 HK, SPEC §2, §6.10 | I |

## A5 Username and password (UC-A2)
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T04-45 | A5 focus order: username → password → "Sign In" (fi: "Kirjaudu"), then Menu | No focus trap, and Menu returns to A3. The fields have `.textContentType(.username)` and `.password` | 04 NV/A5, 04 NV/Focus | U |
| T04-46 | Correct credentials | `POST /Users/AuthenticateByName {Username, Pw}` → token to the Keychain → `AppState.phase = .signedIn` → home | 04 TL2, 01 endpoints | X, U, I |
| T04-47 | Wrong password (401) | Inline error "Incorrect username or password" (fi: "Väärä käyttäjätunnus tai salasana"), the password field is cleared and focus returns to it. The state is `invalidCredentials`, not session expiry | 04 HK UC-A2, S2.2, 02 v1.3.2 | U, X |
| T04-48 | 🔒 Password lifecycle, also after a successful sign-in | The password is not found in a UserDefaults dump, Keychain items, logs or JUnit. `Pw` is redacted, and the field is empty after the call | S1.2, S5.2 | X, K |
| T04-49 | 🔒 Screenshots of A5 | The password is not visible in clear text (secure field, mock credentials) | S5.5 | S, K |
| T04-50 | Network error, timeout or 500/503 during sign-in | A plain-language error that is not "wrong password" and does not lead to the `unauthorized` state. The message text is open (Q4-15) | S2.2, 02 §3, 02 v1.3.2 | X |
| T04-51 | Non-ASCII letters and emoji in username and password (`Äijä`, `pässi🔑+ "x"`) on a Docker server | Sign-in succeeds, i.e. the values pass through the JSON body unchanged | 04 UC-A2, 01 endpoints | I |

## Post-sign-in actions and storage
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T04-52 | Successful sign-in | The mock verifies the `POST /Sessions/Capabilities/Full` call: `PlayableMediaTypes` [`Video`, `Audio`], `SupportsMediaControl` and `DeviceProfile`. The profile before M08 and handling a failed call are open (Q4-13) | 04 TL2 | X |
| T04-53 | 🔒 Keychain attributes (SecureStore mock) | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and `kSecAttrSynchronizable = false`. The key is `serverId + userId`, DeviceId is its own item, and updates use `SecItemUpdate`. Regression: T01-31 | S1.1, S1.4, SPEC v1.3.1 | X |
| T04-54 | 🔒 Token location | The token is not in UserDefaults, a plist, Caches or `UserSession`. UserDefaults holds only the server (URL, name, id and pin) | S1.3, 02 §2 | X |
| T04-55 | UserDefaults size with 10 servers and 10 users | < 50 KB | 02 §2, 02 HK | X |
| T04-56 | 🔒 Auth header before and after sign-in | Before sign-in there is no `Token` field, after it there is. Only one `Authorization` header is sent, and requests carry no `ApiKey` query. Regressions: T01-02, T01-03 and T01-05 | 01 Auth, S1.5, S1.6 | X |

## Launch while signed in (UC-A3, K10)
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T04-57 | Force quit and relaunch, `/Users/Me` 200 | Home view without the sign-in view | 04 HK UC-A3, 04 TL1 | U |
| T04-58 | `/Users/Me` 401 | A3 with the message "Session expired" (fi: "Istunto päättyi") (text differs from 02: Q4-11). The token is removed from the Keychain, and the sign-in view is shown only once (no duplicates) | 04 TL1, 02 §3, S2.2 | X, U |
| T04-59 | Server down at launch (connection refused) | Home from cache and the offline banner. The sign-in view is not shown, and the token is kept | 04 HK UC-A3, SPEC K10 | U |
| T04-60 | At launch `/Users/Me` answers with a 6 s delay (injected `Clock`) | 5 s timeout, no retries (mock: exactly 1 `/Users/Me` call) → home from cache in offline mode | 04 TL1, 04 T1.3.3/Q4-09 | X |
| T04-61 | 🔒 `/Users/Me` returns 403, 500, 502, 503, 504 or a TLS error | No sign-out, and the token is kept. What the UI shows on 403 and 500 is open (Q4-10) | S2.2, 02 v1.3.2 | X |
| T04-62 | Device offline at launch | Home from cache and the banner "No network connection" | 04 TL1, 02 §3 Offline | U |
| T04-63 | Offline launch with Caches cleared (no home-view snapshot) | No crash and no sign-in view. What is shown is open (Q4-10) | 02 §2, SPEC K12 | U |
| T04-64 | Connection returns after an offline launch | The banner disappears ≤ 2 s, and home refreshes without signing in again | 02 §3 Offline | U |
| T04-65 | Server version below the minimum at launch | `blockingError = .unsupportedServer`, `phase = .needsLogin`, and the token is kept | 02 v1.3.2 | X |
| T04-87 | After an offline launch the server comes back (injected `Clock`) | Background ping every 10 s. When the server answers, home refreshes and the banner disappears without signing in again. A later 401 signs out per S2.2 | 04 T1.3.3/Q4-09, 02 §3 Server down | X, U |

## Sign-out and server removal (UC-A4)
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T04-66 | Sign-out via the confirmation dialog | The mock verifies the `POST /Sessions/Logout` call, and the Keychain is empty | 04 HK UC-A4, S2.1 | X, U |
| T04-67 | 🔒 Sign-out while offline, or `Logout` returns 500 | The Keychain is cleared anyway, and the user is told that the server session may remain active until an administrator removes the device (fi: "Palvelimen istunto voi jäädä voimaan, kunnes ylläpitäjä poistaa laitteen.") | S2.1, 03 HK | X, U |
| T04-68 | View after sign-out, default focus of the confirmation dialog, and relaunch | After relaunch the user is not signed in. The target view and the dialog's default focus are open (Q4-12) | 04 TL3, S2.1 | U |
| T04-69 | 🔒 Docker: after sign-out, `GET /Users/Me` with the old token | 401, i.e. the token has been invalidated on the server | S2.1 | I |
| T04-70 | 🔒 Removing a server from the list | All of the server's Keychain tokens and pins are removed, and `phase` → `.needsServer`. Accounts on other servers are kept | S2.3, 02 v1.3.2 | X |

## UC-A6 LAN discovery (P1)
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T04-71 | P1 🔒 Spoofed discovery response | The list shows the name and address (`Home Server — http://192.168.1.10:8096`). No automatic connection or sign-in | S4.7, 04 HK UC-A6 | X, U |
| T04-72 | P1 🔒 The name is longer than 64 characters or contains HTML | Plain text, truncated to 64 characters. Only the address, name and id are taken from the response | S4.7 | X |
| T04-73 | P1 🔒 Discovery `Id` ≠ `Id` of the `/System/Info/Public` response | The user is warned | S4.7, 03 HK | X |
| T04-74 | P1 🔒 Discovery response with a saved server's id but a different address | The saved address does not change | S4.7 | X |
| T04-75 | P1 Local Network permission denied | Manual address entry works | 04 UC-A6 | U, M |

## Resolutions, platforms, performance and CI
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T04-76 | Snapshots A1–A5 on 1080p and 4K simulators (default, Reduce Transparency, Increase Contrast) | The glass panel is visible over the background without clipping. With Reduce Transparency the sign-in panel is opaque | 05 §2, 05 §5, 05 HK | S |
| T04-77 | Contrast of the Quick Connect code and error texts on the glass panel | WCAG AA (4.5:1 body text, 3:1 large text) | 05 L-3 | S |
| T04-78 | iOS: shared auth ViewModels and services on the iOS simulator | The same unit tests pass (`test-ios`), and the ViewModels have no iOS branches | 11 HK, 00 `test-ios` | X, K |
| T04-79 | P1 iOS UI: XCUITest on iPhone and iPad simulators | M04's acceptance criteria where applicable, with touch (M11) | 11 HK | U |
| T04-80 | A2: iPhone continuity keyboard | Input reaches the field (device) | 04 NV/A2 | M |
| T04-81 | Cold launch while signed in → home | P1 ≤ 1.5 s (A15) / ≤ 3.0 s (oldest). Simulator `XCTApplicationLaunchMetric` only for regression; on device it is recorded for the release | 02 P1, 02 v1.3.2 | X, M |
| T04-82 | 🔒 Release build | `-uitest-mock-server` and `MockAPIClient` are absent from the binary (regression T00-19) | 00 Testability | K |
| T04-83 | 🔒 Artifacts of M04 test runs | JUnit, logs and coverage contain no token, no `Pw` and no QC secret, and the scan fails the job on a hit | S5.5, 00 Artifacts | K |

## Open questions
| # | Question | Spec wording | For |
|---|---|---|---|
| Q4-01 | **Resolved (Spesifikaatio 2026-10-22)**: MIN = `10.10.0`, only the numeric part is compared, RC and beta suffixes are ignored, unparseable → "Not a Jellyfin server" (04 T1.3.3). Tests T04-19 and T04-20. **Note:** Tutkija reported the Kotlin SDK's `minimumVersion` as `ServerVersion(12,0,0,0)`. Tutkija confirmed this: Jellyfin jumped from 10.11 to 12.0. MIN 10.10.0 is a deliberate deviation from the SDK recorded by Spesifikaatio (04 T1.3.3). The binding MIN is still **10.10.0** (the user confirmed support for 10.10+). | 04: "Server version X is too old (requires ≥ MIN)" · SPEC §2: "**10.10** (in practice 10.10.7) – ASSUMPTION" · 02: "Mock version 10.9.11 → blocking view." | Spesifikaatio |
| Q4-02 | **Resolved (Spesifikaatio 2026-10-22)**: the subpath is kept. Scheme given → only that one. Port given → only that one, https first and then http. Otherwise https:443, https:8920, http:8096, http:80. HTTP only if S4.3 allows the host. 5 s per attempt, 20 s in total, the first valid Jellyfin response wins. Tests T04-06…T04-08, T04-12, T04-13 and T04-23. New sub-question Q4-18. | 04: "if the scheme is missing, `https://` is tried first, then `http://`. Default ports are tried in order: the entered one, then 8920 (https) and 8096 (http)." | Spesifikaatio |
| Q4-03 🔒 | **Resolved (Spesifikaatio+Turvallisuus 2026-10-22):** TLS error → A2c, never to HTTP. Moving to the next attempt happens only on connection refused and timeout, and to HTTP only for a host allowed by S4.3. **A DNS error stops the search immediately** with "Server not found" (04 T1.3.3/Q4-02, 03 T1.3.3/Q4-03; spec files as of 2026-10-22 at 10:31). Tests T04-06, T04-14 and T04-84 | 04: "`https://` is tried first, then `http://`" · S4.4: "accepted only after the user's confirmation" | Spesifikaatio, Turvallisuus |
| Q4-04 🔒 | **Resolved (Spesifikaatio+Turvallisuus 2026-10-22):** `.home.arpa`, `.internal` and `.lan` are **not** local; they get the `publicHTTPRejected` error and a hint to use an IP address or a `.local` name. ATS exceptions are forbidden, and `NSAllowsLocalNetworking = YES` is mandatory (03 T1.3.3/Q4-04, 04 T1.3.3/Q4-02). Tests T04-13, T04-85, T04-90 and T04-91 | S4.3: "`.local`, single-label names and **private** IP addresses" · "**Public addresses require HTTPS**" | Turvallisuus |
| Q4-05 🔒 | **Resolved (Spesifikaatio 2026-10-22)**: on A2 the text field (when filled, "Continue"), on A2b and A2c "Cancel". Tests T04-04 and T04-27. | 04: "every view has one defined default focus (`prefersDefaultFocus`)" | Spesifikaatio, Turvallisuus |
| Q4-06 | What is shown when Quick Connect is disabled: A3 with only the password, or straight to A5? | 04: "if `GET /QuickConnect/Enabled` is true … **Quick Connect has the default focus**" (the false case is not described) | Spesifikaatio |
| Q4-07 | Is `Initiate` called on entering A3 or only on A4? | 04 A3: "(started with the call `POST /QuickConnect/Initiate`)" | Spesifikaatio |
| Q4-08 | Is the code renewed automatically after 5 minutes, and how many times? What happens when the app goes to the background? | 04 A4: "The code is renewed when it expires." · S3.3: "the code expires/times out after 5 minutes or when the view is left (the polling task is cancelled)" | Spesifikaatio |
| Q4-09 | **Resolved (Spesifikaatio 2026-10-22)**: at launch 5 s, no retries. Timeout → home from cache in offline mode and a background ping every 10 s. 401 signs out. 02's 15 s and 2 retries apply to other calls. Tests T04-60 and T04-87. | 04 TL1: "(timeout 5 s)" · 02: "The API request timeout is 15 s, and idempotent GETs are retried 2 times" | Spesifikaatio |
| Q4-10 | What does launch show when `/Users/Me` returns 403 or 500, and what does an offline launch show without a cached snapshot? | 04 TL1: "Network error → **home from cache in offline mode**" (403/500 and empty Caches are missing) | Spesifikaatio |
| Q4-11 | Which message for 401: "Session expired" (fi: "Istunto päättyi") or "Session expired, please sign in again" (fi: "Istunto päättyi, kirjaudu uudelleen")? | 04 TL1: "401 → A3 with the message "Session expired"" · 02: ""Session expired, please sign in again"" | Spesifikaatio |
| Q4-12 | Which view does sign-out lead to (A1, A3 or A2), what is the confirmation dialog's default focus, and where is sign-out triggered before M10? | 04 TL3: "Sign-out (Settings → Sign Out, confirmation dialog): S2.1." | Spesifikaatio |
| Q4-13 | Which DeviceProfile is sent before M08? Does a failed Capabilities call block the `.signedIn` state? | 04 TL2: "`POST /Sessions/Capabilities/Full` (… DeviceProfile from M08). After that `AppState.phase = .signedIn`." | Spesifikaatio, Koodari |
| Q4-14 | **Resolved (Spesifikaatio+Turvallisuus 2026-10-22):** a valid response requires the `Id` and `ProductName` fields (T04-18). If `StartupWizardCompleted = false`, sign-in does not continue: "Server setup is not complete. Finish setup in a web browser at <server URL>." is shown with a "Try again" button that retries the check. No in-app wizard and no admin creation (P0). Tests T04-88 and T04-92 | 04: ""Not a Jellyfin server"" · 01: "`ServerName`, `Version`, `Id`, `StartupWizardCompleted`" | Spesifikaatio |
| Q4-15 | What are the error messages for sign-in network and 5xx errors and for a Quick Connect authentication 401? | 04 A5: "The error message for 401 is "Incorrect username or password"." (no others) | Spesifikaatio |
| Q4-16 🔒 | Is `ServerName` truncated on A2 (S4.7's 64-character limit applies only to discovery)? | S4.7: "The name is shown as plain text, truncated to 64 characters." | Turvallisuus |
| Q4-17 | **Resolved (Spesifikaatio 2026-10-22)**: all module files and SPEC.md are now v1.3.3 (2026-10-22). | SPEC.md line 1 and line 3 | Spesifikaatio |
| Q4-18 | **Resolved (Spesifikaatio+Turvallisuus 2026-10-22):** a 2xx response that is not a valid Jellyfin response moves on to the next candidate. If nothing succeeds and some candidate answered non-Jellyfin, the error is "Not a Jellyfin server"; otherwise "Server not found". TLS and DNS errors still stop the search. HTTP candidates are tried only for hosts allowed by S4.3, i.e. a public name never goes to HTTP (captive portal). Tests T04-86 and T04-89 | 04 T1.3.3: "The first response that is a valid Jellyfin response (`Id` and `ProductName`) wins." · "Moving to the next attempt happens only on a connection-level error (DNS, connection refused, timeout)." | Spesifikaatio |
| Q4-19 | **Resolved (Spesifikaatio 2026-10-22):** two-part `10.10` is accepted and parsed as `10.10.0`. A one-part or non-numeric version is unparseable → "Not a Jellyfin server". Test T04-20 | 04 T1.3.3: "the numeric `major.minor.patch` part is compared" | Spesifikaatio |
