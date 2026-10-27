# M07 implementation questions and integration notes

The binding inputs are the merged spec PR #18 decisions and the verbatim canonical `spec/TESTPLAN-M07.md`. Coverage and automation limits are recorded in `docs/TEST-COVERAGE-M07.md`.

| Question | Conservative implementation | Follow-up |
| --- | --- | --- |
| Q7-19: server failure during browsing or a filter change | Retain the previous grid/detail/episode content, set `AppState.connectivity` to `.serverUnreachable`, and show a banner with the existing `AuthCopy.Key.serverUnreachable`. Failed actions show inline errors. Show the blocking M05 error component only if there is no content. A failed season switch restores the previous season label with its row. | This follows binding M02 v1.3.4; no approval is needed. The existing AppState 10-second reachability loop performs recovery, and visible views retry when connectivity becomes online. |
| Q7-08: playback and dismissal before M08 is merged | `LibraryPlaybackIntent` carries a validated item ID, nonnegative position, and track preselection. `LibrarySession.onPlayback` is the integration hook. `playbackDidEnd` notifies the series focus model after M08 commits user data. Play currently shows a localized availability notice. DEBUG fixtures exercise dismissal without creating a player or sending playback reports. | M08 must supply presentation and call the dismissal hook. Actual player return tests remain blocked on M08. |
| Q7-01: random order across pages | Send Jellyfin's `Random` sort, bypass response caching for random queries, consume server offsets, and deduplicate repeated IDs. | Jellyfin does not supply an ordering seed in this spec. Random pages can overlap or omit items as the server reshuffles; stable exhaustive random browsing needs a server ordering contract. |
| Q7-02: library tab limit and empty libraries | Use M05's assumed five direct library tabs and an overflow Libraries tab. UserViews remains the source of truth. | Confirm the five-tab assumption. M06 can replace Home, and M09 can add its semantic Search tab when merged. |
| Q7-03: default episode across seasons | Read the series episode metadata to locate the first chronological in-progress episode, otherwise the first unplayed episode, otherwise the first episode. Sort specials last. Explicit season detail scopes the initial play target to that season. Down from the picker uses that season's first unplayed episode, otherwise its first episode. | The spec does not define multiple simultaneous resume positions. The first chronological resume wins. |

## Shared changes and integration boundaries

- `MetadataPolicy.swift` is byte-for-byte identical to the M06 and M09 worktree copies. All metadata length/count caps, the image cap, and the recent-search cap live there. M07 does not store search history.
- The old shared `MetadataSanitizer.plainText` removed tags and decoded entities. Binding S6.1 supersedes that behavior: it now strips only controls and bidi characters. Existing M04/S4.7 tests were updated to preserve literal tags/entities while retaining the 64-grapheme name cap and host fallback. Authentication routing and decisions are unchanged.
- `AuthFlow.featureApp` and `makeFeatureClient()` are composition hooks. Credentials remain inside the core. `AuthRootView` adds signed-in library tabs and releases feature state on sign-out. Existing auth DEBUG launches use library fixtures rather than making live feature requests.
- M05's `HeroHeader`, `GlassBanner`, and `ErrorStateView` accept optional feature content/message overrides. Their default behavior is unchanged. The title override reuses the core server-down key rather than adding a duplicate translation.
- The merged base includes the M05 compilation fixes. Linux cannot type-check SwiftUI against the Apple SDK or execute tvOS focus tests.
- `project.yml` already includes all shared unit/UI-test directories in both schemes. Comments identify M07 coverage; no workflow, signing, entitlement, bundle identifier, or plist changes are needed.
- Images use CoreNetworking authorization and an ephemeral bounded download. Both declared size and received chunks are checked; compressed bytes live only in DiskImageCache under the exact SHA-256 tuple digest. ImageIO thumbnail creation and immediate decoding run in a detached utility task. Network errors never log image URLs.

## Deliberately deferred

P1: collections, person navigation, alphabet jump, version selection, trailers, continuous rows spanning all seasons, and the iOS product layout. Physical Apple TV frame rate/hitch measurements and accessibility screenshot review require Apple hardware/simulators. See `docs/TEST-COVERAGE-M07.md` for exact coverage.
