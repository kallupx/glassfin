# Test plan – M05 (design system: Liquid Glass) and the ADR M05-1 prototype

**Author:** Testaaja · 2026-10-22 · **Based on:** spec/05-design-system.md, 02-state-errors-performance.md, 03-security.md, 07-library-detail.md (focus rules), 11-ios-ui.md, 00-infra-ci.md, SPEC.md, all v1.3.3 (2026-10-22). **Updated 2026-10-22:** 05's "Clarifications v1.3.3" are taken into account.
**Environment:** Testaaja runs Linux. Snapshots and XCUITests run in CI's `full-ui` job: ready-for-review state, main push or the `full-ci` label on a draft (00 "Public repo"). The simulators are "Apple TV 4K (3rd generation)" (4K) and "(at 1080p)". Testaaja reviews the PNG images and diffs on Linux. A8, A10X and A12 device tests are done by Koodari or the user (SPEC §8 R7).
**Work queue:** Queue B, depends only on M00. ADR M05-1 is done before M06 (SPEC §3).

**References:** `05 §n` = section of 05-design-system.md · `L-n` / `G-n` = legibility and glass budget rules · `05 HK` = acceptance criteria · `02 Pn` = 02's performance table · `07 FS n` = 07's focus rule n · `Sx.y` = 03-security.md. (Short codes HK, FS and T1.3.3 are kept as reference codes.)
**Run:** **L** = Linux `swift test` (⚠️ UI code does not compile on Linux, so only possible pure helper functions) · **X** = macOS XCTest · **U** = macOS XCUITest · **S** = snapshot (1080p + 4K, PNG diff) · **K** = review or Linux CI lint script · **M** = manual device test or screen recording.
**🔒** = raised to Turvallisuus.
**UI strings:** labels are given as the English dev-language string (`Localizable.xcstrings`) with the Finnish localization in parentheses. Snapshots and XCUITests run in the `en` locale; tests identify elements by `accessibilityIdentifier` (T05-22) or catalog key, not by hardcoded label text.

## Structural rules and build
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T05-01 | Glass surfaces vs the §2 table | Glass only in the tab bar, button rows, season picker, filter bar, banner, trickplay and next-up overlays and the sign-in panel. Not on cards or subtitles | 05 §2, 05 HK | K, S |
| T05-02 | Custom glass elements | Every custom `glassEffect` is inside a `GlassEffectContainer` (review and grep). `GlassBanner` is an exception case (Q5-02) | 05 §1.2, 05 HK | K |
| T05-03 | Custom backgrounds, shadows and borders on controls or navigation | Lint script or review finds 0 hits. SwiftLint's `custom_rules` does not work in the Linux container, so the rule is implemented as a script | 05 §1.3, 05 HK, 00 `lint` v1.3.2 | K |
| T05-04 | Custom blur layer on top of glass | None | 05 §1.3 | K |
| T05-05 | Text colors on glass | Only system vibrant and semantic colors (`.primary`, `.secondary`), no hardcoded ones | 05 §1.6, L-2 | K, S |
| T05-06 | `Glass.tint` usage | Only for meaning, e.g. the Play button with the accent color | 05 §1.4 | K |
| T05-07 | Build with the tvOS 26 SDK (`macos-26` + Xcode 26) and the tvOS 27 SDK | Compiles without `#available` checks, and the deployment target is 26 | 05 §0, 00 Image risk | X |
| T05-08 | iOS target with the same design system components | Compiles with the iOS 26 minimum (`test-ios`) | 05 §0, 11 Policy | X |

## Components (§7)
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T05-09 | `PosterCard` focused and unfocused, fixtures: progress 0 / 50 / 100 %, watched, episode counter and unknown duration | 2:3 poster, title below only when focused, and `ConcentricRectangle` corners. With an unknown duration no progress bar is shown | 05 §7, 01 HK tick limits | S |
| T05-10 | `PosterCard`: long press | The context menu opens. The card is `.buttonStyle(.card)` (native lift and parallax), no glass | 05 §7, 05 §2 | U |
| T05-11 | `LandscapeCard` | 16:9 Thumb or Backdrop, progress and "32 min left" (fi: "32 min jäljellä") | 05 §7 | S |
| T05-12 | `MediaRow` focus memory: row 2 item 5 → up to row 1 → down | Focus returns to row 2 item 5, not to the geometrically nearest one | 05 §7, 05 §3, 05 HK | U |
| T05-13 | `HeroHeader` opens | Play has the default focus, and it is `.glassProminent` | 05 §7, 05 HK | U, S |
| T05-14 | `HeroHeader`: up and down navigation past the description | The description does not get focus, and "More" (fi: "Lisää") opens the full text | 05 §7, 05 HK, SPEC K5 | U |
| T05-15 | 🔒 `HeroHeader`: overview contains HTML (`<a href>`, `<script>`, `&amp;`) | Shown as plain text: tags are stripped, HTML and Markdown are not rendered, and links cannot be opened | S6.1, S6.2 | X, S |
| T05-16 | `GlassActionBar`: left and right, then down | Moves between the buttons (`.focusSection()`). The down move leaves to the row, and there is no focus trap | 05 §7, 05 §3 | U |
| T05-17 | `GlassActionBar` with 9 buttons | Expected result is open: does the component prevent it, or is the limit only a usage guideline (Q5-07) | G-1 | X, K |
| T05-18 | `GlassBanner` (offline) | Not focusable (focus does not move to it from any direction). Appears ≤ 2 s after the network drops and disappears ≤ 2 s after the connection returns | 05 §7, 05 §2, 02 §3 Offline | U |
| T05-19 | `AsyncPoster`: blurhash → image | Fade 150 ms. The state for an image load error (404, timeout) is open (Q5-08) | 05 §7 | S, X |
| T05-20 | `SkeletonRow` vs the final row | Same dimensions (frame comparison): layout and focus do not jump when loading finishes | 05 §7, 07 Series view | S, X |
| T05-21 | `ErrorStateView` | "Try Again" (fi: "Yritä uudelleen") (`.glassProminent`) has the default focus, and pressing it starts a refetch | 05 §7 | U |
| T05-22 | `accessibilityIdentifier` on every component | Naming `screen.element` | 00 Testability | K, U |
| T05-23 | 🔒 Snapshot fixtures and screenshots | Mock data only: no tokens, QC secrets or passwords. The artifact scan is green | S5.5, 00 Artifacts | K |

## Focus and Siri Remote navigation (§3, §8)
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T05-24 | Standard button focused and unfocused | The glass appearance comes automatically when focused | 05 §0, 05 §3 | S |
| T05-25 | Custom `focusable()` element | `.regular` when focused, otherwise `.identity` (`isFocused`) | 05 §3 | S |
| T05-26 | Focus move inside a `GlassEffectContainer` | The `glassEffectID` morph is visible in the screen recording | 05 §3 | M |
| T05-27 | TabView with 3 libraries and with 7 libraries | Tabs Home (fi: "Koti"), libraries, Search (fi: "Haku") (`Tab(role: .search)`) and Settings (fi: "Asetukset"). With seven libraries 5 are shown and the rest under the "Libraries" (fi: "Kirjastot") tab (ASSUMPTION, Q5-09) | 05 §8, 05 §0 | U |
| T05-28 | Menu chain: detail → library → tab root → tab bar → exit | Back to the previous view, from the root to the tab bar, and exit from the tab bar (system) | 05 §8 | U |
| T05-29 | Focus trap search: up from every focusable element and Menu in every catalog or demo view | The tab bar is always reachable, and no element is left as the only focus target | 05 §3 (M07 FS 1–6 apply) | U |
| T05-30 | Play/Pause in a browse view | Playback starts from the focused item (tested once M06/M07 exist) | 05 §3 | U |

## Legibility and contrast (§4)
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T05-31 | Text over a Backdrop | Always a glass panel or a bottom gradient (black 0 → 60 %, the bottom 40 % of the height) | L-1 | S, K |
| T05-32 | Contrast on three backgrounds (bright Backdrop, dark Backdrop and a busy poster) | Body text ≥ 4.5:1, large text and icons ≥ 3:1. The measurement method is open (Q5-03) | L-3, 05 HK | S |
| T05-33 | Icons | Every icon has an `accessibilityLabel` | L-4 | U, K |
| T05-34 | Content scrolls under the tab bar | The tab bar stays legible (`scrollEdgeEffectStyle`, system default) | L-5 | S |

## Accessibility (§5)
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T05-35 | Reduce Transparency | System components adapt automatically. Custom glass surfaces (banner, Next Up card and sign-in panel) are opaque. The exact color is ⚠️ open (Q5-05) | 05 §5 | S |
| T05-36 | Increase Contrast | Custom glass surfaces have a thin `.separator` border, text is `.primary` and the tint is removed. In the default state there is **no** border (§1.3). The snapshot covers both states | 05 §5, 05 §1.3, 05 T1.3.3/Q5-01 | S |
| T05-37 | Reduce Motion | The `glassEffectID` morph, parallax and background crossfade are removed or replaced with an instant switch | 05 §5 | U, M |
| T05-38 | Bold Text and the largest text size | The layout adapts, and the Play button, error messages or the QC code are not truncated. tvOS 26 vs 27 (Q5-04) | 05 §5, 05 §1.6 | S |
| T05-39 | Snapshot matrix: component × {1080p, 4K} × {default, Reduce Transparency, Increase Contrast, Reduce Motion} | All PNG images and the ref/diff images of failures are artifacts and open on Linux | 05 HK, 00 Artifacts | S |
| T05-40 | Snapshot reproducibility: the same commit run twice | Identical result or within the agreed tolerance (Q5-03) | 05 HK | S |

## Performance (§6)
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T05-41 | Number of glass surfaces in a view (detail and series view) | At most 1 tab bar and 2 `GlassEffectContainer`s at the same time, each with ≤ 8 elements. How the banner is counted is open (Q5-02) | G-1, 07 Glass budget | K, U |
| T05-42 | Scrolling cells (cards, grids) | No glass | G-2 | K |
| T05-43 | During playback (once M08 exists) | Glass only in the system transport bar and one custom overlay | G-3 | K, M |
| T05-44 | Focus scrolling on home and detail on device, Instruments Hitches and Core Animation | A12 < 10 ms/s and 60 fps, A15 < 5 ms/s, A8 < 10 ms/s. The result is recorded for the release | G-4, 05 HK, 02 P3 | M |
| T05-45 | Focus scrolling in a 2,000-item grid on the simulator (`XCTOSSignpostMetric`) | Regression trend only, not an absolute target | 02 P3, 02 §4, 02 v1.3.2 | X |
| T05-46 | Memory while browsing and memory warning | P11 ≤ 250 MB (A15) / ≤ 200 MB (oldest). NSCache images (max 150 MB) are purged on a memory warning | 02 P11, 02 §2 | X, M |

## ADR M05-1 prototype (⚠️ items before M06)
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T05-47 | `.buttonStyle(.card)` focused on tvOS 26 and 27 | Screen recording and snapshot. The ADR records whether the card gets glass or the traditional lift and parallax. The system default is accepted | 05 §0 ⚠️, 05 §2, 05 HK | S, M |
| T05-48 | `AVPlayerViewController`'s transport bar and info panel | The ADR records whether glass comes automatically | 05 §0 ⚠️, 08 Playback view | M |
| T05-49 | `Glass.interactive()` on tvOS | The ADR records whether it has an effect | 05 §0 ⚠️ | M |
| T05-50 | Rendering on Apple TV HD (A8) and 4K 1st generation (A10X) | The ADR records whether the result is blur or opaque. L-3 contrast is also checked without glass | 05 §0 ⚠️, 05 HK | M |
| T05-51 | `Picker(.segmented)` as the season picker on tvOS 26 | The glass style is recorded (whether it belongs in the ADR, Q5-06) | 05 §2 ⚠️ | S, M |
| T05-52 | tvOS "tinted/clear" appearance setting | Whether it exists is recorded (whether it belongs in the ADR, Q5-06) | 05 §0 ⚠️ | M |
| T05-53 | ADR M05-1 document | Every ⚠️ item has a result and evidence (PNG or recording), and the ADR is merged before M06 starts | 05 HK, SPEC §3, SPEC R11 | K |

## iOS (P1, M11)
| ID | Scenario | Expected result | Reference | Run |
|---|---|---|---|---|
| T05-54 | P1 iOS TabView | iOS 26 glass tab bar and `Tab(role: .search)`, on iPad `tabViewStyle(.sidebarAdaptable)` and on iPhone `tabBarMinimizeBehavior` (⚠️ API to be verified) | 05 §8, 11 Principles | U, S |
| T05-55 | P1 iOS touch controls | `Glass.interactive()` on custom touch controls, no `.card` style | 11 Principles | K, S |

## Open questions
| # | Question | Spec wording | For |
|---|---|---|---|
| Q5-01 | **Resolved (Spesifikaatio 2026-10-22)**: Increase Contrast wins. §1.3's border ban applies only to the default state, and in the `.increased` state custom glass surfaces get a `.separator` border (05 T1.3.3). Test T05-36. | §1.3: "**No custom backgrounds, shadows or borders on controls**" · §5: "Thin border (`.separator`) on custom glass surfaces" | Spesifikaatio |
| Q5-02 | Must `GlassBanner` be inside a `GlassEffectContainer`, and does it count toward G-1's two containers? | §1.2: "always inside a `GlassEffectContainer`" · §2: "`glassEffect(.regular, in: .capsule)`" · G-1: "at most one tab bar and two `GlassEffectContainer`s" | Spesifikaatio |
| Q5-03 | How is AA contrast measured on glass (pixel sample, vibrant color, dynamic sampling), and what is the snapshot diff tolerance? | L-3: "checked with snapshot tests on three backgrounds" | Spesifikaatio, Koodari |
| Q5-04 | How does text size scaling work on the minimum version tvOS 26, when the setting is only mentioned in tvOS 27? | §1.6: "Dynamic Type (tvOS 27's Dynamic Text setting)" · §0: "The minimum OS is 26" | Spesifikaatio, Tutkija |
| Q5-05 | Which semantic color is the Reduce Transparency fallback on tvOS? Without it the snapshot reference cannot be locked. | §5: "⚠️ the exact tvOS semantic color is chosen during implementation" | Koodari |
| Q5-06 | Which ⚠️ items belong in ADR M05-1? The acceptance criterion has 4 items, §0 has 5, and §2 additionally has `Picker(.segmented)`. | HK: "⚠️ items (card style glass, AVPlayerViewController glass, A8/A10X rendering, `interactive()` on tvOS)" · §0: "Does tvOS have a Liquid Glass "tinted/clear" appearance setting" · §2: "`Picker(.segmented)` (⚠️ check tvOS 26's glass style)" | Spesifikaatio |
| Q5-07 | Is the 8-element limit enforced by the component or a usage rule? | G-1: "Each container has max 8 elements." | Spesifikaatio |
| Q5-08 | What is `AsyncPoster`'s load error state? Does Reduce Motion apply to the 150 ms fade? | §7: "Blurhash placeholder → image (fade 150 ms)" · §5: "replaced with an instant switch" (the fade is not mentioned) | Spesifikaatio |
| Q5-09 | Is the limit of 5 library tabs confirmed? What is shown when there are 0 libraries? | §8: "(UserViews; ASSUMPTION max 5, the rest under the "Libraries" tab)" | Spesifikaatio, user |
| Q5-10 | Who does the A8, A10X and A12 device tests, and on which devices? CI's simulators are only "Apple TV 4K (3rd generation)" and "(at 1080p)", so old-device rendering and G-4 cannot be verified in CI. | 00: "simulators "Apple TV 4K (3rd generation)" and "(at 1080p)"" · SPEC R7: "Device measurements are done by Koodari or the user" | Koodari, user |
| Q5-11 | Artifact retention: 7 or 14 days? Is `.xcresult` uploaded at all? This affects whether Testaaja has time to review the snapshot diffs. | 00: "`.xcresult`: retention 7 days" · "retention is 7 days (small text artifacts 14 days)" · "Public repo": "`.xcresult` bundles are not uploaded as artifacts, and artifact `retention-days: 14`" | Spesifikaatio, Koodari |
| Q5-12 | **Resolved (Spesifikaatio 2026-10-22)**: all module files and SPEC.md are now v1.3.3 (2026-10-22). | SPEC.md line 1 and line 3 | Spesifikaatio |
