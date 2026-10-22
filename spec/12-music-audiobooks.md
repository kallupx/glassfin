# M12 – Music, lyrics, and audiobooks (P1)

**Spec version:** v1.3.3 (22.10.2026). Changes are shown in SPEC.md's change history.

**Dependencies:** M01–M08 (PlaybackCoordinator, the audio engine). **Pain point:** music and audiobook libraries are missing from many clients.

## Scope
- A music library: "Albums" (fi: "Albumit"), "Artists" (fi: "Artistit"), "Tracks" (fi: "Kappaleet"), "Playlists" (fi: "Soittolistat"), and "Genres" (fi: "Genret"). Endpoints: `GET /Items?includeItemTypes=MusicAlbum|Audio`, `GET /Artists/AlbumArtists`, `GET /Artists`, and `GET /Playlists/{id}/Items`.
- Playback: `GET /Audio/{id}/universal` (the container and codec list from the DeviceProfile), `AVQueuePlayer`, shuffle, repeat, gapless (if possible), and Instant Mix (`GET /Items/{id}/InstantMix`).
- The Now Playing view: cover art, progress, and **synchronized lyrics** (`GET /Audio/{id}/Lyrics`, parity with Android TV 0.18).
- Background playback on tvOS: music continues while the user browses elsewhere in the app (a mini-player banner).
- Audiobooks (`AudioBook`): tracks, playback speed, and the resume position. Reporting with the same Sessions/Playing endpoints.
- ReplayGain (`NormalizationGain`; 12.0 parses album gain): volume normalization (a setting).

## Acceptance criteria
- [ ] Album playback, next/previous, shuffle, and Now Playing in Control Center.
- [ ] Lyrics stay in sync within ± 300 ms.
- [ ] An audiobook's resume position is kept across devices (server reporting).
