# M08a profiles, stream fallback and tracks

This implements only runtime DeviceProfile negotiation, server remux/transcode
fallback, audio/subtitle selection and subtitle delivery from spec/08-playback.md.
Trickplay, media segments and next episode remain on their separate branch.

## Integration

`PlaybackCoordinator` now defaults to full M08a. Its existing initializer still
accepts the same session, engine, origin and progress timer. Optional
`PlaybackConfiguration` and `GlassfinClock` injection make capability, bitrate,
subtitle policy and startup deadlines testable. `.poc` retains the locked PoC
behavior and its regression suite. The existing PoC test rig now explicitly opts
into that tier; no existing test assertion was changed.

As before, a caller supplies the authenticated, pinned `PlaybackSessionProviding`
client and shares its `URLSessionOriginClient` with `AVPlayerEngine`. This checkout's
Home still has its pre-existing playback placeholder; the playback entry point
remains `play(itemID:choice:)` plus `PlaybackView(coordinator:engine:)` for the detail
integration. This PR does not replace another module's navigation.

Runtime capability snapshots use VideoToolbox's hardware decode checks for HEVC
and AV1 and AVPlayer's eligible/available HDR modes for the current device/display.
Opus is excluded without a verified capability. H.264 and HEVC have conservative,
injectable level caps (5.2 and 5.1), bit-depth and profile constraints. Wire field
names and string-valued `MaxAudioChannels` match the pinned jellyfin-sdk-swift
entities. Playback uses the existing `JellyfinAPIClient` abstraction and SDK-backed
Apple client rather than introducing another API or authentication stack.

Default tracks use `/Users/Me.Configuration` audio/subtitle preferences. Default
subtitle mode is left to Jellyfin; explicit None, Always, OnlyForced and Smart
modes have portable mappings. Server-selected default stream indexes are retained.
Stream IDs are Jellyfin indexes, never native option-array offsets. Native options
are matched by title/language; ambiguous matches use fresh PlaybackInfo. HLS audio
also switches natively when its selection group actually contains the requested
track. System-menu changes that map unambiguously are reported too.

A server change closes the old session, negotiates the same media source and
position with new track indexes, loads a fresh play session and reports the new
selection. Pause state survives a track reload. DirectPlay failure retries with
direct play disabled; copied-video failure retries with video copy disabled.
Known video transcode reasons and selected burn-in subtitles report Transcode.
Copied video with converted audio reports DirectStream (PB11).

External text uses the canonical SDK subtitle route with `Stream.vtt`, authenticated
headers, a streaming 10 MiB cap and a 15-second total deadline. It never follows
server-supplied subtitle delivery URLs. A plain-text system-font overlay renders
VTT cues, including overlapping and CJK text; markup is displayed literally per
S6.1. PGS/VobSub use Encode. ASS/SSA default to text conversion; switching the
setting chooses Encode and renegotiates a selected ASS track. Only these choices
and remote bitrate enter UserDefaults; subtitle bytes/cues stay in memory.

The existing media loader, pinning, URLCache policy, redirect checks, chunk caps,
D4 playlist credential carrier and redaction remain in force. Full M08a does not
rewrite server-negotiated video/audio codecs or stream indexes into the HLS URL.
The AVPlayer handoff remains credential-free; server-written HLS media credential
queries retain ADR M08-2's previously accepted risk. Pinned self-signed HLS stays
blocked before playlist requests.

## UI hooks

`PlaybackTrackMenus` supplies the native tvOS transport menus without changing
player layout. Their UIMenu identifiers are `playback.tracks.audio`,
`playback.tracks.subtitle` and `playback.tracks.options`. UIActions expose matching
accessibility identifiers, with `.INDEX` appended for a stream or `.off` for
subtitles off. Other hooks: `playback.tracks.convertASS`,
`playback.tracks.diagnostics`, `playback.subtitle.overlay`,
`settings.playback.convertASS` and `settings.playback.remoteBitrate`.

The options menu shows PlayMethod, redacted reasons, source/negotiated codecs,
reported bitrate when available and a buffer snapshot. Settings offers ASS
conversion and remote bitrate (default 20 Mbps) when initialized with a full
`PlaybackConfiguration`. The existing PoC shell uses the default `.poc` settings
configuration and keeps only Sign out and the app version, as required by SPEC
section 3a and TPOC-42. Local-address servers use the
spec's 120 Mbps default. All new UI copy uses the app's en/fi String Catalog.

## Open questions and validation limits

- The startup sequence names audio conversion Transcode, whereas PB11 and the
  test matrix name copied video/audio conversion DirectStream. PB11 is used here.
- Apple provides hardware decoder support checks but no general decoder-level
  query used by this implementation. Are the conservative H.264 5.2 / HEVC 5.1
  caps appropriate for every supported device, or should measured device-specific
  caps replace them? Higher-level files can incur unnecessary video transcoding.
- Opus stays disabled until native MP4 playback support is verified on the target
  device/OS combinations. AV1 and HDR/DV advertisements need device tests too.
- LAN classification reuses the security policy's local-address classifier; it
  does not measure the connection or infer VPN/reverse-proxy routing. Automatic
  bitrate measurement remains P1.
- The specification does not fix a subtitle timeout. The new total deadline uses
  the existing API client's 15-second request timeout as its default.
- Playback startup's first-frame watchdog currently uses the engine's `.playing`
  event as the first-frame proxy. Native rendered-frame timing and P5/P6 need
  Apple/device validation. Existing Playing reporting still begins at engine
  readiness, as in the PoC; this does not prove rendered-frame timing.
- Native HLS timeline behavior (StartTimeTicks versus media timestamps), resume
  accuracy, paused switches, P9 switch deadlines and server subtitle extraction
  must be tested against the Docker matrix and actual native playback.
- Native matching deliberately avoids guessing between duplicate-language tracks.
  The custom menus always retain the server track indexes; ambiguous native system
  menu changes cannot be mapped back reliably and should use the custom menus.
- CJK fallback and literal subtitle markup require screenshots on tvOS 26/27 and
  hardware. VTT styling, positioning, voice labels and presentation refinements
  are not implemented; style settings are P1.
- iOS custom transport menus remain P1; the overlay and core coordinator compile
  for iOS, and the new menus are attached only on tvOS.
- The existing Q8P-07 conditional Ping policy, Q8P-09 queued report policy,
  reconnect handling and general media timeout questions remain outside these
  three scoped additions. The 10-second startup watchdog does not implement
  PB12's 30-second network recovery UI.
- Docker is not installed in this workspace. No real server or credentials were
  used. Live server matrix tests are gated off; local fixtures establish request
  policy and state transitions, not actual server transcoding or AVPlayer decoding.

## Verification

Linux Swift 6.4.1 build and tests pass: 532 Debug tests and 531 Release tests,
including eight gated live-server skips in each, with zero failures. There are
29 new portable tests. The native coverage run passes at 91.70% (8781/9576), above
the 80% gate. SwiftLint, strict swift-format, license checks, source/design-system/
image/string guards, entitlements, debug-string and unit-target checks, artifact
redactor self-tests, 33 Python tests and 22 Docker-script self-test cases pass.
SwiftLint's unavailable SourceKit custom rule is covered by the independent
source grep guard. No Docker server or Apple build was run locally.

Apple CI must compile
the native VideoToolbox/AVFoundation/UIKit paths and validate Siri Remote focus,
menu accessibility IDs, CJK rendering, HLS seek/track switching, HDR/DV matching,
certificate behavior and Release app binary scans. Device performance acceptance
and the real transcoding check in the spec's Clarifications remain outstanding.

## API references

- [AVPlayer HDR modes](https://developer.apple.com/documentation/avfoundation/avplayer/availablehdrmodes)
  and [HDR eligibility](https://developer.apple.com/documentation/avfoundation/avplayer/eligibleforhdrplayback).
- [Native tvOS transport menus](https://developer.apple.com/documentation/avkit/avplayerviewcontroller/transportbarcustommenuitems).
- Wire entities and subtitle routes were checked against the resolved
  [jellyfin-sdk-swift source](https://github.com/jellyfin/jellyfin-sdk-swift).
