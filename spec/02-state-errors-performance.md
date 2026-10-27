# M02 – State management, error handling, cache, and performance (P0, cross-cutting)

**Spec version:** v1.3.3 (22.10.2026). Changes are shown in SPEC.md's change history.

**Dependencies:** M01. The module's contents (AppState, cache, the error model, and measurement) are implemented before the UI modules. The performance requirements apply to every module.

## 1. State management
- Use the **Observation framework (`@Observable`)** and `@MainActor` view models. View models are in the `CoreState` target, so iOS uses the same ones.
- Layers:
  - `AppState` (global, `@MainActor @Observable`) contains: `phase: .launching | .needsServer | .needsLogin(ServerInfo) | .signedIn(UserSession)`, `connectivity: .online | .offline | .serverUnreachable | .degraded`, `activeServer`.
  - Per-view view models (`HomeViewModel`, `LibraryViewModel`, `SeriesViewModel`, `PlayerViewModel`, `SearchViewModel`) publish a `LoadState<T>` value:
    ```swift
    public enum LoadState<T: Sendable>: Sendable { case idle, loading(previous: T?), loaded(T), failed(AppError, previous: T?) }
    ```
    `previous` makes it possible to show the old content during a refresh or an error. The user does not see an empty screen if data already exists.
  - `UserDataStore` (actor) is the **only source of truth** in memory for played, position, and favorite state. Every view reads the state from it. Update sources: (1) one's own playback and actions, optimistically, (2) the WebSocket `UserDataChanged`, (3) a refetch. This fixes the pain point "the played state does not update".
- Navigation: `NavigationStack` and a typed `Route` enum per tab. State (focus and scroll) is restored on back navigation.
- Concurrency: structured concurrency. When a view disappears, its tasks are cancelled (the `.task` modifier). Stale search requests are cancelled.

## 2. Cache and storage (tvOS limits)
- tvOS has only about **500 KB** of persistent storage (UserDefaults, the Researcher's report part 3), and the Caches directory can be purged when the app is not running. Therefore:
  - **Keychain:** the token and DeviceId (see 03-security.md).
  - **UserDefaults** (< 50 KB budget): the server list (URL, name, id, the certificate pin fingerprint), the active user id, and the user's settings.
  - **Caches** (purgeable): images (disk LRU max 300 MB) and the latest home-view JSON snapshot for a fast cold start (stale-while-revalidate).
  - **Memory:** NSCache images (max 150 MB, cleared on a memory warning) and API responses with a TTL (home 60 s, library lists 5 min, invalidation from a WebSocket event).
- The application works correctly even if Caches has been purged: the content then just loads more slowly.

## 3. Error handling
A single error model:
```swift
public enum AppError: Error, Sendable, Equatable {
  case offline                    // the device has no network (NWPathMonitor)
  case serverUnreachable          // DNS, connection refused, or timeout
  case tlsUntrusted(CertificateInfo) // a self-signed or changed certificate → 03-security
  case unauthorized               // ONLY HTTP 401 from an authenticated request (v1.2). Never from a network, TLS, timeout, or 5xx error.
  case invalidCredentials         // 401 from a sign-in request (wrong username or password), not the end of the session
  case insecureRedirect           // S4.6: an HTTPS→HTTP redirect, or a cross-host redirect of an ApiKey URL, was rejected
  case forbidden                  // 403: no permission (for example an admin action)
  case notFound
  case serverError(status: Int)
  case unsupportedServer(version: String) // below the minimum version
  case playback(PlaybackError)
  case decoding                   // unexpected JSON
  case cancelled                  // not shown to the user
  case internalInvariant          // for example CR/LF in a header value (S1.6). Does not crash; logged as non-fatal.
}
```

| Situation | Detection | Behavior | Acceptance criterion |
|---|---|---|---|
| Offline | `NWPathMonitor` and URLError `.notConnectedToInternet` | A subtle banner at the top: "No network connection" (fi: "Ei verkkoyhteyttä"). Cached content stays browsable, and playback is blocked with a clear message. When the connection returns, content refreshes automatically. | Cutting and restoring the network in the simulator: the banner appears within ≤ 2 s and disappears within ≤ 2 s of the connection returning, and home updates without user action. |
| Poor network | Request duration > 3 s, playback stalls | Skeleton and shimmer states. The API request timeout is 15 s, and idempotent GETs are retried twice with backoff (0.5 s, 1.5 s). During playback, a calculated bitrate (transcoding) and a message if buffering lasts > 5 s. | With Network Link Conditioner's "3G" profile, home loads without a crash, and every section has a skeleton or an error state. |
| Server down | A connection error or 502/503/504, WebSocket `ServerShuttingDown`/`ServerRestarting` | A full-screen state "Can't reach the server" (fi: "Palvelimeen ei saada yhteyttä"; same string key as 04 Q4-10), plus the actions "Try again" (fi: "Yritä uudelleen") and "Change server" (fi: "Vaihda palvelinta"). A background ping every 10 s, and when the server returns, the state recovers automatically. | Stopping the server during browsing → the error state within ≤ 15 s. Starting the server → recovery within ≤ 15 s without signing in again. |
| Token expired or revoked | **Only** HTTP 401 from any authenticated request (v1.2). A network error, timeout, TLS error, and 5xx are never this state. | All in-flight requests are cancelled. The token is removed from the Keychain, and the user is sent to sign in against the same server with the message "Session expired, please sign in again" (fi: "Istunto päättyi, kirjaudu uudelleen"; one string key everywhere, 04 Q4-11). **No retry loop is made.** | Mock 401 → the sign-in view once (no several overlapping ones), and the token has been removed from the Keychain (unit test). |
| 403 | HTTP 403 | An inline message "You don't have permission to do this" (fi: "Ei oikeuksia tähän toimintoon"). The session is not signed out. | An admin action without permission → the message, and the session remains. |
| Old server | `/System/Info/Public.Version` < minimum | A blocking view that states the required version. | Mock version 10.9.11 → the blocking view. |
| Playback error | AVPlayerItem `.failed` or `PlaybackInfoResponse.ErrorCode` | See 08-playback.md: automatic fallback direct play → direct stream → transcode, and only then an error message. For the PoC, the lighter chain in [SPEC.md §3a](SPEC.md#3a-poc-tier-p0-poc-decided-27102026) (Q8P-06) applies instead. | See 08. |
| Unexpected JSON | `DecodingError` | The item is skipped in the list and the error is logged without the token. The whole view does not crash. | A fixture with one broken item → the others are shown. |

- **Server down while content is already on screen (v1.3.4, consistent with 04 Q4-10):** if the current view already has loaded or cached content, it stays visible, `connectivity = .serverUnreachable`, and the banner is shown; actions that need the server show an inline error. The full-screen "Server down" state above is used only when the current view has no content to show. Recovery happens automatically through the 10 s ping.
- Error messages are written in plain language. Technical details are shown only in the Settings → Diagnostics view (fi: "Asetukset → Diagnostiikka").
- Crash reporting: ❓ OPEN, whether to use MetricKit (default, no third parties) or a separate service. In both cases tokens and URLs are filtered (03-security.md).

## 4. Performance requirements (measurable targets)
Measurement devices (verified 21.10.2026: tvOS 26 supports every Apple TV HD and 4K model; Liquid Glass is only on 4K 2nd and 3rd generation):
- Apple TV 4K (3rd generation, A15)
- **Apple TV 4K (2nd generation, A12)**: the oldest glass device, glass budget M05 G-4
- **Apple TV HD (A8, 2015)**: the oldest tvOS 26 device, no glass (column "oldest")
 Network: gigabit LAN and Wi-Fi 5. Server: Jellyfin 12.x, a test library of 5,000 movies and 500 series.

| # | Metric | Target (A15) | Target (oldest) | How measured |
|---|---|---|---|---|
| P1 | Cold start → the home view's first row is visible (signed in, LAN) | ≤ 1.5 s | ≤ 3.0 s | XCTApplicationLaunchMetric and os_signpost |
| P2 | All home sections loaded (LAN, p95) | ≤ 1.0 s from launch or from returning | ≤ 2.0 s | signpost |
| P3 | Focus moves and scrolling (rows, a grid of 2,000 items) | 60 fps, hitch ratio < 5 ms/s | < 10 ms/s | XCTOSSignpostMetric / Instruments Hitches |
| P4 | Poster appears (from cache / from the LAN) | ≤ 100 ms / ≤ 500 ms | ≤ 200 / ≤ 800 ms | signpost |
| P5 | Playback start (Play → first frame), direct play LAN | ≤ 1.5 s | ≤ 2.5 s | signpost `playback.firstFrame` |
| P6 | Playback start, transcoding | ≤ 4 s | ≤ 6 s | the same |
| P7 | Seek (scrub confirmation → playback resumes), direct play LAN | ≤ 1.0 s | ≤ 2.0 s | the same |
| P8 | The trickplay preview image appears while scrubbing | ≤ 150 ms (tile cached) | ≤ 300 ms | signpost |
| P9 | Track change (audio/subtitles) during playback, direct play / HLS | ≤ 1.0 s, no playback restart | ≤ 2.0 s | manual and a UI test |
| P10 | Search: first results after typing (after the 300 ms debounce, LAN) | ≤ 500 ms | ≤ 1,000 ms | signpost |
| P11 | Memory use while browsing | ≤ 250 MB | ≤ 200 MB | XCTMemoryMetric |
| P12 | Memory use during playback (AVPlayer) / remux path | ≤ 400 MB / ≤ 500 MB | ≤ 300 / ≤ 400 MB | XCTMemoryMetric |
| P13 | Memory leak: 10 play–stop cycles | growth < 20 MB | same | XCTMemoryMetric |
| P14 | Played-state update on the home view after playback | ≤ 2 s | ≤ 2 s | UI test |
| P15 | A change from another client (WebSocket) appears | ≤ 5 s | ≤ 5 s | integration test |

- P1, P3, P5, P11, and P13 run as `XCTMetric` tests in CI on the simulator for regression tracking. Simulator numbers do not match the device, so the absolute targets are confirmed on device before every release (the Coder or the user, because the Tester has no device).
- Images are always requested at the displayed size (`maxWidth` = displayed pixel width × the screen scale). Full-size images are not loaded.
- Lists are lazy (`LazyHGrid`/`LazyVGrid`) and paged (`limit=50`, the next page when 10 items remain).

## Acceptance criteria (module)
- [ ] `AppState`, `LoadState`, `AppError`, `UserDataStore`, and the cache layer are implemented and unit-tested.
- [ ] Every error situation in the table has at least one automatic test (mock).
- [ ] Signpost instrumentation for P1–P15 is in place, and the `XCTMetric` tests run in CI.
- [ ] The UserDefaults size is tested (< 50 KB with 10 servers and 10 users).

## Clarifications v1.3.2 (22.10.2026, PR #7's open questions)
- 502/503/504 and connection errors → `serverUnreachable` (an idempotent GET is retried). Other 5xx, including 500 → `serverError(status:)`, no retry.
- 401: on sign-in, `invalidCredentials`; on an authenticated call, `unauthorized` (the only one that signs the user out); on a public/anonymous call (for example `/System/Ping`), `serverError(status: 401)`.
- Redirect: `notFollowed` → `serverUnreachable`/`offline`; S4.6 violations → `insecureRedirect`.
- A server that is too old: `blockingError = .unsupportedServer`, `phase` `.needsLogin`, the token is kept.
- Switching or removing a server → `.needsServer`. Switching does not delete tokens; removal deletes only that server's Keychain accounts.
- The WebSocket `UserDataChanged` wins over a pending optimistic change; a list refetch does not.
- Home rows: `limit=20` per row. Libraries: `limit=50`, prefetch when 10 remain.
- Buffering message (> 5 s): "Buffering is taking longer than usual" (fi: "Puskurointi kestää tavallista pidempään").
- P1 ends when the home view (including the cached snapshot) is visible. The transcoding signpost starts from the `PlaybackInfo` response. Simulator XCTMetric numbers are not device targets; the hitch ratio is measured with Instruments on device.
- Playback's default `maxBitrate` is 120 Mbit/s. The fallback chain is implemented in M08.
- Crash reporting is not part of M02; the MetricKit default remains, with the decision before TestFlight.
