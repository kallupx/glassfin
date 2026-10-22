# Glassfin – a Jellyfin client for tvOS (and later for iOS) – Specification v1.3.3

**Author:** Spec · **Date:** 22.10.2026 · **Version:** v1.3.3 · **Status:** DRAFT. Security has approved 03-security.md. The user confirmed §6.10, §6.11, and §6.13 on 21.10.2026. The change history is below.
**Sources:** the Researcher's research report v1, parts 1–5; the user's goals in the group; requests from Security and the Tester; team decisions (iOS, admin, security); and Spec's own web checks on 21.10.2026 (Jellyfin OpenAPI 12.2.0, jellyfin-sdk-swift, Apple and GitHub release notes, licenses). Downloaded OpenAPI copy: `/workspace/jellyfin-tvos/research/openapi.json`.

> Markers: **P0** = MVP, **P1** = the next release (parity and iOS), **P2** = later. **ASSUMPTION – requires user confirmation** = a default chosen by Spec. ⚠️ = unverified information or a risk. **[AGREED]** = agreed with Security.

## Change history
- **v1.3.3 (22.10.2026, repo made public)** The user made the `kallupx/glassfin` repo public on 22.10.2026 after the Coder's gitleaks audit. R13 is closed. CI limits were relaxed (00-infra-ci.md, "Public repo"), and a self-hosted runner is forbidden. §3 adds parallel work queues. The Tester's questions Q4-01, Q4-02, Q4-05, Q4-09, Q5-01, and Q8-2-01 are resolved (at the end of 04, 05, and 08, "Clarifications v1.3.3"). Module files now have a version header. Security's rulings Q4-03, Q4-04, Q8-2-03, Q8-2-06, Q8-2-07, and Q8-2-09 are recorded at the end of 03-security.md. The Tester's T numbers are used as the test identifiers for M04, M05, and ADR M08-2 (`/workspace/jellyfin-tvos/test/TESTPLAN-*.md`). The repo language is English, the UI development language is English, and Finnish is a localization. The README is a short WIP README (00-infra-ci.md, "Language and README").
- **v1.3.2 (22.10.2026, review of PR #5 (M03))** S4.3: HTTP is allowed only for private IP ranges (the list is in 03-security.md); other IPs → `publicHTTPRejected`. S4.4: acceptance of a self-signed certificate is bound to the fingerprint the user saw, not to a Bool. M02 clarifications based on the 16 questions in PR #7 (end of 02-state-errors-performance.md).
- **v1.3.1 (21.10.2026, standing rules from the review of PR #1)**
  - S4.6: "same host" means the same origin (scheme + host + port). A port change is handled as a cross-host redirect.
  - S5: `ApiKey`/`api_key` detection and redaction are case-insensitive.
  - S3 (new input rule): item, user, and library IDs are validated as 32-character hex GUIDs (with or without hyphens) in a single `JellyfinID` type before they are used in a path. This also applies to deep links, Top Shelf, and WebSocket messages.
  - S1: the Keychain access group is `$(AppIdentifierPrefix)org.glassfin.app`, and it is read from Info.plist. An update is done with a `SecItemUpdate` call, not by deleting and adding.
  - S5.5: `*.xcresult` never ends up in CI artifacts for integration tests, and a redaction failure fails the job.
  - M00: the Linux container's Swift version is kept on the same minor version as Xcode's Swift. Actions are pinned to a SHA, downloaded binaries get a sha256 check, and `release.yml` uses an `environment: release` environment that has a required reviewer.
  - M01: the WebSocket token travels in the `Authorization` header. This is verified by Docker test T01-30. If some server version requires a query token, the matter is escalated to the group and is not changed silently.
- **v1.3 (21.10.2026, user confirmations)**
  - §6.10 Docker integration-test server: CONFIRMED
  - §6.11 MPL-2.0: CONFIRMED
  - §6.13 bundle ID `org.glassfin.app`: CONFIRMED
  - M00: the UI-test mock server and `-uitest-*` arguments exist only in `#if DEBUG` builds, and CI checks the release binary (Security).
  - ~~The repo stays private.~~ **v1.3.3: the repo is public from 22.10.2026** (the user's decision). Standard runners are free, and R13 is closed.
- **v1.2 (21.10.2026, the Tester's questions and Security's clarifications)**
  - **The package name is `GlassfinCore` everywhere** (the old working name was removed from every file; grep: 0 hits).
  - **M00, CI artifacts:** JUnit XML, PNG screenshots, `xccov` coverage JSON, and logs of failed tests, in addition to `.xcresult`, so they can be read on Linux. S5 redaction and scanning also apply to artifacts (S5.5).
  - **M00, integration-test server (PROPOSAL, §6.10):** `jellyfin/jellyfin` containers `10.10.7`, `10.11.11`, and `12.2` as a Linux service, a generated and seeded test library, no macOS minutes. Credentials are generated per run (v1.3.2). ⚠️ The SDK's Linux build is unverified, and there is a fallback plan for it.
  - **M01, tick edge cases:** a negative position → 0 and one warning. `RunTimeTicks` ≤ 0 → the duration is unknown, and no progress bar is shown. A negative value is never sent to the server.
  - **M01, WebSocket reconnect:** full jitter `random(0, min(30 s, 1 s · 2^n))`, and the counter resets only after 10 s of a stable connection. The time source is an injected `Clock`, and in the foreground the client connects immediately.
  - **S1.6/M01, header encoding:**
    - Values are URL-encoded and wrapped in quotes, and CR/LF or any other control character is rejected.
    - Verified against the server's `GetParts` (`WebUtility.UrlDecode`) and jellyfin-sdk-typescript (`encodeURIComponent`).
    - ⚠️ jellyfin-sdk-swift 3.3.0 does not encode, so the header is built by us.
  - **S2.2/M01/M02:** only HTTP 401 signs the user out. Network, TLS, timeout, and 5xx errors never do.
  - **S4.6 [AGREED]:**
    - A cross-host redirect and an HTTPS→HTTP redirect of an `ApiKey` URL are rejected (not mere removal of the parameter). Same-host HTTPS works.
    - The rule covers only the app's own requests, so AVPlayer is always given a resolved final URL.
    - `ApiKey` in HLS transcoding segments is an accepted risk.
  - **ADR M08-2:** in HLS, the resource loader in practice intercepts only playlists and keys (⚠️ forum reports). The prototype tests direct play, the server's HLS (segments probably need `ApiKey`), and our own loopback remux (no token) separately.
- **v1.1 (21.10.2026)**
  - **Security approved 03-security.md.** Marked as agreed:
    - S1.1 `AfterFirstUnlockThisDeviceOnly` (tvOS has no lock screen, and a stricter class would break Top Shelf)
    - S3.3 Quick Connect polling 5 s and timeout 5 min
    - S4.3 public addresses require HTTPS
    - S4.4 CA certificates are not pinned
  - **S1.4:** a shared Keychain access group only for the app and Top Shelf targets (CI check).
  - **S1.5/S5.1 conflict resolved:** the media token is passed primarily as a header (`AVAssetResourceLoaderDelegate`, or the undocumented `AVURLAssetHTTPHeaderFieldsKey` ⚠️). The fallback is `ApiKey=` only in media URLs, and then S5 redaction is mandatory. New ADR M08-2: one prototype resolves both this and R3 (media from self-signed servers).
  - **Jellyfin 12.0 removed `api_key`.** The only query parameter is `ApiKey` (according to Jellyfin, a last resort, because it leaks into proxy logs). Wording corrected in M01, M03, and M08.
  - **New requirements:**
    - S4.6: the Authorization header is not forwarded on a cross-host redirect, and an HTTPS → HTTP redirect is rejected. Added to M01's acceptance criteria.
    - S4.7: UDP 7359 discovery responses are untrusted, the address is always shown, and the user chooses. Added to M04.
  - **Quick Connect:** the start is **`POST /QuickConnect/Initiate`** (12.0 removed GET). Added to M04's acceptance criteria.
  - **ADR M08-1 decided (the Researcher verified):** `AVPlayerViewController` shows scrub thumbnails only for an `#EXT-X-I-FRAME-STREAM-INF` variant, which Jellyfin does not produce (trickplay is JPEG sprites). Therefore a custom scrubbing overlay is built with Jellyfin's sprites, and no server plugin is required. A third-party native-trickplay plugin (10.11 only) is an optional alternative. A trickplay glass overlay was added to M05. R1 is closed by the decision; an implementation risk remains (⚠️ tracking the native scrub state, or a custom scrub bar).
- **v1.0+ (21.10.2026, the same day):**
  - open source and an MPL-2.0 proposal (B1 → R9, LGPL conditions L1–L5)
  - the name Glassfin (name conflict R10)
  - Liquid Glass design system (M05)
  - an Apple Developer account is not an M00 blocker
  - the repo `kallupx/glassfin` and CI cost limits (R13)
- **v1.0 (21.10.2026):** the first version.

---

## 1. Goals and principles
Build **Glassfin**: the best, most efficient, easiest to use, and cleanest Jellyfin client for Apple TV. Later there will be an iOS version **under the same name (Glassfin)** and with the same features.
1. **Reliability before features.** The Researcher's conclusion: the greatest competitive advantage comes from playback reliability and from polishing basic navigation. Every known pain point has been turned into a requirement and an acceptance criterion (§4).
2. **Liquid Glass look (the user's decision):** Apple's tvOS/iOS 26 design language. Glass is in navigation and controls, and content (posters, backdrops, video) stays opaque. System components first (`TabView`, `.buttonStyle(.glass)`, `GlassEffectContainer`, the native transport bar, `.card`). See 05-design-system.md.
3. **One shared core:** the Swift package `GlassfinCore` contains the API, models, view models and state, playback logic, and auth and networking. Only the UI is platform-specific. The iOS target builds from day one.
4. **Testability:** protocol-based services, a mockable API client, and macOS CI (the Tester has only Linux).
5. **Security by default:** the token is in the Keychain, there is no `NSAllowsArbitraryLoads` setting, and tokens are not in logs.

## 2. Platforms and versions
| Item | Decision | Rationale |
|---|---|---|
| tvOS minimum | **tvOS 26** – ASSUMPTION, requires user confirmation | Verified: the current public version is tvOS 27.0 (14.9.2026), and the 27.2 RC was released on 19.10.2026. The proposed minimum is the current version minus one. The Researcher's alternatives "17 or 18" are outdated (Apple moved to year-based numbering, 18 → 26). |
| iOS minimum | **iOS 26** – ASSUMPTION | The same core and the same APIs |
| Build tools | Xcode 27, Swift 6 | The GitHub `xcode-27` runner has been generally available since 15.10.2026 |
| Jellyfin server minimum | **10.10** (in practice 10.10.7) – ASSUMPTION, requires user confirmation | Media segments and trickplay require 10.10+, and Android TV requires the same. ⚠️ **New finding:** the current server is **Jellyfin 12.2** (5.10.2026; 12.0 was released on 8.9.2026), and the Researcher's report did not mention the 12.x series. 12.0 removed legacy auth and the `GET /QuickConnect/Initiate` route. Test against 10.10.7, 10.11.x, and 12.x. Alternative: a minimum of 10.11, which shrinks the test matrix. |
| SDK | jellyfin-sdk-swift ≥ 3.3.0 (MPL-2.0, generated for 12.1) | ⚠️ Compatibility with 10.10 is unverified, and it is verified with integration tests (M00/M01). |

## 3. Modules in implementation order (for the Coder)
| # | File | Module | Priority | Dependencies | Notes |
|---|---|---|---|---|---|
| M00 | [00-infra-ci.md](00-infra-ci.md) | Repo, project, macOS CI (tvOS and iOS), lint, and artifacts for the Tester | **P0** | – | First. Repo `kallupx/glassfin` (public from 22.10.2026). No blockers. |
| M01 | [01-core.md](01-core.md) | GlassfinCore: networking, the auth header, the API layer (SDK), domain models, endpoints, and WebSocket | **P0** | M00 | Shared by tvOS and iOS |
| M02 | [02-state-errors-performance.md](02-state-errors-performance.md) | State management (`@Observable`), the error model, cache (the tvOS 500 KB limit), performance targets P1–P15 | **P0** | M01 | Cross-cutting |
| M03 | [03-security.md](03-security.md) | Security requirements S1–S9 | **P0** | M01 | 🔒 Security reviews |
| M04 | [04-auth.md](04-auth.md) | Adding a server, Quick Connect, password, sign-out, and the certificate flow | **P0** | M01–M03, M05 | |
| M05 | [05-design-system.md](05-design-system.md) | Liquid Glass design system, components, focus rules, accessibility, the glass performance budget, and the screen hierarchy | **P0** | M00 | In parallel with M01–M04. ADR M05-1 (the ⚠️ items) before M06 |
| M06 | [06-home.md](06-home.md) | Home: continue watching, next up, and recently added | **P0** | M01–M05 | |
| M07 | [07-library-detail.md](07-library-detail.md) | Libraries, detail, and the series, season, and episode view | **P0** | M01–M05 | |
| M08 | [08-playback.md](08-playback.md) | **M08a** AVPlayer + the server's DirectStream/Transcode, DeviceProfile, reporting, tracks, segments, trickplay, and next-up | **P0** | M01–M07 | ADR M08-2 (the media token and self-signed media) as a prototype first. ADR M08-1 is decided (a custom sprite overlay). |
| M08b | [08-playback.md](08-playback.md#m08b--on-device-remux-p1) | On-device FFmpeg remux | P1 | M08a, the R2 prototype | LGPL conditions L1–L5 (§7) |
| M09 | [09-search.md](09-search.md) | Search | **P0** | M01–M07 | |
| M10 | [10-settings.md](10-settings.md) | Settings (P0 minimum), diagnostics, and the in-app license view | **P0**/P1 | M02, M04, M08 | |
| M11 | [11-ios-ui.md](11-ios-ui.md) | iOS UI for the MVP modules | P1 | tvOS M04, M06, and M07 stable | +30–50%, assumption |
| M12 | [12-music-audiobooks.md](12-music-audiobooks.md) | Music, lyrics, and audiobooks | P1 | M08 | |
| M13 | [13-livetv.md](13-livetv.md) | Live TV and recordings | P1 | M08 | |
| M14 | [14-alt-player.md](14-alt-player.md) | VLCKit (or MPV) fallback engine: PGS, ASS, and DTS/TrueHD direct play | P1 | M08 | Infuse parity, LGPL conditions L1–L5 (§7) |
| M15 | [15-extras.md](15-extras.md) | Multiple servers and users, Top Shelf, collections, PiP, and trailers | P1/P2 | M04, M06, M07 | |
| M16 | [16-syncplay.md](16-syncplay.md) | SyncPlay | P2 | M08 | |
| M17 | [17-admin.md](17-admin.md) | Admin: a light tvOS version and a full iOS version | P2 | M01–M04, M10 | |
| M18 | [18-ios-downloads.md](18-ios-downloads.md) | iOS downloads and offline | P2 | M11, M08 | iOS only |

### Parallel work queues (v1.3.3)
The Coder runs several agents at the same time. One agent per queue, its own branch and PR, and two queues do not edit the same module.
- **Immediately:**
  - **Queue A:** get CI green on PRs [#5](https://github.com/kallupx/glassfin/pull/5) (M03), [#7](https://github.com/kallupx/glassfin/pull/7) (M02), and [#9](https://github.com/kallupx/glassfin/pull/9) and merge them. Then M04.
  - **Queue B:** the M05 design system and the ADR M05-1 prototype (depends only on M00).
  - **Queue C:** the ADR M08-2 prototype (the media token and self-signed media), no UI.
- **Once M04 and M05 are merged:** M06 (home) and M07 (libraries and detail) in parallel.
- **Once M07 is merged:** M08a (playback) and M09 (search) in parallel. M10 starts once M08a is merged.
- Shared files (`GlassfinCore` models, design-system components): changes go in their own small PR before the module PR, so that conflicts stay small.

**MVP (P0) is done when:** M00–M10 are accepted (each file's acceptance criteria are checked off, the Tester's report says "acceptable", and Security's review is done) and performance targets P1–P15 have been measured on device.

## 4. Pain points → requirement → acceptance criterion
Source: the Researcher's report, part 2 (Reddit, the Jellyfin forum, Swiftfin #1743) and part 3.
| # | Pain point | Requirement | Acceptance criterion (summarized) | Module / priority |
|---|---|---|---|---|
| K1 | Scrubbing or seeking is missing or broken | PB1 native scrubbing in every PlayMethod, PB2 trickplay | Seeking in direct play ≤ 1.0 s and in transcoding ≤ 3 s. 20 consecutive seeks without a stall. Thumbnail ≤ 150 ms. | M08 P0 |
| K2 | The played state does not update, and the library does not update without a restart | `UserDataStore` as the single source of truth, reporting Start/Progress/Stopped, WebSocket `UserDataChanged`/`LibraryChanged`, and a refresh when returning to the foreground | Home updates ≤ 2 s after playback (P14), a change from another client ≤ 5 s (P15) | M02, M06, M08 P0 |
| K3 | Audio and subtitle selection is hard to find, and switching does not work during playback | PB3 one-press selection in the Info panel, switching on the fly. PB4 default selection from the user's language settings. | An embedded track switches in ≤ 1 s without an interruption, a server-side switch ≤ 4 s, and the position is preserved within ± 2 s | M08 P0 |
| K4 | The next episode does not start automatically | PB7 a countdown from the Outro segment, or 30 s before the end | A 10 s countdown → the next episode with the same track languages. Cancel (fi: "Peru") works. | M08 P0 |
| K5 | Focus jumps in the season and episode view, and focus gets stuck on the description | Focus rules 1–6 (M07), the description is not focusable (M05 HeroHeader), per-row focus memory | Each rule has its own XCUITest. Going back restores the same item. | M05, M07 P0 |
| K6 | Search is buggy (characters disappear, results overlap) | SR1 cancellation of stale searches and a term check, SR2 state in the ViewModel | Responses arriving in reverse order → only the latest is shown. 20 characters typed quickly → all of them are retained. | M09 P0 |
| K7a | The intro skipper does not work | PB6 media segments with a native `contextualActions` button: "Ask" (fi: "Kysy") / "Skip" (fi: "Ohita") / "Do nothing" (fi: "Ei mitään") | The button appears and disappears at the segment boundaries, and auto-skip works | M08 P0 |
| K7b | Live TV: no audio, or it crashes | M13 a live-specific TranscodingProfile and forced audio compatibility | Audio is heard on MP2, AC-3, and AAC test channels, 2 h without a crash | M13 P1 |
| K8 | Unnecessary transcoding (wrong device profile) | A runtime DeviceProfile from the device's and the display's capabilities, plus a diagnostics overlay (`TranscodeReasons`) | Test-matrix files 1–3 DirectPlay, 4–6 DirectStream (video copy) | M08 P0 |
| K9 | Music and audiobook libraries are missing | M12 | Album, lyrics, and the audiobook resume position | M12 P1 |
| K10 | Sign-out between sessions | The token is in the Keychain (S1.1). A network error never signs the user out; only 401 does. | Force-quit, and the server down at launch → home from the cache without signing in | M04 P0 |
| K11 | tvOS 26: subtitles appear as boxes (CJK) | PB5 a custom `SubtitleOverlay` with the system font and a CJK fallback (or native, if it is proven to work) | ja/zh/ko test subtitles render correctly on tvOS 26 and 27 (screenshot) | M08 P0 |
| K12 | (part 3) tvOS has only about 500 KB of persistent storage, and Caches can be purged | Storage budget: Keychain, UserDefaults < 50 KB, Caches purgeable | The app works after the cache has been cleared, UserDefaults < 50 KB tested | M02 P0 |
| K13 | (part 3) Apple TV does not bitstream TrueHD or DTS | PB11 the server transcodes the audio (video copy). M14 decodes to PCM on device. | A TrueHD 7.1 MKV plays as DirectStream within the P6 limits | M08 P0, M14 P1 |

## 5. Feature parity (summary)
| Feature | Android TV / web | Infuse | Us |
|---|---|---|---|
| Quick Connect, sign-in | ✔ | ✘ | **P0** |
| Home, libraries, series, search | ✔ | ✔ | **P0** |
| Media segments (skip/ask) | ✔ (10.10+) | partial | **P0** |
| Trickplay | ✔ | own | **P0** (ADR M08-1) |
| DirectPlay MP4/HEVC/DV/Atmos | ✔ | ✔ | **P0** |
| MKV without server load | – | ✔ | P0 server remux (DirectStream), P1 on-device remux (M08b) |
| PGS/ASS natively, DTS/TrueHD decoding | partial | ✔ | P0 burn-in/transcoding, **P1 M14** |
| Music, lyrics | ✔ | ✔ | P1 |
| Live TV, recordings | ✔ | limited | P1 |
| Top Shelf, multi-user | – | ✔ | P1 |
| SyncPlay | web ✔, Android TV ✘ | ✘ | P2 |
| Admin | web ✔ | ✘ | P2 |
| Downloads | mobile ✔ | ✔ (iOS) | P2 (iOS only) |
| Photos, books | web ✔ | partial | P2 |
| SMB/Plex/other sources | – | ✔ | ✘ out of scope (the Researcher's assumption) |

## 6. Decisions that require user confirmation
1. **Server minimum 10.10 (10.10.7)**, with testing also on 10.11.x and 12.x. Alternative: 10.11+.
2. **tvOS 26+ / iOS 26+**, build with Xcode 27.
3. **The MVP playback path = AVPlayer + the server's DirectStream/Transcode.** On-device remux (M08b) and the VLCKit fallback engine (M14) are P1. The license no longer blocks them (§7 B1 → R9), but M08b still waits for the R2 performance prototype. This means the MVP is not yet at Infuse level for PGS, ASS, DTS, and TrueHD files.
4. **Admin tools in P2** (team decision): tvOS light, iOS full.
5. **The iOS UI is P1**, and it starts once tvOS auth, home, and library are stable. +30–50% is the Researcher's unmeasured estimate.
6. **"Infuse level" = playback quality and smoothness**, not multi-source support (SMB, Plex).
7. On the home view, "Continue watching" (fi: "Jatka katsomista") and "Next Up" (fi: "Seuraavat jaksot") are separate rows (a P1 setting combines them). Libraries are shown as their own tabs (max 5).
8. ~~Public server addresses require HTTPS~~ **AGREED with Security (S4.3).** HTTP is allowed only on the LAN. Noted for the user, because it is a visible limitation.
9. ~~Repo~~ **RESOLVED: public GitHub repo `kallupx/glassfin`** (private on 21.10., made public by the user's decision on 22.10.2026 after the gitleaks audit). It can be moved to an organization later. Standard GitHub runners (including `xcode-27`) are free; up to 5 macOS jobs can run at once.
10. **CI integration-test server – CONFIRMED:** `jellyfin/jellyfin` Docker containers (`10.10.7`, `10.11.11`, and `12.2`) as a GitHub Actions service on a Linux runner, seeded with a small generated or CC0 test library. No macOS minutes, and credentials are generated for every run (M00, v1.3.2). ⚠️ The SDK's Linux build is unverified, and the fallback plan is in M00. **CONFIRMED 21.10.2026.** Tests never use the user's real server or credentials.
11. **The application's license: MPL-2.0** – **CONFIRMED 21.10.2026** (the user decided on 21.10.2026 that the app is free and open source; see §7 R9).
12. ~~The application's name~~ **RESOLVED: Glassfin** (the same name on tvOS and iOS, the user's decision on 21.10.2026). ⚠️ The name-check result is in §7 R10.
13. **Bundle ID: `org.glassfin.app`** (tvOS and iOS shared, universal purchase). Top Shelf extension `org.glassfin.app.topshelf`, App Group `group.org.glassfin.app`, and Keychain access group `$(AppIdentifierPrefix)org.glassfin.app`. **CONFIRMED 21.10.2026.** Reverse DNS requires that the user owns or controls the domain `glassfin.org`, or that their own domain is chosen.
14. ~~Apple Developer account in M00~~ → **required before TestFlight** (see §7 "Required before TestFlight").
15. Crash reporting (MetricKit or something else).

## 7. Blockers, licenses, and what is required before TestFlight
### ~~B1~~ → R9 – Licenses: RESOLVED WITH CONDITIONS (no longer a blocker)
**Change on 21.10.2026:** the user decided that the application is **free and open source**. Therefore B1 has been changed from a blocker into risk R9, which has a proposed resolution. M08b and M14 are no longer blocked because of the license (they are still P1).

**The application's license: MPL-2.0** – **CONFIRMED 21.10.2026**
- The same license as Swiftfin and jellyfin-sdk-swift (verified from GitHub on 21.10.2026). Swiftfin's code may be reused, provided that file-level MPL-2.0 notices are preserved in copied files.
- MPL-2.0 is file-level copyleft. It is compatible with LGPL libraries when they are linked as separate dynamic libraries.

**Rationale** (*not legal advice*):
- The conflict with the App Store terms has historically concerned the **GPL**: VLC was removed from the App Store in 2011. VLC later returned after libVLC was relicensed to LGPL and the iOS app to an MPL/GPL dual license. ⚠️ This is historical background that was not re-verified in this work.
- LGPL-licensed FFmpeg and VLCKit are widely shipped in App Store apps as dynamic frameworks. Verified examples: Swiftly Player and Sotto IPTV publish license pages stating that VLCKit is a dynamic framework and that FFmpeg is built without the `--enable-gpl` option.
- Because our entire source is public and the libraries are linked dynamically, LGPL's relinking and source-code obligations are met: the user can build the app themselves with a replaced library, and the libraries' source code is available.

**Verified license facts** (web check on 21.10.2026):
- **FFmpeg:** LGPL-2.1+, but GPL if the build includes `--enable-gpl` components (ffmpeg.org/legal, which also has a compliance checklist).
- **VLCKit:** LGPL-2.1 (libVLC LGPL-2.1+).
- **mpv:** GPLv2+ by default, and LGPLv2.1+ only with a `-Dgpl=false` build. mpv's Copyright file emphasizes that the flag alone does not create the license; the licenses of the files actually used must be checked.
- **MPVKit:** an LGPL default variant and a separate GPL variant. Maintenance is limited.
- **kingslay/FFmpegKit:** GPL-3.0.

**Mandatory conditions (L1–L5)**, which apply to M00, M08b, M10, and M14:
- **L1 LGPL builds only:** FFmpeg without the `--enable-gpl` and `--enable-nonfree` options, mpv with the `-Dgpl=false` option (from MPVKit, only the LGPL variant, not `MPVKit-GPL`), and VLCKit as an LGPL build without GPL modules. **kingslay/FFmpegKit (GPL-3.0) is forbidden**, as are x264 and other GPL or nonfree components.
- **L2 Dynamic frameworks:** LGPL libraries are embedded as separate dynamic frameworks ("Embed & Sign"). They are not linked statically.
- **L3 CI check (M00):** the build fails if a GPL or nonfree configuration is detected.
- **L4 License files in the repo:** `THIRD_PARTY_LICENSES`, plus a source offer or links to the exactly corresponding source code and build configuration of each binary library (the configure line and a possible `changes.diff`).
- **L5 In-app license view (M10):** lists every third-party component, its license, and a source-code link. The notice required by FFmpeg's checklist: "This software uses libraries from the FFmpeg project under the LGPLv2.1".

**Remaining risk:** small. It materializes if a dependency silently switches to a GPL build, and L3 covers this. The final legal interpretation is the user's responsibility.

### ~~B2 – GitHub repo~~ RESOLVED
The repo is **`kallupx/glassfin`**, public from 22.10.2026 (later, possibly to an organization). **M00 has no blockers**, and §6.10 is confirmed. Source availability (MPL-2.0, LGPL L1–L5) is already satisfied.
- Consequence: in a public repo everything is visible (code, PRs, Actions logs, and artifacts). S5 redaction and the artifact rules are therefore mandatory, and a self-hosted runner is forbidden (00-infra-ci.md).

### Required before TestFlight (not an M00 blocker): a paid Apple Developer Program
**Not required to start development** (verified from Apple's documentation on 21.10.2026):
- **CI simulator builds and tests:** no Apple account is required (`xcodebuild … CODE_SIGNING_ALLOWED=NO`, simulator).
- **A free Apple ID (Personal Team) for one's own device:** max 3 devices and 3 apps per device. Provisioning profiles, App IDs, and devices expire **every 7 days**, and at most 10 App IDs can be registered per 7 days (Apple "Developer account overview").

**Apple's "Supported capabilities (tvOS)" table (free = the "Apple Developer" column):**
- Also allowed with a free account: **App Groups, Keychain sharing, Background modes, and Data protection**. Therefore a Top Shelf extension with an App Group or a shared Keychain works in development even with a free account. ⚠️ Note: the parent's assumption "App Groups require a paid account" does not hold according to Apple's table. The Personal Team limit of 10 App IDs / 7 days can still get in the way, because each extension is its own App ID.
- **Only with a paid account:** Push notifications, iCloud (CloudKit, KVS), Associated domains, Sign in with Apple, Siri, Group Activities (SharePlay), Game Center, In-App Purchase, **User management** (tvOS system profiles, M15 P2), and App Attest. The multicast entitlement (UC-A6 LAN discovery) is requested separately from Apple ⚠️ (presumably requires membership).

**TestFlight automation:** the App Store Connect API key (`ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_P8`) is stored **only as GitHub Actions secrets** (preferably a `production` environment with manual approval). **The key is never put in chat, the repo, issues, or logs.** The user adds it themselves in the GitHub UI. See 00-infra-ci.md `release.yml`.

**Paid membership ($99/year) is required before:** TestFlight, App Store release, provisioning profiles longer than 7 days, device testing on more than three devices, and the capabilities listed above that are available only with a paid account. Timing: at the latest before the MVP beta phase.

## 8. Risks
| # | Risk | Impact | Mitigation |
|---|---|---|---|
| R1 | ~~Trickplay in the native transport bar~~ **Decided (ADR M08-1):** Jellyfin lacks the I-frame variant, so a custom sprite overlay is built. Remaining implementation risk: tracking the native scrub state, or a custom scrub bar ⚠️ | K1 quality and a native feel | A prototype in M08, a UI test, and the Tester's assessment |
| R2 | On-device remux performance on 50–80 GB files is verified only as a claim by GMPlayer | M08b | A prototype and metrics before M08b |
| R3 | AVPlayer does not use the app's URLSession delegate, so media from a self-signed server can fail, and the token must be passed to media without putting it in the URL ⚠️ | S4.4, S1.5 | **ADR M08-2**: one prototype (`AVAssetResourceLoaderDelegate` → the undocumented header option → `ApiKey` fallback). M08b also solves it. |
| R4 | SDK 3.x (12.x) vs server 10.10 | Compatibility | Integration tests against three server versions |
| R5 | `NSAllowsLocalNetworking` does not allow HTTP to a public domain | Some users | §6.8, a clear error message |
| R6 | MPVKit maintenance | M14 | VLCKit first |
| R7 | The Tester cannot run device tests | Quality | CI artifacts. Device measurements are done by the Coder or the user before release (with a free Apple ID, max 3 devices, 7-day provisioning). |
| R8 | Multicast entitlement for LAN discovery ⚠️ | UC-A6 | P1, requested from Apple if needed |
| R9 | Licenses (former blocker B1) | M08b, M14 | An MPL-2.0 app and conditions L1–L5, see §7 |
| R10 | **Name conflict "Glassfin"** (checked 21.10.2026). No iOS or tvOS app named Glassfin was found in the App Store (iTunes Search API). On GitHub: **KBH-Reeper/GlassFin**, about 250 stars, active 9/2026, is a **Jellyfin-web CSS theme** (Liquid Glass style), so it is in the same ecosystem. In addition, pkyanam/jellyflex describes itself as "Glassfin: a Plex-inspired Jellyfin web frontend" (3 stars), and there are a few empty `glassfin` repos. | Confusion in the Jellyfin community ("GlassFin theme" vs "Glassfin app"), search visibility, and a possible request to rename | The user decides whether to keep the name. Options: a distinctive spelling or a subtitle (for example "Glassfin for Jellyfin"), contacting the theme's author. A trademark search (USPTO/EUIPO) was not done ⚠️. Note: use of the Jellyfin name/logo in a third-party app may be subject to guidelines that were not checked ⚠️. |
| R11 | Liquid Glass details on tvOS are unverified (glass on the card style, AVPlayerViewController's glass, rendering on A8/A10X devices) ⚠️ | The look of M05–M08 | The ADR M05-1 prototype before M06 |
| ~~R13~~ | ~~Actions minutes in a private repo~~ **CLOSED 22.10.2026: the repo is public, and standard runners are free.** Remaining: macOS concurrency of 5 jobs (queues), and the `xcode-27` image is still in preview | CI queues while several agents are running | 00-infra-ci.md "Public repo": concurrency cancellation, full-ui only once ready for review. Fallback: `macos-26` + Xcode 26 |
| R12 | Glass GPU load on Apple TV 4K (2nd generation) (A12, the oldest glass device) | Hitches | Budget G-1…G-5 (M05) |

## 9. Conflicts and ambiguities
1. **"Support everything Android/web/desktop support" vs the MVP scope:** resolved by phasing (§5). Some web features are not meaningful on tvOS (books, comics, metadata editing, extensive admin), so they are P2 or iOS-only. The user must confirm that this interpretation is acceptable.
2. **"At least as good as Infuse" vs the AVPlayer MVP:** Infuse plays PGS, ASS, and DTS/TrueHD without a server. The MVP needs server transcoding or burn-in for these. Full parity requires M14 (P1; the license no longer prevents it, see §7 R9). In addition, Infuse's multi-source support is scoped out (assumption).
3. **"Most efficient" vs on-device FFmpeg remux:** on-device remux increases memory and CPU use on Apple TV but reduces server load. The spec prioritizes smoothness on the device (the P12 limit is 500 MB).
4. **Feature parity vs the tvOS platform:** downloads are impossible on tvOS (500 KB) and belong only to iOS. This departs from the goal of "the same features on iOS and tvOS".
5. **The Researcher's version proposals are outdated:** "tvOS 17 or 18" → the current version is tvOS 27. Server 10.10 → the current version is 12.2. In addition, 12.0's breaking changes (legacy auth, `GET /QuickConnect/Initiate`, `/emby` routes) have been taken into account.
6. ~~**Security's Keychain class**~~ **RESOLVED (21.10.2026):** the class is `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, confirmed by Security. 03-security.md S1.1 is authoritative.
7. **The Researcher's report differs slightly between two versions:** part 4 sent directly to Spec cites DTS/TrueHD as the reason for the VLCKit fallback path, and the group version does not. The spec follows the broader version.

## 10. Gaps in this spec
- The group-chat transcript was not obtained directly (it was not saved). Researcher parts 1–3 were read verbatim from the Researcher's own transcript.
- The contents of Swiftfin PR #1230 (admin) and Swiftfin's DeviceProfile code were not reviewed. They are references for the Coder.
- The exact form of the WebSocket path, the server-side expiry of the Quick Connect code, and `NSAllowsLocalNetworking` behavior for AVPlayer on tvOS 26 are unverified (marked ⚠️ in the modules).
