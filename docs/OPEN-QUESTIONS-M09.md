# M09 open questions

The question numbers below match the canonical plan, [TESTPLAN-M09.md](../spec/TESTPLAN-M09.md). Automation gaps and environment limitations for every test ID are listed in [M09-TEST-MAPPING.md](M09-TEST-MAPPING.md).

| Question | Current behavior / decision needed |
|---|---|
| Q9-02 | Query eligibility and transmission trim surrounding whitespace. Confirm this policy. |
| Q9-03 | The canonical default of 100 graphemes is enforced before transmission. Confirm this product limit. |
| Q9-04 | Search state is retained for the app session when leaving the tab. Confirm retention lifetime. |
| Q9-05 | Successful sibling rows remain visible; a failed row is hidden. Confirm this canonical default versus a per-row inline error. |
| Q9-06 | Only opening a result records the query, following the canonical default. Confirm whether explicit submission should also record it. |
| Q9-07 | Comparison trims whitespace and ignores case, following the canonical default. Confirm whether diacritics should also be folded. |
| Q9-08 | Clear all is immediate in the Search view. Confirm whether individual deletion or confirmation is needed. |
| Q9-09 | Offline preflight blocks requests while recent queries remain available for filling the field. Device UI verification is pending. |
| Q9-11 | One Han (including supplementary Han), kana, half-width kana, Hangul syllable or jamo grapheme is eligible. Confirm script ranges. |
| Q9-12 | Full M07 navigation is absent from this branch. The current session-scoped detail shows bounded literal name and overview. Integrate movie/series detail and episode season/focus when M07 lands. |
| Q9-16 | Rows page automatically. Confirm whether P0 should instead show exactly 24 with no additional pages. |

Q9-01 is resolved: three parallel `/Items` requests remain the default. ADR-M09-1 proposes a 20% median improvement with no p95 regression on every supported version before changing to hints; benchmark evidence is still pending. Q9-10 follows the final shared state rule: keep visible content with the `.serverUnreachable` banner; use the existing blocking key only when there is no content. Q9-13 keeps people, collections and music outside P0. Q9-14 and Q9-15 are resolved by S6.1/S6.6/S6.7; implementation verification is recorded in the mapping.

Docker, Xcode, Apple simulators and ImageIO are unavailable locally. Live endpoint evidence, Apple UI/snapshots, actual thumbnail decoding and physical-device timing/memory still require their designated environments.
