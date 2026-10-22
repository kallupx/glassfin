# M08 – Video playback (P0, the most important module)

**Dependencies:** M01, M02, M03, M05, and M07. **Prerequisite for M08b:** performance prototype R2 has passed, and LGPL conditions L1–L5 are met (SPEC.md §7 R9). The license is no longer a blocker, because the app is open source and the license proposal is MPL-2.0.
**Background (Researcher, part 3):** AVPlayer does not open MKV and does not support DTS, TrueHD, PGS, or ASS. Its strengths are the native UI, frame-rate and HDR matching, and Dolby Vision P5/P8. Apple TV does not bitstream TrueHD or DTS on any client, and Atmos works only through DD+ (E-AC-3 JOC).

## Split
| Part | Contents | Priority |
|---|---|---|
| **M08a** | AVPlayer path: direct play (MP4/MOV/M4V) plus the server's DirectStream (remux to HLS, video copied) and Transcode. DeviceProfile, reporting, native transport bar, tracks, media segments, trickplay, and next episode. | **P0 (MVP)** |
| **M08b** | On-device FFmpeg remux (MKV → fMP4/HLS locally) → AVPlayer. Reduces server load and keeps DV inside MKV. | **P1** (prerequisite: R2 prototype, LGPL conditions L1–L5) |
| **M14** | An alternate playback engine (VLCKit or MPVKit) for PGS, ASS, and DTS/TrueHD decode without transcoding. Infuse parity. | P1 (LGPL conditions L1–L5) |

**DEFAULT – needs the user's confirmation:** the MVP playback path is **AVPlayer plus the server's DirectStream/Transcode fallback**. A fallback is required anyway. On-device remux is now allowed from a license point of view (MPL-2.0 proposal and LGPL conditions, SPEC.md §7 R9), but it stays P1 because its performance on 50–80 GB files is unverified (R2). It is added in M08b once the R2 prototype meets the metrics.

## Player abstraction (GlassfinCore/CorePlayback)
```swift
public protocol PlaybackEngine: AnyObject, Sendable {           // AVPlayerEngine (P0), RemuxEngine (M08b), VLCEngine/MPVEngine (M14)
  var state: AsyncStream<PlaybackState> { get }                 // idle, loading, playing, paused, buffering, ended, failed(PlaybackError)
  var position: Duration { get }
  func load(_ source: PlaybackSource, startAt: Duration) async throws
  func play(); func pause(); func seek(to: Duration) async
  func select(audio: Track.ID?) async throws; func select(subtitle: Track.ID?) async throws
}
public protocol PlaybackCoordinator { /* PlaybackInfo → engine choice → reporting → segments → next-up; testable without UI */ }
```
- `PlaybackCoordinator` is UI-independent, so iOS uses it as-is. The tvOS UI is an `AVPlayerViewController` wrapper (`UIViewControllerRepresentable`).

## Starting playback (sequence)
1. The user presses Play or Resume → `POST /Items/{id}/PlaybackInfo` with body `{DeviceProfile, UserId, StartTimeTicks, MaxStreamingBitrate, AudioStreamIndex?, SubtitleStreamIndex?, MediaSourceId?, EnableDirectPlay:true, EnableDirectStream:true, EnableTranscoding:true, AllowVideoStreamCopy:true, AllowAudioStreamCopy:true}`.
2. From the response, choose `MediaSources[0]` (or the version the user picked):
   - `SupportsDirectPlay` → `GET /Videos/{id}/stream?static=true&mediaSourceId=&playSessionId=&deviceId=&ApiKey=` (PlayMethod `DirectPlay`).
   - otherwise `TranscodingUrl` (server HLS; `DirectStream` when video and audio are copied, otherwise `Transcode`). The URL is relative, so it is joined to the server base URL. Check that it contains `ApiKey`, or add it. **The URL is not logged** (S5.1).
3. `AVURLAsset` → `AVPlayerItem`. `preferredForwardBufferDuration` may stay at the default.
4. First frame → `POST /Sessions/Playing` (PlaybackStartInfo: ItemId, MediaSourceId, PlaySessionId, PlayMethod, PositionTicks, AudioStreamIndex, SubtitleStreamIndex, CanSeek).
5. Progress: `POST /Sessions/Playing/Progress` every 10 s **and immediately** on pause, resume, after a seek, and on a track change (`IsPaused`, `PositionTicks`). For transcode sessions, also `POST /Sessions/Playing/Ping` if the server requires it (DEFAULT: 30 s).
6. Stop (Menu, end, or error) → `POST /Sessions/Playing/Stopped {PositionTicks, PlaySessionId, Failed}`. Reporting tolerates a network error: one retry, and a failed Stopped is kept in memory and sent when the connection returns (same app session).
7. **Automatic fallback:** if the AVPlayerItem goes to `.failed`, or the first frame does not arrive within 10 seconds of direct play, PlaybackInfo is requested again with `EnableDirectPlay=false` (→ DirectStream), and then with `AllowVideoStreamCopy=false` (→ Transcode). The user sees only a loading indicator unless everything fails. The final error is plain language ("This file could not be played", details in Diagnostics).

## DeviceProfile (pain point: "unnecessary transcoding")
- Built **at runtime from the device's capabilities**, not from a hard-coded list. Swiftfin's `DeviceProfile` extension is the reference (Researcher report).
- DirectPlayProfiles (AVPlayer):
  - Container `mp4, m4v, mov`.
  - Video `h264, hevc`, and `av1` only if `VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)`.
  - Audio `aac, ac3, eac3, alac, flac, mp3`, and `opus` only if support is confirmed.
- CodecProfiles: HEVC and H.264 levels and bit depth. `VideoRangeType` allows `SDR, HDR10, HLG, DOVI, DOVIWithHDR10, DOVIWithSDR` only when the display and the device support them (`AVPlayer.availableHDRModes`, `eligibleForHDRPlayback`). Otherwise the server tone-maps.
- TranscodingProfiles: `Type=Video, Protocol=hls, Container=mp4 (fMP4)`, VideoCodec `hevc,h264`, AudioCodec `eac3,ac3,aac`, `MaxAudioChannels=8`, `BreakOnNonKeyFrames=true` (check the SDK field names).
- SubtitleProfiles: `vtt` (External/Hls), `mov_text` (Embed). `pgssub, dvdsub, ass/ssa`:
  - MVP: `Encode` (server burn-in) for PGS, VobSub, and ASS when they are selected. For ASS the alternative is a `vtt` conversion, which drops styles (a setting, default = conversion).
  - M14: client-side rendering.
- `MaxStreamingBitrate`: LAN 120 Mbps (DEFAULT) and remote is a user setting (default 20 Mbps). P1: an automatic value from a `GET /Playback/BitrateTest` measurement.
- **Diagnostics overlay** (Settings → Show playback info, or the Info panel during playback): PlayMethod, `TranscodeReasons`, source and target codecs, bitrate, and buffer. The user and the Tester can see immediately why a transcode is happening.

## Playback view and the Siri Remote
- **Liquid Glass:** playback chrome is the system's (`AVPlayerViewController`), which is assumed to pick up a glass appearance automatically on tvOS 26 (verified in ADR M05-1). No custom transport bar or chrome, except on the M14 VLC path, where a custom bar imitates the system glass look (`glassEffect` inside a `GlassEffectContainer`). During playback at most one custom glass overlay is visible (G-3). Subtitles are not glass.
- **Native `AVPlayerViewController`** (transport bar, clickpad scrubbing, ±10 s click left/right, swipe scrubbing, and the Info panel on a swipe down).
- Panel contents: `transportBarCustomMenuItems` (tvOS 15+) for audio, subtitle, quality, and speed menus, if the native `AVMediaSelectionGroup` menu does not cover every track (for example external subtitles from the server). `customInfoViewControllers` shows episode details and a Next episodes tab.
- **Frame-rate and dynamic-range matching:** `appliesPreferredDisplayCriteriaAutomatically = true`. Behavior depends on the user's tvOS settings (Match Content), and Settings explains that.
- Now Playing and MPRemoteCommandCenter: title, series, artwork, and duration to Control Center. Also works with the iPhone Remote app.
- **Focus during playback:** when the transport bar is hidden, the only focusable element is a possible "Skip intro" button.

## Features and acceptance criteria
| ID | Feature (pain point) | Requirement | Acceptance criterion |
|---|---|---|---|
| PB1 | Scrubbing and seeking (pain point 1) | Native scrubbing in every PlayMethod. During transcode, a seek requests a new stream with `StartTimeTicks` if HLS does not reach that position. | Seeking to any position works for direct play (P7 ≤ 1.0 s) and for transcode (≤ 3 s). The ±10 s click works. 20 seeks in a row do not stall playback. |
| PB2 | Trickplay preview | When `Trickplay` data exists (`fields=Trickplay`), scrubbing shows a thumbnail. Images are fetched with `GET /Videos/{id}/Trickplay/{width}/{index}.jpg` (a tile image, cropped with `Interval` / `TileWidth` / `TileHeight`), and tiles are prefetched when scrubbing starts. **Open technical decision (ADR M08-1):** AVPlayerViewController has no public tvOS API for custom scrub thumbnails (unverified). Options: (a) a server HLS I-frame/image playlist, if AVPlayer uses it; (b) a custom overlay on the native transport bar; (c) a custom transport bar. The Coder builds a short prototype before implementation and records the decision. | When trickplay data exists → the thumbnail appears within P8. No data → scrubbing works without a thumbnail. |
| PB3 | Track change during playback (pain point 3) | Audio and subtitles are one press away in the Info panel. Embedded tracks (MP4/HLS) are switched with `AVMediaSelectionGroup` without a reload. If a track needs a server change (for example transcode or burn-in), PlaybackInfo is requested with the new `AudioStreamIndex` / `SubtitleStreamIndex`, and playback continues from the same position. | An embedded track changes within 1 s without a gap (P9). A server switch is within 4 s, and the position stays within ± 2 s. The selection is reported in Progress. |
| PB4 | Default track selection | Use the user's Jellyfin settings (`AudioLanguagePreference`, `SubtitleLanguagePreference`, `SubtitleMode`). The fields come from the `Configuration` section of `/Users/Me`; confirm that. Per-series memory: if the user changes the track on an episode, the same language is selected on the next episode (P1). | Fixture: the user's language is fi and the movie has fi and en tracks → fi is selected. |
| PB5 | Subtitle rendering (tvOS 26 CJK tofu bug) | External subtitles that contain text (SRT/VTT → `Stream.vtt` from the server) are rendered with a custom `SubtitleOverlay` using the system font and a CJK fallback, or natively if a test shows the native path works. Style settings: size, background, and position (P1). | Test media with Japanese, Chinese, and Korean SRT plus ASS (converted) → glyphs render correctly on the tvOS 26 and 27 simulator and on device (screenshot). No tofu boxes. |
| PB6 | Media segments: intro, recap, outro, preview, and commercial (pain point 7) | `GET /MediaSegments/{id}` at the start of playback. When a segment starts, show a `contextualActions` button "Skip intro" / "Skip recap" (tvOS 15+ native). A per-segment-type setting: **Ask (default) / Skip automatically / Do nothing** (the Android TV model). The button disappears when the segment ends. | Mock segment Intro 60–150 s → the button appears at 60 s and disappears at 150 s. A press seeks to 150 s. Auto mode skips without a press. No segments (server < 10.10 or no data) → no error. |
| PB7 | Next episode automatically (pain point 4) | For an episode, fetch the next one with `GET /Shows/{seriesId}/Episodes?startItemId=&limit=2` or NextUp. When the Outro segment starts (or 30 s before the end if there is no segment), show a card "Next: S1E3 – name" (a custom `glassEffect` panel, ConcentricRectangle, thumbnail, Reduce Transparency → opaque) and a 10 s countdown. Actions are "Play now" (`.glassProminent`, default focus) and "Cancel" (`.glass`). After the countdown the next episode starts with the same track languages. A setting turns this on or off. P1: "Are you still watching?" after three automatic episodes with no user action. | The last episode → no card. Otherwise a 10 s countdown → the next episode starts, and the previous one is reported with Stopped and marked played on the server. "Cancel" → playback continues to the end, and menu returns to the episode view with focus on the next episode. |
| PB8 | Resume | `StartTimeTicks` = `UserData.PlaybackPositionTicks`. Detail has "Resume" and "Play from start". | Resume starts within ± 2 s of the saved position. |
| PB9 | Played state updates (pain point 2) | Reporting follows steps 4–6. Stopped updates `UserDataStore` immediately. | P14 ≤ 2 s. The server dashboard shows an active session with the correct PlayMethod. |
| PB10 | HDR and Dolby Vision | DV P5/P8 and HDR10 play natively when the display supports them. Otherwise the server tone-maps (DeviceProfile). | HDR10, DV P5, and DV P8.1 MP4 files from the test matrix → DirectPlay and the correct display mode (device test). |
| PB11 | Audio | E-AC-3 (Atmos JOC) and AC-3 direct. DTS, DTS-HD, and TrueHD → the server transcodes audio (E-AC-3 or multichannel AAC, keeping the channels) and the video is copied (DirectStream). Explained to the user in the Info panel. | MKV (HEVC + TrueHD 7.1) → DirectStream, video copy, audio transcode (diagnostics shows it), and playback starts within P6. |
| PB12 | Error during playback | A network drop → a buffering indicator. If playback does not recover within 30 seconds, an error message and "Try again", which continues from the same position. Token 401 → follow the error table in 02. | Disconnect the network for 10 s → playback continues when the connection returns, without user action. |
| PB13 | Aspect ratio and zoom | P1: Aspect fill / fit (`videoGravity`). | – |
| PB14 | Playback speed | P1: 0.5–2× (`AVPlayer.rate`, native speed menu on tvOS 16+). | – |
| PB15 | Chapters | P1: a chapter list in the Info panel (`fields=Chapters`) and a jump to a chapter. | – |

## Test-media matrix (CI integration and device tests)
The Tester maintains the list, and the files live on the test server:
1. MP4 H.264 AAC stereo (DirectPlay)
2. MP4 HEVC 10-bit HDR10, E-AC-3 5.1 Atmos (DirectPlay)
3. MP4 DV P8.1, MP4 DV P5 (DirectPlay)
4. MKV H.264 AC-3, external SRT + embedded (DirectStream)
5. MKV HEVC TrueHD 7.1, PGS (DirectStream and audio transcode, PGS burn-in → Transcode)
6. MKV HEVC DTS-HD MA, ASS (DirectStream and audio transcode, ASS → VTT)
7. AVI MPEG-4 Part 2 (Transcode)
8. 50–80 GB UHD remux MKV (R2 performance)
9. An episode with intro and outro segments and trickplay data
10. CJK subtitles (ja, zh, ko)
11. VobSub (supported in 12.0)

## Module acceptance criteria
- [ ] PB1–PB12 are met. Each has an automatic test where that is possible (PlaybackCoordinator with a mocked engine and API), and the device test is recorded.
- [ ] Test-matrix files 1–7 and 9–11 play with the expected PlayMethod (diagnostics recorded).
- [ ] The reporting sequence Start → Progress×N → Stopped is verified with a mock API, including pause, seek, track change, and error (`Failed=true`).
- [ ] No token URLs in logs (S5).
- [ ] Memory P12/P13 and start P5/P6 are met.
- [ ] ADR M08-1 (trickplay implementation) is recorded before PB2.

## M08b – on-device remux (P1)
- **Prerequisites:** LGPL conditions L1–L5 (SPEC.md §7 R9): FFmpeg without `--enable-gpl` and `--enable-nonfree`, a dynamic framework, a CI check, `THIRD_PARTY_LICENSES`, and an in-app license view. Also an R2 prototype that has passed: an 80 GB UHD remux starts within 3 s, seek within 2 s, memory ≤ 500 MB, and a 2-hour playback has no dropouts.
- Scope: `RemuxEngine` implements `PlaybackEngine` (FFmpeg demux MKV → fMP4 segments → a local HLS server or `AVAssetResourceLoader`). Chosen in the DeviceProfile as direct play for an MKV container when the codecs are AVPlayer-compatible.
- FFmpeg-based library: LGPL build only. For example an LGPL-2.1+ FFmpeg build shipped as dynamic frameworks, or our own build. **kingslay/FFmpegKit (GPL-3.0) is forbidden.** Security updates follow S6.3.
- Extra benefit: playback of self-signed servers (the S4.4 risk), because the traffic goes through the app's own URLSession.
