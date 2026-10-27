# M07 – Libraries, detail views, and the series, season, and episode view (P0)

**Spec version:** v1.3.3 (22.10.2026). Changes are shown in SPEC.md's change history.

**Dependencies:** M01, M02, and M05 (M06 is not required). **iOS UI:** P1 (M11).

## Use cases
- **UC-L1 (P0)** Browsing a movie library as a grid, sorting (name, date added, release year, rating, random), and filtering (unplayed (fi: "katsomaton"), favorites (fi: "suosikit"), genre, year).
- **UC-L2 (P0)** Opening a series → season → episode → playback.
- **UC-L3 (P0)** A movie's detail → play, resume, played, or favorite, trailers (P1), and similar.
- **UC-L4 (P1)** Collections (BoxSet), people (an actor's movies), and an alphabet jump.
- **UC-L5 (P1)** More than one version (MediaSources > 1): version selection on detail. Server 12.0 supports many versions for episodes too.

## Library view
- `GET /Items?parentId=<lib>&includeItemTypes=Movie|Series&recursive=true&sortBy=…&sortOrder=…&startIndex=…&limit=50&fields=PrimaryImageAspectRatio&enableTotalRecordCount=true&enableUserData=true`
- `LazyVGrid`, 6 posters per row (tvOS 1080p/4K). Paging starts when 10 items remain.
- The sort and filter bar is above the grid as its own `focusSection` region. **Liquid Glass:** the bar is one `GlassEffectContainer`, with `.glass` buttons and `Menu` menus (M05 §2). The grid's cards are not glass. Filters are fetched with `GET /Items/Filters2?parentId=`. Choices are saved per library (UserDefaults).
- The total count is shown ("1,234 movies" (fi: "1 234 elokuvaa")).
- Returning from detail to the grid: **the same item is focused and the scroll position is kept**.

## Movie detail
- `HeroHeader` (M05): a backdrop (`backgroundExtensionEffect`), a Logo, a meta row, and a **glass button row** (`GlassActionBar`, where "Play" (fi: "Toista") is `.glassProminent` and the others are `.glass`): `[▶ Play / Resume 32:10]` (fi: "Toista / Jatka 32:10") `[↺ Start over]` (fi: "Alusta") (only if there is progress) `[✓ Played]` (fi: "Katsottu") `[♡ Favorite]` (fi: "Suosikki") `[Audio/Subtitles]` (fi: "Ääni/Tekstitys") (preselection before playback) `[More]` (fi: "Lisää").
- Rows below: "Cast" (fi: "Näyttelijät") (`People`, P1 linking to a person) and "Similar" (fi: "Samankaltaiset") (`GET /Items/{id}/Similar`).
- A technical row: resolution, the HDR/DV type (`VideoRangeType`), the audio codec and channels, and the subtitle languages (MediaStreams). Infuse shows the corresponding information, and users value it.

## Series, season, and episode view (pain point: "focus jumps")
One view with two `focusSection` regions:
```
[HeroHeader: the series logo, ▶ Resume S2E5 / Play S1E1 (fi: "Jatka S2E5 / Toista S1E1"), ✓, ♡]
[Season picker: Season 1 | Season 2 | Season 3 | Specials]    ← focusSection A (a horizontal row, GlassEffectContainer + glassEffectID morph for the selection)
   (fi: "Kausi 1 | Kausi 2 | Kausi 3 | Erikoisjaksot")
[Episode row: LandscapeCard × N (thumb, SxEy, name, runtime, progress, ✓)]   ← focusSection B
[The selected episode's overview (not focusable)]
```
- Data: `GET /Shows/{seriesId}/Seasons?enableUserData=true` and `GET /Shows/{seriesId}/Episodes?seasonId=…&fields=Overview,PrimaryImageAspectRatio&enableUserData=true`.
- **Focus rules** (they apply to every view, and they are checked with UI tests):
  1. When the view opens, the default focus is the "Resume"/"Play" button (fi: "Jatka"/"Toista"). The episode row is already scrolled to the next unplayed or in-progress episode, and the season picker is on that season.
  2. Moving focus to a season in the season picker (not a click) changes the episode row's content (debounce 200 ms). Focus stays in the season picker, and it does not jump to the episode row.
  3. Down from the season picker → focus goes to the episode row on **that season's first unplayed episode** (or the first episode), not on a random geometrically nearest card. Implementation: `.focusSection()` and `@FocusState` or `defaultFocus`.
  4. Up from the episode row → focus goes to the selected season in the season picker.
  5. Returning from playback → focus on the same episode or, if the episode was watched to the end, on the next episode.
  6. The episode overview is not focusable.
- **Glass budget (G-1):** the series view has at most two glass containers visible at the same time (the HeroHeader button row and the season picker). Episode cards are content.
- While episodes load, skeleton cards are shown (the same size), so that layout and focus do not jump.
- P1: every season's episodes on one continuous row, with the season picker acting as a jump index (the Apple TV app's model). Which one is the default? **DECIDED (Q7-25, user 27.10.2026):** the default is the per-season model with the season picker described above.

## Acceptance criteria
- [ ] UC-L1: the grid, sorting, and filtering work. In a library of 2,000 items, P3 (60 fps) is met, and paging works without empty gaps.
- [ ] Returning from detail to the grid → the same item is focused (XCUITest).
- [ ] Focus rules 1–6 are covered by XCUITests, each with its own test and screenshot.
- [ ] A series whose S2E5 is in progress → the view opens on season 2 and episode 5, and the button reads "Resume S2E5" (fi: "Jatka S2E5").
- [ ] A played mark from the context menu updates the card immediately (an optimistic update) and the server (`POST /UserPlayedItems/{id}`). An error restores the state and shows a message.
- [ ] Specials (Season 0) appear as the last season.
- [ ] The technical row shows the resolution, the HDR type, and the audio codec correctly with fixture data (HDR10, DV P8, DTS-HD MA 7.1).
