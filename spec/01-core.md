# M01 – GlassfinCore: networking, API client, and data models (P0)

**Dependencies:** M00. **Platforms:** tvOS 26+ and iOS 26+ (DEFAULT, see SPEC.md). The same code is used on both platforms. **GlassfinCore must not import SwiftUI or UIKit**, except in adapters explicitly marked with `#if os(...)`.

## Scope
1. Swift package `GlassfinCore`, with these targets:
   - `CoreNetworking`: server connection, auth header, and TLS handling (see 03-security.md).
   - `CoreAPI`: a protocol-based API layer built on top of jellyfin-sdk-swift.
   - `CoreModels`: the app's own domain models, which SDK DTOs are mapped into.
   - `CoreServices`: services such as LibraryService, PlaybackInfoService, ReportingService, and SearchService.
   - `CoreState`: view models and state machines, shared by tvOS and iOS (see 02-state-errors-performance.md).
   - `CorePlayback`: platform-independent playback logic (DeviceProfile, media segments, reporting, next-up). The AVPlayer adapter lives here, because AVFoundation exists on both platforms.
   - `CoreTestSupport`: mocks and fixtures.
2. Dependency **jellyfin-sdk-swift `from: "3.3.0"`**. Verified 21 Oct 2026: license MPL-2.0, Package.swift supports `tvOS(.v16)` and `iOS(.v16)`, 3.3.0 is generated for server 12.1, and 3.2.0 moved to the `ApiKey` parameter. The SDK's Quick Connect polling tolerates transient errors (3.1.0).
   - The SDK is used **only inside the `CoreAPI` target**. The rest of the code sees only our protocols and domain models, so an SDK update or a server-version difference does not spread into the UI.
   - Unverified: SDK 3.x compatibility with server 10.10/10.11. If the minimum is 10.10 (DEFAULT), integration tests also run against 10.10.7 and 10.11.x (M00).

## Authentication header (agreed with Security)
- On every request: `Authorization: MediaBrowser Client="Glassfin", Device="<tvOS device name>", DeviceId="<stable UUID>", Version="<app version>", Token="<token>"`. Before login the same header is sent without Token.
- **Legacy headers (`X-Emby-Token`, `X-Emby-Authorization`, `X-MediaBrowser-Token`) and an `api_key` query are never used.** Verified: Jellyfin 12.0 rejects them by default.
- When a header cannot be used (media URLs handed to AVPlayer, images), use the **`ApiKey` query parameter** (works on 10.8+). For images, prefer a header via our own URLSession download; see 05-design-system.md. Rule: never send both a header and a query on the same request.
- `DeviceId` is generated once (UUID) and stored in the Keychain (`ThisDeviceOnly`). The server binds the token to the DeviceId.

## Endpoints in use (verified from the Jellyfin OpenAPI spec)
Source: `https://api.jellyfin.org/openapi/jellyfin-openapi-stable.json` (version 12.2.0, downloaded 21 Oct 2026, copy: `/workspace/jellyfin-tvos/research/openapi.json`). "Auth" means the request requires a token.

| Use | Method and path | Auth | Notes |
|---|---|---|---|
| Server identification | `GET /System/Info/Public` | – | `ServerName`, `Version`, `Id`, `StartupWizardCompleted`; version check |
| Ping / reachability | `GET /System/Ping` | – | Connection-state monitoring |
| Password login | `POST /Users/AuthenticateByName` | – | Body `{Username, Pw}` → `AuthenticationResult{User, SessionInfo, AccessToken, ServerId}` |
| Quick Connect enabled? | `GET /QuickConnect/Enabled` | – | |
| Quick Connect start | `POST /QuickConnect/Initiate` | – | **POST only.** `GET` was removed in 12.0. → `QuickConnectResult{Secret, Code, …}` |
| Quick Connect state | `GET /QuickConnect/Connect?secret=` | – | Poll → `Authenticated` |
| Quick Connect token | `POST /Users/AuthenticateWithQuickConnect` | – | Body `{Secret}` → `AuthenticationResult` |
| Logout | `POST /Sessions/Logout` | yes | Revokes the token on the server |
| Current user | `GET /Users/Me` | yes | Token validation at launch, `Policy.IsAdministrator` |
| Public users | `GET /Users/Public` | – | User picker (P1) |
| Capabilities | `POST /Sessions/Capabilities/Full` | yes | `ClientCapabilitiesDto{PlayableMediaTypes, SupportedCommands, SupportsMediaControl, DeviceProfile}` |
| Libraries | `GET /UserViews` | yes | |
| Continue watching | `GET /UserItems/Resume` | yes | `mediaTypes=Video`, `limit`, `fields`, `enableImageTypes` |
| Next episodes | `GET /Shows/NextUp` | yes | `enableResumable=false`, `enableRewatching`, `nextUpDateCutoff` |
| Recently added | `GET /Items/Latest` | yes | `parentId` (library), `groupItems=true` |
| Item listing | `GET /Items` | yes | `parentId, includeItemTypes, sortBy, sortOrder, filters, genres, years, startIndex, limit, recursive, fields, enableTotalRecordCount, nameStartsWith, audioLanguages, subtitleLanguages` |
| Single item | `GET /Items/{itemId}` | yes | `userId` |
| Seasons | `GET /Shows/{seriesId}/Seasons` | yes | `enableUserData` |
| Episodes | `GET /Shows/{seriesId}/Episodes` | yes | `seasonId`, `startItemId`, `adjacentTo`, `fields` |
| Similar | `GET /Items/{itemId}/Similar` | yes | |
| Filters | `GET /Items/Filters2` | yes | Genre and year filters for the library view |
| Images | `GET /Items/{itemId}/Images/{imageType}` | – | `maxWidth, maxHeight, quality, tag, format, fillWidth, fillHeight`. The server does not scale up from 12.0 onward. |
| Played / unplayed | `POST` and `DELETE /UserPlayedItems/{itemId}` | yes | |
| Favorite | `POST` and `DELETE /UserFavoriteItems/{itemId}` | yes | |
| User data | `GET` and `POST /UserItems/{itemId}/UserData` | yes | |
| Search | `GET /Search/Hints` | yes | `searchTerm*`, `includeItemTypes`, `limit`. Alternatively `GET /Items?searchTerm=&recursive=true` |
| Playback info | `POST /Items/{itemId}/PlaybackInfo` | yes | Body `PlaybackInfoDto{DeviceProfile, MaxStreamingBitrate, StartTimeTicks, AudioStreamIndex, SubtitleStreamIndex, MediaSourceId, EnableDirectPlay, EnableDirectStream, EnableTranscoding, AllowVideoStreamCopy, AllowAudioStreamCopy}` → `PlaybackInfoResponse{MediaSources, PlaySessionId, ErrorCode}` |
| Direct stream | `GET /Videos/{itemId}/stream` | ApiKey query | `static=true`, `mediaSourceId`, `playSessionId`, `deviceId` |
| HLS master | `GET /Videos/{itemId}/master.m3u8` | ApiKey query | Not present in the downloaded stable spec, but confirmed via the Rust SDK (`GetMasterHlsVideoPlaylist`) and other API docs. In practice the URL is taken **ready-made from `MediaSourceInfo.TranscodingUrl`**, and is not built by the client. |
| Subtitles (external) | `GET /Videos/{routeItemId}/{routeMediaSourceId}/Subtitles/{routeIndex}/Stream.{routeFormat}` | – | `routeFormat=vtt`. HLS subtitles: `/Videos/{itemId}/{mediaSourceId}/Subtitles/{index}/subtitles.m3u8` |
| Media segments | `GET /MediaSegments/{itemId}` | yes | `includeSegmentTypes` ∈ `Intro, Outro, Recap, Preview, Commercial, Unknown` → `[MediaSegmentDto{Type, StartTicks, EndTicks}]` |
| Trickplay | `GET /Videos/{itemId}/Trickplay/{width}/{index}.jpg` | yes | `mediaSourceId`. Metadata comes from `BaseItemDto.Trickplay` (`fields=Trickplay`) → `TrickplayInfoDto{Width, Height, TileWidth, TileHeight, ThumbnailCount, Interval}` |
| Playback started | `POST /Sessions/Playing` | yes | `PlaybackStartInfo` |
| Playback progress | `POST /Sessions/Playing/Progress` | yes | `PlaybackProgressInfo` |
| Playback stopped | `POST /Sessions/Playing/Stopped` | yes | `PlaybackStopInfo{PositionTicks, PlaySessionId, Failed}` |
| Live-session keepalive | `POST /Sessions/Playing/Ping` | yes | For transcoding sessions |
| Bitrate test | `GET /Playback/BitrateTest` | yes | Automatic quality on a remote connection (P1) |
| WebSocket | `wss://<server>/socket?ApiKey=…&deviceId=…` | yes | Not in OpenAPI. SDK 3.0 includes socket support and reconnect fixes. Message types (`SessionMessageType`, verified from the spec): `UserDataChanged`, `LibraryChanged`, `Play`, `Playstate`, `GeneralCommand`, `ServerShuttingDown`, `ServerRestarting`, `KeepAlive`, `ForceKeepAlive`. The exact path and auth parameter are checked against the SDK socket code. |

Endpoints for later phases (checked to exist): `/Artists`, `/Artists/AlbumArtists`, `/Audio/{itemId}/universal`, `/Audio/{itemId}/Lyrics`, `/Items/{itemId}/InstantMix`, `/Playlists/{playlistId}/Items`, `/LiveTv/Channels`, `/LiveTv/Programs`, `/LiveTv/Programs/Recommended`, `/LiveTv/Recordings`, `/LiveTv/Timers`, `/SyncPlay/*`, `/Sessions`, `/Library/Refresh`, `/ScheduledTasks`, `/ScheduledTasks/Running/{taskId}`, `/Users`, `/Users/{userId}/Policy`, `/Devices`, `/System/Restart`, `/Localization/ParentalRatings`.

## Domain models (illustrative signatures, not the implementation)
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
- Times in Jellyfin are **ticks (1 tick = 100 ns)**. The `Duration` ↔ ticks conversion happens in one place, and it has a unit test.
- DTO → domain mappers are pure functions, and each has a fixture test (12.x and 10.10 responses).

## Service protocols (examples)
```swift
public protocol JellyfinAPIClient: Sendable {   // thin layer over the SDK, mockable
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
```

## Acceptance criteria
- [ ] GlassfinCore builds for tvOS 26 and iOS 26 targets, and it has no SwiftUI or UIKit imports without an `#if` adapter (checked in CI with grep).
- [ ] Every P0 endpoint listed above is wrapped in a service, and each has a mock test (success, 401, 404, 500, timeout, malformed JSON).
- [ ] The auth header is exactly the specified form (unit test). Legacy headers and `api_key` do not appear in the code (CI grep).
- [ ] The ticks ↔ Duration conversion has tests for the edge cases (0, negative, > 24 h).
- [ ] Integration test against a 12.x server: login, `UserViews`, `Resume`, and `PlaybackInfo` succeed. The same on 10.10.7 if the minimum stays at 10.10.
- [ ] `ServerEventStream` reconnects with exponential backoff (1, 2, 4 … max 30 s) and emits `UserDataChanged` and `LibraryChanged` (tested with a mock socket).
