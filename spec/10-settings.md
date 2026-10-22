# M10 – Settings and diagnostics (P0 minimum, P1 extension)

**Spec version:** v1.3.3 (22.10.2026). Changes are shown in SPEC.md's change history.

**Dependencies:** M02, M04, and M08 (playback settings).

## P0
- **Account** (fi: "Tili"): the server's name, URL, and encryption indicator (🔒/🔓), the user, and "Sign out" (fi: "Kirjaudu ulos") (confirmation, S2.1).
- **Playback** (fi: "Toisto"):
  - The media-segment action per type ("Ask" (fi: "Kysy") / "Skip" (fi: "Ohita") / "Do nothing" (fi: "Ei mitään")), PB6
  - The next episode automatically (on/off), PB7
  - Max bitrate for a remote connection
  - ASS handling (conversion to VTT / burn-in)
- **Subtitles** (fi: "Tekstitys"): size and background (P0, if SubtitleOverlay is in use in PB5).
- **About** (fi: "Tietoja"): the app version, the server version, the app's own license (MPL-2.0, a proposal), and a link to the source repo.
- **Licenses (L5, mandatory, SPEC.md §7 R9):** lists every third-party component, such as jellyfin-sdk-swift (MPL-2.0), Get, and swift-nio-transport-services, and in the P1 phase FFmpeg, VLCKit, and MPV. Each shows the license text, the version, and a source-code link. For FFmpeg, the notice "This software uses libraries from the FFmpeg project under the LGPLv2.1" is included. The view is generated at build time from the same data as the repo's `THIRD_PARTY_LICENSES`. On tvOS, links cannot be opened, so the URL is shown as text (and as a QR code in P2).
- **Diagnostics** (fi: "Diagnostiikka"): connectivity, the latest playback's PlayMethod and TranscodeReasons, the cache size, and "Clear cache" (fi: "Tyhjennä välimuisti"). The log excerpt is redacted (S5).

## P1
- Several servers and users (M15), the home view's row order and Up Next combining, subtitle styles, per-series track memory, "Are you still watching?" (fi: "Katsotko vielä?"), the choice of Top Shelf content, and theme music and theme video on detail.
- Storage: UserDefaults (< 50 KB budget, 02). Jellyfin's per-user settings (languages, SubtitleMode) are read from the server. Writing them to the server is P2.

## Acceptance criteria
- [ ] Every P0 setting affects behavior (a unit test per setting: for example segment "Skip" (fi: "Ohita") → an automatic seek).
- [ ] Settings survive a restart.
- [ ] The license view lists every third-party dependency, and the contents match the `THIRD_PARTY_LICENSES` file (CI compares them in M00). A new dependency without a license entry fails CI.
- [ ] Diagnostics shows no tokens (an S5 test).
