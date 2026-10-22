# M13 – Live TV and recordings (P1)

**Spec version:** v1.3.3 (22.10.2026). Changes are shown in SPEC.md's change history.

**Dependencies:** M08. **Pain point:** "Live TV has no audio, or it crashes."

## Scope
- A channel list (`GET /LiveTv/Channels`), a program guide (EPG) as a grid (`GET /LiveTv/Programs`, paged with a time window), recommended (`GET /LiveTv/Programs/Recommended`), plus recordings (`GET /LiveTv/Recordings`) and timers (`GET`/`POST /LiveTv/Timers`).
- Playback: `PlaybackInfo` and `AutoOpenLiveStream=true` → `LiveStreamId`, reporting with `LiveStreamId`, and `Ping`. Channel change up/down during playback (P2).
- **Audio requirement:** a live stream's audio is always transcoded to something AVPlayer can play (AAC or AC-3) if the source is MPEG-TS and MP2/AC-3 is not supported. The DeviceProfile contains a live-specific TranscodingProfile.
- 12.0: the server no longer returns "server-local" stream URLs, which reduces errors.

## Acceptance criteria
- [ ] A channel starts within ≤ 5 s, and audio is heard on the test channels (MPEG-TS MP2, AC-3, and AAC).
- [ ] 2 hours of live playback without a crash (memory P12).
- [ ] EPG scrolling at 60 fps (P3), and the current program is highlighted.
