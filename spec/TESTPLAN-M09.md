# Test plan – M09 (search)

**Author:** Testaaja · 2026-10-27 · **Based on:** spec/09-search.md, 02-state-errors-performance.md, 03-security.md, 05-design-system.md, 01-core.md, SPEC.md on `main` (`a617f71`, v1.3.3), and the pending spec PR #18 (`spec/m06-m07-m09-decisions`, head `61d944c`, incl. `e5edd3a`, v1.3.4) for S6.1, S6.6, S6.7, the recent-searches limit and the Q9-01 default.
**Recovery note (2026-10-27):** the original file written earlier today was lost when `/workspace/jellyfin-tvos` was restored to an older state at 21:46 UTC. No copy survived on the box or on any GitHub branch, so this file was regenerated from the spec with the same IDs, sections and coverage, and the decisions made since then are applied.
**Environment:** Testaaja runs Linux. Mac tests run in CI (`test-tvos`, `test-ios`, `full-ui`), and Testaaja reads the artifacts (JUnit, PNG, coverage). Device tests are done by Koodari or the user (SPEC §8 R7). The endpoint benchmark (T09-21) and the seeded-item check (T09-22) run in the Docker integration job.
**Work queue:** M09 depends on M01, M02, M05, M06 and M07 (09 Dependencies). Branch `feat/m09-search`.

**References:** `SRn` = 09 search rules · `09 Input` / `09 Results` / `09 Recent` / `09 HK` = 09 sections and acceptance criteria · `02 §n` / `02 Pn` / `02 v1.3.4` = 02-state-errors-performance.md · `05 §n`, `G-n` = 05-design-system.md · `Sx.y` = 03-security.md.
**Run:** **L** = Linux `swift test` (GlassfinCore targets only: view models, URL building, paging, stores, `MetadataPolicy`) · **X** = macOS XCTest · **U** = macOS XCUITest (`XCUIRemote`, mock server `-uitest-mock-server`) · **S** = snapshot (1080p + 4K) · **I** = Linux Docker integration (`integration.yml`, 10.10.7 / 10.11.11 / 12.2) · **K** = review or CI lint script · **M** = manual device test.
**🔒** = raised to Turvallisuus (traceable to 03-security.md).
**UI strings and assertions:** expected UI texts are given as the English dev-language string (`Localizable.xcstrings`) with the Finnish localization in parentheses. X and L tests assert on state / error type or on the String Catalog key, never on a hardcoded string. U and S tests run in the `en` locale and identify elements by `accessibilityIdentifier` (`screen.element`) or catalog key.

## Input
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T09-01 | Open the Search tab | `.searchable` field with the system keyboard; focus on the field; recent searches shown below it (if any) | 09 Input | U |
| T09-02 | Type "star" | One request 300 ms after the last character (debounce), not one per character | 09 Input, SR2 | X |
| T09-03 | One character "s" (Latin) | No request (minimum 2 characters); recent searches stay visible | SR3 | L, X |
| T09-04 | Two characters "st" | A request is sent | SR3 | L |
| T09-05 | One CJK character "日" | A request is sent (CJK minimum 1, detection per Q9-11) | SR3, Q9-11 | L |
| T09-06 | Only whitespace "   " | No request; leading and trailing whitespace trimmed before the length check (Q9-02) | SR3, Q9-02 | L |
| T09-07 | 20 characters typed quickly (< 300 ms apart) | Exactly one request, for the final text | SR2, 09 HK | X |
| T09-08 | Very long query (500 characters) | Capped per Q9-03 (ASSUMPTION: 100 graphemes) before the request; no crash | Q9-03 | L |
| T09-09 | Clear the field | Results disappear, recent searches are shown, any in-flight request is cancelled | 09 Input, SR1 | X, U |
| T09-10 | Siri dictation into the field | Handled like typing (debounce, minimum length) | 09 Input | M |
| T09-11 | Keyboard and results on screen together | The results grid is below the keyboard and reachable with Down; Up returns to the keyboard | 09 Results, 05 §8 | U |
| T09-12 | Leaving the tab and coming back | The query and results are kept per Q9-04 (ASSUMPTION: kept for the app session) | Q9-04 | U |

## Race conditions and cancellation
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T09-13 | New text while a request is in flight | The previous `Task` is cancelled before the new one starts (SR1) | SR1 | X |
| T09-14 | Responses arrive in reverse order: s / st / sta / star, mock answers "star" first and "s" last | Only the "star" results are shown; late responses are discarded | SR1, 09 HK | X |
| T09-15 | Response for an old query after the field was cleared | Discarded; the recent searches stay | SR1 | X |
| T09-16 | Cancelled request | `.cancelled` is never shown to the user and never counted as an error | 02 §3, SR1 | X |
| T09-17 | The three parallel `/Items` requests of one query | All three are cancelled together when the query changes; no partial mix of two queries in the rows | SR1, Q9-01 | X |
| T09-18 | Leaving the Search tab during a request | The request is cancelled (`.task`) | 02 §1 | X |
| T09-19 | Same query typed again ("star" → "sta" → "star") | Per the debounce only the final "star" is sent; the result is identical | SR2 | X |
| T09-20 | Focus in the results while a new response arrives | Focus does not jump to the top unless the focused item disappeared | 09 Results, SR4 | U |

## API and endpoint choice
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T09-21 | Endpoint benchmark on the Docker servers (10.10.7, 10.11.11, 12.2): `/Items` × 3 in parallel vs `/Search/Hints`, alternating paired samples, the same seeded library and query set | p50 and p95 per server version written to the CI artifact; the output contains no query text, no token and no URL with parameters | Q9-01, 09 Results (PR #18) | I |
| T09-22 | Seeded item with "ä" in its name ("Hämärä") on all 3 Docker servers | Found with the query "hämä" through both `/Items` and `/Search/Hints` | Q9-01, 09 HK | I |
| T09-23 | Default request set (`/Items` × 3) | Three parallel `GET /Items` with `searchTerm`, `recursive=true`, `limit=24`, `enableUserData=true`, `fields=PrimaryImageAspectRatio` and `includeItemTypes=Movie` / `Series` / `Episode` respectively | 09 Results (PR #18), Q9-01 | L |
| T09-24 | Alternative `/Search/Hints` request (implemented only if the ADR switches) | `GET /Search/Hints` with `searchTerm`, `limit`, `includeItemTypes=Movie,Series,Episode`; the mapping to the same row model | 09 Results, Q9-01 | L |
| T09-25 | **Q9-01 (decided in PR #18, pending merge):** endpoint in use | The default is 3 parallel `/Items` requests. `/Search/Hints` is used only if the T09-21 benchmark shows it clearly faster on all 3 CI server versions and an ADR records it; the test checks that the code matches the ADR in force | 09 Results (PR #18), Q9-01 | L, K |
| T09-26 | 🔒 Query encoding: `&`, `#`, `=`, `+`, `/`, `%`, `?`, `ä`, `日本`, an emoji | Sent as one `searchTerm` value via `URLQueryItem` (percent-encoded); no extra parameters; the server receives the exact text | S6.5, 09 HK | L, I |
| T09-27 | 🔒 No string concatenation for search URLs | `URLComponents` only; the source check finds no interpolation of the query into a path | S6.5 | K |
| T09-28 | Result order | Within a row the server's order is kept; no client-side reordering | 09 Results | L |
| T09-29 | One of the three requests fails (500) | The other rows are shown; the failed row shows its own error or is hidden per Q9-05 | 09 Results, Q9-05 | X |
| T09-30 | P1 rows (people, collections, music) | Not shown in P0 (Q9-13) | 09 Results, Q9-13 | X |

## Results and focus
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T09-31 | Results for "star" (mock with movies, series and episodes) | Grouped rows "Movies" (fi: "Elokuvat"), "Series" (fi: "Sarjat"), "Episodes" (fi: "Jaksot") in this order | 09 Results | U, S |
| T09-32 | A group with no results | The row is hidden; no empty header | 09 Results | X, S |
| T09-33 | No results at all | "No results for “xyz”" (fi: "Ei tuloksia haulle “xyz”"), the query shown as verbatim text | SR5, 09 HK | U, S |
| T09-34 | Loading state | A progress indicator or skeleton row while the first response is pending; old results are not shown for a new query | 09 Results | S |
| T09-35 | Movie and series result cards | `PosterCard` with title and year | 09 Results, 05 §7 | S |
| T09-36 | Episode result card | `LandscapeCard` with the series name, `SxEy` and the episode name | 09 Results, 05 §7 | S |
| T09-37 | Click on a movie or series result | Opens M07 movie detail or the series view; Menu returns to search with the same query and focus (SR4) | SR4, 02 §1 | U |
| T09-38 | Click on an episode result | Per Q9-12 (ASSUMPTION: the series view on that episode's season, the episode focused) | Q9-12 | U |
| T09-39 | Play/Pause on a result | Plays directly (movie, episode) like on home | 09 Results | X |
| T09-40 | Focus memory between rows | Down and Up between rows returns to the remembered item | 05 §7 | U |
| T09-41 | A row with 24 results | All 24 shown; no "See more" in P0 (Q9-16) | 09 Results, Q9-16 | X |
| T09-42 | Glass on the search view | Only system components (keyboard, field) and the banner are glass; results are content | G-2 | S, K |

## Recent searches
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T09-43 | A query is saved | Saved when a result is opened, or per Q9-06 (ASSUMPTION: on opening a result, not on each debounce) | 09 Recent, S6.7 (PR #18), Q9-06 | X |
| T09-44 | Limit | At most 20 entries (`MetadataPolicy.recentSearchesMax = 20`); the 21st removes the oldest | S6.7 (PR #18), 09 Recent (PR #18) | L |
| T09-45 | Order | Most recent first | 09 Recent | L |
| T09-46 | Duplicates | The same query again moves it to the top, no duplicate; comparison per Q9-07 (ASSUMPTION: trimmed, case-insensitive) | 09 Recent, Q9-07 | L |
| T09-47 | Scope | Stored per server ID and user ID; another user or server does not see them | S6.7 (PR #18) | L, X |
| T09-48 | 🔒 Storage location | A file in Application Support (excluded from backup); not in the Keychain, not in UserDefaults | S6.7 (PR #18) | X, K |
| T09-49 | 🔒 Stored content | Query text only: no token, no URL, no server address, no item IDs | S6.7 (PR #18) | L |
| T09-50 | 🔒 Not logged | Neither saving nor reading logs the query text (log capture) | S6.7 (PR #18), S5 | X, K |
| T09-51 | 🔒 Sign-out | The signed-out user's recent searches on that server are deleted | S6.7 (PR #18), 04 sign-out | X |
| T09-52 | 🔒 Server removal | All recent searches of the removed server are deleted | S6.7 (PR #18) | X |
| T09-53 | Clear by the user | "Clear recent searches" (fi: "Tyhjennä viimeisimmät haut") removes all; UX per Q9-08 | 09 Recent, Q9-08 | U, X |
| T09-54 | 🔒 Not synced | Not in iCloud key-value storage or CloudKit; not sent to the server | S6.7 (PR #18) | K |
| T09-55 | Persistence and corruption | Kept after a restart; a corrupt or oversize file is discarded without a crash and the list starts empty | S6.7 (PR #18), 02 §2 | X |

## Errors and connectivity
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T09-56 | Offline when searching | `GlassBanner` "No network connection"; no request; recent searches stay usable for filling the field (Q9-09) | 02 §3, Q9-09 | U, X |
| T09-57 | Server down with results already shown | The results stay visible with the `.serverUnreachable` banner (PR #18) | 02 v1.3.4 (PR #18) | X |
| T09-58 | Server down with nothing displayable | Per Q9-10 (ASSUMPTION: an inline message in the results area instead of the full-screen state, so the field stays usable) | 02 §3, Q9-10 | X, U |
| T09-59 | 401 during search | Requests are cancelled, the token removed, sign-in opens once with the session-expired message | 02 §3 (PR #17), S2.2 | X |
| T09-60 | 502 / 503 / 504 | The GET is retried twice (0.5 s, 1.5 s) only if the query is still current | 02 §3, SR1 | X |
| T09-61 | Unexpected JSON: a broken item in a response | The item is skipped and the rest is shown | 02 §3 | X |

## Performance
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T09-62 | Last character → results visible (LAN, 10,000-item mock library) | P10 ≤ 500 ms (A15) / ≤ 1,000 ms (oldest), measured from the end of the debounce | 02 P10, 09 HK | X, M |
| T09-63 | Typing and scrolling results | 60 fps while typing; memory within P11 | 02 P3, 02 P11 | X, M |

## Security
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T09-64 | 🔒 Untrusted metadata in search results: `Name`, `SeriesName`, `ProductionYear` text, `Overview`, `Genres`, person names and `Role`, containing HTML (`<b>x</b>`, `<script>`, `&amp;`), Markdown, control and bidi characters (U+0000, U+202E, U+200F), and values at, one below and one above each limit with multi-scalar emoji and combining sequences at the boundary | Control and bidi characters are stripped with the Q4-16 / S4.7 function. **No tag removal and no parsing:** HTML and Markdown stay literal text; no highlighting that parses the name. Rendered only with `Text(verbatim:)`. Truncated after cleaning, in grapheme clusters: `Overview` 2,000; `Taglines` at most 3, each 200; `Genres` at most 10, each 64; every other otherwise-unlimited server string (names) 200; `ServerName` and `PublicUser.name` 64 (Q4-16). Values come from the `MetadataPolicy` constants; result cards keep their layout | S6.1 (PR #18 `e5edd3a`), Q4-16, Q9-14 | L, X, S |
| T09-65 | 🔒 Result images | `Authorization` header only, never a token in the URL; `DiskImageCache` key = SHA-256 of (server ID, item ID, type, tag, size); 20 MB cap counted during download; thumbnail decode only | S6.6 (PR #18), Q9-15 | L, X |
| T09-66 | 🔒 The search term is not logged | No query text in logs, os_signpost names or crash breadcrumbs; URLs are logged without the query | S5, S6.7 (PR #18) | X, K |
| T09-67 | 🔒 CI artifacts of M09 runs and benchmark output | No query text, no token, no URL with parameters; the artifact scan passes | S5.5, Q9-01 | K |

## Image pipeline limits (added 2026-10-27, S6.6)
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T09-68 | 🔒 Result thumbnails from large sources (3840 × 2160 backdrop as an episode thumb, 6000 × 9000 poster) | Decoded via `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize` = card size × scale; the full bitmap is never decoded | S6.6 (PR #18), 02 §4 | L, X |
| T09-69 | 🔒 A result image over 20 MB (streamed, or with a lying `Content-Length`) and a decompression bomb | That card shows its placeholder; the rest of the row and focus are unaffected; memory within P11; no crash | S6.6 (PR #18), 02 P11 | X |

## Open questions
| # | Question | Spec wording | For |
|---|---|---|---|
| Q9-01 | **DECIDED (PR #18, pending merge):** the default is 3 parallel `/Items` requests (Movie, Series, Episode). Switch to `/Search/Hints` only if it is clearly faster on all 3 CI server versions (T09-21), recorded in an ADR. Tests T09-21…T09-25 | 09 Results (PR #18): "default: three parallel `/Items` requests … `/Search/Hints` only if … ADR" | Spesifikaatio, Koodari |
| Q9-02 | Is whitespace trimmed before the minimum-length check and before sending? | SR3: "minimum 2 characters" | Spesifikaatio |
| Q9-03 | Maximum query length? | Not covered | Spesifikaatio, Turvallisuus |
| Q9-04 | Are the query and results kept when the user leaves the tab and returns? | Not covered | Spesifikaatio |
| Q9-05 | What does a row whose request failed look like (hidden, inline error)? | Not covered | Spesifikaatio |
| Q9-06 | When is a query saved to recent searches (on opening a result, on submit)? | 09 Recent: "recent searches" | Spesifikaatio |
| Q9-07 | Duplicate rule for recent searches (case, whitespace, diacritics)? | Not covered | Spesifikaatio |
| Q9-08 | How does the user clear recent searches (one entry, all, confirmation)? | Not covered | Spesifikaatio |
| Q9-09 | What does search show offline? | 02 §3 offline row | Spesifikaatio |
| Q9-10 | Server down with nothing displayable on search: full-screen state or inline message? | 02 §3 full-screen state | Spesifikaatio |
| Q9-11 | How is CJK detected for the 1-character minimum (Unicode script of the first character, Hangul and Kana included)? | SR3: "(CJK 1)" | Spesifikaatio |
| Q9-12 | Where does a click on an episode result go? | Not covered | Spesifikaatio |
| Q9-13 | Are people, collections and music rows shown in P0? | 09 Results: P1 | Spesifikaatio |
| Q9-14 🔒 | **RESOLVED (locked in PR #18 `e5edd3a`, agreed by Turvallisuus and Spesifikaatio):** metadata: no tag stripping and no parsing, HTML verbatim as text, only control and bidi characters filtered, `Text(verbatim:)` only; grapheme limits `Overview` 2,000, `Taglines` 3 × 200, `Genres` 10 × 64, every other otherwise-unlimited string 200, `ServerName` and `PublicUser.name` 64 (Q4-16). Recent searches: max 20, in Application Support, query text only (no tokens or URLs), cleared on sign-out and on server removal, not synced, not logged. Reference 03 S6.1, S6.6, S6.7 (PR #18). Tests T09-43…T09-55, T09-64 | S6.1 / S6.7 (PR #18 `e5edd3a`) | Turvallisuus, Spesifikaatio |
| Q9-15 🔒 | **RESOLVED (Turvallisuus + Spesifikaatio, PR #18, 03 S6.6):** `Authorization` header only, never a token in the URL; `DiskImageCache` under SHA-256 of (server, item, type, tag, size); 20 MB cap counted during download, `Content-Length` never trusted; decode only via `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize`. Tests T09-65, T09-68, T09-69 | S6.6 (PR #18) | Turvallisuus, Spesifikaatio |
| Q9-16 | Is there a "See more" for a row with more than 24 results? | Not covered | Spesifikaatio |
