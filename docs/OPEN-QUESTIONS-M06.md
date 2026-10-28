# M06 remaining questions and evidence

Binding inputs are the merged `spec/01-core.md`, `spec/02-state-errors-performance.md`, `spec/03-security.md`, `spec/06-home.md`, and the verbatim [canonical test plan](../spec/TESTPLAN-M06.md). Question numbers below follow that plan. The earlier local implementation question numbering has been removed.

| Question | Current behavior / remaining decision |
|---|---|
| Q6-01 | When both personal rows are empty, default focus falls through to the first visible Latest row. Confirm this fallback; a dedicated tvOS focus fixture remains pending (T06-03). |
| Q6-02 | Latest includes movies, tvshows, homevideos, boxsets, mixed, musicvideos, trailers and unspecified collection types; excludes explicit music, Live TV, books and unknown plugin types. Confirm the video classification (T06-08). |
| Q6-03 | Cross-row overlap policy is still pending. Requests send `enableResumable=false`; explicit Resume/Next Up overlap de-duplication is not implemented (T06-11). |
| Q6-04 | Home has fixed 20-item rows, without paging or See all in P0 (T06-16). Confirm the P0 scope. |
| Q6-05 | Latest title uses the localized `home.latest` format with the sanitized library name. Confirm the format (T06-17). |
| Q6-06 | Latest requests `groupItems=true`; the card uses the server's returned item and unplayed count. Grouped-series presentation still needs a fixture and snapshot review (T06-22). |
| Q6-07 | Missing or failed backdrops keep the previous backdrop, falling back to the content scrim on first use (T06-26). |
| Q6-08 | Go to series is shown only for episodes with a valid series ID. The handoff preserves the season ID and index. M07 owns the series destination and season picker (T06-38). |
| Q6-09 | A removed focused item selects the same-row neighbor. If that row disappears, focus falls through to the next available row; confirm the whole-row policy on tvOS (T06-65). |
| Q6-10 | Remove from Continue Watching sends `POST /UserItems/{id}/UserData` with position zero and played false. Optimistic rollback is implemented. Actual absence from Resume after refetch still requires the disposable 10.10.7 / 10.11.11 / 12.2 matrix (T06-37). |
| Q6-11 | Failed sections show an inline catalog message and focusable retry; only that section refetches. Confirm focus after retry on tvOS (T06-14). |
| Q6-12 | Play/Pause sends the sanitized item and nonnegative resume position to an M08 handoff. Actual playback awaits M08 integration (T06-32, T06-58). |
| Q6-13 | Empty guidance and retry use the existing en/fi catalog keys. Confirm the wording and tab escape with snapshot/UI review (T06-04). |
| Q6-16 | Other rows expose Play, played/unplayed and favorite actions; Go to series is episode-only; Remove from Continue Watching is resume-only (T06-34). |
| Q6-19 | The 250 ms debounce still applies with Reduce Motion; the crossfade duration becomes zero. Visual confirmation remains on Apple TV (T06-25). |

## Pending integration and platform evidence

- [The coverage map](TEST-COVERAGE-M06.md) accounts for every canonical T06 ID and records partial and unautomated scenarios with reasons.
- M07 detail and M08 playback destinations are explicit handoffs. Home does not implement a competing series or player screen.
- Real-client WebSocket delivery within five seconds needs the disposable server matrix (T06-59).
- Apple builds, remote focus tests, ImageIO decoding and screenshot rendering require Xcode. Memory/hitch/cold-start budgets and the decompression-bomb peak require supported Apple TV hardware and Instruments. Linux verification does not claim those results.
