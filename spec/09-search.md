# M09 – Search (P0)

**Spec version:** v1.3.3 (22.10.2026). Changes are shown in SPEC.md's change history.

**Dependencies:** M01, M02, M05, and M07. **iOS UI:** P1.

## Pain point
"Search is buggy: characters disappear and results overlap." The cause is probably a race in which an old request's response overwrites a newer one, plus the text field's state being reset on a re-render.

## User path
1. The Search tab (fi: "Haku") → the system's `.searchable` keyboard (tvOS's native row keyboard; dictation and the iPhone keyboard also work automatically).
2. Typing → a 300 ms debounce → results grouped into rows: "Movies" (fi: "Elokuvat"), "Series" (fi: "Sarjat"), "Episodes" (fi: "Jaksot"), "People" (fi: "Henkilöt") (P1), "Music" (fi: "Musiikki") (P1, once M12 is done).
3. Down from the keyboard → to the result rows (the rows are `focusSection` regions). A click → detail. Back returns to search, and the text and the results are kept.
4. An empty search field: recent searches (max 20, per server ID + user ID, Application Support, deleted on sign-out, clearable; 03 S6.7) and P1 suggestions.

## API
- `GET /Items?searchTerm=<q>&recursive=true&includeItemTypes=Movie,Series,Episode&limit=24&fields=PrimaryImageAspectRatio&enableUserData=true`. Separate parallel requests are made for movies, series, and episodes, so that each row gets its own limit.
- Alternative: `GET /Search/Hints?searchTerm=&includeItemTypes=&limit=` (lighter). **The Coder measures** the LAN latency of both in a library of 5,000 items and chooses the faster one, as long as the results contain the needed image tags. **Default until measured (v1.3.4): the three parallel `/Items` requests.** Switch to `/Search/Hints` only if the measurement shows it is clearly faster on all three CI server versions; record the result in an ADR.
- Note: Jellyfin 12.0 has plugin-extensible search providers, so the order of results can vary by server. The client does not re-sort results, except that it groups them by type.

## Requirements
- **SR1** Every new input cancels the previous in-flight search (`Task.cancel()`), and only the latest search term's results are shown (the term is attached to the response, and it is checked before display).
- **SR2** The text field's state is in the ViewModel, not in the view's internal state, so a re-render does not lose characters.
- **SR3** The minimum length is 2 characters (CJK: 1 character).
- **SR4** Result states: loading (skeleton), empty ("No results for X" (fi: "Ei tuloksia haulle X")), and error (retry).
- **SR5** The search term is URL-encoded through the SDK (S6.5).

## Acceptance criteria
- [ ] Unit test: fast input "s", "st", "sta", "star" and responses in reverse order → only the "star" results are visible.
- [ ] XCUITest: typing 20 characters quickly → every character is in the field.
- [ ] The first results appear within P10's limits (≤ 500 ms after the debounce on the LAN).
- [ ] Returning from detail → the search text, the results, and focus are kept.
- [ ] Special characters (`&`, `#`, `ä`, `日本`) work (the mock verifies the encoding).
