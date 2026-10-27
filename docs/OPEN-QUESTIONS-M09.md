# M09 open questions

The question numbers below match the canonical plan, [TESTPLAN-M09.md](../spec/TESTPLAN-M09.md). Automation gaps and environment limitations for every test ID are listed in [M09-TEST-MAPPING.md](M09-TEST-MAPPING.md).

| Question | Current behavior / decision needed |
|---|---|
| Q9-02 | Query eligibility and transmission trim surrounding whitespace. Confirm this policy. |
| Q9-03 | Maximum query length is unspecified in the module spec. Canonical plan assumes 100 graphemes; implementation alignment is pending. |
| Q9-04 | Search state is retained for the app session when leaving the tab. Confirm retention lifetime. |
| Q9-05 | A failed parallel request currently fails the entire initial query. Canonical plan expects successful sibling rows; choose hidden failed rows or inline errors. |
| Q9-06 | Completed successful queries, including zero results, are recorded. Canonical plan assumes recording when opening a result. |
| Q9-07 | Duplicate comparison is exact text. Canonical plan assumes trimmed, case-insensitive matching. |
| Q9-08 | Clear all is immediate in the Search view. Confirm whether individual deletion or confirmation is needed. |
| Q9-09 | Offline behavior needs explicit request preflight and recent-query usability verification. |
| Q9-11 | One Han (including supplementary Han), kana, half-width kana, Hangul syllable or jamo grapheme is eligible. Confirm script ranges. |
| Q9-12 | Full M07 navigation is absent from this branch. The current session-scoped detail shows bounded literal name and overview. Integrate movie/series detail and episode season/focus when M07 lands. |
| Q9-16 | Rows page automatically. Confirm whether P0 should instead show exactly 24 with no additional pages. |

Q9-01 is resolved: three parallel `/Items` requests remain the default. ADR-M09-1 proposes a 20% median improvement with no p95 regression on every supported version before changing to hints; benchmark evidence is still pending. Q9-10 follows the final shared state rule: keep visible content with the `.serverUnreachable` banner; use the existing blocking key only when there is no content. Q9-13 keeps people, collections and music outside P0. Q9-14 and Q9-15 are resolved by S6.1/S6.6/S6.7; implementation verification is recorded in the mapping.

Q6-20 and Q7-25 are resolved owner decisions, not open questions: separate Continue Watching and Next Up home rows; per-season episodes with a season picker. This branch has no M06/M07 feature implementation to adjust.

Docker, Xcode, Apple simulators and ImageIO are unavailable locally. Live endpoint evidence, Apple UI/snapshots, actual thumbnail decoding and physical-device timing/memory still require their designated environments.
