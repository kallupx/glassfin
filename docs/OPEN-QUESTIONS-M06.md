# M06 implementation decisions and remaining questions

Binding inputs: `spec/06-home.md`, Q4-10, and spec PR #18's M01/M02/S6.1/S6.6/S6.7 updates supplied in `/workspace/codex-logs/spec18-*.md`. The PR #18 metadata rule overrides older tag-removal expectations, including the existing sanitizer's behavior.

| ID | Decision / remaining work | Code |
|---|---|---|
| Q6-01 | Remove from Continue Watching sends `POST /UserItems/{id}/UserData` with position zero and played false. The row updates optimistically and rolls back on failure. Confirm the server's Resume-list behavior on 10.10.7, 10.11.11, and 12.2; the disposable-server reset test is supplied. No separate hide endpoint is assumed. | `HomeViewModel.removeFromResume` |
| Q6-02 | M07 is developed separately. Home passes the sanitized `MediaItem` (or series ID) into a NavigationStack destination. The local detail destination is a TODO stub until M07 is integrated. | `HomeRootView` |
| Q6-03 | M08 is developed separately. Home passes a `HomePlaybackRequest` containing the focused item and nonnegative resume position. Play/Pause and the context Play action reach this destination; actual AVPlayer playback awaits M08. | `HomeRootView`, `HomeNavigation.swift` |
| Q6-04 | P15's real server delivery latency still needs matrix evidence. The header-only URLSession socket adapter uses the existing reconnect stream, AppState consumes events, and Home responds to its generations. Mock delivery is tested. A socket 401 terminates the stream and session without retry. | `URLSessionEventSocket.swift`, `AuthFlow.makeHomeEvents` |
| Q6-05 | Resolved P0 default: separate Continue Watching and Next Up rows. Favorites and the combined-row preference remain disabled P1 stubs. | `HomeFutureFeatures` |
| Q6-06 | Row order/visibility editing is P1; server DisplayPreferences is P2. No settings controls are exposed yet. | `HomeFutureFeatures` |
| Q6-07 | Latest rows include video collection types movies, tvshows, homevideos, boxsets, mixed, musicvideos, trailers, and unspecified/mixed views. Other explicit types are omitted. Unknown plugin-defined collection types need an explicit video classification before inclusion. | `HomeMetadata.isVideoLibrary` |
| Q6-08 | The shared view compiles into both app targets, but a dedicated iOS touch layout remains M11/P1. | `HomeFutureFeatures` |
| Q6-14 | Resolved: full-screen server-down copy reuses `AppErrorMessage.key(for: .serverUnreachable)` / `AuthCopy.Key.serverUnreachable`. No new server-down title is added to either catalog. Cached content remains visible with GlassBanner. | `HomeViewModel.serverDownTitleKey`, M05 message override hooks |

## Integration and verification limits

- The only change in M05 Shell is an optional Settings content hook, necessary to preserve M04 sign-out inside the shared shell. Existing callers retain the demo Settings content. The known `some View` versus `TabContent` compile issue is deliberately untouched; so are the separate Demo and GlassChrome fixes.
- Other M05 hooks accept already decoded poster/placeholder images and localized core error/banner copy. Existing default behavior is unchanged. Home decodes both thumbnails and BlurHash placeholders on worker tasks.
- Home's endpoints are fixed 20-item rows. Lazy stacks avoid eagerly constructing cells; Home does not invent paging beyond the spec's row limits. Library browsing owns larger paged lists.
- New snapshots contain server/user ownership and per-library rows. Unowned legacy snapshots are supported by the M02-compatible model initializer, but the app requires ownership before displaying a snapshot. Other-user snapshots never become Home content.
- The shared `MetadataPolicy.swift` is byte-identical to the M07 and M09 worktrees at verification time. Keep that file identical when stacking these branches.
- Apple-platform compilation, XCUITests, PNG generation, hardware metrics, and the Docker matrix cannot run in this Linux workspace without Xcode / Docker. See the test map for exact coverage and commands.
