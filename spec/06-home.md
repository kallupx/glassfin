# M06 – Home view (P0)

**Spec version:** v1.3.3 (22.10.2026). Changes are shown in SPEC.md's change history.

**Dependencies:** M01, M02, M04, and M05. **iOS UI:** P1 (M11).

## User path (Siri Remote)
1. The app opens to home. Focus is on the first card of the "Continue watching" (fi: "Jatka katsomista") row, or, if that row is empty, on the "Next Up" (fi: "Seuraavat jaksot") row.
2. Left and right browse a row, up and down change rows, and the tab bar is at the top.
3. When a card is focused, its backdrop changes subtly into the view's background (a 300 ms crossfade, a 250 ms debounce, so that fast browsing does not load unnecessary images). Reduce Motion replaces the crossfade with an immediate change.
   **Liquid Glass (M05):** the Liquid Glass tab bar floats over the backdrop (system, `scrollEdgeEffectStyle` default). Cards and rows are content without glass (G-2). Row titles are the system's vibrant text over the gradient (L-1). The offline banner is a `GlassBanner`.
4. A click opens detail (M07). **Play/Pause starts playback directly** from the resume position.
5. A long press opens a context menu: "Mark as played" (fi: "Merkitse katsotuksi"), "Remove from Continue Watching" (fi: "Poista jatka katsomista -listalta") (= mark unplayed or reset the position; ⚠️ Jellyfin has no separate "hide from resume" endpoint, so the implementation is done with a UserData update, to be verified), "Go to series" (fi: "Siirry sarjaan"), and "Favorite" (fi: "Suosikki").

## Sections and endpoints
| Order | Section | Endpoint | Parameters |
|---|---|---|---|
| 1 | Continue watching (fi: "Jatka katsomista") | `GET /UserItems/Resume` | `mediaTypes=Video, limit=20, fields=PrimaryImageAspectRatio,Overview, enableImageTypes=Primary,Backdrop,Thumb,Logo, enableUserData=true` |
| 2 | Next Up (fi: "Seuraavat jaksot") | `GET /Shows/NextUp` | `limit=20, enableResumable=false, enableRewatching=false, fields=…` |
| 3…n | Recently added (fi: "Viimeksi lisätyt") / library | `GET /Items/Latest` | `parentId=<library>, limit=20, groupItems=true`, one row per video library (`UserViews`) |
| P1 | Favorites (fi: "Suosikit") | `GET /Items` | `isFavorite=true, recursive=true` |
- **DECIDED (Q6-20, user 27.10.2026):** "Continue watching" (fi: "Jatka katsomista") and "Next Up" (fi: "Seuraavat jaksot") are shown as **separate rows**, as in Jellyfin web. The alternative is a combined "Up Next" row in the manner of the Apple TV app (a P1 setting).
- All sections are fetched **in parallel** (`async let` or a TaskGroup). One failed section shows its own error state, and the rest of the view does not crash.
- Empty rows are hidden. If all of them are empty, an empty state "Your library is empty" (fi: "Kirjastosi on tyhjä") is shown, plus guidance.
- The home view's order and visible rows can be edited in settings (P1), at which point the server's `DisplayPreferences` are also taken into account (P2).

## Updating (pain point: "the played state does not update, and the library does not update without a restart")
- When playback ends (M08 `Stopped`), `UserDataStore` updates optimistically at once, and the Resume and NextUp rows are fetched again.
- The WebSocket `UserDataChanged` updates the corresponding cards, and `LibraryChanged` refetches the Latest rows (debounce 2 s).
- When the app returns to the foreground (`scenePhase` → active) and more than 60 s have passed since the previous fetch, home is fetched again quietly (the old content stays visible, and focus does not move).
- **Focus must not jump** during an update. If the focused item leaves the row, focus moves to the neighboring item on the same row.

## Acceptance criteria
- [ ] Every section is visible with mock data. Screenshots at 1080p and 4K.
- [ ] Watching an episode to the end → return home → the episode leaves the "Continue watching" (fi: "Jatka katsomista") row, and the next episode appears on the "Next Up" (fi: "Seuraavat jaksot") row within ≤ 2 s (P14), without a restart.
- [ ] An item marked played on another client updates on home within ≤ 5 s (WebSocket, integration test P15).
- [ ] A 500 error in one section → an error state and a retry for that section, and the other sections are shown.
- [ ] Play/Pause on the focused card starts playback from the resume position.
- [ ] A background update does not move focus (UI test: focus is on the same item before and after the update).
- [ ] Performance: P1, P2, and P3 are met. The glass budget G-4 is met on Apple TV 4K 2nd generation.
- [ ] Snapshots: default and Reduce Transparency (the tab bar and the banner opaque).
