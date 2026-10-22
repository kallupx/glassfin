# M18 – iOS downloads and offline playback (P2, iOS only)

**Spec version:** v1.3.3 (22.10.2026). Changes are shown in SPEC.md's change history.

**Dependencies:** M11 (iOS UI) and M08. **Not for tvOS:** tvOS has no persistent storage (about 500 KB, and Caches can be purged; Researcher, part 3).

- Download: `GET /Videos/{id}/stream?static=true` (the original) or a server-transcoded version with a quality choice (`AVAssetDownloadURLSession` for HLS).
- Data Protection and exclusion from backup (S8.1).
- Offline viewing progress is synced to the server when the connection returns (Sessions/Playing reporting, or `UserItems/{id}/UserData`).
- Acceptance criteria: an episode downloaded in airplane mode plays, and progress syncs within ≤ 30 s of the connection returning.
