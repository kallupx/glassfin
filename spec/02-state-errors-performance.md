# M02 – State, error handling, cache, and performance (P0, cross-cutting)

**Dependencies:** M01. This module (AppState, cache, error model, and measurement) is implemented before the UI modules. The performance requirements apply to every module.

## 1. State management
- Use the **Observation framework (`@Observable`)** and `@MainActor` view models. View models live in the `CoreState` target, so iOS uses the same ones.
- Layers:
  - `AppState` (global, `@MainActor @Observable`) contains: `phase: .launching | .needsServer | .needsLogin(ServerInfo) | .signedIn(UserSession)`, `connectivity: .online | .offline | .serverUnreachable | .degraded`, `activeServer`.
  - Per-view view models (`HomeViewModel`, `LibraryViewModel`, `SeriesViewModel`, `PlayerViewModel`, `SearchViewModel`) publish a `LoadState<T>`:
    ```swift
    public enum LoadState<T: Sendable>: Sendable { case idle, loading(previous: T?), loaded(T), failed(AppError, previous: T?) }
    ```
    `previous` lets the UI keep showing old content during a refresh or an error. The user does not see an empty screen when data already exists.
  - `UserDataStore` (actor) is the **only in-memory source of truth** for played state, position, and favorite state. Every view reads that state from it. Update sources: (1) our own playback and actions, optimistically, (2) the WebSocket `UserDataChanged` event, (3) a refetch. This fixes the "played state does not update" pain point.
- Navigation: `NavigationStack` and a typed `Route` enum per tab. State (focus and scroll) is restored on back navigation.
- Concurrency: structured concurrency. When a view disappears, its tasks are cancelled (`.task` modifier). Stale search requests are cancelled.

## 2. Cache and storage (tvOS limits)
- tvOS has only about **500 KB** of persistent storage (UserDefaults, Researcher report part 3), and the Caches directory can be purged while the app is not running. Therefore:
  - **Keychain:** token and DeviceId (see 03-security.md).
  - **UserDefaults** (< 50 KB budget): server list (URL, name, id, certificate pin fingerprint), active user id, and user settings.
  - **Caches** (purgeable): images (disk LRU, max 300 MB) and the latest home-screen JSON snapshot for a fast cold start (stale-while-revalidate).
  - **Memory:** NSCache images (max 150 MB, cleared on a memory warning) and API responses with a TTL (home 60 s, library lists 5 min, invalidated by a WebSocket event).
- The app still works if Caches has been purged: content just loads more slowly.

## 3. Error handling
One error model:
```swift
public enum AppError: Error, Sendable, Equatable {
  case offline                    // the device has no network (NWPathMonitor)
  case serverUnreachable          // DNS, connection refused, or timeout
  case tlsUntrusted(CertificateInfo) // self-signed or changed certificate → 03-security
  case unauthorized               // 401: token expired or revoked
  case forbidden                  // 403: no permission (for example an admin action)
  case notFound
  case serverError(status: Int)
  case unsupportedServer(version: String) // below the minimum version
  case playback(PlaybackError)
  case decoding                   // unexpected JSON
  case cancelled                  // not shown to the user
}
```

| Situation | Detection | Behavior | Acceptance criterion |
|---|---|---|---|
| Offline | `NWPathMonitor` and URLError `.notConnectedToInternet` | A subtle banner at the top: "No network connection". Cached content stays browsable, and playback is blocked with a clear message. When the connection returns, content refreshes automatically. | Disconnect and reconnect the network in the simulator: the banner appears within 2 s and disappears within 2 s of the connection returning, and home refreshes without user action. |
| Poor network | Request duration > 3 s, playback stalls | Skeleton and shimmer states. API timeout is 15 s, and idempotent GETs are retried twice with backoff (0.5 s, 1.5 s). During playback, lower the bitrate (transcode) and show a message if buffering lasts > 5 s. | On the Network Link Conditioner "3G" profile, home loads without crashing, and every section has a skeleton or an error state. |
| Server down | Connection error or 502/503/504, WebSocket `ServerShuttingDown` / `ServerRestarting` | A full-screen state "Cannot reach the server" with actions "Try again" and "Switch server". Ping in the background every 10 s, and when the server returns, the state recovers automatically. | Stopping the server during browsing → error state within 15 s. Starting the server → recovery within 15 s without signing in again. |
| Token expired or revoked | HTTP 401 from any request | All in-flight requests are cancelled. The token is removed from the Keychain, and the user is sent to login for the same server with the message "Session ended, sign in again". **There is no retry loop.** | Mock 401 → the login view once (no stacked copies), and the token is gone from the Keychain (unit test). |
| 403 | HTTP 403 | Inline message "You do not have permission for this action". The session is not signed out. | An admin action without permission → the message, and the session remains. |
| Old server | `/System/Info/Public.Version` < minimum | A blocking view that states the required version. | Mock version 10.9.11 → the blocking view. |
| Playback error | AVPlayerItem `.failed` or `PlaybackInfoResponse.ErrorCode` | See 08-playback.md: automatic fallback direct play → direct stream → transcode, and only then an error message. | See 08. |
| Unexpected JSON | `DecodingError` | The item is skipped in the list and the error is logged without the token. The whole view does not crash. | A fixture with one broken item → the others still appear. |

- Error messages are written in plain language. Technical detail is shown only in Settings → Diagnostics.
- Crash reporting: OPEN, whether to use MetricKit (the default, no third parties) or a separate service. In either case tokens and URLs are filtered (03-security.md).

## 4. Performance requirements (measurable targets)
Measurement devices (verified 21 Oct 2026: tvOS 26 supports every Apple TV HD and 4K model; Liquid Glass is only on 4K 2nd and 3rd generation):
- Apple TV 4K (3rd generation, A15)
- **Apple TV 4K (2nd generation, A12)**: oldest glass device, glass budget M05 G-4
- **Apple TV HD (A8, 2015)**: oldest tvOS 26 device, no glass ("oldest" column)
 Network: LAN gigabit and Wi-Fi 5. Server: Jellyfin 12.x, a test library of 5,000 movies and 500 series.

| # | Metric | Target (A15) | Target (oldest) | How to measure |
|---|---|---|---|---|
| P1 | Cold start → first home row visible (signed in, LAN) | ≤ 1.5 s | ≤ 3.0 s | XCTApplicationLaunchMetric and os_signpost |
| P2 | All home sections loaded (LAN, p95) | ≤ 1.0 s from launch or return | ≤ 2.0 s | signpost |
| P3 | Focus moves and scrolling (rows, a 2,000-item grid) | 60 fps, hitch ratio < 5 ms/s | < 10 ms/s | XCTOSSignpostMetric / Instruments Hitches |
| P4 | Poster visible (from cache / from LAN) | ≤ 100 ms / ≤ 500 ms | ≤ 200 / ≤ 800 ms | signpost |
| P5 | Playback start (Play → first frame), direct play LAN | ≤ 1.5 s | ≤ 2.5 s | signpost `playback.firstFrame` |
| P6 | Playback start, transcode | ≤ 4 s | ≤ 6 s | same |
| P7 | Seek (scrub confirm → playback resumes), direct play LAN | ≤ 1.0 s | ≤ 2.0 s | same |
| P8 | Trickplay preview appears while scrubbing | ≤ 150 ms (tile cached) | ≤ 300 ms | signpost |
| P9 | Track change (audio/subtitles) during playback, direct play / HLS | ≤ 1.0 s, playback does not restart | ≤ 2.0 s | manual and UI test |
| P10 | Search: first results after typing (after the 300 ms debounce, LAN) | ≤ 500 ms | ≤ 1,000 ms | signpost |
| P11 | Memory while browsing | ≤ 250 MB | ≤ 200 MB | XCTMemoryMetric |
| P12 | Memory during playback (AVPlayer) / remux path | ≤ 400 MB / ≤ 500 MB | ≤ 300 / ≤ 400 MB | XCTMemoryMetric |
| P13 | Memory leak: 10 play–stop cycles | growth < 20 MB | same | XCTMemoryMetric |
| P14 | Played-state update on home after playback | ≤ 2 s | ≤ 2 s | UI test |
| P15 | A change from another client (WebSocket) becomes visible | ≤ 5 s | ≤ 5 s | integration test |

- P1, P3, P5, P11, and P13 run as `XCTMetric` tests in CI on the simulator for regression tracking. Simulator numbers do not match a device, so the absolute targets are confirmed on device before each release (Coder or the user, because the Tester has no device).
- Images are always requested at the displayed size (`maxWidth` = displayed pixel width × screen scale). Full-size images are not downloaded.
- Lists are lazy (`LazyHGrid` / `LazyVGrid`) and paged (`limit=50`, next page when 10 items remain).

## Acceptance criteria (module)
- [ ] `AppState`, `LoadState`, `AppError`, `UserDataStore`, and the cache layer are implemented and unit-tested.
- [ ] Every error row in the table has at least one automatic test (mock).
- [ ] Signpost instrumentation for P1–P15 is in place, and the `XCTMetric` tests run in CI.
- [ ] The UserDefaults size is tested (< 50 KB with 10 servers and 10 users).
