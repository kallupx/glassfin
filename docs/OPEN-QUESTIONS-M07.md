# M07 implementation questions and integration notes

The binding inputs are the merged spec PR #18 decisions and the verbatim canonical `spec/TESTPLAN-M07.md`. Coverage and automation limits are recorded in `docs/TEST-COVERAGE-M07.md`.

| Question | Current behavior | Outstanding decision or integration |
| --- | --- | --- |
| Q7-01: random paging | Send Jellyfin's Random sort, bypass response caching, consume server offsets and deduplicate IDs. | No seed is specified. Overlapping random pages cannot guarantee exhaustive browsing. |
| Q7-03: mixed libraries | Request Movie and Series. | Confirm mixed-library contents, including collections (Q7-21). |
| Q7-07: fully watched series | No Next Up result falls back to the first regular season and its first episode. | Confirm the rewatch label and focus. |
| Q7-08: playback return | LibraryPlaybackIntent carries the item, position and track preselection. LibrarySession.onPlayback and playbackDidEnd provide the presentation/return hooks. Finished episodes advance to the next unplayed episode or season. | M08 must present the player and invoke the return hook after committing UserData. Current UI tests exercise DEBUG hooks. |
| Q7-09: empty or virtual seasons | The picker displays the seasons returned by Jellyfin. | Decide whether to hide virtual/empty seasons. |
| Q7-10: long seasons | The selected season is fetched as one episode list and cached for the view's lifetime. | Specify episode paging for long seasons. |
| Q7-14: saved choices | Small JSON values under library.choices.<server>.<user>.<library> in the settings store. | Agree the namespace and aggregate settings budget. |

Other unresolved product questions remain as written in the canonical plan:
Q7-02 (empty states), Q7-04 (paging errors), Q7-05 (track preselection),
Q7-06 (versions), Q7-11 (deleted items), Q7-12 (filter failure), Q7-13 (count plurals),
Q7-15 (start-over semantics), Q7-16 (cast focus), Q7-17 (Specials naming),
Q7-18 (trailers), Q7-20 (episode click), and Q7-22 (HDR labels).
Coverage limitations and current assumptions are in `docs/TEST-COVERAGE-M07.md`.
The five-direct-library-tab assumption comes from M05 and needs product review.

## Shared changes and integration boundaries

- `MetadataPolicy.swift` centralizes all metadata length/count caps, the image cap, and the recent-search cap. M07 does not store search history.
- The old shared `MetadataSanitizer.plainText` removed tags and decoded entities. Binding S6.1 supersedes that behavior: it now strips only controls and bidi characters. Existing M04/S4.7 tests were updated to preserve literal tags/entities while retaining the 64-grapheme name cap and host fallback. Authentication routing and decisions are unchanged.
- `AuthFlow.featureApp` and `makeFeatureClient()` are composition hooks. Credentials remain inside the core. `AuthRootView` adds signed-in library tabs and releases feature state on sign-out. Existing auth DEBUG launches use library fixtures rather than making live feature requests.
- M05's `HeroHeader`, `GlassBanner`, and `ErrorStateView` accept optional feature content/message overrides. Their default behavior is unchanged. The title override reuses the core server-down key rather than adding a duplicate translation.
- The merged base includes the M05 compilation fixes. Linux cannot type-check SwiftUI against the Apple SDK or execute tvOS focus tests.
- `project.yml` already includes all shared unit/UI-test directories in both schemes. Comments identify M07 coverage; no workflow, signing, entitlement, bundle identifier, or plist changes are needed.
- Mid-browse failures retain content and use the existing `.serverUnreachable` banner key. Blocking server-down UI uses that same key only when there is no displayable content.
- The shared HomeViewModel keeps Continue Watching and Next Up as separate state rows. M07 does not replace the M06 Home UI.
- Series detail uses a season picker and one episode list. A series-scoped Next Up request locates the initial season without fetching every season's episodes. Switching cancels the previous request and reuses completed season lists.
- Images use CoreNetworking authorization and an ephemeral bounded download. Both declared size and received chunks are checked; compressed bytes live only in DiskImageCache under the exact SHA-256 tuple digest. ImageIO thumbnail creation and immediate decoding run in a detached utility task. Network errors never log image URLs.

## Deliberately deferred

P1: collections, person navigation, alphabet jump, version selection, trailers, continuous rows spanning all seasons, and the iOS product layout. Physical Apple TV frame rate/hitch measurements and accessibility screenshot review require Apple hardware/simulators. See `docs/TEST-COVERAGE-M07.md` for exact coverage.
