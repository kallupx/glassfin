# M01 – GlassfinCore: networking, the API client, and data models (P0)

**Spec version:** v1.3.3 (22.10.2026). Changes are shown in SPEC.md's change history.

**Dependencies:** M00. **Platforms:** tvOS 26+ and iOS 26+ (ASSUMPTION, see SPEC.md). The same code is used on both platforms. **GlassfinCore must not import SwiftUI or UIKit**, except in separately marked `#if os(...)` adapters.

## Scope
1. A Swift package `GlassfinCore`, whose targets are:
   - `CoreNetworking`: the server connection, the auth header, and TLS handling (see 03-security.md).
   - `CoreAPI`: a protocol-based API layer built on top of jellyfin-sdk-swift.
   - `CoreModels`: the application's own domain models, into which the SDK's DTOs are mapped.
   - `CoreServices`: services such as LibraryService, PlaybackInfoService, ReportingService, and SearchService.
   - `CoreState`: view models and state machines, shared between tvOS and iOS (see 02-state-errors-performance.md).
   - `CorePlayback`: platform-independent playback logic (DeviceProfile, media segments, reporting, next-up). The AVPlayer adapter is here, because AVFoundation exists on both platforms.
   - `CoreTestSupport`: mocks and fixtures.
2. Dependency **jellyfin-sdk-swift `from: "3.3.0"`**. Verified 21.10.2026: license MPL-2.0, Package.swift supports `tvOS(.v16)` and `iOS(.v16)`, 3.3.0 was generated for server version 12.1, and 3.2.0 moved to the `ApiKey` parameter. The SDK's Quick Connect polling tolerates transient errors (3.1.0).
   - The SDK is used **only inside the `CoreAPI` target**. The rest of the code sees only our own protocols and domain models, so that an SDK update or server-version differences do not spread into the UI.
   - ⚠️ Unverified: SDK 3.x compatibility with server 10.10/10.11. If the minimum is 10.10 (ASSUMPTION), integration tests also run against 10.10.7 and 10.11.x (M00).

## Authentication header (agreed with Security)
- On every request: `Authorization: MediaBrowser Client="Glassfin", Device="<tvOS device name>", DeviceId="<persistent UUID>", Version="<app version>", Token="<token>"`. Before sign-in, the same header is sent without a Token.
- **Encoding of values (v1.2, 03-security.md S1.6):** every value is URL-encoded (percent-encoding; only RFC 3986 unreserved characters stay as themselves; `+` → `%2B`, space → `%20`) and wrapped in quotation marks. For example, the device name `Olkkari "TV", 📺` → `Device="Olkkari%20%22TV%22%2C%20%F0%9F%93%BA"`.
  - **Verified 21.10.2026:** the server's `AuthorizationContext.GetParts` splits on the `"`/`,` characters and decodes with `WebUtility.UrlDecode`. jellyfin-sdk-typescript uses `encodeURIComponent`.
  - jellyfin-apiclient-javascript (the old web client) and **jellyfin-sdk-swift 3.3.0 do not encode**. The Swift SDK does not even wrap values in quotes. Therefore `CoreNetworking` builds the header itself (`AuthHeaderBuilder`) and replaces the SDK's header with `setValue`.
  - CR/LF or any other control character in the raw value → the value is rejected (fallback `"Apple TV"` for the device name).
- **Legacy headers (`X-Emby-Token`, `X-Emby-Authorization`, `X-MediaBrowser-Token`) or an `api_key` query are never used.** Verified: Jellyfin 12.0 removed them. The only remaining query parameter is `ApiKey`, which Jellyfin calls a last resort.
- **API calls:** always a header; `ApiKey` is forbidden.
- **Images (S6.6, AGREED with Security 27.10.2026):** requests go through `CoreNetworking` with the `Authorization` header, like API calls. A token (`ApiKey`/`api_key`) is never put in an image URL. Images are cached only in `DiskImageCache` under hashed keys (S6.6).
- **Media (AVPlayer):** primarily a header (`AVAssetResourceLoaderDelegate`, or the undocumented `AVURLAssetHTTPHeaderFieldsKey` ⚠️, ADR M08-2). The fallback is an `ApiKey` query **only in media URLs**, and it is built in a single `MediaURLBuilder` with mandatory S5 redaction (03-security.md S1.5). Rule: never both a header and a query on the same request.
- `DeviceId` is generated once (UUID) and stored in the Keychain (`ThisDeviceOnly`). The token is bound to the DeviceId on the server.

## Endpoints in use (verified from Jellyfin's OpenAPI spec)
Source: `https://api.jellyfin.org/openapi/jellyfin-openapi-stable.json` (version 12.2.0, downloaded 21.10.2026, copy: `/workspace/jellyfin-tvos/research/openapi.json`). "Auth" means the request requires a token.

| Use | Method and path | Auth | Notes |
|---|---|---|---|
| Server identification | `GET /System/Info/Public` | – | `ServerName`, `Version`, `Id`, `StartupWizardCompleted`; version check |
| Ping / reachability | `GET /System/Ping` | – | Connectivity tracking |
| Sign-in with a password | `POST /Users/AuthenticateByName` | – | Body `{Username, Pw}` → `AuthenticationResult{User, SessionInfo, AccessToken, ServerId}` |
| Quick Connect enabled? | `GET /QuickConnect/Enabled` | – | |
| Quick Connect start | `POST /QuickConnect/Initiate` | – | **POST only.** `GET` was removed in 12.0. → `QuickConnectResult{Secret, Code, …}` |
| Quick Connect status | `GET /QuickConnect/Connect?secret=` | – | Polling → `Authenticated` |
| Quick Connect token | `POST /Users/AuthenticateWithQuickConnect` | – | Body `{Secret}` → `AuthenticationResult` |
| Sign-out | `POST /Sessions/Logout` | ✔ | Invalidates the token on the server |
| Current user | `GET /Users/Me` | ✔ | Token validation at launch, `Policy.IsAdministrator` |
| Public users | `GET /Users/Public` | – | User picker (P1) |
| Capabilities | `POST /Sessions/Capabilities/Full` | ✔ | `ClientCapabilitiesDto{PlayableMediaTypes, SupportedCommands, SupportsMediaControl, DeviceProfile}` |
| Libraries | `GET /UserViews` | ✔ | |
| Continue watching | `GET /UserItems/Resume` | ✔ | `mediaTypes=Video`, `limit`, `fields`, `enableImageTypes` |
| Next Up | `GET /Shows/NextUp` | ✔ | `enableResumable=false`, `enableRewatching`, `nextUpDateCutoff` |
| Recently added | `GET /Items/Latest` | ✔ | `parentId` (library), `groupItems=true` |
| Item listing | `GET /Items` | ✔ | `parentId, includeItemTypes, sortBy, sortOrder, filters, genres, years, startIndex, limit, recursive, fields, enableTotalRecordCount, nameStartsWith, audioLanguages, subtitleLanguages` |
| Single item | `GET /Items/{itemId}` | ✔ | `userId` |
| Seasons | `GET /Shows/{seriesId}/Seasons` | ✔ | `enableUserData` |
| Episodes | `GET /Shows/{seriesId}/Episodes` | ✔ | `seasonId`, `startItemId`, `adjacentTo`, `fields` |
| Similar | `GET /Items/{itemId}/Similar` | ✔ | |
| Filters | `GET /Items/Filters2` | ✔ | Genre and year filters for the library view |
| Images | `GET /Items/{itemId}/Images/{imageType}` | ✔ (header, S6.6) | `maxWidth, maxHeight, quality, tag, format, fillWidth, fillHeight`. The server does not upscale from 12.0 onward. |
| Played / unplayed | `POST` and `DELETE /UserPlayedItems/{itemId}` | ✔ | |
| Favorite | `POST` and `DELETE /UserFavoriteItems/{itemId}` | ✔ | |
| User data | `GET` and `POST /UserItems/{itemId}/UserData` | ✔ | |
| Search | `GET /Search/Hints` | ✔ | `searchTerm*`, `includeItemTypes`, `limit`. Alternatively `GET /Items?searchTerm=&recursive=true` |
| Playback info | `POST /Items/{itemId}/PlaybackInfo` | ✔ | Body `PlaybackInfoDto{DeviceProfile, MaxStreamingBitrate, StartTimeTicks, AudioStreamIndex, SubtitleStreamIndex, MediaSourceId, EnableDirectPlay, EnableDirectStream, EnableTranscoding, AllowVideoStreamCopy, AllowAudioStreamCopy}` → `PlaybackInfoResponse{MediaSources, PlaySessionId, ErrorCode}` |
| Direct stream | `GET /Videos/{itemId}/stream` | ApiKey query | `static=true`, `mediaSourceId`, `playSessionId`, `deviceId` |
| HLS master | `GET /Videos/{itemId}/master.m3u8` | ApiKey query | ⚠️ Not found in the downloaded stable spec, but verified through the Rust SDK (`GetMasterHlsVideoPlaylist`) and other API documents. In practice the URL is taken **ready-made from the `MediaSourceInfo.TranscodingUrl` field**, and is not built by us. |
| Subtitles (external) | `GET /Videos/{routeItemId}/{routeMediaSourceId}/Subtitles/{routeIndex}/Stream.{routeFormat}` | – | `routeFormat=vtt`. HLS subtitles: `/Videos/{itemId}/{mediaSourceId}/Subtitles/{index}/subtitles.m3u8` |
| Media segments | `GET /MediaSegments/{itemId}` | ✔ | `includeSegmentTypes` ∈ `Intro, Outro, Recap, Preview, Commercial, Unknown` → `[MediaSegmentDto{Type, StartTicks, EndTicks}]` |
| Trickplay | `GET /Videos/{itemId}/Trickplay/{width}/{index}.jpg` | ✔ | `mediaSourceId`. Metadata comes from the field `BaseItemDto.Trickplay` (`fields=Trickplay`) → `TrickplayInfoDto{Width, Height, TileWidth, TileHeight, ThumbnailCount, Interval}` |
| Playback started | `POST /Sessions/Playing` | ✔ | `PlaybackStartInfo` |
| Playback progress | `POST /Sessions/Playing/Progress` | ✔ | `PlaybackProgressInfo` |
| Playback stopped | `POST /Sessions/Playing/Stopped` | ✔ | `PlaybackStopInfo{PositionTicks, PlaySessionId, Failed}` |
| Live-session keepalive | `POST /Sessions/Playing/Ping` | ✔ | For transcoding sessions |
| Bitrate test | `GET /Playback/BitrateTest` | ✔ | Automatic quality level on a remote connection (P1) |
| WebSocket | `wss://<server>/socket` (auth primarily with the `Authorization` header in the WebSocket handshake; ⚠️ if the SDK or the server requires a query, `?ApiKey=…&deviceId=…`, and the URL is redacted per S5) | ✔ | Not in OpenAPI. SDK 3.0 includes socket support and reconnect fixes. Message types (`SessionMessageType`, verified from the spec): `UserDataChanged`, `LibraryChanged`, `Play`, `Playstate`, `GeneralCommand`, `ServerShuttingDown`, `ServerRestarting`, `KeepAlive`, `ForceKeepAlive`. ⚠️ The exact form of the path and the auth parameter is checked from the SDK's socket code. |

Endpoints for later phases (checked to exist): `/Artists`, `/Artists/AlbumArtists`, `/Audio/{itemId}/universal`, `/Audio/{itemId}/Lyrics`, `/Items/{itemId}/InstantMix`, `/Playlists/{playlistId}/Items`, `/LiveTv/Channels`, `/LiveTv/Programs`, `/LiveTv/Programs/Recommended`, `/LiveTv/Recordings`, `/LiveTv/Timers`, `/SyncPlay/*`, `/Sessions`, `/Library/Refresh`, `/ScheduledTasks`, `/ScheduledTasks/Running/{taskId}`, `/Users`, `/Users/{userId}/Policy`, `/Devices`, `/System/Restart`, `/Localization/ParentalRatings`.

## Domain models (illustrative signatures, not an implementation)
```swift
public struct ServerInfo: Sendable, Hashable, Codable { let id: String; let name: String; let url: URL; let version: SemVer }
public struct UserSession: Sendable { let server: ServerInfo; let userId: String; let userName: String; let isAdministrator: Bool }
// The token is NOT in UserSession. It is read only from CoreNetworking's SecureStore.

public enum MediaKind: Sendable { case movie, series, season, episode, boxSet, musicAlbum, audio, audioBook, liveTvChannel, folder, other(String) }

public struct MediaItem: Sendable, Identifiable, Hashable {
  let id: String; let kind: MediaKind; let name: String; let overview: String?
  let seriesId: String?; let seasonId: String?; let indexNumber: Int?; let parentIndexNumber: Int?
  let runtime: Duration?; let productionYear: Int?; let officialRating: String?; let communityRating: Double?
  let images: ImageSet            // tags and blurhashes: Primary, Backdrop, Logo, Thumb
  let userData: UserItemState     // played, playbackPosition, isFavorite, unplayedCount, playedPercentage
  let trickplay: [Int: TrickplayInfo]? // width → info
  let chapters: [Chapter]
}
public struct MediaSegment: Sendable { enum Kind { case intro, outro, recap, preview, commercial, unknown }; let kind: Kind; let range: Range<Duration> }
public struct PlaybackSource: Sendable { let mediaSourceId: String; let playSessionId: String; let method: PlayMethod /* directPlay | directStream | transcode */
  let url: URL; let audioTracks: [Track]; let subtitleTracks: [Track]; let transcodeReasons: [String] }
```
- Times in Jellyfin are **ticks (1 tick = 100 ns)**. The `Duration` ↔ ticks conversion is done in one place, and a unit test is written for it.
- **Invalid tick values (v1.2, the Tester's question) – expected result:** a negative value is invalid input, **never a crash** (no `precondition`, no trap, no force-unwrap; an `Int64` overflow is also handled with saturation).
  - A negative `PlaybackPositionTicks`/resume value or any other position → **clamped to 0**. In addition, **one non-fatal warning** is logged per item and session (`Logger.warning`, containing the itemId and the field name, not the token and not the URL).
  - `RunTimeTicks` ≤ 0 or missing → `runtime = nil` (duration unknown). The UI hides the progress bar and the remaining time, and `playedPercentage` is ignored.
  - Position > runtime (when runtime is known) → shown as a full bar; the data is not clamped.
  - **A negative `PositionTicks` or `StartTimeTicks` value is never sent to the server.** Reporting (`Playing`, `Progress`, `Stopped`) and PlaybackInfo clamp the value to ≥ 0 as the last step.
- DTO → domain mappers are pure functions, and each has a fixture test (12.x and 10.10 responses).

## Service protocols (examples)
```swift
public protocol JellyfinAPIClient: Sendable {   // a thin layer over the SDK, mockable
  func send<T: Decodable & Sendable>(_ request: APIRequest<T>) async throws(APIError) -> T
}
public protocol LibraryService: Sendable {
  func userViews() async throws(APIError) -> [Library]
  func items(in library: Library.ID, query: ItemQuery, page: PageRequest) async throws(APIError) -> Page<MediaItem>
  func resume(limit: Int) async throws(APIError) -> [MediaItem]
  func nextUp(limit: Int) async throws(APIError) -> [MediaItem]
  func latest(in library: Library.ID, limit: Int) async throws(APIError) -> [MediaItem]
  func seasons(series: MediaItem.ID) async throws(APIError) -> [MediaItem]
  func episodes(series: MediaItem.ID, season: MediaItem.ID?) async throws(APIError) -> [MediaItem]
  func setPlayed(_ id: MediaItem.ID, _ played: Bool) async throws(APIError)
  func setFavorite(_ id: MediaItem.ID, _ fav: Bool) async throws(APIError)
}
public protocol ServerEventStream: Sendable { var events: AsyncStream<ServerEvent> { get } }   // WebSocket
public struct ReconnectPolicy: Sendable { var base: Duration = .seconds(1); var factor = 2.0; var max: Duration = .seconds(30); var stableAfter: Duration = .seconds(10) }
// WebSocketClient<C: Clock<Duration>>(policy:, clock: C, random: any RandomNumberGenerator)
```

### WebSocket reconnect (v1.2)
- **Exponential backoff with full jitter:** `delay = random(0, min(max, base · 2^n))`, where base = 1 s, factor 2, max = 30 s, and n = the number of consecutive failed attempts (starting from 0).
- **The counter is reset only once the connection has stayed open for 10 s.** This way a flapping connection (opens and drops immediately) does not return to rapid attempts.
- **The time source is an injected `Clock`** (Swift's `Clock` protocol, `ContinuousClock` in production, a manually advanced test clock in tests). The random-number generator is also injected (`RandomNumberGenerator`), so that jitter is deterministic in tests.
- **When returning to the foreground** (`scenePhase == .active`), connect **immediately**: the pending backoff delay is cancelled. The counter is not reset before a stable connection of 10 s.
- In the background the connection is closed, and no retries are made.
- `401` during the handshake → the session has expired (rule below). Other errors → backoff.

## Acceptance criteria
- [ ] GlassfinCore builds for the tvOS 26 and iOS 26 destinations, and it has no SwiftUI or UIKit imports without an `#if` adapter (checked in CI with grep).
- [ ] Every P0 endpoint listed above is wrapped in a service, and each has a mock test (success, 401, 404, 500, timeout, malformed JSON).
- [ ] The auth header is in exactly the specified form (unit test). Legacy headers or `api_key` do not occur in the code (CI grep).
- [ ] The ticks ↔ Duration conversion has tests with edge cases (0, negative, > 24 h).
- [ ] An integration test against a 12.x server: sign-in, `UserViews`, `Resume`, and `PlaybackInfo` succeed. The same on 10.10.7, if the minimum stays at 10.10.
- [ ] **Redirects (S4.6):** the networking layer's redirect delegate removes the `Authorization` header when the host, port, or scheme changes, and rejects HTTPS → HTTP redirects. Tests: cross-host (header absent), HTTPS→HTTP (error `AppError.serverUnreachable` / its own `insecureRedirect`), same-host (works, max 5), and a redirect loop (error).
- [ ] `ApiKey` occurs in the code only in `MediaURLBuilder` (CI grep), and API requests never have an `ApiKey` query (mock verification).
- [ ] `ServerEventStream` reconnects with full-jitter backoff and produces `UserDataChanged` and `LibraryChanged` events. Tests with a test clock and a fixed RNG:
  - the delay's upper bound is 1, 2, 4, 8, 16, 30, 30 … s, and every delay is in the range [0, upper bound]
  - a connection that drops in < 10 s → the counter does not reset
  - a connection that stays up ≥ 10 s → the counter resets
  - foreground → a connection attempt immediately, with no delay
- [ ] **Tick edge cases (v1.2):** a negative position or resume → 0 and exactly one warning (the log has no token). `RunTimeTicks` 0 or negative → `runtime == nil`, and no progress bar is shown (snapshot). A negative `PositionTicks` value never reaches the reporting mock. A fuzz test with random `Int64` values does not crash.
- [ ] **Header encoding (v1.2, S1.6):** tests with device names that contain `"`, `,`, `=`, `+`, a space, an emoji, and Finnish diacritics. The result is wrapped in quotation marks and percent-encoded, and server-side parsing (a Swift port of the `GetParts` logic in the test, and an integration test `GET /Sessions` → `DeviceName`) returns the original name. CR/LF or a control character → rejection. The request has exactly one `Authorization` header.
- [ ] **Only 401 signs the user out (v1.2, S2.2):** 401 on an authenticated request → `AppError.unauthorized` → the session ends. A network error, timeout, TLS error, 403, and 500/502/503/504 → **never** `unauthorized`. The token stays in the Keychain (a mock test for each). 401 on a sign-in request → `invalidCredentials`, not session expiry.
- [ ] **`ApiKey` redirect (v1.2, S4.6):** `ApiKey` URL + cross-host redirect → rejected (not mere removal of the parameter). `ApiKey` URL + HTTPS→HTTP → rejected. Same-host HTTPS → works.
