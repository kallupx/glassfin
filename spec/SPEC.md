# Glassfin – a Jellyfin client for tvOS (and later iOS) – Specification v1.3.3

**Author:** Specification · **Date:** 22 Oct 2026 · **Version:** v1.3.3 · **Status:** DRAFT. Security has accepted 03-security.md. Waiting for the user's confirmations (§6). The changelog is below.
**Sources:** the Researcher's report v1 parts 1–5, the user's goals in the group, requests from Security and the Tester, team decisions (iOS, admin, security), and Specification's own web checks on 21 Oct 2026 (Jellyfin OpenAPI 12.2.0, jellyfin-sdk-swift, Apple and GitHub release notes, licenses). Downloaded OpenAPI copy: `/workspace/jellyfin-tvos/research/openapi.json`.

> Markers: **P0** = MVP, **P1** = the next release (parity and iOS), **P2** = later. **DEFAULT – needs the user's confirmation** = the default Specification chose. A warning mark in a module means unverified information or a risk. **[AGREED]** = agreed with Security.

## Changelog
- **v1.3.3 (22 Oct 2026, public repository)**
  - `kallupx/glassfin` is public. Standard GitHub-hosted runner minutes are free.
  - **M00, public-repo CI** (00-infra-ci.md, section "Public repo (v1.3.3)"):
    - Every workflow (`ci.yml`, `integration.yml`, `release.yml`) sets `concurrency` with `cancel-in-progress: true`.
    - A draft pull request runs `lint`, `test-tvos`, and `test-ios` (when the macOS path filter matches). Push to `main` does not run `test-tvos` or `test-ios`.
    - `full-ui` runs when a pull request becomes ready for review (`pull_request` types include `ready_for_review`) and on push to `main`. The `full-ci` label still runs `full-ui` on a draft. `full-ui` is not path-filtered.
    - `test-tvos` and `test-ios` share the macOS path gate. A tvOS-only change runs both.
    - Every uploaded artifact uses `retention-days: 14`. xcresult bundles are not uploaded.
    - Self-hosted runners and `-xlarge` labels stay forbidden. `scripts/ci-grep.sh` rejects both. `xcode-27` remains the standard hosted label.
  - The specification documents in `spec/` are English.
- **v1.2 (21 Oct 2026, Tester questions and Security clarifications)**
  - **The package name is `GlassfinCore` everywhere** (the old working name was removed from every file, grep: 0 hits).
  - **M00, CI artifacts:** JUnit XML, PNG screenshots, `xccov` coverage JSON, and logs of failed tests in addition to `.xcresult`, so they can be read on Linux. S5 redaction and scanning also cover artifacts (S5.5).
  - **M00, integration test server (PROPOSAL, §6.10):** `jellyfin/jellyfin` containers `10.10.7`, `10.11.11`, and `12.2` as a Linux service, a generated and seeded test library, no macOS minutes. Credentials only from GitHub Secrets. The SDK's Linux build is unverified, and there is a fallback plan.
  - **M01, tick edge cases:** a negative position → 0 and one warning. `RunTimeTicks` ≤ 0 → duration unknown, and no progress bar is shown. A negative value is never sent to the server.
  - **M01, WebSocket reconnect:** full jitter `random(0, min(30 s, 1 s · 2^n))`, and the counter resets only after 10 s of a stable connection. The time source is an injected `Clock`, and the foreground reconnects immediately.
  - **S1.6/M01, header encoding:**
    - Values are URL-encoded and quoted, and CR/LF or any other control character is rejected.
    - Verified against the server's `GetParts` (`WebUtility.UrlDecode`) and jellyfin-sdk-typescript (`encodeURIComponent`).
    - jellyfin-sdk-swift 3.3.0 does not encode, so the header is built by us.
  - **S2.2/M01/M02:** only HTTP 401 signs the user out. Network, TLS, timeout, and 5xx errors never do.
  - **S4.6 [AGREED]:**
    - A cross-host redirect and an HTTPS→HTTP redirect of an `ApiKey` URL are rejected (not merely stripping the parameter). Same-host HTTPS works.
    - The rule covers only the app's own requests, so AVPlayer is always given the resolved final URL.
    - `ApiKey` in HLS transcode segments is an accepted risk.
  - **ADR M08-2:** a resource loader in HLS in practice intercepts only playlists and keys (forum reports). The prototype tests direct play, the server's HLS (segments likely need `ApiKey`), and our own loopback remux (no token) separately.
- **v1.1 (21 Oct 2026)**
  - **Security accepted 03-security.md.** Marked as agreed:
    - S1.1 `AfterFirstUnlockThisDeviceOnly` (tvOS has no lock screen, and a stricter class would break Top Shelf)
    - S3.3 Quick Connect polling at 5 s and a timeout of 5 min
    - S4.3 public addresses require HTTPS
    - S4.4 CA certificates are not pinned
  - **S1.4:** a shared Keychain access group only for the app and Top Shelf targets (CI check).
  - **S1.5/S5.1 conflict resolved:** the media token is passed primarily as a header (`AVAssetResourceLoaderDelegate` or the undocumented `AVURLAssetHTTPHeaderFieldsKey`). The fallback is `ApiKey=` only on media URLs, and then S5 redaction is mandatory. New ADR M08-2: one prototype settles both this and R3 (media from self-signed servers).
  - **Jellyfin 12.0 removed `api_key`.** The only query parameter is `ApiKey` (Jellyfin calls it a last resort, because it leaks into proxy logs). Wording corrected in M01, M03, and M08.
  - **New requirements:**
    - S4.6: the Authorization header is not forwarded on a cross-host redirect, and an HTTPS → HTTP redirect is rejected. Added to M01's acceptance criteria.
    - S4.7: UDP 7359 discovery responses are untrusted, the address is always shown, and the user chooses. Added to M04.
  - **Quick Connect:** the start is **`POST /QuickConnect/Initiate`** (12.0 removed GET). Added to M04's acceptance criteria.
  - **ADR M08-1 decided (the Researcher confirmed):** `AVPlayerViewController` shows scrub thumbnails only for an `#EXT-X-I-FRAME-STREAM-INF` variant, which Jellyfin does not produce (trickplay is JPEG sprites). So we build our own scrubbing overlay with Jellyfin's sprites, and no server plugin is required. A third-party native-trickplay plugin (10.11 only) is an optional alternative. A trickplay glass overlay was added to M05. R1 is closed by the decision; an implementation risk remains (tracking the native scrub state, or our own scrub bar).
- **v1.0+ (21 Oct 2026, the same day):**
  - open source and the MPL-2.0 proposal (B1 → R9, LGPL conditions L1–L5)
  - the name Glassfin (name conflict R10)
  - Liquid Glass design system (M05)
  - an Apple Developer account is not an M00 blocker
  - repository `kallupx/glassfin` and CI cost limits (R13)
- **v1.0 (21 Oct 2026):** first version.

---

## 1. Goal and principles
Build **Glassfin**: the best, fastest, easiest, and cleanest Jellyfin client for Apple TV. Later, an iOS version with **the same name (Glassfin)** and the same features.
1. **Reliability before features.** The Researcher's conclusion: the biggest competitive advantage comes from playback reliability and from polishing basic navigation. Every known pain point is turned into a requirement and an acceptance criterion (§4).
2. **Liquid Glass look (the user's decision):** Apple's tvOS/iOS 26 design language. Glass is in navigation and controls, and content (posters, backgrounds, video) stays opaque. System components first (`TabView`, `.buttonStyle(.glass)`, `GlassEffectContainer`, the native transport bar, `.card`). See 05-design-system.md.
3. **One shared core:** the Swift package `GlassfinCore` contains the API, models, view models and state, playback logic, and auth and networking. Only the UI is platform-specific. The iOS target builds from day 1.
4. **Testability:** protocol-based services, a mockable API client, and macOS CI (the Tester has only Linux).
5. **Security by default:** the token in the Keychain, no `NSAllowsArbitraryLoads`, and no tokens in logs.

## 2. Platforms and versions
| Item | Decision | Reason |
|---|---|---|
| tvOS minimum | **tvOS 26** – DEFAULT, needs the user's confirmation | Verified: the current public version is tvOS 27.0 (14 Sep 2026), and 27.2 RC was released on 19 Oct 2026. The proposed minimum is current minus one. The Researcher's options "17 or 18" are outdated (Apple moved to year numbering, 18 → 26). |
| iOS minimum | **iOS 26** – DEFAULT | The same core and the same APIs |
| Build tools | Xcode 27, Swift 6 | GitHub `xcode-27` runner generally available from 15 Oct 2026 |
| Jellyfin server minimum | **10.10** (in practice 10.10.7) – DEFAULT, needs the user's confirmation | Media segments and trickplay require 10.10+, and Android TV requires the same. **New observation:** the current server is **Jellyfin 12.2** (5 Oct 2026; 12.0 was released 8 Sep 2026), and the Researcher's report did not mention the 12.x line. 12.0 removed legacy auth and the `GET /QuickConnect/Initiate` route. Test on 10.10.7, 10.11.x, and 12.x. Alternative: a minimum of 10.11, which shrinks the test matrix. |
| SDK | jellyfin-sdk-swift ≥ 3.3.0 (MPL-2.0, generated for 12.1) | Compatibility with 10.10 is unverified, and it is confirmed with integration tests (M00/M01). |

## 3. Modules in implementation order (for the Coder)
| # | File | Module | Priority | Dependencies | Notes |
|---|---|---|---|---|---|
| M00 | [00-infra-ci.md](00-infra-ci.md) | Repository, project, macOS CI (tvOS and iOS), lint, and artifacts for the Tester | **P0** | – | First. Repository `kallupx/glassfin` (public as of v1.3.3). No blockers. |
| M01 | [01-core.md](01-core.md) | GlassfinCore: network, auth header, API layer (SDK), domain models, endpoints, and WebSocket | **P0** | M00 | Shared by tvOS and iOS |
| M02 | [02-state-errors-performance.md](02-state-errors-performance.md) | State (`@Observable`), error model, cache (tvOS 500 KB limit), performance targets P1–P15 | **P0** | M01 | Cross-cutting |
| M03 | [03-security.md](03-security.md) | Security requirements S1–S9 | **P0** | M01 | Security reviews |
| M04 | [04-auth.md](04-auth.md) | Adding a server, Quick Connect, password, sign-out, and the certificate flow | **P0** | M01–M03, M05 | |
| M05 | [05-design-system.md](05-design-system.md) | Liquid Glass design system, components, focus rules, accessibility, glass performance budget, and screen hierarchy | **P0** | M00 | In parallel with M01–M04. ADR M05-1 (the open items) before M06 |
| M06 | [06-home.md](06-home.md) | Home: continue watching, next up, and recently added | **P0** | M01–M05 | |
| M07 | [07-library-detail.md](07-library-detail.md) | Libraries, detail, and series, season, and episode views | **P0** | M01–M05 | |
| M08 | [08-playback.md](08-playback.md) | **M08a** AVPlayer + the server's DirectStream/Transcode, DeviceProfile, reporting, tracks, segments, trickplay, and next-up | **P0** | M01–M07 | ADR M08-2 (media token and self-signed media) as a prototype first. ADR M08-1 is decided (our own sprite overlay). |
| M08b | [08-playback.md](08-playback.md#m08b--on-device-remux-p1) | On-device FFmpeg remux | P1 | M08a, R2 prototype | LGPL conditions L1–L5 (§7) |
| M09 | [09-search.md](09-search.md) | Search | **P0** | M01–M07 | |
| M10 | [10-settings.md](10-settings.md) | Settings (P0 minimum), diagnostics, and the in-app license view | **P0**/P1 | M02, M04, M08 | |
| M11 | [11-ios-ui.md](11-ios-ui.md) | iOS UI for the MVP modules | P1 | tvOS M04, M06, and M07 stable | +30–50%, the default estimate |
| M12 | [12-music-audiobooks.md](12-music-audiobooks.md) | Music, lyrics, and audiobooks | P1 | M08 | |
| M13 | [13-livetv.md](13-livetv.md) | Live TV and recordings | P1 | M08 | |
| M14 | [14-alt-player.md](14-alt-player.md) | VLCKit (or MPV) fallback engine: PGS, ASS, and DTS/TrueHD direct play | P1 | M08 | Infuse parity, LGPL conditions L1–L5 (§7) |
| M15 | [15-extras.md](15-extras.md) | Several servers and users, Top Shelf, collections, PiP, and trailers | P1/P2 | M04, M06, M07 | |
| M16 | [16-syncplay.md](16-syncplay.md) | SyncPlay | P2 | M08 | |
| M17 | [17-admin.md](17-admin.md) | Admin: a light tvOS version and a full iOS version | P2 | M01–M04, M10 | |
| M18 | [18-ios-downloads.md](18-ios-downloads.md) | iOS downloads and offline | P2 | M11, M08 | iOS only |

**The MVP (P0) is done when:** M00–M10 are accepted (each file's acceptance criteria checked, the Tester's report is "acceptable", and Security's review is done) and performance targets P1–P15 have been measured on device.

## 4. Pain points → requirement → acceptance criterion
Source: the Researcher's report, part 2 (Reddit, the Jellyfin forum, Swiftfin #1743) and part 3.
| # | Pain point | Requirement | Acceptance criterion (short) | Module / priority |
|---|---|---|---|---|
| K1 | Scrubbing or seeking is missing or broken | PB1 native scrubbing in every PlayMethod, PB2 trickplay | Seek in direct play ≤ 1.0 s and in transcode ≤ 3 s. 20 seeks in a row without a stall. Thumbnail ≤ 150 ms. | M08 P0 |
| K2 | Played state does not update, the library does not update without a restart | `UserDataStore` as the single source of truth, reporting Start/Progress/Stopped, WebSocket `UserDataChanged` / `LibraryChanged`, and a refresh when returning to the foreground | Home updates within 2 s after playback (P14), another client's change within 5 s (P15) | M02, M06, M08 P0 |
| K3 | Audio and subtitle selection is hard to find, and switching during playback fails | PB3 one-press selection in the Info panel, switch on the fly. PB4 default selection from the user's language settings. | An embedded track changes within 1 s without a gap, a server switch within 4 s, and the position stays within ± 2 s | M08 P0 |
| K4 | The next episode does not start automatically | PB7 a countdown from the Outro segment or 30 s before the end | A 10 s countdown → the next episode with the same track languages. Cancel works. | M08 P0 |
| K5 | Season and episode focus jumps, and focus gets stuck in the description | Focus rules 1–6 (M07), the description is not focusable (M05 HeroHeader), per-row focus memory | An XCUITest for each rule. Back restores the same item. | M05, M07 P0 |
| K6 | Search is buggy (characters disappear, results overlap) | SR1 cancel stale searches and check the term, SR2 state in the view model | Responses that arrive out of order → only the latest is shown. 20 characters typed quickly → all of them are kept. | M09 P0 |
| K7a | Intro skipper does not work | PB6 media segments with a native `contextualActions` button: Ask / Skip / Do nothing | The button appears and disappears at the segment boundaries, and auto-skip works | M08 P0 |
| K7b | Live TV: no audio, or it crashes | M13 a live-specific TranscodingProfile and forced audio compatibility | Audio is heard on MP2, AC-3, and AAC test channels, 2 h without a crash | M13 P1 |
| K8 | Unnecessary transcoding (wrong device profile) | A runtime DeviceProfile from the device and display capabilities, plus a diagnostics overlay (`TranscodeReasons`) | Test-matrix files 1–3 DirectPlay, 4–6 DirectStream (video copy) | M08 P0 |
| K9 | Music and audiobook libraries are missing | M12 | Album, lyrics, and the audiobook resume point | M12 P1 |
| K10 | Signed out between sessions | Token in the Keychain (S1.1). A network error never signs the user out; only 401 does. | Force-quit, and the server down at launch → home from cache without signing in | M04 P0 |
| K11 | tvOS 26: subtitles render as boxes (CJK) | PB5 a custom `SubtitleOverlay` with the system font and a CJK fallback (or native, if it is shown to work) | ja/zh/ko test subtitles render correctly on tvOS 26 and 27 (screenshot) | M08 P0 |
| K12 | (part 3) tvOS has only about 500 KB of persistent storage, and Caches can be purged | Storage budget: Keychain, UserDefaults < 50 KB, Caches purgeable | The app works after the cache is purged, UserDefaults < 50 KB tested | M02 P0 |
| K13 | (part 3) Apple TV does not bitstream TrueHD or DTS | PB11 the server transcodes audio (video copy). M14 decodes to PCM on device. | A TrueHD 7.1 MKV plays as DirectStream within P6 | M08 P0, M14 P1 |

## 5. Feature parity (summary)
| Feature | Android TV / web | Infuse | Us |
|---|---|---|---|
| Quick Connect, sign-in | yes | no | **P0** |
| Home, libraries, series, search | yes | yes | **P0** |
| Media segments (skip/ask) | yes (10.10+) | partial | **P0** |
| Trickplay | yes | its own | **P0** (ADR M08-1) |
| DirectPlay MP4/HEVC/DV/Atmos | yes | yes | **P0** |
| MKV without server load | – | yes | P0 server remux (DirectStream), P1 on-device remux (M08b) |
| PGS/ASS natively, DTS/TrueHD decode | partial | yes | P0 burn-in/transcode, **P1 M14** |
| Music, lyrics | yes | yes | P1 |
| Live TV, recordings | yes | limited | P1 |
| Top Shelf, multi-user | – | yes | P1 |
| SyncPlay | web yes, Android TV no | no | P2 |
| Admin | web yes | no | P2 |
| Downloads | mobile yes | yes (iOS) | P2 (iOS only) |
| Photos, books | web yes | partial | P2 |
| SMB/Plex/other sources | – | yes | out of scope (the Researcher's assumption) |

## 6. Decisions that need the user's confirmation
1. **Server minimum 10.10 (10.10.7)**, also tested on 10.11.x and 12.x. Alternative: 10.11+.
2. **tvOS 26+ / iOS 26+**, built with Xcode 27.
3. **The MVP playback path = AVPlayer + the server's DirectStream/Transcode.** On-device remux (M08b) and the VLCKit fallback engine (M14) are P1. The license no longer blocks them (§7 B1 → R9), but M08b still waits for the performance prototype R2. This means the MVP is not yet at Infuse level for PGS, ASS, DTS, and TrueHD files.
4. **Admin tools in P2** (team decision): tvOS light, iOS full.
5. **The iOS UI is P1**, and it starts when tvOS auth, home, and library are stable. +30–50% is the Researcher's unmeasured estimate.
6. **"Infuse level" = playback quality and smoothness**, not multi-source support (SMB, Plex).
7. On home, "Continue watching" and "Next episodes" are separate rows (a P1 setting merges them). Libraries are shown as their own tabs (max 5).
8. ~~Public server addresses require HTTPS~~ **AGREED with Security (S4.3).** HTTP is allowed only on the LAN. Noted for the user, because it is a visible limitation.
9. ~~Repository~~ **RESOLVED: GitHub repository `kallupx/glassfin`** (the user's decision 21 Oct 2026). It can move to an organization later. The original plan was to make it public at release. **As of 22 Oct 2026 it is public**, and the v1.3.3 CI rules apply (00-infra-ci.md). While it was private, macOS minutes were consumed at about 10x, so a Free account's budget was about 200 macOS minutes per month.
10. **CI integration test server – PROPOSAL (v1.2) – needs the user's confirmation:** `jellyfin/jellyfin` Docker containers (`10.10.7`, `10.11.11`, and `12.2`) as a GitHub Actions service on a Linux runner, seeded with a small generated or CC0 test library. No macOS minutes, and credentials come only from Secrets (M00). The SDK's Linux build is unverified, and the fallback is in M00. The workflow that implements this is `integration.yml` (`workflow_dispatch` only).
11. **Application license: MPL-2.0** – PROPOSAL – needs the user's confirmation (the user decided on 21 Oct 2026 that the app is free and open source; see §7 R9).
12. ~~Application name~~ **RESOLVED: Glassfin** (the same name on tvOS and iOS, the user's decision 21 Oct 2026). The name-check result is in §7 R10.
13. **Bundle ID: `org.glassfin.app`** (shared by tvOS and iOS, universal purchase). Top Shelf extension `org.glassfin.app.topshelf`, App Group `group.org.glassfin.app`, and Keychain access group `$(AppIdentifierPrefix)org.glassfin.app`. **PROPOSAL / placeholder – needs the user's confirmation.** Reverse DNS requires that the user owns or controls the domain `glassfin.org`, or that another domain is chosen.
14. ~~Apple Developer account in M00~~ → **required before TestFlight** (see §7 "Required before TestFlight").
15. Crash reporting (MetricKit or something else).

## 7. Blockers, licenses, and what is required before TestFlight
### ~~B1~~ → R9 – Licenses: RESOLVED WITH A PROPOSAL (no longer a blocker)
**Change 21 Oct 2026:** the user decided that the application is **free and open source**. B1 was therefore changed from a blocker to risk R9, which has a proposed resolution. M08b and M14 are no longer blocked by the license (they are still P1).

**Application license: MPL-2.0** – **PROPOSAL – needs the user's confirmation**
- The same license as Swiftfin and jellyfin-sdk-swift (verified on GitHub 21 Oct 2026). Swiftfin code can be reused as long as copied files keep their file-level MPL-2.0 notices.
- MPL-2.0 is file-level copyleft. It is compatible with LGPL libraries when they are linked as separate dynamic libraries.

**Reasoning** (*not legal advice*):
- The App Store terms conflict has historically concerned **GPL**: VLC was removed from the App Store in 2011. VLC later returned after libVLC was relicensed to LGPL and the iOS app to an MPL/GPL dual license. This is historical background that was not re-checked in this work.
- LGPL-licensed FFmpeg and VLCKit ship widely in App Store apps as dynamic frameworks. Verified examples: Swiftly Player and Sotto IPTV publish license pages stating that VLCKit is a dynamic framework and that FFmpeg is built without `--enable-gpl`.
- Because our source is public and the libraries are linked dynamically, LGPL's relink and source obligations are met: a user can build the app with a replaced library, and the libraries' source is available.

**Verified license facts** (web check 21 Oct 2026):
- **FFmpeg:** LGPL-2.1+, but GPL if the build includes `--enable-gpl` parts (ffmpeg.org/legal, which also has a compliance checklist).
- **VLCKit:** LGPL-2.1 (libVLC LGPL-2.1+).
- **mpv:** GPLv2+ by default, and LGPLv2.1+ only with a `-Dgpl=false` build. mpv's Copyright file stresses that the flag alone does not create the license; the licenses of the files actually used must be checked.
- **MPVKit:** an LGPL default variant and a separate GPL variant. Maintenance is light.
- **kingslay/FFmpegKit:** GPL-3.0.

**Mandatory conditions (L1–L5)**, which apply to M00, M08b, M10, and M14:
- **L1 LGPL builds only:** FFmpeg without `--enable-gpl` and `--enable-nonfree`, mpv with `-Dgpl=false` (from MPVKit only the LGPL variant, not `MPVKit-GPL`), and VLCKit as an LGPL build without GPL modules. **kingslay/FFmpegKit (GPL-3.0) is forbidden**, as are x264 and other GPL or nonfree components.
- **L2 Dynamic frameworks:** LGPL libraries are embedded as separate dynamic frameworks ("Embed & Sign"). They are not linked statically.
- **L3 CI check (M00):** the build fails if a GPL or nonfree configuration is detected.
- **L4 License files in the repository:** `THIRD_PARTY_LICENSES` plus a source offer or links to the exact matching source and build configuration of each binary library (configure line and any `changes.diff`).
- **L5 In-app license view (M10):** lists every third-party component, its license, and a source link. The FFmpeg checklist notice: "This software uses libraries from the FFmpeg project under the LGPLv2.1".

**Remaining risk:** small. It materializes if a dependency silently switches to a GPL build, and L3 covers that. The final legal interpretation is the user's responsibility.

### ~~B2 – GitHub repository~~ RESOLVED
The repository is **`kallupx/glassfin`**. It was private, it may later move to an organization, and it was planned to become public at release. **It was made public on 22 Oct 2026.** **M00 has no remaining blockers.** The only open item is the choice of integration test server (§6.10), and that does not block starting M00. The implemented workflow is `integration.yml`.
- Consequence while it was private: macOS runners consumed free minutes at about 10x. The cost limits and savings are in 00-infra-ci.md (R13). On the public repository those minute limits do not apply to standard runners. Self-hosted runners and larger runners stay forbidden.

### Required before TestFlight (not an M00 blocker): a paid Apple Developer Program membership
**Not required to start development** (verified from Apple's documentation 21 Oct 2026):
- **CI simulator builds and tests:** no Apple account is required (`xcodebuild … CODE_SIGNING_ALLOWED=NO`, simulator).
- **A free Apple ID (Personal Team) for a personal device:** max 3 devices and 3 apps per device. Provisioning profiles, App IDs, and devices expire **every 7 days**, and at most 10 App IDs can be registered per 7 days (Apple "Developer account overview").

**Apple's "Supported capabilities (tvOS)" table (free = the "Apple Developer" column):**
- Also allowed on a free account: **App Groups, Keychain sharing, Background modes, and Data protection**. So a Top Shelf extension with an App Group or a shared Keychain works in development on a free account too. The parent's assumption "App Groups require a paid account" does not match Apple's table. The Personal Team limit of 10 App IDs / 7 days can still get in the way, because each extension is its own App ID.
- **Paid account only:** Push notifications, iCloud (CloudKit, KVS), Associated domains, Sign in with Apple, Siri, Group Activities (SharePlay), Game Center, In-App Purchase, **User management** (tvOS system profiles, M15 P2), and App Attest. The multicast entitlement (UC-A6 LAN discovery) is requested separately from Apple (presumably requires membership).

**TestFlight automation:** the App Store Connect API key (`ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_P8`) is stored **only as GitHub Actions secrets** (preferably a `production` environment with manual approval). **The key is never put in chat, the repository, issues, or logs.** The user adds it in the GitHub UI. See 00-infra-ci.md `release.yml`.

**A paid membership ($99/year) is required before:** TestFlight, App Store release, provisioning profiles longer than 7 days, device testing on more than three devices, and the paid-only capabilities listed above. Timing: at the latest before the MVP beta.

## 8. Risks
| # | Risk | Impact | Mitigation |
|---|---|---|---|
| R1 | ~~Trickplay in the native transport bar~~ **Decided (ADR M08-1):** Jellyfin has no I-frame variant, so we build our own sprite overlay. Remaining implementation risk: tracking the native scrub state, or our own scrub bar | Quality of K1 and the native feel | A prototype in M08, a UI test, and the Tester's assessment |
| R2 | On-device remux performance on 50–80 GB files is confirmed only by GMPlayer's claim | M08b | A prototype and metrics before M08b |
| R3 | AVPlayer does not use the app's URLSession delegate, so media from a self-signed server can fail, and the token has to be passed to media without putting it in the URL | S4.4, S1.5 | **ADR M08-2**: one prototype (`AVAssetResourceLoaderDelegate` → undocumented header option → `ApiKey` fallback). M08b also solves this. |
| R4 | SDK 3.x (12.x) vs server 10.10 | Compatibility | Integration tests on three server versions |
| R5 | `NSAllowsLocalNetworking` does not allow HTTP to a public domain | Some users | §6.8, a clear error message |
| R6 | MPVKit maintenance | M14 | VLCKit first |
| R7 | The Tester cannot run device tests | Quality | CI artifacts. Device measurements are done by the Coder or the user before release (a free Apple ID: max 3 devices, 7-day provisioning). |
| R8 | Multicast entitlement for LAN discovery | UC-A6 | P1, request it from Apple if needed |
| R9 | Licenses (former blocker B1) | M08b, M14 | An MPL-2.0 app and conditions L1–L5, see §7 |
| R10 | **Name conflict "Glassfin"** (checked 21 Oct 2026). The App Store had no iOS or tvOS app named Glassfin (iTunes Search API). On GitHub: **KBH-Reeper/GlassFin**, about 250 stars, active as of Sep 2026, is a **Jellyfin web CSS theme** (Liquid Glass style), so it is in the same ecosystem. Also pkyanam/jellyflex describes itself as "Glassfin: a Plex-inspired Jellyfin web frontend" (3 stars), and a few empty `glassfin` repositories. | Confusion in the Jellyfin community ("GlassFin theme" vs "Glassfin app"), search visibility, and a possible request to rename | The user decides whether to keep the name. Options: a distinctive spelling or a subtitle (for example "Glassfin for Jellyfin"), contact the theme author. A trademark search (USPTO/EUIPO) was not done. Jellyfin's name/logo use in a third-party app may have guidelines that were not checked. |
| R11 | Liquid Glass details on tvOS are unverified (card-style glass, AVPlayerViewController glass, rendering on A8/A10X) | Look of M05–M08 | ADR M05-1 prototype before M06 |
| R13 | GitHub Actions minutes on a private repository: about 200 macOS min/month on a Free account (macOS about 10x, verified from GitHub Docs) | CI stops when the quota is exhausted | M00 savings 1–9. Escalation: a self-hosted Mac, GitHub Pro, or making the repository public earlier. **The repository is public as of v1.3.3, so this budget no longer binds standard runners.** Self-hosted and `-xlarge` stay forbidden. |
| R12 | Glass GPU load on Apple TV 4K 2nd generation (A12, the oldest glass device) | Hitches | Budget G-1…G-5 (M05) |

## 9. Conflicts and ambiguities
1. **"Support everything Android/web/desktop support" vs the MVP scope:** resolved by phasing (§5). Some web features are not meaningful on tvOS (books, comics, metadata editing, a broad admin), so they are P2 or iOS-only. The user should confirm that this reading is acceptable.
2. **"At least as good as Infuse" vs the AVPlayer MVP:** Infuse plays PGS, ASS, and DTS/TrueHD without a server. The MVP needs the server to transcode or burn those in. Full parity needs M14 (P1; the license no longer blocks it, see §7 R9). Infuse's multi-source support is also out of scope (the assumption).
3. **"The fastest" vs FFmpeg remux on device:** on-device remux increases memory and CPU use on Apple TV but reduces server load. The spec prioritizes smoothness on the device (P12 limit 500 MB).
4. **Feature parity vs the tvOS platform:** downloads are impossible on tvOS (500 KB) and belong only on iOS. This differs from the goal "the same features on iOS and tvOS".
5. **The Researcher's version proposals are outdated:** "tvOS 17 or 18" → the current version is tvOS 27. Server 10.10 → the current version is 12.2. 12.0's breaking changes (legacy auth, `GET /QuickConnect/Initiate`, `/emby` routes) are accounted for.
6. **Security's Keychain class:** `...ThisDeviceOnly` is agreed. The spec proposes `AfterFirstUnlockThisDeviceOnly` as the exact class because of Top Shelf and background work, and Security still has to confirm it.
7. **A small difference between two versions of the Researcher's report:** part 4 sent directly to Specification names DTS/TrueHD as the reason for the VLCKit fallback; the group version does not. The spec follows the broader version.

## 10. Gaps in this specification
- The group-chat transcript was not available directly (it was not stored). The Researcher's parts 1–3 were read verbatim from the Researcher's own transcript.
- The contents of Swiftfin PR #1230 (admin) and Swiftfin's DeviceProfile code were not reviewed. They are references for the Coder.
- The exact WebSocket path, the server-side Quick Connect code lifetime, and `NSAllowsLocalNetworking` behavior in AVPlayer on tvOS 26 are unverified (marked in the modules).
- Module files 06, 07, and 09–18 are referenced above and are not in the repository yet.
