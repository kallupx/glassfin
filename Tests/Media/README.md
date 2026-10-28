# Test media

Generated media stays outside the repository. Run
`scripts/generate-playback-media.sh MEDIA_DIRECTORY [FFMPEG_PATH]` on Linux or
macOS; both integration runners use the same seed.

- Six movies F1–F6: F1/F3 are about 60 seconds, F2/F4/F5/F6 are six seconds.
- `Shows/Glassfin Test Show (2026)/Season 01`: three 60-second H.264/AAC episodes.
- `Season 02/Glassfin Test Show S02E01.mp4`: one six-second episode.
- Local NFO metadata fixes series/episode titles and 2026 air dates without online providers.

The two-season seed supports TPOC-24/38/39; TPOC-82 is a mock-only single-season
picker journey. The bootstrap waits for two seasons and four probed episodes.
All patterns and sine waves are synthetic and dedicated to CC0.
