# M08 – Video playback (P0, the application's most important module)

**Spec version:** v1.3.3 (22.10.2026). Changes are shown in SPEC.md's change history.

**Dependencies:** M01, M02, M03, M05, and M07. **Prerequisite for M08b:** the R2 performance prototype has passed, and the LGPL conditions L1–L5 are met (SPEC.md §7 R9). The license is no longer a blocker, because the app is open source and the license proposal is MPL-2.0.
**Background (Researcher, part 3):** AVPlayer does not open MKV and does not support DTS, TrueHD, PGS, or ASS. Its strengths are a native UI, frame-rate and HDR matching, and Dolby Vision P5/P8. Apple TV does not bitstream TrueHD or DTS with any client, and Atmos works only through DD+ (E-AC-3 JOC).


> **PoC tier:** for the PoC, [SPEC.md §3a](SPEC.md#3a-poc-tier-p0-poc-decided-27102026) "M08a-PoC playback" overrides this module (static DeviceProfile, no video transcoding, unsupported-video message). The rest of this module applies to full M08a.

## Split
| Part | Contents | Priority |
|---|---|---|
| **M08a** | The AVPlayer path: direct play (MP4/MOV/M4V) plus the server's DirectStream (remux to HLS, video is copied) and Transcode. DeviceProfile, reporting, the native transport bar, tracks, media segments, trickplay, and the next episode. | **P0 (MVP)** |
| **M08b** | On-device FFmpeg remux (MKV → fMP4/HLS locally) → AVPlayer. Reduces server load and preserves DV in MKV. | **P1** (prerequisite: the R2 prototype, LGPL conditions L1–L5) |
| **M14** | An alternative playback engine (VLCKit or MPVKit) for PGS, ASS, and DTS/TrueHD decoding without transcoding. Infuse parity. | P1 (LGPL conditions L1–L5) |

**ASSUMPTION – requires user confirmation:** the MVP playback path is **AVPlayer and the server's DirectStream/Transcode fallback**. The fallback is needed in any case. As for the license, on-device remux is now allowed (the MPL-2.0 proposal and the LGPL conditions, SPEC.md §7 R9), but it stays in P1, because its performance on 50–80 GB files is unverified (R2). It is added in M08b once the R2 prototype passes the metrics.

## Player abstraction (GlassfinCore/CorePlayback)
```swift
public protocol PlaybackEngine: AnyObject, Sendable {           // AVPlayerEngine (P0), RemuxEngine (M08b), VLCEngine/MPVEngine (M14)
  var state: AsyncStream<PlaybackState> { get }                 // idle, loading, playing, paused, buffering, ended, failed(PlaybackError)
  var position: Duration { get }
  func load(_ source: PlaybackSource, startAt: Duration) async throws
  func play(); func pause(); func seek(to: Duration) async
  func select(audio: Track.ID?) async throws; func select(subtitle: Track.ID?) async throws
}
public protocol PlaybackCoordinator { /* PlaybackInfo → engine selection → reporting → segments → next-up; testable without UI */ }
```
- `PlaybackCoordinator` is UI-independent, so iOS uses it as-is. The tvOS UI is an `AVPlayerViewController` wrapper (`UIViewControllerRepresentable`).

## Playback start (sequence)
1. The user presses "Play" (fi: "Toista") or "Resume" (fi: "Jatka") → `POST /Items/{id}/PlaybackInfo` with the body `{DeviceProfile, UserId, StartTimeTicks, MaxStreamingBitrate, AudioStreamIndex?, SubtitleStreamIndex?, MediaSourceId?, EnableDirectPlay:true, EnableDirectStream:true, EnableTranscoding:true, AllowVideoStreamCopy:true, AllowAudioStreamCopy:true}`.
2. `MediaSources[0]` is chosen from the response (or the version the user chose):
   - `SupportsDirectPlay` → `GET /Videos/{id}/stream?static=true&mediaSourceId=&playSessionId=&deviceId=` (PlayMethod `DirectPlay`). The token is passed per ADR M08-2: primarily a header, fallback `ApiKey=` (only `MediaURLBuilder`).
   - otherwise `TranscodingUrl` (the server's HLS; `DirectStream` if video and audio are copied, otherwise `Transcode`). The URL is relative, so it is joined to the server's base URL. The token is passed per ADR M08-2. If the URL returned by the server already contains `ApiKey`/`api_key`, it is removed on the header path, so that a header and a query are not used at the same time. **The URL is not logged** (S5.1).
3. `AVURLAsset` → `AVPlayerItem`. `preferredForwardBufferDuration` may be the default.
   - **ADR M08-2 – passing the token to media and self-signed servers (one prototype resolves S1.5 and R3), done before M08a's implementation:**
     - (a) `AVURLAsset(url:, options: ["AVURLAssetHTTPHeaderFieldsKey": ["Authorization": …]])`. ⚠️ **An undocumented key**: behavior on tvOS 26/27, coverage of HLS segments and variant playlists, and App Store acceptability are unverified. It does not solve R3.
     - (b) **`AVAssetResourceLoaderDelegate`** with a custom scheme (`glassfin-media://`): the app fetches the data with its own URLSession, which adds the header, applies S4.4 pinning, and applies the S4.6 redirect rules. A documented API, which would also solve R3.
       - ⚠️ **Limitation (Researcher, v1.2; forum reports, unverified on tvOS 26):** the delegate intercepts only custom-scheme URLs. In HLS it in practice intercepts only **playlists and keys, not media segments**: AVPlayer fetches the segments itself, so they get neither a header nor pinning.
       - Other risks: performance (P5/P7), URL rewriting of playlists, AirPlay, and HDR/DV matching.
     - (c) Fallback: `ApiKey=` only in media URLs, and mandatory S5 redaction.
     - **The prototype tests three cases separately** (a result per case into the ADR):
       1. **Direct play, one file** (`/Videos/{id}/stream?static=true`): does (b) work for the whole file with range requests, or (a)? The goal is a header without `ApiKey`.
       2. **The server's HLS transcoding** (`TranscodingUrl`): playlists can go through (b), but **segments probably need the `ApiKey` fallback** (c). This is a **risk accepted by Security (v1.2)**, as long as S5 redaction and the S4.6 redirect rule are in effect.
       3. **Our own loopback remux (M08b):** a local `127.0.0.1` HLS that fetches the source with the app's URLSession (header, pinning, S4.6). **It does not need a token for AVPlayer.** This is the long-term path, which removes `ApiKey` and also solves R3 for HLS.
     - **Metrics for the ADR:** the three cases work, start P5/P6, seek P7, and a self-signed server plays (cases 1 and 3). The server's logs do not show a token on the header paths.
     - **Default order:** case 1: (b) → (a) → (c). Case 2: playlist (b) or (a), and segments (c). Case 3: no token. The decision is recorded in ADR M08-2.
   - **Redirects and the resolved URL ([AGREED] with Security, v1.2, 03-security.md S4.6):**
     - AVPlayer follows redirects itself, past the app's URLSession delegate. Therefore `MediaURLBuilder` **resolves the final URL with the app's URLSession** under the S4.6 rules (direct play: `HEAD /Videos/{id}/stream`; HLS: `GET` of the master playlist), and **AVPlayer is given only this resolved URL**.
     - If an `ApiKey` URL redirects to another host or HTTPS → HTTP, playback is rejected (`AppError.insecureRedirect`), and the URL is not given to AVPlayer.
     - `ApiKey` in the URLs of transcoded HLS segments is an accepted risk, as long as redaction and the redirect rule are in effect.
4. The first frame → `POST /Sessions/Playing` (PlaybackStartInfo: ItemId, MediaSourceId, PlaySessionId, PlayMethod, PositionTicks, AudioStreamIndex, SubtitleStreamIndex, CanSeek).
5. Progress: `POST /Sessions/Playing/Progress` every 10 s **and immediately** on pause, resume, after a seek, and on a track change (`IsPaused`, `PositionTicks`). For transcoding sessions, also `POST /Sessions/Playing/Ping` if the server requires it (ASSUMPTION: 30 s).
6. Stop (Menu, the end, or an error) → `POST /Sessions/Playing/Stopped {PositionTicks, PlaySessionId, Failed}`. Reporting tolerates a network error: one retry, and a failed Stopped is kept in memory and sent when the connection returns (the same app session).
7. **Automatic fallback:** if the AVPlayerItem goes to `.failed`, or the first frame does not arrive within 10 seconds in direct play, PlaybackInfo is requested again with `EnableDirectPlay=false` (→ DirectStream), and after that with `AllowVideoStreamCopy=false` (→ Transcode). The user sees only a loading indicator, unless everything fails. The final error is shown in plain language ("This file could not be played" (fi: "Tätä tiedostoa ei voitu toistaa"), with further details in Diagnostics).

## DeviceProfile (pain point: "unnecessary transcoding")
- Built **at runtime from the device's capabilities**, not from a hardcoded list. Swiftfin's `DeviceProfile` extension is the reference (the Researcher's report).
- DirectPlayProfiles (AVPlayer):
  - Container `mp4, m4v, mov`.
  - Video `h264, hevc`, and `av1` only if `VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)`.
  - Audio `aac, ac3, eac3, alac, flac, mp3`, and `opus` only if support is verified.
- CodecProfiles: HEVC and H.264 levels and bit depth. `VideoRangeType` allows `SDR, HDR10, HLG, DOVI, DOVIWithHDR10, DOVIWithSDR` only if the display and the device support them (`AVPlayer.availableHDRModes`, `eligibleForHDRPlayback`). Otherwise the server tone-maps.
- TranscodingProfiles: `Type=Video, Protocol=hls, Container=mp4 (fMP4)`, VideoCodec `hevc,h264`, AudioCodec `eac3,ac3,aac`, `MaxAudioChannels=8`, `BreakOnNonKeyFrames=true` (the SDK's field names are checked).
- SubtitleProfiles: `vtt` (External/Hls), `mov_text` (Embed). `pgssub, dvdsub, ass/ssa`:
  - MVP: `Encode` (burn-in on the server) for PGS, VobSub, and ASS when they are selected. For ASS, the alternative is a `vtt` conversion, in which case styles are lost (a setting, default = conversion).
  - M14: client-side rendering.
- `MaxStreamingBitrate`: LAN 120 Mbps (ASSUMPTION) and, for a remote connection, the user's setting (default 20 Mbps). P1: an automatic value measured with `GET /Playback/BitrateTest`.
- **Diagnostics overlay** (Settings → "Show playback info" (fi: "Asetukset → Näytä toistotiedot"), or the Info panel during playback): PlayMethod, `TranscodeReasons`, the source and target codecs, bitrate, and buffer. The user and the Tester immediately see why transcoding happens.

## The playback view and the Siri Remote
- **Liquid Glass:** playback chrome is the system's (`AVPlayerViewController`), which is assumed to get a glass appearance on tvOS 26 automatically (⚠️ verified in ADR M05-1). The only custom chrome elements are the trickplay overlay (PB2, ADR M08-1) and a possible custom scrub bar. A custom transport bar is otherwise not built, except on M14's VLC path, where a custom bar mimics the system's glass appearance (`glassEffect` inside a `GlassEffectContainer`). During playback, at most one custom glass overlay is visible (G-3). Subtitles are not glass.
- **The native `AVPlayerViewController`** (the transport bar, clickpad scrubbing, a ±10 s click left/right, swipe scrubbing, and the Info panel by swiping down).
- The panel's contents: `transportBarCustomMenuItems` (tvOS 15+) for audio, subtitle, quality, and speed menus, if the native `AVMediaSelectionGroup` menu does not cover every track (for example the server's external subtitles). `customInfoViewControllers` shows the episode's details and a Next Up tab (fi: "Seuraavat jaksot").
- **Frame-rate and dynamic-range matching:** `appliesPreferredDisplayCriteriaAutomatically = true`. Behavior depends on the user's tvOS settings (Match Content), and settings tell the user about it.
- Now Playing and MPRemoteCommandCenter: title, series, image, and runtime to Control Center. It also works with the iPhone's Remote app.
- **Focus during playback:** when the transport bar is hidden, the only focusable element is a possible "Skip intro" (fi: "Ohita intro") button.

## Features and acceptance criteria
| ID | Feature (pain point) | Requirement | Acceptance criterion |
|---|---|---|---|
| PB1 | Scrubbing and seeking (pain point 1) | Native scrubbing in every PlayMethod. During transcoding, a seek requests a new stream with `StartTimeTicks` if HLS does not extend to the position. | Seeking to any position works in direct play (P7 ≤ 1.0 s) and in transcoding (≤ 3 s). A ±10 s click works. 20 consecutive seeks do not stall playback. |
| PB2 | Trickplay preview | **ADR M08-1 DECIDED (v1.1, the Researcher verified):** `AVPlayerViewController` shows scrub thumbnails only if the HLS master has an `#EXT-X-I-FRAME-STREAM-INF` variant. **Jellyfin does not produce it**, because its trickplay is JPEG sprites (tile images). Therefore **a custom scrubbing overlay is built with Jellyfin's trickplay sprites**, and no server plugin is required. Metadata comes from the field `fields=Trickplay` (`TrickplayInfoDto{Width, Height, TileWidth, TileHeight, ThumbnailCount, Interval}`), and images from `GET /Videos/{id}/Trickplay/{width}/{index}.jpg` (the tile is cropped from the index `floor(pos/Interval)`). Tiles are preloaded when scrubbing starts (the current ± 2 tiles), and the LRU memory is at most 20 tiles. The overlay shows the thumbnail and the timestamp above the scrub position in a glass panel (M05, G-3: at most one custom overlay). Implementation: tracking the native transport bar's scrub state, or, if that cannot be read reliably, a custom scrub bar (`playbackControlsIncludeTransportBar = false` + Siri Remote pan gestures) alongside the native info and menu panels. ⚠️ Which one is possible is resolved in the prototype. A native-like feel is a requirement (clickpad scrubbing, a ±10 s click). **Optional alternative:** a third-party "native trickplay" server plugin that produces an I-frame variant (10.11 only) is mentioned to users, but it is not required. | Trickplay data exists → the thumbnail appears within P8's limits (≤ 150 ms from cache). No data → scrubbing works without a thumbnail. Scrubbing feels native (a UI test and the Tester's assessment of a screen recording). |
| PB3 | Track change on the fly (pain point 3) | Audio and subtitles are one press away in the Info panel. Embedded tracks (MP4/HLS) are switched with `AVMediaSelectionGroup` without a reload. If a track requires a server-side change (for example transcoding or burn-in), PlaybackInfo is requested with a new `AudioStreamIndex`/`SubtitleStreamIndex`, and playback continues from the same position. | An embedded track switches in ≤ 1 s without an interruption (P9). A server-side switch ≤ 4 s, and the position is preserved within ± 2 s. The selection is reported in Progress. |
| PB4 | Default track selection | The user's Jellyfin settings are used (`AudioLanguagePreference`, `SubtitleLanguagePreference`, `SubtitleMode`). ⚠️ The fields come from the `Configuration` part of the `/Users/Me` response, to be checked. Per-series memory: if the user changes the track on an episode, the same language is chosen for the next episode (P1). | Fixture: the user's language is fi and the movie has fi and en tracks → fi is chosen. |
| PB5 | Subtitle rendering (tvOS 26's CJK-box bug) | External subtitles that contain text (SRT/VTT → `Stream.vtt` from the server) are rendered with a custom `SubtitleOverlay` view using the system font, which has a CJK fallback, or natively if a test shows that native works. Style settings: size, background, and position (P1). | Test media with Japanese, Chinese, and Korean SRT plus ASS (converted) → the characters render correctly in the tvOS 26 and 27 simulators and on device (screenshot). No boxes. |
| PB6 | Media segments: intro, recap, outro, preview, and commercial (pain point 7) | `GET /MediaSegments/{id}` at the start of playback. When a segment starts, a `contextualActions` button is shown, "Skip intro" (fi: "Ohita intro") / "Skip recap" (fi: "Ohita kertaus") (tvOS 15+ native). A setting per segment type: **"Ask" (fi: "Kysy") (default) / "Skip automatically" (fi: "Ohita automaattisesti") / "Do nothing" (fi: "Älä tee mitään")** (the Android TV model). The button disappears when the segment ends. | A mock segment Intro 60–150 s → the button is visible at 60 s and disappears at 150 s. A press seeks to 150 s. Auto mode skips without a press. No segments (server < 10.10, or no data) → no error. |
| PB7 | The next episode automatically (pain point 4) | The next episode is fetched with `GET /Shows/{seriesId}/Episodes?startItemId=&limit=2` or NextUp. When the Outro segment starts (or 30 s before the end, if there is no segment), a card is shown, "Next: S1E3 – name" (fi: "Seuraava: S1E3 – nimi") (a custom `glassEffect` panel, ConcentricRectangle, a thumbnail, Reduce Transparency → opaque) and a 10 s countdown, and the actions are "Play now" (fi: "Toista nyt") (`.glassProminent`, default focus) and "Cancel" (fi: "Peru") (`.glass`). After the countdown the next episode starts with the same track languages. A setting on/off. P1: "Are you still watching?" (fi: "Katsotko vielä?") after three automatic episodes with no user action. | The last episode → no card. Otherwise a 10 s countdown → the next episode starts, and the previous one is reported with Stopped and marked played on the server. "Cancel" (fi: "Peru") → playback continues to the end, and Menu returns to the episode view with focus on the next episode. |
| PB8 | Resume | `StartTimeTicks` = `UserData.PlaybackPositionTicks`. Detail has "Resume" (fi: "Jatka") and "Start over" (fi: "Alusta"). | Resume starts within ± 2 s of the saved position. |
| PB9 | The played state updates (pain point 2) | Reporting per items 4–6. Stopped updates `UserDataStore` immediately. | P14 ≤ 2 s. The server's dashboard shows an active session with the correct PlayMethod. |
| PB10 | HDR and Dolby Vision | DV P5/P8 and HDR10 play natively when the display supports them. Otherwise the server tone-maps (DeviceProfile). | The test matrix's HDR10, DV P5, and DV P8.1 MP4 files → DirectPlay and the correct display mode (device test). |
| PB11 | Audio | E-AC-3 (Atmos JOC) and AC-3 directly. DTS, DTS-HD, and TrueHD → the server transcodes the audio (E-AC-3 or multichannel AAC, keeping the channels), and the video is copied (DirectStream). An explanation for the user in the Info panel. | MKV (HEVC + TrueHD 7.1) → DirectStream, video copy, audio transcode (diagnostics shows it), and playback starts within P6's limits. |
| PB12 | An error during playback | A network drop → a buffering indicator. If playback does not recover within 30 seconds, an error message and "Try again" (fi: "Yritä uudelleen"), which continues from the same position. Token 401 → per 02's error table. | Cutting the network for 10 s → playback continues when the connection returns, without user action. |
| PB13 | Aspect ratio and zoom | P1: Aspect fill / fit (`videoGravity`). | – |
| PB14 | Playback speed | P1: 0.5–2× (`AVPlayer.rate`, the native speed menu on tvOS 16+). | – |
| PB15 | Chapters | P1: a chapter list in the Info panel (`fields=Chapters`) and a jump to a chapter. | – |

## Test-media matrix (CI integration and device tests)
The Tester maintains the list, and the files are on the test server:
1. MP4 H.264 AAC stereo (DirectPlay)
2. MP4 HEVC 10-bit HDR10, E-AC-3 5.1 Atmos (DirectPlay)
3. MP4 DV P8.1, MP4 DV P5 (DirectPlay)
4. MKV H.264 AC-3, external SRT + embedded (DirectStream)
5. MKV HEVC TrueHD 7.1, PGS (DirectStream and audio transcode, PGS burn-in → Transcode)
6. MKV HEVC DTS-HD MA, ASS (DirectStream and audio transcode, ASS → VTT)
7. AVI MPEG-4 Part 2 (Transcode)
8. A 50–80 GB UHD remux MKV (R2 performance)
9. An episode with intro and outro segments and trickplay data
10. CJK subtitles (ja, zh, ko)
11. VobSub (12.0 supports it)

## Module acceptance criteria
- [ ] PB1–PB12 are met. Each has an automatic test where that is possible (PlaybackCoordinator with a mocked engine and API), and a device test is recorded.
- [ ] Test-matrix files 1–7 and 9–11 play with the expected PlayMethod (diagnostics recorded).
- [ ] The reporting sequence Start → Progress×N → Stopped is verified with the mock API, including pause, seek, a track change, and an error (`Failed=true`).
- [ ] No token URLs in logs (S5).
- [ ] Memory P12/P13 and start P5/P6 are met.
- [ ] ADR M08-1 (a custom trickplay overlay) is recorded: tracking the native scrub state, or a custom scrub bar.
- [ ] ADR M08-2 (media-token header / resource loader / ApiKey fallback, and self-signed media) is recorded before M08a's playback path is implemented, and it has a separate result for the three cases: direct play, the server's HLS transcoding, and our own loopback remux.
- [ ] The URL given to AVPlayer is always the final URL resolved by `MediaURLBuilder`. Mock tests: a cross-host or HTTPS→HTTP redirect of an `ApiKey` URL → playback is rejected, and same-host HTTPS → playback starts.
- [ ] Reporting never has a negative `PositionTicks` value (M01's tick rules), and an unknown duration does not show a progress bar.

## M08b – on-device remux (P1)
- **Prerequisites:** the LGPL conditions L1–L5 (SPEC.md §7 R9): FFmpeg without the `--enable-gpl` and `--enable-nonfree` options, a dynamic framework, a CI check, `THIRD_PARTY_LICENSES`, and the license view. Also, the R2 prototype has passed: an 80 GB UHD remux starts in ≤ 3 s, a seek in ≤ 2 s, memory ≤ 500 MB, and a 2-hour playback has no dropouts.
- Scope: `RemuxEngine` implements `PlaybackEngine` (FFmpeg demuxes MKV → fMP4 segments → a local HLS server or `AVAssetResourceLoader`). It is chosen in the DeviceProfile as direct play for an MKV container when the codecs are AVPlayer-compatible.
- An FFmpeg-based library: an LGPL build only. For example an LGPL-2.1+ FFmpeg build shipped as dynamic frameworks, or our own build. **kingslay/FFmpegKit (GPL-3.0) is forbidden.** Security updates per S6.3.
- An extra benefit: playback from self-signed servers (the S4.4 risk), because the network traffic goes through the app's own URLSession.

## Clarifications v1.3.3 (22.10.2026)
- **Q8-2-01, the scope of ADR M08-2 and the test environment:**
  - Queue C resolves case 1 (direct play) and case 2 (the server's HLS). Case 3 (loopback remux) moves to M08b, because it requires FFmpeg. The ADR records for case 3 only the planned token-free model.
  - macOS runners do not have Docker. Therefore simulator tests run against an in-test mock HTTP(S) server. The mock server serves a small static MP4 plus an HLS playlist and segments, some of which require a header and some `ApiKey`.
  - The self-signed certificate is created during the CI run with `openssl`. The key is not committed.
  - Against a real Jellyfin server (Linux Docker), only URL and token construction plus `PlaybackInfo` and `TranscodingUrl` are tested, not playback.
  - Verification of real transcoding and playback on a device or a local server is done before M08a is merged.
