# ADR M08-1: Jellyfin trickplay and playback companion controls

Status: implemented; Apple platform acceptance pending.

## Decision

Use a custom scrub control when validated Jellyfin trickplay metadata and a known
runtime are available. Otherwise retain native scrubbing. The native seek delegate
provides the final destination before playback resumes; it does not document a
continuous preview position. No private AVKit views, KVC, polling of undocumented
state, or server plugins are used.

The adapter sets `playbackControlsIncludeTransportBar = false` while the custom
scrub surface is active. Outside scrubbing, the native transport bar remains
available for the audio, subtitle, and playback options menus. Horizontal pan enters scrubbing;
Select confirms, Menu cancels, and directional clicks move ten seconds. Playback
resumes after leaving scrubbing only if it was playing beforehand. Vertical gestures
stay with AVKit. The thumbnail and timestamp track the preview position.

Skip uses native `contextualActions`, updated only when the action changes. No
explicit focus update is issued for Skip. Next Up defaults to Play now when entering
the card; appearance does not explicitly move focus away from an active transport
bar. Scrubbing suppresses Next Up and contextual actions; only one custom glass
surface appears. Existing design-system chrome supplies Reduce Transparency and
contrast behavior.

## Networking and memory

Metadata is fetched with `Fields=Trickplay`. The selected media-source ID scopes the
resolution dictionary and tile requests. `Interval` is milliseconds; segment times
are ticks. A frame index maps to a sprite sheet and row-major cell. Prefetch order is
current, -1, +1, -2, +2, clipped to the available sheets. Requests are serialized;
replacing a scrub task cancels the old download before starting another.

All requests use the session's existing CoreNetworking client (header authentication,
certificate pin, redirect policy, `urlCache = nil`). Sprite downloads enforce the
existing 20 MB per-chunk-counted response cap. Metadata responses are capped at 1 MB.
There are no new URL constructors, credential parameters, logs, or disk caches.

The compressed LRU has hard limits of 20 sheets and 40 MiB. The decoded LRU has hard
limits of 20 sheets and 64 MiB. ImageIO checks sprite dimensions before thumbnail
creation, downsamples to at most 4096 pixels, then crops the requested cell. Invalid
metadata dimensions, integer overflows, incomplete metadata, and invalid images
produce no preview. Memory warnings and playback changes clear both caches. These
are cache budgets; transient decoding, the displayed crop, AVPlayer, and the rest of
the app need device memory measurements (P12/P13).

## Segments and Next Up

Segments use half-open intervals, so Intro 60–150 appears at 60 and disappears at
150. Settings persist Ask (default), Skip automatically, or Do nothing per type.
Invalid/unknown segments are ignored; absent endpoints/data never fail playback.
An authenticated 401 follows session-expiry handling and is not retried.

Episode resolution uses the server's ordered `startItemId` result with limit 2 and
requires the current item followed by an episode in the same series. It supports
season boundaries and never guesses if the current item is absent. The earliest
Outro triggers Next Up; without an Outro, runtime minus 30 seconds triggers it.
Unknown runtime has no fallback trigger. Countdown uses ten monotonic seconds.
Cancellation suppresses further prompts for that item and records the next item
for focus restoration. Handoff awaits Stopped, sends the played-state request,
updates the shared UserDataStore, and starts the next item from zero.

`PlaybackView` requires the app's shared UserDataStore and a return-focus callback.
The existing M07/Home detail and playback routes on main are placeholders; their
future host must pass these dependencies. `makeCompanion(playNext:)` / the view's
`playNext` callback is the integration point for carrying selected audio/subtitle
languages to the next episode. The merged playback adapter retains the native
track menus and subtitle overlay from the track-selection implementation on main.

## Defaults and questions for spec review

- Autoplay's initial value is unspecified: use on, consistent with PB7's automatic
  playback requirement. Preferences currently apply to this app installation.
- Pausing, buffering, scrubbing, or seeking before the trigger dismisses the prompt
  and restarts a full countdown once eligible again. Cancel remains effective for
  the entire item, including after seeks.
- Overlapping segments use earliest start, then shortest end, then type. Do nothing
  removes that segment from Skip selection. It does not disable an Outro's Next Up
  trigger; autoplay has its own setting.
- Auto-skip Outro and Next Up can conflict: Next Up takes precedence while eligible
  so its full countdown remains usable. With autoplay disabled/cancelled, Outro
  auto-skip applies normally.
- A failed played-state request other than 401 does not block the next episode;
  local played state is optimistic. Should that mutation have a durable retry?

## Acceptance still requiring Apple platforms

Xcode compilation of SwiftUI/UIKit/ImageIO and tvOS 26/27 Focus Engine behavior,
remote scrubbing recording, native Info/menu interactions, Menu cancellation and
return focus, Reduce Transparency, P8 cached preview latency, and P12/P13 memory
measurements remain mandatory. UI identifiers are `playback.trickplay.*`,
`playback.scrub.timeline`, `playback.next.*`, and `settings.playback.*`. The native
Skip action has `UIAction.Identifier("playback.segment.skip")`; AVKit owns the
rendered button, so accessibility identifier propagation must be verified in the
simulator. No real server or user credentials were used for development/tests.

## References

- [AVKit seek delegate](https://developer.apple.com/documentation/avkit/avplayerviewcontrollerdelegate/playerviewcontroller(_:timetoseekafterusernavigatedfrom:to:))
- [AVKit transport visibility](https://developer.apple.com/documentation/avkit/avplayerviewcontroller/playbackcontrolsincludetransportbar)
- [AVKit contextual actions](https://developer.apple.com/documentation/avkit/avplayerviewcontroller/contextualactions)
- [Jellyfin episode ordering](https://github.com/jellyfin/jellyfin/blob/master/Jellyfin.Api/Controllers/TvShowsController.cs)

## Linux validation (2026-10-28)

- `swift build --package-path Packages/GlassfinCore`: passed (Swift 6.4.1).
- `swift test --package-path Packages/GlassfinCore`: 540 discovered, 532 passed,
  8 Docker integration tests skipped without a configured fixture server, 0 failures.
- New coverage: 37 Linux feature tests and 2 ImageIO tests compiled/run only on Apple
  platforms. Existing test assertions were not changed.
- `scripts/coverage-gate.sh`: passed, 91.47% (8564/9363 lines), threshold 80%.
- SwiftLint, strict recursive swift-format, ci-grep, image pipeline, String Catalog,
  design system, licenses, entitlements, debug-only strings, unit-test-target checks,
  artifact redaction self-tests, shell syntax, 33 Python tests, and the 22-case Docker
  harness self-test passed. No Docker server or actual playback was started locally.
