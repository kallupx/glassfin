# M01 – GlassfinCore: verkko, API-asiakas ja datamallit (P0)

**Riippuvuudet:** M00. **Alustat:** tvOS 26+ ja iOS 26+ (OLETUS, ks. SPEC.md). Samaa koodia käytetään molemmilla alustoilla. **GlassfinCore ei saa importata SwiftUI:ta tai UIKitiä**, paitsi erikseen merkityissä `#if os(...)` -adaptereissa.

## Laajuus
1. Swift package `GlassfinCore`, jonka targetit ovat:
   - `CoreNetworking`: palvelinyhteys, auth-header ja TLS-käsittely (ks. 03-security.md).
   - `CoreAPI`: jellyfin-sdk-swiftin päälle rakennettu protokollapohjainen API-kerros.
   - `CoreModels`: sovelluksen omat domain-mallit, joihin SDK:n DTO:t mapataan.
   - `CoreServices`: palvelut, kuten LibraryService, PlaybackInfoService, ReportingService ja SearchService.
   - `CoreState`: ViewModelit ja tilakoneet, jaettu tvOS:n ja iOS:n kesken (ks. 02-state-errors-performance.md).
   - `CorePlayback`: alustariippumaton toistologiikka (DeviceProfile, media segments, raportointi, next-up). AVPlayer-adapteri on tässä, koska AVFoundation on molemmilla alustoilla.
   - `CoreTestSupport`: mockit ja fixturet.
2. Riippuvuus **jellyfin-sdk-swift `from: "3.3.0"`**. Varmistettu 21.10.2026: lisenssi MPL-2.0, Package.swift tukee `tvOS(.v16)` ja `iOS(.v16)`, 3.3.0 on generoitu palvelinversiolle 12.1, ja 3.2.0 siirtyi `ApiKey`-parametriin. SDK:n Quick Connect -polling sietää ohimenevät virheet (3.1.0).
   - SDK:ta käytetään **vain `CoreAPI`-targetin sisällä**. Muu koodi näkee vain omat protokollat ja domain-mallit, jotta SDK-päivitys tai palvelinversioerot eivät leviä UI:hin.
   - ⚠️ Varmistamatta: SDK 3.x:n yhteensopivuus palvelimen 10.10/10.11 kanssa. Jos minimi on 10.10 (OLETUS), integraatiotestit ajetaan myös 10.10.7:ää ja 10.11.x:ää vastaan (M00).

## Autentikointi-header (Turvallisuuden kanssa sovittu)
- Joka pyynnössä: `Authorization: MediaBrowser Client="Glassfin", Device="<tvOS-laitteen nimi>", DeviceId="<pysyvä UUID>", Version="<app-versio>", Token="<token>"`. Ennen kirjautumista sama header lähetetään ilman Tokenia.
- **Legacy-headereita (`X-Emby-Token`, `X-Emby-Authorization`, `X-MediaBrowser-Token`) tai `api_key`-queryä ei käytetä koskaan.** Varmistettu: Jellyfin 12.0 hylkää ne oletuksena.
- Kun headeria ei voi käyttää (AVPlayerille annettavat media-URL:t, kuvat), käytetään **`ApiKey`-queryparametria** (toimii 10.8+). Kuville suositellaan headeria oman URLSession-latauksen kautta, ks. 05-design-system.md. Sääntö: ei koskaan sekä headeria että queryä samassa pyynnössä.
- `DeviceId` generoidaan kerran (UUID) ja tallennetaan Keychainiin (`ThisDeviceOnly`). Token on sidottu DeviceId:hen palvelimella.

## Käytettävät endpointit (varmistettu Jellyfinin OpenAPI-specistä)
Lähde: `https://api.jellyfin.org/openapi/jellyfin-openapi-stable.json` (versio 12.2.0, ladattu 21.10.2026, kopio: `/workspace/jellyfin-tvos/research/openapi.json`). "Auth" tarkoittaa, että pyyntö vaatii tokenin.

| Käyttö | Metodi ja polku | Auth | Huom. |
|---|---|---|---|
| Palvelimen tunnistus | `GET /System/Info/Public` | – | `ServerName`, `Version`, `Id`, `StartupWizardCompleted`; versiotarkistus |
| Ping / tavoitettavuus | `GET /System/Ping` | – | Yhteystilan seuranta |
| Kirjautuminen salasanalla | `POST /Users/AuthenticateByName` | – | Body `{Username, Pw}` → `AuthenticationResult{User, SessionInfo, AccessToken, ServerId}` |
| Quick Connect käytössä? | `GET /QuickConnect/Enabled` | – | |
| Quick Connect aloitus | `POST /QuickConnect/Initiate` | – | **Vain POST.** `GET` poistettiin 12.0:ssa. → `QuickConnectResult{Secret, Code, …}` |
| Quick Connect tila | `GET /QuickConnect/Connect?secret=` | – | Pollaus → `Authenticated` |
| Quick Connect token | `POST /Users/AuthenticateWithQuickConnect` | – | Body `{Secret}` → `AuthenticationResult` |
| Uloskirjautuminen | `POST /Sessions/Logout` | ✔ | Mitätöi tokenin palvelimella |
| Nykyinen käyttäjä | `GET /Users/Me` | ✔ | Tokenin validointi käynnistyksessä, `Policy.IsAdministrator` |
| Julkiset käyttäjät | `GET /Users/Public` | – | Käyttäjävalitsin (P1) |
| Kyvykkyydet | `POST /Sessions/Capabilities/Full` | ✔ | `ClientCapabilitiesDto{PlayableMediaTypes, SupportedCommands, SupportsMediaControl, DeviceProfile}` |
| Kirjastot | `GET /UserViews` | ✔ | |
| Jatka katsomista | `GET /UserItems/Resume` | ✔ | `mediaTypes=Video`, `limit`, `fields`, `enableImageTypes` |
| Seuraavat jaksot | `GET /Shows/NextUp` | ✔ | `enableResumable=false`, `enableRewatching`, `nextUpDateCutoff` |
| Viimeksi lisätyt | `GET /Items/Latest` | ✔ | `parentId` (kirjasto), `groupItems=true` |
| Kohteiden listaus | `GET /Items` | ✔ | `parentId, includeItemTypes, sortBy, sortOrder, filters, genres, years, startIndex, limit, recursive, fields, enableTotalRecordCount, nameStartsWith, audioLanguages, subtitleLanguages` |
| Yksittäinen kohde | `GET /Items/{itemId}` | ✔ | `userId` |
| Kaudet | `GET /Shows/{seriesId}/Seasons` | ✔ | `enableUserData` |
| Jaksot | `GET /Shows/{seriesId}/Episodes` | ✔ | `seasonId`, `startItemId`, `adjacentTo`, `fields` |
| Samankaltaiset | `GET /Items/{itemId}/Similar` | ✔ | |
| Suodattimet | `GET /Items/Filters2` | ✔ | Genre- ja vuosisuodattimet kirjastonäkymään |
| Kuvat | `GET /Items/{itemId}/Images/{imageType}` | – | `maxWidth, maxHeight, quality, tag, format, fillWidth, fillHeight`. Palvelin ei skaalaa ylös 12.0:sta alkaen. |
| Katsottu / ei katsottu | `POST` ja `DELETE /UserPlayedItems/{itemId}` | ✔ | |
| Suosikki | `POST` ja `DELETE /UserFavoriteItems/{itemId}` | ✔ | |
| Käyttäjädata | `GET` ja `POST /UserItems/{itemId}/UserData` | ✔ | |
| Haku | `GET /Search/Hints` | ✔ | `searchTerm*`, `includeItemTypes`, `limit`. Vaihtoehtoisesti `GET /Items?searchTerm=&recursive=true` |
| Toistotiedot | `POST /Items/{itemId}/PlaybackInfo` | ✔ | Body `PlaybackInfoDto{DeviceProfile, MaxStreamingBitrate, StartTimeTicks, AudioStreamIndex, SubtitleStreamIndex, MediaSourceId, EnableDirectPlay, EnableDirectStream, EnableTranscoding, AllowVideoStreamCopy, AllowAudioStreamCopy}` → `PlaybackInfoResponse{MediaSources, PlaySessionId, ErrorCode}` |
| Suora stream | `GET /Videos/{itemId}/stream` | ApiKey-query | `static=true`, `mediaSourceId`, `playSessionId`, `deviceId` |
| HLS master | `GET /Videos/{itemId}/master.m3u8` | ApiKey-query | ⚠️ Ei löydy ladatusta stable-specistä, mutta se on varmistettu Rust-SDK:n (`GetMasterHlsVideoPlaylist`) ja muiden API-dokumenttien kautta. Käytännössä URL otetaan **valmiina `MediaSourceInfo.TranscodingUrl`-kentästä**, eikä sitä rakenneta itse. |
| Tekstitys (ulkoinen) | `GET /Videos/{routeItemId}/{routeMediaSourceId}/Subtitles/{routeIndex}/Stream.{routeFormat}` | – | `routeFormat=vtt`. HLS-tekstitys: `/Videos/{itemId}/{mediaSourceId}/Subtitles/{index}/subtitles.m3u8` |
| Media segments | `GET /MediaSegments/{itemId}` | ✔ | `includeSegmentTypes` ∈ `Intro, Outro, Recap, Preview, Commercial, Unknown` → `[MediaSegmentDto{Type, StartTicks, EndTicks}]` |
| Trickplay | `GET /Videos/{itemId}/Trickplay/{width}/{index}.jpg` | ✔ | `mediaSourceId`. Metadata saadaan kentästä `BaseItemDto.Trickplay` (`fields=Trickplay`) → `TrickplayInfoDto{Width, Height, TileWidth, TileHeight, ThumbnailCount, Interval}` |
| Toisto alkoi | `POST /Sessions/Playing` | ✔ | `PlaybackStartInfo` |
| Toiston edistyminen | `POST /Sessions/Playing/Progress` | ✔ | `PlaybackProgressInfo` |
| Toisto loppui | `POST /Sessions/Playing/Stopped` | ✔ | `PlaybackStopInfo{PositionTicks, PlaySessionId, Failed}` |
| Live-session keepalive | `POST /Sessions/Playing/Ping` | ✔ | Transkoodaussessioille |
| Bitrate-testi | `GET /Playback/BitrateTest` | ✔ | Automaattinen laatutaso etäyhteydellä (P1) |
| WebSocket | `wss://<server>/socket?ApiKey=…&deviceId=…` | ✔ | Ei ole OpenAPI:ssa. SDK 3.0 sisältää socket-tuen ja reconnect-korjaukset. Viestityypit (`SessionMessageType`, varmistettu specistä): `UserDataChanged`, `LibraryChanged`, `Play`, `Playstate`, `GeneralCommand`, `ServerShuttingDown`, `ServerRestarting`, `KeepAlive`, `ForceKeepAlive`. ⚠️ Polun ja auth-parametrin tarkka muoto tarkistetaan SDK:n socket-koodista. |

Myöhempien vaiheiden endpointit (tarkistettu olemassaoleviksi): `/Artists`, `/Artists/AlbumArtists`, `/Audio/{itemId}/universal`, `/Audio/{itemId}/Lyrics`, `/Items/{itemId}/InstantMix`, `/Playlists/{playlistId}/Items`, `/LiveTv/Channels`, `/LiveTv/Programs`, `/LiveTv/Programs/Recommended`, `/LiveTv/Recordings`, `/LiveTv/Timers`, `/SyncPlay/*`, `/Sessions`, `/Library/Refresh`, `/ScheduledTasks`, `/ScheduledTasks/Running/{taskId}`, `/Users`, `/Users/{userId}/Policy`, `/Devices`, `/System/Restart`, `/Localization/ParentalRatings`.

## Domain-mallit (havainnollistavat signatuurit, ei toteutus)
```swift
public struct ServerInfo: Sendable, Hashable, Codable { let id: String; let name: String; let url: URL; let version: SemVer }
public struct UserSession: Sendable { let server: ServerInfo; let userId: String; let userName: String; let isAdministrator: Bool }
// Token EI ole UserSessionissa. Sitä luetaan vain CoreNetworkingin SecureStoresta.

public enum MediaKind: Sendable { case movie, series, season, episode, boxSet, musicAlbum, audio, audioBook, liveTvChannel, folder, other(String) }

public struct MediaItem: Sendable, Identifiable, Hashable {
  let id: String; let kind: MediaKind; let name: String; let overview: String?
  let seriesId: String?; let seasonId: String?; let indexNumber: Int?; let parentIndexNumber: Int?
  let runtime: Duration?; let productionYear: Int?; let officialRating: String?; let communityRating: Double?
  let images: ImageSet            // tagit ja blurhashit: Primary, Backdrop, Logo, Thumb
  let userData: UserItemState     // played, playbackPosition, isFavorite, unplayedCount, playedPercentage
  let trickplay: [Int: TrickplayInfo]? // width → info
  let chapters: [Chapter]
}
public struct MediaSegment: Sendable { enum Kind { case intro, outro, recap, preview, commercial, unknown }; let kind: Kind; let range: Range<Duration> }
public struct PlaybackSource: Sendable { let mediaSourceId: String; let playSessionId: String; let method: PlayMethod /* directPlay | directStream | transcode */
  let url: URL; let audioTracks: [Track]; let subtitleTracks: [Track]; let transcodeReasons: [String] }
```
- Ajat ovat Jellyfinissä **tickeinä (1 tick = 100 ns)**. Muunnos `Duration` ↔ ticks tehdään yhdessä paikassa, ja sille kirjoitetaan yksikkötesti.
- Mapperit DTO → domain ovat puhtaita funktioita, ja jokaiselle on fixture-testi (12.x ja 10.10 -vastaukset).

## Palveluprotokollat (esimerkkejä)
```swift
public protocol JellyfinAPIClient: Sendable {   // ohut kerros SDK:n päällä, mockattava
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

## Hyväksymiskriteerit
- [ ] GlassfinCore kääntyy tvOS 26- ja iOS 26 -kohteille, eikä siinä ole SwiftUI- tai UIKit-importteja ilman `#if`-adapteria (tarkistetaan CI:ssä grepillä).
- [ ] Jokainen yllä listattu P0-endpoint on kääritty palveluun, ja jokaiselle on mock-testi (onnistuminen, 401, 404, 500, aikakatkaisu, virheellinen JSON).
- [ ] Auth-header on täsmälleen määritellyssä muodossa (yksikkötesti). Legacy-headereita tai `api_key`:ta ei esiinny koodissa (CI-grep).
- [ ] Ticks ↔ Duration -muunnokselle on testit rajatapauksineen (0, negatiivinen, > 24 h).
- [ ] Integraatiotesti 12.x-palvelinta vastaan: kirjautuminen, `UserViews`, `Resume` ja `PlaybackInfo` onnistuvat. Sama 10.10.7:llä, jos minimi pysyy 10.10:ssä.
- [ ] `ServerEventStream` yhdistää uudelleen exponential backoffilla (1, 2, 4 … max 30 s) ja tuottaa `UserDataChanged`- ja `LibraryChanged`-tapahtumat (mock-socketilla testattu).
