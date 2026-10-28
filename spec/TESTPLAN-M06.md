# Test plan – M06 (home view)

**Author:** Testaaja · 2026-10-27 · **Based on:** spec/06-home.md, 02-state-errors-performance.md, 03-security.md, 05-design-system.md, 01-core.md, 04-auth.md (Q4-10, Q4-16), SPEC.md on `main` (`a617f71`, v1.3.3 plus PR #17), and the pending spec PR #18 (`spec/m06-m07-m09-decisions`, head `61d944c`, incl. `e5edd3a`, v1.3.4) for S6.1, S6.6, S6.7, 02 "Server down while content is already on screen" and Q6-20.
**Recovery note (2026-10-27):** the original file written earlier today was lost when `/workspace/jellyfin-tvos` was restored to an older state at 21:46 UTC. No copy survived on the box or on any GitHub branch, so this file was regenerated from the spec with the same IDs, sections and coverage, and the decisions made since then are applied.
**Environment:** Testaaja runs Linux. Mac tests run in CI (`test-tvos`, `test-ios`, `full-ui`), and Testaaja reads the artifacts (JUnit, PNG, coverage). Device tests are done by Koodari or the user (SPEC §8 R7).
**Work queue:** M06 depends on M01, M02, M04 and M05 (06 Dependencies). Branch `feat/m06-home`.

**References:** `06 UP n` = user path step n · `06 Sections` = sections and endpoints table · `06 Upd` = updating section · `06 HK` = acceptance criteria · `02 §n` / `02 Pn` / `02 v1.3.2` / `02 v1.3.4` = 02-state-errors-performance.md · `05 §n`, `L-n`, `G-n` = 05-design-system.md · `Sx.y` = 03-security.md · `Q4-nn` = TESTPLAN-M04 decisions. (Short codes UP, HK are kept as reference codes.)
**Run:** **L** = Linux `swift test` (GlassfinCore targets only: view models, URL building, paging, stores, `MetadataPolicy`) · **X** = macOS XCTest · **U** = macOS XCUITest (`XCUIRemote`, mock server `-uitest-mock-server`) · **S** = snapshot (1080p + 4K) · **I** = Linux Docker integration (`integration.yml`, 10.10.7 / 10.11.11 / 12.2) · **K** = review or CI lint script · **M** = manual device test.
**🔒** = raised to Turvallisuus (traceable to 03-security.md).
**UI strings and assertions:** expected UI texts are given as the English dev-language string (`Localizable.xcstrings`) with the Finnish localization in parentheses. X and L tests assert on state / error type or on the String Catalog key, never on a hardcoded string. U and S tests run in the `en` locale and identify elements by `accessibilityIdentifier` (`screen.element`) or catalog key.

## Launch and default focus
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T06-01 | Signed-in launch (mock with all rows populated) | Home opens. Default focus is on the first card of "Continue watching" (fi: "Jatka katsomista") | 06 UP 1 | U |
| T06-02 | "Continue watching" is empty, "Next Up" has items | Default focus is on the first card of "Next Up" (fi: "Seuraavat jaksot") | 06 UP 1 | U |
| T06-03 | Both "Continue watching" and "Next Up" are empty, Latest rows have items | Default focus is on the first card of the first visible row (ASSUMPTION until Q6-01) | 06 UP 1, Q6-01 | U |
| T06-04 | Every row is empty | Empty state "Your library is empty" (fi: "Kirjastosi on tyhjä") with guidance; the tab bar stays reachable and there is no focus trap | 06 Sections, Q6-13 | U, S |
| T06-05 | Up from the first row, then Menu | Up reaches the tab bar. Menu from home goes to the tab bar and Menu on the tab bar exits (system) | 06 UP 2, 05 §8 | U |

## Sections and endpoints
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T06-06 | Continue watching request | `GET /UserItems/Resume` with exactly `mediaTypes=Video`, `limit=20`, `fields=PrimaryImageAspectRatio,Overview`, `enableImageTypes=Primary,Backdrop,Thumb,Logo`, `enableUserData=true` (mock records the query) | 06 Sections | L |
| T06-07 | Next Up request | `GET /Shows/NextUp` with `limit=20`, `enableResumable=false`, `enableRewatching=false` and the agreed `fields` | 06 Sections | L |
| T06-08 | Latest rows from `UserViews`: 2 movie libraries, 1 TV library, 1 music library, 1 Live TV view | One `GET /Items/Latest` row per video library (`parentId=<library>`, `limit=20`, `groupItems=true`). Non-video views get no row (ASSUMPTION until Q6-02) | 06 Sections, 02 v1.3.2, Q6-02 | L, X |
| T06-09 | Row order | Continue watching, Next Up, then one Latest row per video library in `UserViews` order. The P1 Favorites row is not shown in P0 | 06 Sections | X, U |
| T06-10 | **Q6-20 DECIDED (user 2026-10-27):** an in-progress episode S1E3 and the next episode S1E4 of another series | "Continue watching" and "Next Up" are **two separate rows**: S1E3 is on Continue watching, the other series' next episode is on Next Up. There is no combined "Up Next" row in P0 (the combined row is only a P1 setting) | 06 Sections (PR #18), Q6-20 | X, S |
| T06-11 | The same episode is returned by Resume and by NextUp (mock overlap) | The episode is shown once, on Continue watching (ASSUMPTION until Q6-03); `enableResumable=false` is sent | 06 Sections, Q6-03 | X |
| T06-12 | All sections are fetched in parallel: the mock delays each section by 1 s | All sections finish in < 1.5 s in total (`async let` or a TaskGroup), not sequentially | 06 Sections | X |
| T06-13 | One section returns 500 | That section shows its own error state with "Try again" (fi: "Yritä uudelleen"); the other sections are shown and the view does not crash | 06 Sections, 06 HK, 02 v1.3.2 | X, U |
| T06-14 | "Try again" in a failed section | Only that section is fetched again (mock: exactly one new request); focus stays in the section | 06 HK, Q6-11 | X, U |
| T06-15 | A row whose response has 0 items | The row is hidden; no empty header remains | 06 Sections | X, S |
| T06-16 | A row with exactly 20 items and a server with more | 20 cards (`limit=20`), no paging on home, no "See all" in P0 (Q6-04) | 06 Sections, 02 v1.3.2, Q6-04 | X |
| T06-17 | Row titles | "Continue watching" (fi: "Jatka katsomista"), "Next Up" (fi: "Seuraavat jaksot"), "Recently added" (fi: "Viimeksi lisätyt") with the library name. Keys exist in en and fi; the format with the library name is Q6-05 | 06 Sections, Q6-05 | K, X |
| T06-18 | Unexpected JSON: one broken item in a row | The item is skipped, the rest of the row is shown, the error is logged without the token | 02 §3 | X |
| T06-19 | Section with a `DecodingError` for the whole body | That section shows its error state; other sections are shown | 02 §3 | X |

## Cards and backdrop
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T06-20 | Continue watching card fixtures: progress 10 / 50 / 95 %, unknown duration | `LandscapeCard` with a progress bar and "32 min left" (fi: "32 min jäljellä"). With an unknown duration there is no progress bar | 05 §7, 06 Sections | S |
| T06-21 | Next Up card | Shows the series name, `SxEy` and the episode name | 05 §7 | S |
| T06-22 | Latest row with `groupItems=true`: 5 new episodes of one series | One series card (with the new-episode count if the server gives it, Q6-06), not five episode cards | 06 Sections, Q6-06 | X, S |
| T06-23 | A card is focused and kept focused | After a 250 ms debounce the backdrop changes into the view background with a 300 ms crossfade | 06 UP 3 | U, M |
| T06-24 | Fast browsing: 10 cards, each focused for < 250 ms | Only the last card's backdrop image is requested (mock image request count = 1) | 06 UP 3 | X |
| T06-25 | Reduce Motion on | The backdrop changes immediately, without a crossfade; the debounce still applies (Q6-19) | 06 UP 3, 05 §5, Q6-19 | U, S |
| T06-26 | Item without a backdrop | Fallback per Q6-07 (ASSUMPTION: keep the previous background); no broken image and no crash | 06 UP 3, Q6-07 | S |
| T06-27 | Glass on home | Only the tab bar and the `GlassBanner` are glass; cards and rows are content without glass | 06 UP 3, G-2, 05 §2 | K, S |
| T06-28 | Row titles over the backdrop | System vibrant text over the bottom gradient; legible on bright, dark and busy backdrops | L-1, L-3 | S |
| T06-29 | Image request size | `maxWidth` = displayed pixel width × screen scale for posters, thumbs and backdrops; no full-size images | 02 §4 | L, X |

## Navigation and actions
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T06-30 | Left and right on a row, up and down between rows, row 2 item 5 → up → down | Moves as expected; focus returns to row 2 item 5 (focus memory), not to the geometrically nearest card | 06 UP 2, 05 §7 | U |
| T06-31 | Click on a card, then Menu | Opens M07 detail; Menu returns to home with the same card focused and the scroll position kept | 06 UP 4, 02 §1 | U |
| T06-32 | Play/Pause on a Continue watching card | Playback starts directly from the resume position (`startPositionTicks` from UserData). Until M08 is merged the play hook receives the item and position (Q6-12) | 06 UP 4, 06 HK, Q6-12 | X, U |
| T06-33 | Play/Pause on a Next Up or Latest card without progress | Playback starts from the beginning | 06 UP 4 | X |
| T06-34 | Long press on a Continue watching card | Context menu with "Mark as played" (fi: "Merkitse katsotuksi"), "Remove from Continue Watching" (fi: "Poista jatka katsomista -listalta"), "Go to series" (fi: "Siirry sarjaan") and "Favorite" (fi: "Suosikki"). Items on other rows per Q6-16 | 06 UP 5, Q6-16 | U |
| T06-35 | "Mark as played" | Optimistic update through `UserDataStore` at once, `POST /UserPlayedItems/{id}`; the card leaves Continue watching and the next episode appears on Next Up within ≤ 2 s | 06 UP 5, 02 §1, 02 P14 | X, U |
| T06-36 | "Mark as played" fails (mock 500) | The previous state is restored and a message is shown; the view does not crash | 06 UP 5, 02 §3 | X |
| T06-37 | "Remove from Continue Watching" | Done with a UserData update (position reset / unplayed per Q6-10); the item leaves the row and stays gone after a refetch against a real server (⚠️ no dedicated endpoint) | 06 UP 5 ⚠️, Q6-10 | X, I |
| T06-38 | "Go to series" on an episode card | Opens the M07 series view on that episode's season. For a movie the item is hidden (Q6-08) | 06 UP 5, Q6-08 | U |
| T06-39 | "Favorite" | `POST` / `DELETE /UserFavoriteItems/{id}`; the state is updated optimistically and restored on error | 06 UP 5, 01 endpoints | X |
| T06-40 | Context menu closed with Menu | Focus returns to the same card | 06 UP 5, 05 §3 | U |
| T06-41 | 403 on an action (mark played, favorite) | Inline "You don't have permission to do this" (fi: "Ei oikeuksia tähän toimintoon"); the session is not signed out; state restored | 02 §3 (PR #17) | X |

## Connectivity and errors
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T06-42 | Network drops on home (`NWPathMonitor`) | `GlassBanner` "No network connection" (fi: "Ei verkkoyhteyttä") within ≤ 2 s; cached content stays browsable; playback is blocked with a clear message; the banner is not focusable | 02 §3, 05 §7 | U, X |
| T06-43 | Network returns | The banner disappears within ≤ 2 s and home refreshes automatically without moving focus | 02 §3, 06 Upd | U |
| T06-44 | Cold start with a cached home snapshot | The snapshot is shown at once (stale-while-revalidate) and replaced by fresh data without a focus jump | 02 §2, Q4-10 | X |
| T06-45 | Caches purged before launch | Home loads from the network more slowly; no crash and no empty-screen error | 02 §2 | X |
| T06-46 | **Q6-14 RESOLVED:** server down and nothing displayable (no cache, first load; connection error or 502/503/504) | Full-screen state titled "Can't reach the server" (fi: "Palvelimeen ei saada yhteyttä"), with **one** string key shared by 02 §3 and 04 Q4-10 (no duplicate key in the catalog), plus "Try again" (fi: "Yritä uudelleen") with default focus and "Change server" (fi: "Vaihda palvelinta") | 02 §3 (PR #17), Q4-10, Q6-14 | X, U, S, K |
| T06-47 | "Change server" on the full-screen state | `phase = .needsServer`; A2 opens; tokens are not deleted | 02 §3, 02 v1.3.2 | U |
| T06-48 | Server returns while the full-screen state is shown | The background ping (every 10 s) detects it and home recovers automatically | 02 §3 | X |
| T06-49 | **Q6-15 (decided in PR #18, pending merge):** the server goes down while home content is on screen | The content already shown stays visible, `connectivity = .serverUnreachable` and the banner appears. The full-screen state is **not** shown; it is used only when nothing is displayable | 02 v1.3.4 (PR #18), Q4-10, Q6-15 | X, U |
| T06-50 | In the T06-49 state, an action that needs the server (mark played) | Inline error; the content and focus stay; recovery through the 10 s ping removes the banner | 02 v1.3.4 (PR #18) | X |
| T06-51 | 401 from any home request | All in-flight requests are cancelled, the token is removed, sign-in opens once with "Session expired, please sign in again" (fi: "Istunto päättyi, kirjaudu uudelleen"); no retry loop | 02 §3 (PR #17), S2.2, Q4-11 | X |
| T06-52 | 502 / 503 / 504 vs 500 on a section | 502/503/504: the idempotent GET is retried twice (0.5 s, 1.5 s), then `serverUnreachable`. 500: `serverError(status:)`, no retry, section error | 02 §3, 02 v1.3.2 | X |
| T06-53 | Network Link Conditioner "3G" | Home loads without a crash; every section shows a skeleton or an error | 02 §3 | M, X |
| T06-54 | WebSocket `ServerShuttingDown` / `ServerRestarting` | Handled like server down (T06-46 / T06-49 depending on displayed content) | 02 §3 | X |
| T06-55 | Request timeout | 15 s per API request; the section shows its error state | 02 §3 | X |
| T06-56 | Server unreachable on a cold start that has a cached home snapshot | The cached content is shown with the `.serverUnreachable` banner, not the full-screen state (content is displayable) | 02 v1.3.4 (PR #18), 02 §2 | X |

## Updating
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T06-57 | Playback ends (M08 `Stopped` event, mocked) | `UserDataStore` is updated optimistically at once, and Resume and NextUp are fetched again | 06 Upd | X |
| T06-58 | Watch an episode to the end, return home | The episode leaves "Continue watching" and the next one appears on "Next Up" within ≤ 2 s, without a restart | 06 HK, 02 P14 | U |
| T06-59 | Another client marks an item played (Docker server, WebSocket `UserDataChanged`) | The card updates on home within ≤ 5 s | 06 Upd, 06 HK, 02 P15 | I |
| T06-60 | `UserDataChanged` arrives while an optimistic change is pending | The WebSocket value wins; a list refetch does not override a pending optimistic change | 02 v1.3.2 | X |
| T06-61 | 5 `LibraryChanged` events within 1 s | The Latest rows are fetched once (2 s debounce) | 06 Upd | X |
| T06-62 | Foreground after > 60 s | Home is fetched again quietly; old content stays visible; focus does not move | 06 Upd | X, U |
| T06-63 | Foreground after < 60 s | No refetch | 06 Upd, 02 §2 | X |
| T06-64 | Background update with focus on row 2 item 3 | Focus is on the same item before and after the update (UI test) | 06 Upd, 06 HK | U |
| T06-65 | The focused item leaves its row during an update | Focus moves to the neighbouring item on the same row; if the row disappears, per Q6-09 | 06 Upd, Q6-09 | U |
| T06-66 | Home disappears (tab switch) during loading | Its tasks are cancelled (`.task`), and `.cancelled` is never shown to the user | 02 §1, 02 §3 | X |

## Performance and visual regression
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T06-67 | Cold start → first home row; all sections loaded (LAN) | P1 ≤ 1.5 s (A15) / ≤ 3.0 s (oldest); P2 ≤ 1.0 s / ≤ 2.0 s p95. Simulator `XCTMetric` only for regression; device numbers recorded for the release | 02 P1, 02 P2, 06 HK | X, M |
| T06-68 | Focus scrolling across rows (Instruments Hitches) | 60 fps, hitch ratio < 5 ms/s (A15), < 10 ms/s (oldest); G-4 met on Apple TV 4K 2nd generation | 02 P3, G-4, 06 HK | X, M |
| T06-69 | Memory while browsing home and on a memory warning | P11 ≤ 250 MB / ≤ 200 MB; NSCache images purged on a memory warning | 02 P11, 02 §2 | X, M |
| T06-70 | Snapshot matrix: home with mock data × {1080p, 4K} × {default, Reduce Transparency} | Every section visible; with Reduce Transparency the tab bar and the banner are opaque; PNGs in the artifacts | 06 HK, 05 §5 | S |

## Security
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T06-71 | 🔒 Image requests for posters, thumbs, logos and backdrops | Go through `CoreNetworking` with the `Authorization` header; no `ApiKey`, `api_key` or token in any image URL (built URL and recorded request) | S6.6 (PR #18), 01 Auth (PR #18), Q6-17 | L, X |
| T06-72 | 🔒 `DiskImageCache` keys | Key = SHA-256 of (server ID, item ID, image type, tag, size); stable across launches; a new tag or size gives a new key; raw URLs are never file names and are never logged unredacted; files live in Caches | S6.6 (PR #18), Q6-17 | L |
| T06-73 | 🔒 Untrusted metadata through the home view models and cards: `Name`, `SeriesName`, `Overview`, `Taglines`, `Genres`, people, studios and library (`UserViews`) names containing HTML (`<b>x</b>`, `<script>`, `&amp;`), Markdown (`**x**`), control and bidi characters (U+0000, U+202E, U+200F), and values at, one below and one above each limit with multi-scalar emoji and combining sequences at the boundary | Control and bidi characters are stripped with the Q4-16 / S4.7 function. **No tag removal and no parsing:** `<b>x</b>` and `&amp;` stay literal text, nothing is rendered as HTML or Markdown, nothing becomes a link. Rendered only with `Text(verbatim:)`. Truncated after cleaning, in grapheme clusters (an emoji or combining sequence is never split): `Overview` 2,000; `Taglines` at most 3, each 200; `Genres` at most 10, each 64; every other otherwise-unlimited server string (item, series, person, studio and library names) 200; `ServerName` and `PublicUser.name` 64 (Q4-16). Values come from the `MetadataPolicy` constants and the tests reference the constants; the layout does not break | S6.1 (PR #18 `e5edd3a`), Q4-16, Q6-18 | L, X, S |
| T06-74 | 🔒 Logs and diagnostics while using home | No token, no unredacted URL, no `ApiKey`; the CI grep check passes | S5, S5.4 | K, X |
| T06-75 | 🔒 Snapshot fixtures and CI artifacts of M06 runs | Mock data only; the artifact scan finds no token or secret | S5.5, 00 Artifacts | K |

## Image pipeline limits (added 2026-10-27, S6.6)
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T06-76 | 🔒 Image body streamed with no `Content-Length`, 25 MB | The download is aborted as soon as the counted bytes exceed 20 MB (`MetadataPolicy.imageMaxBytes`); nothing is cached; the card shows its placeholder | S6.6 (PR #18) | L, X |
| T06-77 | 🔒 Lying `Content-Length`: header says 1 MB, body is 25 MB | Aborted at the 20 MB byte count; `Content-Length` is never trusted as the guarantee | S6.6 (PR #18) | L, X |
| T06-78 | 🔒 `Content-Length` 30 MB | May be rejected early before the body; either way no more than 20 MB is ever read | S6.6 (PR #18) | X |
| T06-79 | 🔒 Decompression bomb: a small PNG/JPEG (< 1 MB) declaring 30,000 × 30,000 px as a poster and a backdrop | Decoded only through `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize`; the full bitmap is never decoded; memory stays within the P11 budget (no spike > 50 MB over baseline); no crash | S6.6 (PR #18), 02 P11 | X, M |
| T06-80 | 🔒 Downscale to display size: a 3840 × 2160 backdrop and a 2000 × 3000 poster | The thumbnail option dictionary has `kCGImageSourceThumbnailMaxPixelSize` = displayed size in pixels (× scale), `kCGImageSourceCreateThumbnailFromImageAlways`, `kCGImageSourceCreateThumbnailWithTransform`, `kCGImageSourceShouldCacheImmediately`; decoding is off the main thread | S6.6 (PR #18), 02 §4 | L, X |
| T06-81 | 🔒 Source check of `Apps/` and the image code | No `AsyncImage`, no `UIImage(data:)`, no `Image(uiImage: UIImage(data:))` | S6.6 (PR #18) | K |
| T06-82 | Image rejected by a limit or failing to decode | The card keeps its placeholder, the row and focus are unaffected, the URL is not logged unredacted | S6.6, S5, 05 §7 | X |

## Open questions
| # | Question | Spec wording | For |
|---|---|---|---|
| Q6-01 | Where is the default focus when both "Continue watching" and "Next Up" are empty? | 06 UP 1: "on the first card of the "Continue watching" row, or, if that row is empty, on the "Next Up" row" | Spesifikaatio |
| Q6-02 | Which `UserViews` collection types get a Latest row (movies, tvshows, homevideos, mixed, boxsets; music and Live TV excluded)? | 06 Sections: "one row per video library (`UserViews`)" | Spesifikaatio |
| Q6-03 | Is an item returned by both Resume and NextUp de-duplicated, and on which row is it kept? | 06 Sections: Resume and NextUp are separate requests | Spesifikaatio |
| Q6-04 | Is there a "See all" item at the end of a 20-item row in P0? | 02 v1.3.2: "Home rows: `limit=20` per row" | Spesifikaatio |
| Q6-05 | What is the exact title format of a Latest row ("Recently added in Movies" vs "Movies")? | 06 Sections: "Recently added (fi: "Viimeksi lisätyt") / library" | Spesifikaatio |
| Q6-06 | How is a grouped series item (`groupItems=true`) shown: series card with a count, or the newest episode? | 06 Sections: "`groupItems=true`" | Spesifikaatio |
| Q6-07 | What is the backdrop fallback when the focused item has no backdrop (parent backdrop, keep previous, neutral)? | 06 UP 3: "its backdrop changes subtly into the view's background" | Spesifikaatio |
| Q6-08 | Is "Go to series" hidden for movies, and what does it open for a Next Up episode? | 06 UP 5: ""Go to series" (fi: "Siirry sarjaan")" | Spesifikaatio |
| Q6-09 | Where does focus go when the focused row disappears completely during an update? | 06 Upd: "If the focused item leaves the row, focus moves to the neighboring item on the same row." | Spesifikaatio |
| Q6-10 | "Remove from Continue Watching": mark unplayed or only reset the position? Which UserData fields are sent? Confirmation? | 06 UP 5: "(= mark unplayed or reset the position; ⚠️ … to be verified)" | Spesifikaatio, Tutkija |
| Q6-11 | What does a failed section look like: a row-sized inline error with a focusable "Try again"? Where is focus after a retry? | 06 Sections: "One failed section shows its own error state" | Spesifikaatio |
| Q6-12 | What does Play/Pause do before M08 is merged (hook, disabled, message)? | 06 UP 4: "Play/Pause starts playback directly" | Koodari |
| Q6-13 | What is the guidance content and action of the empty state "Your library is empty"? | 06 Sections: "an empty state … is shown, plus guidance" | Spesifikaatio |
| Q6-14 | **RESOLVED (Spesifikaatio, PR #17, merged `a617f71`):** the full-screen server-down title is "Can't reach the server" (fi: "Palvelimeen ei saada yhteyttä"), one string key shared by 02 §3 and 04 Q4-10. Test T06-46 | 02 §3: "A full-screen state "Can't reach the server" … same string key as 04 Q4-10" | Spesifikaatio |
| Q6-15 | **DECIDED (PR #18, pending merge):** when the server goes down mid-browse, the content already shown stays visible and the `.serverUnreachable` banner appears; the full-screen state is used only when nothing is displayable. Tests T06-49, T06-50, T06-56 | 02 v1.3.4 (PR #18): "Server down while content is already on screen … stays visible … The full-screen "Server down" state above is used only when the current view has no content to show." | Spesifikaatio |
| Q6-16 | Which context menu items appear on Next Up and Latest cards ("Remove from Continue Watching" only on its own row)? | 06 UP 5 lists one menu for all cards | Spesifikaatio |
| Q6-17 🔒 | **RESOLVED (Turvallisuus + Spesifikaatio, PR #18, 03 S6.6):** image requests carry the `Authorization` header, never a token in the URL; `DiskImageCache` under a SHA-256 key of (server, item, type, tag, size); 20 MB cap counted during download without trusting `Content-Length`; decoded only via `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize`, downscaled to display size. Tests T06-71, T06-72, T06-76…T06-82 | 01 Auth (main): "Images: the endpoint does not require a token, so a token is not added." → replaced by S6.6 in PR #18 | Turvallisuus, Spesifikaatio |
| Q6-18 🔒 | **RESOLVED (locked in PR #18 `e5edd3a`, agreed by Turvallisuus and Spesifikaatio):** no tag stripping and no parsing; HTML shown verbatim as text; only control and bidi characters filtered; `Text(verbatim:)` only. Limits in grapheme clusters: `Overview` 2,000; `Taglines` 3 × 200; `Genres` 10 × 64; every other otherwise-unlimited string 200; `ServerName` and `PublicUser.name` 64 (Q4-16). Test T06-73 | S6.1 (main): "HTML tags are removed" → replaced in PR #18: "No tag removal and no parsing" | Turvallisuus, Spesifikaatio |
| Q6-19 | Does the 250 ms backdrop debounce also apply with Reduce Motion, and is the backdrop load covered by P4? | 06 UP 3: "Reduce Motion replaces the crossfade with an immediate change." | Spesifikaatio |
| Q6-20 | **RESOLVED (user 2026-10-27):** "Continue watching" and "Next Up" are separate home rows. Test T06-10 | 06 Sections (PR #18): "DECIDED (Q6-20, user 27.10.2026)" | user |
