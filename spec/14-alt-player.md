# M14 – An alternative playback engine (P1, Infuse parity)

**Spec version:** v1.3.3 (22.10.2026). Changes are shown in SPEC.md's change history.

**Dependencies:** M08, the `PlaybackEngine` protocol. **License:** no longer a blocker (the app is open source, MPL-2.0 proposal). The LGPL conditions L1–L5 (SPEC.md §7 R9) are mandatory.

## Why
Infuse plays, among other things, MKV, DTS-HD, TrueHD (decoded to PCM), and PGS directly. On the AVPlayer path these require server transcoding or burn-in (M08 PB11, PB5). The user's goal "at least as good as Infuse" is therefore not met by the MVP alone (see SPEC.md conflicts).

## Options (verified 21.10.2026)
| Library | License | Notes |
|---|---|---|
| VLCKit (videolan/vlckit) | **LGPL-2.1** (the GitHub repo); libVLC LGPL-2.1+ | Swiftfin uses it and recommends it. According to the Researcher, DV and HDR10+ work only at fallback level, and HomePod problems have been reported. Third-party App Store apps ship it as a dynamic framework (for example Swiftly Player, Sotto). |
| MPVKit (mpvkit/MPVKit) | **LGPL** (the default build) / GPL (the `MPVKit-GPL` variant, samba) | README: "only suitable for learning libmpv and will not be maintained too frequently". ⚠️ A maintenance risk. mpv is GPLv2+ by default and LGPLv2.1+ only with a `-Dgpl=false` build, and mpv's own Copyright file notes that a build flag alone does not create an LGPL license. |
| FFmpeg alone + custom rendering | LGPL-2.1+ (without `--enable-gpl`/`--enable-nonfree`) | A large amount of work. |

**Allowed builds (L1):** VLCKit as an LGPL build without GPL modules, and MPVKit's LGPL variant (mpv `-Dgpl=false`). **`MPVKit-GPL` and kingslay/FFmpegKit (GPL-3.0) are forbidden.** The libraries are embedded as dynamic frameworks (L2), and the CI check (L3) is in use.

**Recommendation (ASSUMPTION):** VLCKit (an LGPL build, a dynamic framework) as the fallback path for formats that the AVPlayer and remux paths do not cover. The engine is chosen automatically per file (PGS/ASS/DTS/TrueHD direct play) or by a user setting. The native UI is kept, because the VLC path gets its own transport bar that mimics the native one.

## Acceptance criteria
- [ ] Test-matrix files 5 and 6 play in **DirectPlay** mode on the VLC path: PGS and ASS render with their styles, and TrueHD/DTS are decoded to PCM.
- [ ] Switching the engine does not change reporting, segments, or next-up behavior (the same `PlaybackCoordinator`).
- [ ] L1–L5 are met: M00's CI license check is green, VLCKit/MPV is listed in `THIRD_PARTY_LICENSES` with source-code links, and it appears in M10's license view.
