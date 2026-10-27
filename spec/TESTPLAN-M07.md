# Test plan – M07 (library grid, movie detail and series view)

**Author:** Testaaja · 2026-10-27 · **Based on:** spec/07-library-detail.md, 02-state-errors-performance.md, 03-security.md, 05-design-system.md, 01-core.md, SPEC.md on `main` (`a617f71`, v1.3.3), and the pending spec PR #18 (`spec/m06-m07-m09-decisions`, head `61d944c`, incl. `e5edd3a`, v1.3.4) for S6.1, S6.6, 02 "Server down while content is already on screen" and Q7-25.
**Recovery note (2026-10-27):** the original file written earlier today was lost when `/workspace/jellyfin-tvos` was restored to an older state at 21:46 UTC. No copy survived on the box or on any GitHub branch, so this file was regenerated from the spec with the same IDs, sections and coverage, and the decisions made since then are applied.
**Environment:** Testaaja runs Linux. Mac tests run in CI (`test-tvos`, `test-ios`, `full-ui`), and Testaaja reads the artifacts (JUnit, PNG, coverage). Device tests are done by Koodari or the user (SPEC §8 R7).
**Work queue:** M07 depends on M01, M02, M05 and M06 (07 Dependencies). Branch `feat/m07-library-detail`.

**References:** `UC-Ln` = 07 use cases · `07 Grid` / `07 Detail` / `07 Series` / `07 Tech` / `07 HK` = 07 sections and acceptance criteria · `FSn` = 07 series focus rules · `02 §n` / `02 Pn` / `02 v1.3.4` = 02-state-errors-performance.md · `05 §n`, `L-n`, `G-n` = 05-design-system.md · `Sx.y` = 03-security.md.
**Run:** **L** = Linux `swift test` (GlassfinCore targets only: view models, URL building, paging, stores, `MetadataPolicy`) · **X** = macOS XCTest · **U** = macOS XCUITest (`XCUIRemote`, mock server `-uitest-mock-server`) · **S** = snapshot (1080p + 4K) · **I** = Linux Docker integration (`integration.yml`, 10.10.7 / 10.11.11 / 12.2) · **K** = review or CI lint script · **M** = manual device test.
**🔒** = raised to Turvallisuus (traceable to 03-security.md).
**UI strings and assertions:** expected UI texts are given as the English dev-language string (`Localizable.xcstrings`) with the Finnish localization in parentheses. X and L tests assert on state / error type or on the String Catalog key, never on a hardcoded string. U and S tests run in the `en` locale and identify elements by `accessibilityIdentifier` (`screen.element`) or catalog key.
**Subtitles:** no S6.4 row is included. The M07 tech row only lists subtitle languages from `MediaStreams` and does not download or parse subtitle files, so the S6.4 limits (10 MB, timeout) belong to M08.

## Library grid
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T07-01 | Open a movie library from the tab bar (UC-L1) | `GET /Items` with `parentId=<library>`, `includeItemTypes=Movie`, `recursive=true`, `sortBy=SortName`, `sortOrder=Ascending`, `startIndex=0`, `limit=50`, `fields=PrimaryImageAspectRatio`, `enableImageTypes=Primary`, `enableUserData=true` | UC-L1, 07 Grid | L |
| T07-02 | Open a TV library | Same request with `includeItemTypes=Series` | UC-L1, 07 Grid | L |
| T07-03 | Grid layout | `LazyVGrid` with 6 `PosterCard`s per row (2:3) at 1080p and 4K; the title is under the poster | 07 Grid, 05 §7 | S |
| T07-04 | Default focus | First poster on first open; the remembered item on returning from detail | 07 Grid, 02 §1 | U |
| T07-05 | Paging: 50 items loaded, focus reaches the item with 10 left | The next page is requested once (`startIndex=50`) and appended; no duplicates; focus does not jump | 07 Grid, 02 v1.3.2 | X, U |
| T07-06 | Fast scrolling triggers the paging threshold repeatedly | Only one page request is in flight at a time | 07 Grid | X |
| T07-07 | Last page (`TotalRecordCount` reached) | No further requests | 07 Grid | L |
| T07-08 | Library of 5,000 items scrolled to the end (mock) | All pages load; memory within P11; scrolling 60 fps | 07 HK, 02 P3, 02 P11 | X, M |
| T07-09 | Sort menu: name, date added, release date, rating, random | `sortBy` = `SortName` / `DateCreated` / `PremiereDate` / `CommunityRating` / `Random`; the list is fetched again from `startIndex=0`; focus to the first item | 07 Grid | L, U |
| T07-10 | Ascending / descending | `sortOrder` toggles; random sort hides the order choice and paging follows Q7-01 | 07 Grid, Q7-01 | L |
| T07-11 | Filters: watched / unwatched / favorites | `filters=IsPlayed` / `IsUnplayed` / `IsFavorite` added to the query | 07 Grid | L |
| T07-12 | Genre and year filters from `GET /Items/Filters2` | The filter menu shows the server's genres and years; the choice is sent as `genres=` / `years=` | 07 Grid | L, X |
| T07-13 | Choices saved per library | Sort and filter are kept per library ID after a restart; another library keeps its own choices; storage under the agreed key (Q7-14) | 07 Grid, Q7-14, 02 §2 | X |
| T07-14 | Item count | "124 movies" (fi: "124 elokuvaa") with `TotalRecordCount`; singular and plural from the String Catalog (Q7-13) | 07 Grid, Q7-13 | K, X |
| T07-15 | Filter with no results | Empty state with "Clear filters" (fi: "Tyhjennä suodattimet"), focus on the button (Q7-02) | 07 Grid, Q7-02 | U, S |
| T07-16 | Empty library | Empty state distinct from "no results" (Q7-02) | Q7-02 | S |
| T07-17 | Mixed library (`collectionType` empty or `mixed`) | Per Q7-03 (ASSUMPTION: `includeItemTypes=Movie,Series`) | Q7-03 | L |
| T07-18 | Watched badge and progress on posters | Watched check mark and progress bar from `UserData` | 05 §7 | S |
| T07-19 | Click a poster | Movie → movie detail; series → series view; Menu returns to the grid with focus on the same item | UC-L2, UC-L3, 02 §1 | U |
| T07-20 | Images in the grid | `maxWidth` = poster pixel width × scale; images outside the visible area are cancelled when scrolling past | 02 §4 | X |

## Movie detail
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T07-21 | Open movie detail (UC-L2) | `GET /Items/{id}` with the detail `fields` (Overview, Genres, People, Studios, Taglines, MediaStreams, MediaSources, ExternalUrls); one request | UC-L2, 07 Detail | L |
| T07-22 | HeroHeader | Backdrop, logo (falls back to the title as text), year, runtime, `OfficialRating`, `CommunityRating`, genres | 07 Detail, 05 §7 | S |
| T07-23 | Buttons without progress | "Play" (fi: "Toista") has default focus; "Favorite" and "Mark as played" next to it | 07 Detail | U |
| T07-24 | Buttons with progress | "Resume" (fi: "Jatka") with the remaining time has default focus and "Start over" (fi: "Aloita alusta") is next to it (Q7-15) | 07 Detail, Q7-15 | U, X |
| T07-25 | "Resume" | The play hook receives `startPositionTicks` from UserData | 07 Detail | X |
| T07-26 | "Start over" | The play hook receives position 0; UserData is not changed before playback (Q7-15) | 07 Detail, Q7-15 | X |
| T07-27 | "Mark as played" / "Mark as unplayed" | Optimistic update through `UserDataStore`, `POST` / `DELETE /UserPlayedItems/{id}`; the button label toggles; restored on error | 07 Detail, 02 §1 | X |
| T07-28 | "Favorite" | `POST` / `DELETE /UserFavoriteItems/{id}`; state toggled optimistically | 07 Detail | X |
| T07-29 | Change in detail, then back to the grid and home | The grid badge and the home rows show the new state at once (shared `UserDataStore`) | 02 §1 | X, U |
| T07-30 | Overview: long text | Shown truncated with "More" (fi: "Lisää"); a click opens the full text in a sheet; Menu closes it and focus returns | 07 Detail | U |
| T07-31 | Cast row | `People` as round portraits with name and role; missing portraits get initials; focusable per Q7-16 | 07 Detail, Q7-16 | S, U |
| T07-32 | Tech row: video | Resolution (4K / 1080p), HDR label (HDR10, HDR10+, Dolby Vision, HLG) from the default video stream `VideoRangeType` (Q7-22) | 07 Tech, Q7-22 | L |
| T07-33 | Tech row: audio | Codec and channels of the default audio stream: "DTS-HD MA 7.1", "Dolby Atmos", "AAC 2.0" | 07 Tech | L |
| T07-34 | Tech row: subtitles | Subtitle languages from `MediaStreams` (`Type=Subtitle`), de-duplicated; no subtitle file is downloaded | 07 Tech | L |
| T07-35 | Tech row fixtures: HDR10 HEVC, Dolby Vision profile 8.1, DTS-HD MA 7.1, SDR AAC stereo | Every fixture gives the expected label set; unknown values give no label instead of a crash | 07 Tech, 07 HK | L |
| T07-36 | Multiple versions (`MediaSources` > 1) | Per Q7-06 (ASSUMPTION: the first source's tech row, no version picker in P0) | Q7-06 | L |
| T07-37 | Trailers (`RemoteTrailers` / `LocalTrailerCount`) | Not shown in P0 (Q7-18) | Q7-18 | X |
| T07-38 | 🔒 `ExternalUrls` (IMDb, TMDb) | Not opened and not rendered as links; no `openURL` | S6.2 | K, X |
| T07-39 | Focus order on movie detail | Down from the buttons goes to Overview "More", then the cast row; Up returns to the buttons; no focus trap | 07 Detail, 05 §8 | U |
| T07-40 | Glass on movie detail | Only the button group is glass (within the 07 glass budget); the HeroHeader text sits on the gradient | 07 Detail, G-2, L-1 | S, K |

## Series view
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T07-41 | Open a series (UC-L3) | `GET /Items/{id}` and `GET /Shows/{id}/Seasons` (with `enableUserData=true`) in parallel | UC-L3, 07 Series | L |
| T07-42 | Episodes of the selected season | `GET /Shows/{id}/Episodes?seasonId=<season>` with `fields=Overview`, `enableUserData=true` | 07 Series | L |
| T07-43 | **Q7-25 DECIDED (user 2026-10-27):** series with 5 seasons | Episodes are shown **one season at a time** with a season picker; only the selected season's episodes are fetched and shown; there is no continuous list of all seasons | 07 Series (PR #18), Q7-25 | X, U, S |
| T07-44 | Switching seasons in the picker | The episode list is replaced by the selected season; the previous season's request is cancelled if still running; the result is cached for the view's lifetime | 07 Series, Q7-25 | X |
| T07-45 | Default season (FS1) | The season of the next unwatched episode, or the first season if nothing is watched | FS1 | X, U |
| T07-46 | Default focus (FS2) | The next unwatched episode (or the one in progress); otherwise "Play" | FS2 | U |
| T07-47 | Fully watched series | Default season and focus per Q7-07 (ASSUMPTION: first season, first episode); label per Q7-07 | Q7-07 | X |
| T07-48 | Down from the season picker (FS3) | Focus goes to the first visible episode of the season, not to the geometrically nearest one | FS3 | U |
| T07-49 | Up from the episode list (FS4) | Focus returns to the selected season in the picker | FS4 | U |
| T07-50 | Season change does not move focus to the top (FS5) | Focus stays in the picker while seasons change | FS5 | U |
| T07-51 | Return from playback or episode detail (FS6) | Focus returns to the same episode; after the last episode of a season, per Q7-08 | FS6, Q7-08 | U |
| T07-52 | Episode card | Thumbnail, `SxEy`, name, runtime, watched check mark or progress bar, two lines of Overview | 07 Series, 05 §7 | S |
| T07-53 | Click an episode | Per Q7-20 (ASSUMPTION: opens episode detail; Play/Pause plays directly) | 07 Series, Q7-20 | U |
| T07-54 | Season "Specials" (season 0) | Shown last in the picker, with the name "Specials" (fi: "Erikoisjaksot") per Q7-17 | 07 Series, Q7-17 | X, S |
| T07-55 | Empty or virtual seasons (no episodes on disk) | Per Q7-09 (ASSUMPTION: hidden) | Q7-09 | X |
| T07-56 | Season with 150 episodes | Paging per Q7-10; scrolling 60 fps | Q7-10, 02 P3 | X |
| T07-57 | "Mark as played" on a season | All episodes of the season are marked optimistically; Next Up updates | 07 Series | X |
| T07-58 | Series "Play" / "Resume" | Starts the next-up episode (or the one in progress) at its resume position | 07 Series | X |
| T07-59 | Skeletons | Skeleton cards while seasons and episodes are loading; no layout jump when data arrives | 07 Series, 05 §7 | S |
| T07-60 | Glass budget on the series view | At most the agreed number of glass surfaces (picker and buttons); Reduce Transparency makes them opaque | 07 Series, G-2, 05 §5 | S, K |
| T07-61 | Series backdrop and logo | Backdrop behind the view; logo or title as text; legible on bright and dark backdrops | 07 Series, L-1 | S |
| T07-62 | Snapshot: series view × {1080p, 4K} × {default, Reduce Transparency} | PNGs in the artifacts | 07 HK | S |

## Errors and connectivity
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T07-63 | **Q7-19 (decided in PR #18, pending merge):** the server goes down while the grid or a detail view is on screen | The content already shown stays visible, `connectivity = .serverUnreachable` and the banner appears; the full-screen state is **not** shown | 02 v1.3.4 (PR #18), Q7-19 | X, U |
| T07-64 | Server down when opening a view with nothing displayable (no cache) | Full-screen "Can't reach the server" (fi: "Palvelimeen ei saada yhteyttä") with the shared key, "Try again" and "Change server" | 02 §3 (PR #17), Q4-10 | X, U |
| T07-65 | Paging request fails (500 or timeout) at the end of the grid | Loaded items stay; a "Try again" item at the end of the grid; no automatic loop (Q7-04) | Q7-04, 02 §3 | X, U |
| T07-66 | `GET /Items/{id}` returns 404 (item deleted) | "This item is no longer available" (fi: "Kohdetta ei enää ole") with a way back; it is removed from the grid (Q7-11) | 02 §3, Q7-11 | X |
| T07-67 | 401 on any M07 request | All requests are cancelled, the token removed, sign-in opens once with the session-expired message | 02 §3 (PR #17), S2.2 | X |
| T07-68 | 403 on an action | Inline "You don't have permission to do this" (fi: "Ei oikeuksia tähän toimintoon"); state restored; not signed out | 02 §3 (PR #17) | X |
| T07-69 | Network drops on the grid or a detail view | `GlassBanner` "No network connection" within ≤ 2 s; content stays browsable; playback blocked with a message | 02 §3 | U |
| T07-70 | `Filters2` fails | The filter menu shows only the built-in filters (watched / unwatched / favorites); the grid works (Q7-12) | Q7-12 | X |
| T07-71 | Unexpected JSON: one broken item on a grid page | The item is skipped; the page and the paging offset stay correct | 02 §3 | X |
| T07-72 | 502 / 503 / 504 on a GET | Retried twice (0.5 s, 1.5 s), then `serverUnreachable` | 02 §3, 02 v1.3.2 | X |

## Performance and visual regression
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T07-73 | Open a library → first posters visible (LAN) | P2 ≤ 1.0 s / ≤ 2.0 s p95 | 02 P2, 07 HK | X, M |
| T07-74 | Scrolling a 1,000-item grid | 60 fps, hitch ratio < 5 ms/s (A15), < 10 ms/s (oldest) | 02 P3, 07 HK | X, M |
| T07-75 | Open movie or series detail | Content within ≤ 1.0 s; backdrop visible within P4 (≤ 100 ms cached / ≤ 500 ms network) | 02 P2, 02 P4 | X, M |
| T07-76 | Snapshot matrix: grid, movie detail × {1080p, 4K} × {default, Reduce Transparency, long texts} | PNGs in the artifacts; no truncation errors | 07 HK, 05 §5 | S |

## Security
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T07-77 | 🔒 Untrusted metadata on the grid, movie detail and series view: `Name`, `OriginalTitle`, `Overview`, `Taglines`, `Genres`, `People[].Name` and `Role`, `Studios`, episode and season names, `OfficialRating` and `MediaStreams` display titles containing HTML (`<b>x</b>`, `<script>`, `&amp;`), Markdown (`**x**`, `[x](y)`), control and bidi characters (U+0000, U+202E, U+200F), and values at, one below and one above each limit with multi-scalar emoji and combining sequences at the boundary; 15 taglines and 40 genres | Control and bidi characters are stripped with the Q4-16 / S4.7 function. **No tag removal and no parsing:** HTML and Markdown stay literal text and nothing becomes a link. Rendered only with `Text(verbatim:)`. Truncated after cleaning, in grapheme clusters: `Overview` 2,000; `Taglines` at most 3, each 200 (only 3 of 15 shown); `Genres` at most 10, each 64 (only 10 of 40 shown); every other otherwise-unlimited server string 200; `ServerName` and `PublicUser.name` 64 (Q4-16). Values come from the `MetadataPolicy` constants and the tests reference the constants; the HeroHeader layout and the buttons stay reachable | S6.1 (PR #18 `e5edd3a`), Q4-16, Q7-24 | L, X, S |
| T07-78 | 🔒 Images (posters, backdrops, logos, thumbnails, cast portraits) | `Authorization` header only, never a token in the URL; `DiskImageCache` key = SHA-256 of (server ID, item ID, type, tag, size); 20 MB cap counted during download; thumbnail decode only | S6.6 (PR #18), Q7-23 | L, X |
| T07-79 | 🔒 Filter and sort parameters | Built with `URLComponents` / `URLQueryItem`; genre names with `&`, `=`, `#`, `/` and `ä` are encoded; no string concatenation of paths | S6.5 | L |

## Image pipeline limits (added 2026-10-27, S6.6)
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T07-80 | 🔒 4K backdrop (3840 × 2160) and a 6000 × 9000 poster on the detail view | Decoded via `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize` = displayed size × scale; the full bitmap is never decoded | S6.6 (PR #18), 02 §4 | L, X |
| T07-81 | 🔒 Backdrop streamed over 20 MB, without `Content-Length` and with a lying `Content-Length` (1 MB) | Aborted when the counted bytes exceed 20 MB; nothing cached; the detail view shows the backdrop fallback; the buttons and focus are unaffected | S6.6 (PR #18) | X |
| T07-82 | 🔒 Decompression bomb as a logo and a backdrop (small file, 30,000 × 30,000 px) | Memory stays within the P11 budget; no crash; the logo falls back to the title as text | S6.6 (PR #18), 02 P11 | X, M |

## Open questions
| # | Question | Spec wording | For |
|---|---|---|---|
| Q7-01 | How does paging work with random sort (does each page re-randomize; duplicates)? | 07 Grid: "random" in the sort list | Spesifikaatio, Tutkija |
| Q7-02 | What do the empty library and the "no results" states look like, and where is focus? | 07 Grid does not define empty states | Spesifikaatio |
| Q7-03 | Which `includeItemTypes` does a mixed library use? | 07 Grid: movie and TV libraries only | Spesifikaatio |
| Q7-04 | What does a failed paging request look like (retry item, automatic retry)? | 07 Grid: "paging when 10 remain" | Spesifikaatio |
| Q7-05 | Is audio and subtitle preselection shown on the detail view in P0? | 07 Detail lists only the tech row | Spesifikaatio |
| Q7-06 | How are multiple versions (`MediaSources` > 1) shown? | Not covered | Spesifikaatio |
| Q7-07 | Default season, focus and label for a fully watched series? | FS1: "the season of the next unwatched episode" | Spesifikaatio |
| Q7-08 | Where does focus go after returning from the last episode of a season? | FS6: "to the same episode" | Spesifikaatio |
| Q7-09 | Are empty or virtual (missing) seasons and episodes shown? | Not covered | Spesifikaatio |
| Q7-10 | Are episodes paged in a season with more than N episodes? | 07 Series: no paging mentioned | Spesifikaatio |
| Q7-11 | What happens on a 404 for a deleted item (message, removal from the grid)? | 02 §3 has no 404 row | Spesifikaatio |
| Q7-12 | What does the filter menu show when `Filters2` fails? | 07 Grid: "genres and years from `/Items/Filters2`" | Spesifikaatio |
| Q7-13 | Plural forms and format of the item count? | 07 Grid: "124 movies" | Spesifikaatio |
| Q7-14 | Storage key and size budget of saved per-library choices (UserDefaults < 50 KB)? | 07 Grid: "saved per library"; 02 §2 budget | Spesifikaatio |
| Q7-15 | "Start over": does it reset UserData, or only start at 0? | 07 Detail: "Start over" | Spesifikaatio |
| Q7-16 | Are cast portraits focusable in P0 (and where does a click go)? | 07 Detail: "Cast row" | Spesifikaatio |
| Q7-17 | Specials season name and order? | 07 Series: "Specials last" | Spesifikaatio |
| Q7-18 | Are trailers shown in P0? | Not covered | Spesifikaatio |
| Q7-19 | **DECIDED (PR #18, pending merge):** when the server goes down mid-browse, the content already shown stays visible and the `.serverUnreachable` banner appears; the full-screen state only when nothing is displayable. Tests T07-63, T07-64 | 02 v1.3.4 (PR #18): "Server down while content is already on screen" | Spesifikaatio |
| Q7-20 | Does a click on an episode play it or open episode detail? | 07 Series | Spesifikaatio |
| Q7-21 | Are BoxSets (collections) shown in the movie grid? | Not covered | Spesifikaatio |
| Q7-22 | Mapping of `VideoRangeType` values to the HDR label (DOVIWithHDR10, HDR10Plus, HLG)? | 07 Tech: "HDR label" | Spesifikaatio, Tutkija |
| Q7-23 🔒 | **RESOLVED (Turvallisuus + Spesifikaatio, PR #18, 03 S6.6):** `Authorization` header only, never a token in the URL; `DiskImageCache` under SHA-256 of (server, item, type, tag, size); 20 MB cap counted during download, `Content-Length` never trusted; decode only via `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize`. Tests T07-78, T07-80…T07-82 | S6.6 (PR #18) | Turvallisuus, Spesifikaatio |
| Q7-24 🔒 | **RESOLVED (locked in PR #18 `e5edd3a`, agreed by Turvallisuus and Spesifikaatio):** no tag stripping and no parsing; HTML shown verbatim as text; only control and bidi characters filtered; `Text(verbatim:)` only. Limits in grapheme clusters: `Overview` 2,000; `Taglines` 3 × 200; `Genres` 10 × 64; every other otherwise-unlimited string 200; `ServerName` and `PublicUser.name` 64 (Q4-16). Test T07-77 | S6.1 (PR #18 `e5edd3a`) | Turvallisuus, Spesifikaatio |
| Q7-25 | **RESOLVED (user 2026-10-27):** episodes are shown one season at a time with a season picker. Tests T07-43, T07-44 | 07 Series (PR #18): "DECIDED (Q7-25, user 27.10.2026)" | user |
