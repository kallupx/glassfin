# Test plan – PoC acceptance (end-to-end simulator journeys, Siri Remote only)

**Author:** Testaaja · 2026-10-27 · **Based on:** SPEC.md, 02-state-errors-performance.md, 03-security.md, 04-auth.md, 05-design-system.md, 06-home.md, 07-library-detail.md, 08-playback.md, 10-settings.md and spec/adr/M08-2.md on `main` (`9f374df`), the PoC tier agreed in the Glassfin group on 2026-10-27 (reference `PoC 10-27`; not yet in SPEC.md, pending Spesifikaatio's spec PR, QPOC-01), and the module plans TESTPLAN-M04, -M05, -M06, -M07, -ADR-M08-2 and -M08a-PoC.
**PoC content:** M02, M04 and M05 as specified · M06 Home with "Continue watching", "Next Up" and "Recently added" as **separate rows** (Q6-20) · M07 grid and detail, series **one season at a time** (Q7-25) · M08a-PoC (TESTPLAN-M08a-PoC) · M10 minimal: "Sign out" + app version only (04 Q4-12 placeholder). **Out of scope:** video transcoding and any DeviceProfile beyond the static one, audio/subtitle tracks, trickplay, media segments, the next-up timer, M09 search, device measurements P1–P15.
**PoC is accepted when:** the PoC PRs are merged to `main` and **every journey below passes in the tvOS simulator against a native macOS Jellyfin server on 10.10.7, 10.11.11 and 12.2**, the full path working end to end: add server → sign in (password **and** Quick Connect) → Home → movie or episode detail → playback. Rows marked *optional* (device checklist) do not block PoC acceptance.
**Environment:** journeys are run with the Siri Remote only (`XCUIRemote` or the simulator's remote window), never with touch or the keyboard except to type text in fields. Journeys run in CI on a **hosted macOS runner against a native macOS Jellyfin server started beside the simulator** (group decision 2026-10-27, QPOC-02 resolved). Evidence **per J journey** is the xcresult, a `xcrun simctl io <sim> recordVideo` recording and redacted `PlaybackInfo`/`/Sessions` logs, uploaded as CI artifacts only after the pre-upload secret scan passes (TPOC-80, TPOC-81), plus a JUnit summary that Testaaja reviews from Linux. Server-side checks (UserData, `/Sessions`, logs) use the server's admin API on the runner; API-level checks on all three versions also run on Linux Docker (**I**). The runner uses the macOS arm64 Jellyfin builds from repo.jellyfin.org for all three versions (10.10.7 from the archive URL, 10.11.11, 12.2 from tag `v12.2`), with jellyfin-ffmpeg installed separately and passed with `--ffmpeg` (QPOC-11 resolved). Build configuration: rows tagged **[Release]** run on the Release build (QPOC-09 resolved); the other journeys may run on Debug. Device rows are done by kallut (SPEC §8 R7).
**Seed (per run, per server version):** `scripts/jellyfin_bootstrap.py` plus the additions in QPOC-03: an admin and a non-admin test user with **passwords generated randomly on every run, never hardcoded** (TPOC-79); a "Movies" library with F1–F5 (+ F6 optional) from TESTPLAN-M08a-PoC Appendix A (**F1 and F3 about 60 s**, the others under 10 s); a "Shows" library with **one series "Glassfin Test Show" with two seasons**: Season 1 with 2–3 episodes (S01E01–S01E03, or S01E01–S01E02; F1 recipe, ~60 s) and Season 2 with one short episode (S02E01, under 10 s); 2026 air dates (locked seed, Q7-25); Quick Connect enabled; `MinResumeDurationSeconds=0` set via `/System/Configuration` (Q8P-08 resolved; `MinResumePct` 5 % and `MaxResumePct` 90 % still apply). The same seed is used for the macOS servers and the Linux API matrix.

**References:** `Tnn-xx` = row in the module test plan (T04 = TESTPLAN-M04, T05 = -M05, T06 = -M06, T07 = -M07, T08-2 = -ADR-M08-2, T08P = -M08a-PoC) · `04 HK UC-An` · `06 UP n` / `06 HK` · `07 FSn` · `08 PBn` · `02 §n` / `02 v1.3.4` · `Sx.y` = 03-security.md · `PoC 10-27` = group decision of 2026-10-27 · `Fn` = test media.
**Run:** **L** = Linux `swift test` · **X** = macOS XCTest · **U** = macOS XCUITest (`XCUIRemote`); in this plan **U means on the hosted macOS runner against the native macOS Jellyfin server** unless the row says "mock" · **S** = snapshot (1080p + 4K) · **I** = Linux Docker integration (`integration.yml`, 10.10.7 / 10.11.11 / 12.2) · **K** = review or CI lint script · **M** = manual (simulator run by Koodari, or an Apple TV run by kallut where the row says device).
**🔒** = raised to Turvallisuus (traceable to 03-security.md).
**[Release]** after 🔒 = the row runs on the **Release** build configuration (token rows: Q8P-15 conditions, the 401 path, log redaction; QPOC-09 resolved).
**UI strings and assertions:** expected UI texts are given as the English dev-language string (`Localizable.xcstrings`) with the Finnish localization in parentheses. U runs are in the `en` locale except journey J12. Elements are identified by `accessibilityIdentifier` or catalog key. Journeys are **ordered**: within a journey each row starts from the state the previous row left.

## J0 Preconditions
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| TPOC-01 | All PoC PRs (M02, M04, M05, M06, M07, M08a-PoC, M10 minimal) are merged; `main` CI (`lint`, `test-linux`, `test-tvos`, `full-ui`, `integration`) is green on the commit under test | The commit SHA is recorded in the run report; no red job, no skipped security job | SPEC §8, PoC 10-27 | K |
| TPOC-02 | Native macOS arm64 Jellyfin servers 10.10.7, 10.11.11 and 12.2 (repo.jellyfin.org; jellyfin-ffmpeg passed with `--ffmpeg`) on the hosted runner, plus the Linux API matrix (Docker) for the **I** rows, all bootstrapped with the seed above | Each server starts with the given `--ffmpeg` path and reports its version on `/System/Info/Public`; both libraries are scanned (movie and series counts match the seed); `MinResumeDurationSeconds` reads back as 0; the 12.2 bootstrap does not stop at "library scan found no movie" | SPEC §2, QPOC-03, QPOC-11, Q8P-08 | I, U |
| TPOC-03 | Module plans' automated rows referenced below | The referenced T04/T06/T07/T08-2/T08P rows are green in CI on the same commit; a journey failure is first checked against the module row | PoC 10-27 | K |
| TPOC-04 | Simulator: tvOS 26 Apple TV 4K (3rd gen) simulator, clean install, `en` locale | App installs and launches; no leftover Keychain items from earlier runs (`-uitest-reset` or simulator erase) | 02 §2 | U |

## J1 First launch: add server and sign in with a password
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| TPOC-05 | Launch after clean install | A1 with "Connect to Server" (fi: "Yhdistä palvelimeen") focused (T04-01); Menu exits | T04-01, T04-02 | U |
| TPOC-06 | Enter the macOS server address (`http://127.0.0.1:8096` on the runner) in A2 → "Continue" | The server is validated with `GET /System/Info/Public`; for HTTP the A2b warning "Connection is not encrypted" (fi: "Yhteys ei ole salattu") appears with "Cancel" (fi: "Peruuta") and "Continue unencrypted" (fi: "Jatka salaamattomana"); after continuing, A3 opens with the server name | T04-04, 04 UC-A1, 04 UC-A5, S4.2 | U |
| TPOC-07 | A3 → password sign-in (A5) with the non-admin test user | `AuthenticateByName` succeeds; Home opens (T04-46); the password field is empty after the call (T04-48) | T04-46, T04-48, 04 HK UC-A2 | U |
| TPOC-08 | Home first view | Rows in order: "Continue watching" hidden (empty), "Next Up" hidden or with S01E01 per server, "Recently added" per library (Movies, Shows) (T06-09, T06-15, T06-17); default focus on the first card of the first visible row (T06-03); tab bar reachable (T06-05) | T06-03, T06-09, T06-15, T06-17, Q6-20 | U |
| TPOC-09 | Screenshots of A1, A2, A3, A5 and Home | Saved per step; no password or token visible (T04-49) | T04-49, S5.5 | U, K |

## J2 First launch with Quick Connect
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| TPOC-10 | Clean install → A1 → A2 (same server) → A3 → "Quick Connect" (A4) | A code is shown; `Initiate` is POST (T04-44) | T04-03, T04-44 | U |
| TPOC-11 | The admin approves the code via the server admin API (`POST /QuickConnect/Authorize?code=`, as the test user) | The app signs in within one polling interval and opens Home; same Home as TPOC-08 | T04-03, T04-44, 04 HK UC-A1 | U |
| TPOC-12 | Quick Connect disabled on the server (12.2 run only, admin setting) | Password sign-in (A5) still works end to end (04 UC-A2: "when Quick Connect is not enabled"); how A3/A4 present the disabled state is recorded | 04 UC-A2, 04 NV/A4 | U |

## J3 Play every matrix file from the library
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| TPOC-13 | Tab bar → "Movies" → grid | Grid with F1–F5 (F6) posters, default focus on the first poster (T07-01, T07-04) | T07-01, T07-04 | U |
| TPOC-14 | F1 (MP4 H.264+AAC) → detail → "Play" (fi: "Toista") | Detail per T07-21…23; DirectPlay starts, picture and sound; Menu back to detail with focus on "Resume" (fi: "Jatka") or "Play" (T08P-06, T08P-22) | T07-21, T07-23, T08P-06, T08P-22 | U |
| TPOC-15 | F2 (MP4/MOV HEVC+EAC3) → "Play" | DirectPlay; plays to the end; returns to detail; item marked played (T08P-07, T08P-23). Simulator HEVC/EAC3 limits are recorded, not failed (Q8P-18) | T08P-07, T08P-23, Q8P-18 | U |
| TPOC-16 | F3 (MKV H.264+AAC) → "Play" | DirectStream remux; plays; server `/Sessions` shows video and audio copied; `TranscodingUrl` `TranscodeReasons` is only `ContainerNotSupported` (T08P-08, T08P-09, T08P-81) | T08P-08, T08P-09, T08P-81 | U, I |
| TPOC-17 | F4 (MKV H.264+DTS) → "Play" | Plays with audio-only transcode, **no error at any point**; `/Sessions` shows `IsVideoDirect=true`, `IsAudioDirect=false`; `TranscodeReasons` has container and `Audio*` reasons only, so the parser allows it (T08P-10, T08P-11, T08P-80) | T08P-10, T08P-11, T08P-80, PoC 10-27 | U, I |
| TPOC-18 | F5 (MKV MPEG-2) → "Play" | Error "This video format isn't supported yet" within ≤ 10 s, no hang; the client's codec check stopped it, so **no `PlaybackInfo` call** was made and `/Sessions` shows no session item or transcode for the device (T08P-79); OK/Menu returns focus to "Play"; then F1 plays normally (T08P-13, T08P-15) | T08P-13, T08P-15, T08P-79, Q8P-05 | U |
| TPOC-19 | *(optional)* F6 (MKV HEVC+AC3) → "Play" | DirectStream remux, both copied (T08P-12) | T08P-12 | U |
| TPOC-20 | During TPOC-14 and TPOC-16: Play/Pause twice, right/left clicks, scrub to the middle | Pause/resume and seek work; Progress reports immediately on each (server `/Sessions` position follows) (T08P-19…21, T08P-27) | T08P-19, T08P-20, T08P-21, T08P-27 | U, I |
| TPOC-21 | Menu chain after playback: detail → grid → tab bar | Focus returns to the same poster in the grid (T07-19), then to the tab bar (T05-28); no focus trap (T05-29) | T07-19, T05-28, T05-29 | U |

## J4 Play from Home
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| TPOC-22 | Home → "Recently added – Movies" → click F3 card | Detail opens (T06-31); "Play" plays F3; Menu returns to detail, Menu again to Home with the same card focused (T06-31) | T06-31, T08P-58 | U |
| TPOC-23 | Home → Play/Pause on the F1 card in "Recently added" (no progress) | Playback starts from the beginning without opening detail (T06-33); Menu returns to Home with the same card focused | T06-33, 06 UP 4 | U |
| TPOC-24 | Home → "Recently added – Shows" → series card | Series view opens (T07-41); the season picker shows "Season 1" and "Season 2"; only the selected season's episodes are listed (T07-43). The picker is also shown for a one-season series (Q7-25; checked in TPOC-82) | T07-41, T07-43, Q7-25 | U |

## J5 Continue watching and resume
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| TPOC-25 | Play F3 (~60 s) and press Menu at about 30 s | `Stopped` with the position; server UserData `PlaybackPositionTicks` ≈ 30 s (T08P-29, T08P-33) | T08P-29, T08P-33, Q8P-08 | U, I |
| TPOC-26 | Menu to Home | F3 appears first in "Continue watching" (fi: "Jatka katsomista") within ≤ 2 s without a restart, with a progress bar and the remaining time; default focus goes there on the next launch (T06-01, T06-20, T06-57) | T06-57, T06-20, T06-01, 02 P14 | U |
| TPOC-27 | Play/Pause on the F3 card in "Continue watching" | Playback starts directly at the saved position ± 2 s, no prompt (T06-32, T08P-39) | T06-32, T08P-39, 08 PB8 | U |
| TPOC-28 | Menu, then click the F3 card → detail | Detail shows "Resume" with the remaining time focused and "Start over" next to it (T07-24) | T07-24 | U |
| TPOC-29 | "Resume" | Starts at the saved position ± 2 s (T07-25, T08P-36/38) | T07-25, T08P-36, T08P-38 | U |
| TPOC-30 | Menu, then "Start over" | Starts at 0 (T07-26, T08P-37); after Menu at ~3 s the "Continue watching" card shows the new position | T07-26, T08P-37 | U |
| TPOC-31 | Play F3 to the end | F3 leaves "Continue watching"; detail shows "Play" and the watched check mark; server `Played=true` (T08P-23) | T08P-23, 06 HK | U, I |

## J6 Episodes and Next Up
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| TPOC-32 | Open "Glassfin Test Show" (nothing watched) | Default season "Season 1", default focus on S01E01 (T07-45, T07-46); down/up between picker and episodes per FS3/FS4 (T07-48, T07-49) | T07-45, T07-46, T07-48, T07-49 | U |
| TPOC-33 | Open S01E01 (episode detail or direct play per Q7-20) and play it to the end | Playback ends, returns to the series view with focus on **S01E02** (FS6, T07-51); S01E01 shows the watched check mark (T07-52) | T07-51, T07-52, T07-53, 07 FS6 | U |
| TPOC-34 | Menu to Home | S01E01 is not on "Continue watching"; **S01E02 is on "Next Up"** (fi: "Seuraavat jaksot") within ≤ 2 s without a restart (T06-58); "Continue watching" and "Next Up" stay separate rows (T06-10) | T06-58, T06-10, 06 HK, Q6-20 | U |
| TPOC-35 | Play/Pause on the S01E02 "Next Up" card | Plays S01E02 from the beginning (T06-33) | T06-33 | U |
| TPOC-36 | Stop S01E02 (F1 recipe, ~60 s) at about 30 s → Home | S01E02 moves to "Continue watching" and is not shown twice (T06-11) | T06-11, Q8P-08 | U |
| TPOC-37 | Series view → "Resume" (series-level button) | Starts S01E02 at the saved position (T07-58) | T07-58 | U |
| TPOC-38 | Watch the last episode of Season 1 (S01E03, or S01E02 with a 2-episode seed) to the end | Return to the series view per Q7-08 (focus on S02E01 or the picker); Home "Next Up" (fi: "Seuraavat jaksot") shows **S02E01** within ≤ 2 s: Next Up crosses the season boundary | T07-51, Q7-08, T06-58 | U |
| TPOC-39 | Switch to "Season 2" in the picker and back to "Season 1" | Season 2 lists only S02E01, Season 1 lists only its episodes; focus stays in the picker while switching; no reload flicker (T07-44, T07-50) | T07-44, T07-50, Q7-25 | U |
| TPOC-82 | One-season series (mock server: a series with a single season) → series view | The season picker **is shown** with only "Season 1" and is focusable; its episodes are listed; down/up between picker and episodes works (Q7-25) | Q7-25, T07-43, T07-44 | U |

## J7 Returning launch
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| TPOC-40 | Force quit and relaunch (server up) | Home without the sign-in view (T04-57); cached snapshot first, then fresh data without a focus jump (T06-44); default focus on the first "Continue watching" card (T06-01) | T04-57, T06-44, T06-01 | U |
| TPOC-41 | Relaunch after the simulator's Caches are purged | Home loads from the network; no crash, still signed in (T06-45) | T06-45 | U |

## J8 Settings: version, sign out and sign back in
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| TPOC-42 | Tab bar → Settings (fi: "Asetukset") | Only "Sign out" (fi: "Kirjaudu ulos") and the app version are shown (Q4-12 placeholder / M10 minimal); the version matches `CFBundleShortVersionString` (build) of the tested build | 04 Q4-12, 10 About, PoC 10-27, QPOC-05 | U, S |
| TPOC-43 | "Sign out" → confirmation dialog | Default focus on "Cancel" (fi: "Peruuta") (Q4-12); "Cancel" keeps the session | 04 Q4-12, T04-68 | U |
| TPOC-44 | "Sign out" confirmed | `POST /Sessions/Logout` is sent, the Keychain is empty (T04-66); target view per Q4-12 (user picker or A3), the server is kept | T04-66, T04-68, 04 Q4-12 | U |
| TPOC-45 | 🔒 [Release] Server admin API: `/Users/Me` with the old token | 401 (T04-69) | T04-69, S2.1 | I |
| TPOC-46 | Sign in again (password) | Home opens; "Continue watching" and "Next Up" show the same items as before sign-out (state is server-side) (T08P-41) | T04-46, T08P-41 | U |
| TPOC-47 | Relaunch after sign-out (without signing in again) | Not signed in; A3 or the user picker opens (T04-68) | T04-68 | U |

## J9 Server unreachable
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| TPOC-48 | Stop the Jellyfin server process on the runner, then relaunch the signed-in app (Home snapshot cached) | Cached Home with the `.serverUnreachable` banner (text: QPOC-06), not the full-screen state; token kept, no sign-in view (T04-59, T06-56) | T04-59, T06-56, 02 v1.3.4 | U |
| TPOC-49 | In that state, open a movie detail that was not cached | Full-screen "Can't reach the server" (fi: "Palvelimeen ei saada yhteyttä") with "Try again" focused and "Change server" (T07-64) | T07-64, T06-46 | U |
| TPOC-50 | In that state, "Play" on a cached detail | A clear playback error, no hang; not signed out (T08P-47 / T08P-52) | T08P-47, T08P-52 | U |
| TPOC-51 | Start the server process again | The 10 s ping detects it; banner disappears and Home refreshes within ≤ 15 s, focus not moved (T04-87, T06-48) | T04-87, T06-48, 02 §3 | U |
| TPOC-52 | Browse the movie grid, then stop the server process mid-browse; move focus and open a detail already loaded | Content stays, banner shown, inline error for server actions (T06-49, T06-50, T07-63) | T06-49, T06-50, T07-63 | U |
| TPOC-53 | Server stopped mid-playback (F1, then F3) | Buffering, the buffering message after 5 s, error with "Try again" after 30 s; after the server is started again, "Try again" continues from the same position (T08P-48) | T08P-48, 08 PB12 | U |
| TPOC-54 | Simulator network off on Home, then on (host network toggle or Network Link Conditioner) | "No network connection" (fi: "Ei verkkoyhteyttä") ≤ 2 s, not focusable; playback blocked with a message; back on → banner gone ≤ 2 s and Home refreshes (T06-42, T06-43, T05-18, T08P-50) | T06-42, T06-43, T05-18, T08P-50 | U, M |

## J10 Session expired
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| TPOC-55 | 🔒 [Release] Signed in on Home; the admin revokes the app's device/token via the server admin API (`DELETE /Devices?id=`); then refresh Home | All requests cancelled; sign-in view once with "Session expired, please sign in again" (fi: "Istunto päättyi, kirjaudu uudelleen"); token removed; no loop (T06-51, T04-58) | T06-51, T04-58, S2.2, 02 §3 | U |
| TPOC-56 | 🔒 [Release] Same revoke during playback of F1 | Media 401 → exactly one `/Users/Me` → 401 → signed out with the same message once (T08P-43) | T08P-43, Q8-2-09 | U |
| TPOC-57 | 🔒 [Release] Same revoke during F3 (DirectStream) | Segment/playlist 401 → same as TPOC-56, no playlist reload loop (T08P-45) | T08P-45, Q8-2-09 | U |
| TPOC-58 | Sign in again after TPOC-55…57 | Home works; the earlier "Continue watching" item resumes correctly | T04-46, T08P-41 | U |
| TPOC-59 | 🔒 A user without playback permission (admin disables "Allow media playback") presses "Play" | "You don't have permission to do this" (fi: "Ei oikeuksia tähän toimintoon"); not signed out (T08P-46, T07-68) | T08P-46, T07-68, S2.2 | U |

## J11 Version matrix
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| TPOC-60 | J1–J10 on 10.10.7 | All rows pass, or a version-specific difference is recorded as a finding | SPEC §2, PoC 10-27 | U |
| TPOC-61 | J1–J10 on 10.11.11 | As TPOC-60 | SPEC §2 | U |
| TPOC-62 | J1–J10 on 12.2 (macOS arm64 build, tag `v12.2`) | As TPOC-60. 12.2 removed `api_key`, so any query credential failure is a finding (S1.5) | SPEC §2, S1.5, QPOC-11 | U |
| TPOC-63 | Next Up and Continue watching contents compared across the three versions after the same J5/J6 steps | Same items; a difference (e.g. `enableResumable` behavior) goes to QPOC-07 | T06-07, QPOC-07 | U, I |

## J12 Finnish locale pass
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| TPOC-64 | Simulator language Finnish (`-AppleLanguages (fi)`); repeat J1, J3 (TPOC-14, TPOC-18), J5, J8, J9 (TPOC-48, TPOC-49, TPOC-54) and J10 (TPOC-55) | Every visible string is Finnish: "Yhdistä palvelimeen", "Jatka katsomista", "Seuraavat jaksot", "Viimeksi lisätyt", "Toista", "Jatka", "Alusta"/"Aloita alusta" (Q7-15), "Asetukset", "Kirjaudu ulos", "Peruuta", "Ei verkkoyhteyttä", "Palvelimeen ei saada yhteyttä", "Yritä uudelleen", "Istunto päättyi, kirjaudu uudelleen", the unsupported-video text (Q8P-10); no English fallback, no truncation at 1080p and 4K | T00-20, T08P-63, 05 L-3 | U, S |
| TPOC-65 | Catalog completeness on the tested commit | Every key has `en` and `fi` (T00-20) | T00-20 | K |

## J13 Security spot checks across the journeys 🔒
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| TPOC-66 | 🔒 [Release] Jellyfin server log (macOS servers, and the Linux API matrix for the I rows) after J1–J10 | No token or password in any logged URL on API, DirectPlay and playlist paths; a credential appears at most on server-generated DirectStream segment requests, the ADR D4 accepted risk (Q8P-15 resolved: conditions T08P-70, T08P-88, T08P-74) | S1.5, ADR D4, T08P-77, Q8P-15 | I, K |
| TPOC-67 | 🔒 [Release] App log (`log collect` from the simulator) and all run artifacts, including the xcresult and the screen recording | No token, `ApiKey=`, `Token="`, `Pw` value; report and AVPlayer errors appear only redacted (T08P-73, T08P-74, T08P-76) | S5.1, S5.2, S5.5 | K |
| TPOC-68 | 🔒 [Release] The tested build is a **Release** configuration build | No header-to-key fallback and no `ApiKey` in app-built URLs (T08P-71, Q8-2-11); the run report records which rows ran on Release (QPOC-09); `check-release-binary.sh` passes (T08P-72) | PoC 10-27, T08P-71, T08P-72 | K, U |
| TPOC-78 | 🔒 Pinned self-signed server (macOS server behind a self-signed TLS endpoint, certificate pinned on first contact): play F1, then F3 | F1 DirectPlay plays normally through the resource loader (T08P-55). F3 (remux) shows "This video can't be played yet from a server with a self-signed certificate." (fi: "Tätä videota ei voi vielä toistaa palvelimelta, jolla on itse allekirjoitettu varmenne.") with no hang and no suggestion to bypass or remove the pin; focus returns to "Play" (T08P-87) | T08P-55, T08P-87, Q8P-13, ADR D5 | U |
| TPOC-79 | 🔒 Seed credentials | The admin and test-user passwords are generated with a CSPRNG on **every run** (two runs give different values) and never hardcoded: a repo scan of `scripts/`, workflows and test code finds no literal password; the value reaches the UI test only through a masked secret/env, never in a command line or a log line | S5.5, QPOC-03 | K, I |
| TPOC-80 | 🔒 Pre-upload artifact scan (runs before every `upload-artifact`) | Scans every artifact (xcresult contents and attachments, app and server logs, `PlaybackInfo`/`/Sessions` logs, JUnit) for `ApiKey=` and `Token=` values and the run's generated passwords; any hit **fails the job and nothing is uploaded**. Self-test: a planted canary (`ApiKey=<canary>`, `Token="<canary>"`, the generated password) in a dummy artifact makes the job fail | S5.5, T08P-76 | K |
| TPOC-81 | 🔒 Evidence for each journey J0–J13 | Each J has its xcresult, an `xcrun simctl io <sim> recordVideo` recording, and the `PlaybackInfo` and `/Sessions` logs passed through the redactor (tokens and `TranscodingUrl` credentials `<redacted>`); all pass TPOC-80; a journey missing any of the three is not accepted | PoC 10-27, QPOC-02, S5.1 | K, U |

## J14 Optional manual checklist on a real Apple TV (kallut, *optional for the PoC*)
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| TPOC-69 | *(optional)* Install the dev build (from Koodari); add your own server; sign in with Quick Connect from the phone | Signed in to Home in one go; the server name and lock indicator shown correctly | 04 UC-A1, S4.2 | M |
| TPOC-70 | *(optional)* Play one MP4 and one MKV from Home | Both play with picture and sound; Menu returns to where playback started | T08P-06, T08P-08 | M |
| TPOC-71 | *(optional)* An MKV with DTS or TrueHD audio from kallut's library | Plays (audio transcoded), no error; sound through the TV/receiver | T08P-10, 08 PB11 | M |
| TPOC-72 | *(optional)* Stop halfway, go Home, resume from "Continue watching" | Resumes within about 2 s of where it stopped | T08P-39, 08 PB8 | M |
| TPOC-73 | *(optional)* Watch an episode to the end | The next episode is on "Next Up" right away | T06-58 | M |
| TPOC-74 | *(optional)* Seek with clicks and swipes, pause/resume on a 4K HEVC file | Responsive; no long stall; note the feel (no P-measurements in the PoC) | 08 PB1 | M |
| TPOC-75 | *(optional)* Turn Wi-Fi off for 10 s during playback | Playback continues by itself | 08 PB12 | M |
| TPOC-76 | *(optional)* Settings → version, then Sign out → Cancel → Sign out | Version visible; Cancel keeps you signed in; sign-out works | 04 Q4-12 | M |
| TPOC-77 | *(optional)* Anything that felt wrong (focus lost, a stuck spinner, English text in Finnish mode) | Write it down with the time and what was on screen; Testaaja turns it into a finding | PoC 10-27 | M |

## Open questions
| # | Question | Spec wording | For |
|---|---|---|---|
| QPOC-01 | The PoC tier, its acceptance rule and the scope list exist only in the group decision of 2026-10-27; SPEC.md on `main` defines only the MVP. Which spec PR carries them, and does it state "simulator + native macOS server on all three versions" as the acceptance bar? | SPEC.md: "**MVP (P0) is done when:** M00–M10 are accepted (…) and performance targets P1–P15 have been measured on device." | Spesifikaatio |
| QPOC-02 | **RESOLVED (group 2026-10-27):** journeys run on a hosted macOS runner against a native macOS Jellyfin server beside the simulator; evidence is the xcresult plus a screen recording uploaded as artifacts (per journey: TPOC-81). QPOC-11 (12.2 macOS build) is also resolved. | 08 v1.3.3 Q8-2-01: "macOS runners do not have Docker. Therefore simulator tests run against an in-test mock HTTP(S) server." | — |
| QPOC-03 | The bootstrap seeds only a "Movies" library with one movie and fails on 12.2 ("library scan found no movie"). The PoC needs F1–F6 (F1/F3 ~60 s), a "Shows" library with one series with Season 1 (2–3 episodes) and Season 2 (one short episode), a non-admin user, Quick Connect enabled and `MinResumeDurationSeconds=0` via `/System/Configuration` (decided, Q8P-08), on both the native macOS servers and the Linux API matrix. Who extends `jellyfin_bootstrap.py` for both targets, and are media generated in the job (not committed, per `Tests/Media/README.md`)? | `Tests/Media/README.md` (paraphrased): media files are not stored in the repo; playback integration downloads or generates them outside the repo | Koodari, Tutkija |
| QPOC-04 | Q7-20 (does clicking an episode open episode detail or play directly) and Q7-08 (focus after the last episode of a season) are still open; TPOC-33 and TPOC-38 follow the ASSUMPTIONs. | 07 FS6: "returning from playback focuses the same episode, or the next if watched to the end" (paraphrased) | Spesifikaatio |
| QPOC-05 | Version string format in the minimal Settings: `1.0 (123)`, with the commit SHA, or the marketing version only? | 04 Q4-12: "a minimal Settings tab placeholder that shows only "Sign out" (fi: "Kirjaudu ulos") and the app version" | Spesifikaatio |
| QPOC-06 | The text of the `.serverUnreachable` banner (content on screen, server down) is not defined; only the offline banner and the full-screen title have texts. Is it "Can't reach the server" in banner form? | 02 v1.3.4: "it stays visible, `connectivity = .serverUnreachable`, and the banner is shown" | Spesifikaatio |
| QPOC-07 | Next Up / Resume behavior may differ between 10.10.7 and 12.2 (e.g. `enableResumable`, `enableRewatching`, episodes of a series with an in-progress episode). Is a version difference a PoC failure or a documented finding? | 06 Sections: `GET /Shows/NextUp` with `enableResumable=false`, `enableRewatching=false` (T06-07) | Tutkija, Spesifikaatio |
| QPOC-08 | Sign-out target view is still Q4-12 (user picker vs A3); TPOC-44/47 accept either. Should the PoC fix it? | 04 Q4-12: "It goes to the user picker if other users of the same server are saved, otherwise to A3 (or A5 under Q4-06)." | Spesifikaatio |
| QPOC-09 | **RESOLVED (group 2026-10-27):** token rows run on the **Release** configuration (Q8P-15 rows, the 401 path, log redaction); other journeys may run on Debug. Tagged rows: TPOC-45, 55, 56, 57, 66, 67, 68. | `HeaderFieldsKeyPolicy.isAllowed(buildIsDebug:)` returns `buildIsDebug` (main `MediaOpenPlan.swift`) · PoC 10-27 (paraphrased): no `ApiKey` in URLs in a Release build | — |
| QPOC-10 | Revoking the token for J10: is `DELETE /Devices?id=` the agreed way on all three versions, or should the mock's 401 injection be used for the simulator and the real server only for T04-69? | 03 S2.2: "only 401 signs out" (paraphrased) | Koodari, Turvallisuus |
| QPOC-11 | **RESOLVED (Tutkija 2026-10-27):** macOS arm64 builds exist on repo.jellyfin.org for 10.10.7 (archive URL), 10.11.11 and 12.2 (tag `v12.2`); jellyfin-ffmpeg is separate and passed with `--ffmpeg`. All three versions run the journeys; the 12.2 conditional is dropped. | Tutkija 2026-10-27 (paraphrased): macOS arm64 builds verified for all three versions | — |
