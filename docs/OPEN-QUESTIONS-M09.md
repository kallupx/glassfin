# M09 implementation questions

These conservative defaults do not block P0. Related code carries matching TODO markers.

| Question | Current behavior | Follow-up |
|---|---|---|
| Q9-01: exact meaning of one-character CJK | Accept a single Han (including supplementary Han), kana, half-width kana, Hangul syllable or jamo grapheme; other scripts need two characters. Whitespace is ignored for eligibility. | Confirm the script range policy, including compatibility Han. |
| Q9-02: M07 destination integration on this stacked branch | Search pushes a session-scoped detail destination that loads and shows literal, bounded name and overview. M07's full detail/playback destination is absent from this branch. Search owns its state and per-row focus memory independently. | Replace the small destination when M07 is merged; preserve its selected-item binding and tab ownership. |
| Q9-03: when and how to record a recent query | Record a completed successful request, including zero results. Store trimmed query text only; exact text duplicates move to the front. No locale-dependent case folding. Failed/cancelled/too-short requests are not recorded. | Confirm if case-insensitive deduplication or recording only submitted/selected queries is preferred. |
| Q9-04: “clearly faster” threshold | Retain `/Items` x3. ADR-M09-1 proposes ≥20% median improvement, no p95 regression and sufficient image tags/row coverage on every CI version, confirmed in another run. | Review real Docker artifacts before accepting a switch. |

Security storage decisions are resolved by spec #18: recent history is per server/user, limited to MetadataPolicy.recentSearchesMax, stored in Application Support, excluded from backup, never logged, and cleared on user sign-out, authenticated 401, server removal or explicit user action. It contains only query text. The original M04 sanitizer behavior and M05 components remain compatible; M09 uses the new literal metadata path. Taglines, genres, people and studios are not rendered by the search destination; their shared limits are defined in the identical MetadataPolicy file for M06/M07.

Local limitations: no Docker executable, Xcode, Apple simulators or ImageIO. T09-21/T09-22, UI tests, Apple image decoding, and P10 on-device/LAN timing need their designated environments. The known M05 compile fixes in Demo.swift, GlassChrome.swift and Shell.swift remain on the separate branch; those files were not edited here.
