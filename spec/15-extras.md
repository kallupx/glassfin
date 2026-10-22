# M15 – Multi-user, Top Shelf, collections, and other parity features (P1/P2)

**Spec version:** v1.3.3 (22.10.2026). Changes are shown in SPEC.md's change history.

**Dependencies:** M04, M06, and M07.

| Feature | Priority | Scope and endpoints | Acceptance criterion |
|---|---|---|---|
| Several servers | P1 | A server list in Settings, switch and remove (S2.3) | A switch within ≤ 2 s without signing in again |
| Multi-user / profiles | P1 | `GET /Users/Public`, profile images, and a user picker at launch (a setting). A token per user in the Keychain (S1.4). P2: integration of tvOS system profiles (User Management, `runsAsCurrentUser`). **Requires a paid Apple Developer Program** (Apple's tvOS capability table). | A user switch within ≤ 2 s. Another user's played state does not leak. |
| Top Shelf extension | P1 | A TV Services extension: Continue watching (fi: "Jatka katsomista") and Next Up (fi: "Seuraavat jaksot"). The extension reads the token from the shared Keychain access group (S1.1) and the cache from the App Group `group.org.glassfin.app` (placeholder). According to Apple's table, App Groups and Keychain sharing are also available with a free account, but the Personal Team limit of 10 App IDs / 7 days also applies to the extension. A deep link opens detail or playback. | Top Shelf shows up-to-date content with a delay of ≤ 15 min. The deep link works. |
| Collections (BoxSet), people, studios | P1 | `GET /Items?includeItemTypes=BoxSet`, `GET /Persons`, and `personIds` | – |
| Playlists (video) | P1 | `GET /Playlists/{id}/Items` | – |
| A favorites row and tab | P1 | `isFavorite=true` | – |
| Trailers and extras | P1 | `GET /Items/{id}/LocalTrailers`, `RemoteTrailers` (YouTube does not play on tvOS, so it is hidden) | – |
| Theme music | P2 | `GET /Items/{id}/ThemeSongs` | – |
| Photos and photo libraries | P2 | `Photo`, `PhotoAlbum`, a slideshow | – |
| Books / comics | P2 (tvOS: not meaningful, iOS under consideration) | – | – |
| Remote control from another client (Play To, `GeneralCommand`) | P2 | WebSocket messages `Play`, `Playstate`, and `GeneralCommand`, `SupportedCommands` in the capabilities call | – |
| Picture in Picture | P1 | tvOS 14+ native PiP | – |
| Siri search and dictation | P2 | App Intents | – |
