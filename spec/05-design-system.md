# M05 – Design system: Liquid Glass (P0)

**Spec version:** v1.3.3 (22.10.2026). Changes are shown in SPEC.md's change history.

**Dependencies:** M00. Can be done in parallel with M01–M04.
**The user's decision on 21.10.2026:** Glassfin's UI follows the **Liquid Glass** design language, which Apple introduced with iOS 26 and tvOS 26. The minimum OS is 26, so **no fallback is made for versions older than 26**.

## 0. Verified facts (Apple documentation, checked 21.10.2026)
- **APIs and their tvOS 26.0 availability** (Apple docs JSON metadata): `View.glassEffect(_:in:)`, `Glass` (`.regular`, `.clear`, `.identity`, `.tint(_:)`, `.interactive(_:)`), `GlassEffectContainer`, `View.glassEffectID(_:in:)`, `View.glassEffectUnion(id:namespace:)`, `PrimitiveButtonStyle.glass` and `.glassProminent`, `View.backgroundExtensionEffect()`, `ConcentricRectangle`, and `View.scrollEdgeEffectStyle(_:for:)`. All are available from tvOS 26.0 and iOS 26.0, so they work in shared code without `#available` checks.
- **Apple's "Adopting Liquid Glass" guidance, tvOS:**
  - "standard buttons and controls take on a Liquid Glass appearance **when focus moves to them**." For custom controls, adding a glass effect on focus is recommended through the standard focus APIs (`focusable()`, `isFocused`, `@FocusState`).
  - "Apple TV 4K (2nd generation) and newer models support Liquid Glass effects. **On older devices, your app maintains its current appearance.**"
- **Device support** (Apple Support and MacRumors): tvOS 26 installs on **every Apple TV HD and Apple TV 4K model**, including the 2015 Apple TV HD (A8). Liquid Glass is in use only on **Apple TV 4K 2nd generation (A12, 2021) and 3rd generation (A15, 2022)**. Apple TV HD (A8) and 4K 1st generation (A10X) have the old appearance.
- **Apple's guidance:**
  - Glass belongs to the **navigation layer** (the tab bar, sidebar, toolbars, and controls), not to content.
  - Glass is used sparingly on custom controls ("Avoid overusing").
  - Nearby glass elements are grouped into a `GlassEffectContainer`, because "glass can not sample other glass" and grouping improves performance.
  - Custom backgrounds are not made for controls or navigation elements.
  - Search uses a semantic `Tab(role: .search)` tab.
  - Testing is done with Reduce Transparency, Reduce Motion, and contrast settings, because standard components adapt automatically and custom elements must be tested.
- **Unverified (⚠️):**
  - ⚠️ On tvOS 26, does `.buttonStyle(.card)` get a glass treatment on focus, or does the traditional lift and parallax remain?
  - ⚠️ Do `AVPlayerViewController`'s transport bar and info panel automatically come in Liquid Glass style? The system player is glass-styled according to press material, but the AVKit documentation was not checked.
  - ⚠️ Does `Glass.interactive()` have any effect on tvOS? According to WWDC25 session 323 it is meant for iOS touch.
  - ⚠️ How exactly does `glassEffect` render on A8 and A10X devices ("maintains its current appearance"): as a blur material, or opaque?
  - ⚠️ Does tvOS have Liquid Glass's "tinted/clear" appearance setting, as iOS 26.1 does?

## 1. Principles
1. **Content is on the stage; glass is the frame.** Backdrops, posters, and video are fully opaque content. Glass is used only in navigation, controls, and overlays floating on top of content.
2. **System components before custom ones.** `TabView` (glass automatically), `.searchable` and `Tab(role: .search)`, `.buttonStyle(.glass)` and `.glassProminent`, the native `AVPlayerViewController`, `Menu`, and `.contextMenu`. Custom glass elements are made only if the system does not offer an equivalent, and then always inside a `GlassEffectContainer`.
3. **No custom backgrounds, shadows, or borders on controls** (Apple's guidance). Custom blur layers are not added on top of glass.
4. **Color sparingly:** `Glass.tint` only to convey meaning, for example the primary "Play" (fi: "Toista") button with the system accent color. Not for decoration.
5. **Concentric shapes:** `ConcentricRectangle` and `containerConcentric` in cards and panels, so that corners align with the glass panels.
6. **Typography:** the system font (SF) and Dynamic Type (tvOS 27's Dynamic Text setting). On top of glass, SwiftUI uses a vibrant text color automatically, and it is not overridden with hardcoded colors.

## 2. Which surfaces are glass and which are content
| Surface | Material | Implementation | Notes |
|---|---|---|---|
| Top tabs (tab bar) | **Glass (system)** | `TabView` and `Tab`, search as `Tab(role: .search)` | No custom background |
| Action buttons on detail ("Play" (fi: "Toista"), "Resume" (fi: "Jatka"), "Played" (fi: "Katsottu"), "Favorite" (fi: "Suosikki"), "More" (fi: "Lisää")) | **Glass** | "Play" (fi: "Toista") `.buttonStyle(.glassProminent)`, the others `.buttonStyle(.glass)`, all inside a `GlassEffectContainer` | Focus shows the system's glass highlight |
| Season picker | **Glass** | `.glass` buttons or `Picker(.segmented)` (⚠️ check tvOS 26's glass style) in one container | `glassEffectID`: the selection transition morphs |
| Sort and filter bar (library) | **Glass** | `.glass` buttons and `Menu`, one `GlassEffectContainer` | |
| Poster cards and episode cards | **Content (NOT glass)** | `.buttonStyle(.card)` (native lift and parallax). ⚠️ If tvOS 26 adds a glass highlight to the card, the system default is accepted | The image is opaque. Text (name, progress) is below the image, not on top of glass |
| Backdrop (home, detail) | **Content** | A full image and `backgroundExtensionEffect()` at the edges, if a glass panel covers part of it | A gradient at the bottom for readability |
| Offline and error banner | **Glass** | `glassEffect(.regular, in: .capsule)` | Not focusable |
| Context menu, track and settings menus | **System** | `.contextMenu`, `Menu`, and `transportBarCustomMenuItems` | |
| Playback: transport bar and info panel | **System (glass by default, ⚠️ to be verified)** | `AVPlayerViewController` | No custom chrome, except trickplay |
| Playback: trickplay preview (scrubbing) | **Custom glass panel** | `glassEffect(.regular, in: ConcentricRectangle())`, with a thumbnail and a timestamp inside. A possible custom scrub bar is also glass (ADR M08-1) | Jellyfin does not produce an I-frame variant, so a custom overlay is mandatory (08 PB2). Counts as G-3's single overlay. |
| Playback: the "Skip intro" (fi: "Ohita intro") and "Next episode" (fi: "Seuraava jakso") card | **System** (`contextualActions`) or custom **glass** | Primarily native `contextualActions`. The next-episode card is a custom `glassEffect` (`.regular`, ConcentricRectangle), with a thumbnail and a `.glassProminent` button "Play now" (fi: "Toista nyt") | See 08-playback.md |
| Subtitles over video | **NOT glass** | A custom SubtitleOverlay (PB5): text and a semi-transparent dark background or an outline | Glass would hurt readability and cost GPU time during playback |
| Quick Connect code, sign-in form | **Glass panel** over a backdrop or a brand image | `glassEffect(.regular, in: ConcentricRectangle())` and the system text fields | |
| Settings | **System** | `Form` and `List` (the system's default style) | |

## 3. Focus behavior on tvOS
- Standard buttons get a glass appearance on focus automatically (verified). Custom focusable elements (`focusable()`) get glass on focus only if a system component does not fit:
  ```swift
  // illustrative
  @Environment(\.isFocused) var isFocused
  content.glassEffect(isFocused ? .regular : .identity, in: .capsule)
  ```
- Focus moves inside a `GlassEffectContainer` morph (`glassEffectID`). Containers are also `.focusSection()` regions.
- All earlier focus rules still apply: a default focus per view, per-row focus memory, and a description that is not focusable (M07 rules 1–6).
- Play/Pause in a browsing view starts playback of the focused item (Infuse-style).

## 4. Readability and contrast
- **L-1** Text is not placed directly on a bright backdrop without a glass panel or a bottom gradient (black 0 → 60%, the bottom 40% of the height).
- **L-2** On top of glass, the system's vibrant and semantic colors are used (`.primary`, `.secondary`). Custom text colors are not used on top of glass.
- **L-3** Contrast is at least WCAG AA (4.5:1 for body text, 3:1 for large text and icons). It is checked with snapshot tests on three backgrounds: a bright backdrop, a dark backdrop, and a busy poster.
- **L-4** Every icon has an `accessibilityLabel` (Apple's guidance).
- **L-5** `scrollEdgeEffectStyle` (the system default) keeps the tab bar readable when content scrolls under it.

## 5. Accessibility
| Setting | Environment value | Behavior |
|---|---|---|
| Reduce Transparency | `accessibilityReduceTransparency` | System components adapt automatically. **Custom glass surfaces** (the banner, the next-episode card, the sign-in panel) are switched to an opaque background (a semantic color of the `Color(.secondarySystemBackground)` kind; ⚠️ the exact tvOS semantic color is chosen during implementation). |
| Increase Contrast | `colorSchemeContrast == .increased` | A thin border (`.separator`) on custom glass surfaces, `.primary` for text, and tint is removed. |
| Reduce Motion | `accessibilityReduceMotion` | Glass morphing (`glassEffectID` transitions), parallax, and the backdrop crossfade are removed or replaced with an immediate change. |
| Bold Text / Dynamic Type | – | Layout flexes, and text is not truncated at critical points. |

## 6. Performance budget
Glass computes background sampling and refraction in real time, and Apple limited it to A12 devices and newer.
- **G-1** At most **one tab bar and two `GlassEffectContainer`s are visible at the same time** (for example the detail button row and the season picker). Each container has at most 8 elements.
- **G-2** **Glass is not used in scrolling cells** (cards and grids), because hundreds of sampling surfaces during scrolling would cause hitches.
- **G-3** During playback, glass is only in the system's transport bar and in a single overlay (a segment or next-up card). There are no continuously visible glass elements.
- **G-4** Metrics (in addition to M02's P3 table):
  - Apple TV 4K 2nd generation (A12, the oldest glass device): **focus-driven scrolling on detail and home, hitch ratio < 10 ms/s, 60 fps**.
  - A15: < 5 ms/s.
  - Apple TV HD (A8, the oldest tvOS 26 device, no glass): < 10 ms/s.
  - Measurement with Instruments' Hitches and Core Animation tools before every release.
- **G-5** If the metric is not met on A12, glass surfaces are reduced first, not content.

## 7. Components
| Component | Description | Focus |
|---|---|---|
| `PosterCard` | A 2:3 poster, the name below (when focused), a progress bar, a played mark, and an episode counter. ConcentricRectangle corners. | `.buttonStyle(.card)`, a context menu on long press |
| `LandscapeCard` | A 16:9 Thumb or Backdrop, progress, and "32 min remaining" (fi: "32 min jäljellä") | As above |
| `MediaRow` | A title and a `LazyHStack`, `.focusSection()`, focus memory | – |
| `HeroHeader` | A full backdrop and `backgroundExtensionEffect`, a Logo, a meta row, and a **glass button row** in a `GlassEffectContainer` ("Play" (fi: "Toista") = `.glassProminent`) | The "Play" (fi: "Toista") button is the default focus. The overview is not focusable, and "More" (fi: "Lisää") opens the full text |
| `GlassActionBar` | A reusable button row: a `GlassEffectContainer` and `.glass`/`.glassProminent` buttons | `.focusSection()` |
| `GlassBanner` | An offline and error notice (capsule glass, a Reduce Transparency fallback) | Not focusable |
| `AsyncPoster` | A blurhash placeholder → the image (a 150 ms fade) | – |
| `SkeletonRow` | Shimmer, the same size as the final row | – |
| `ErrorStateView` | An icon, a message, and a `.glassProminent` "Try again" (fi: "Yritä uudelleen") | Default focus |

## 8. Navigation and screen hierarchy (tvOS)
```
TabView (Liquid Glass tab bar, system)
├── Home (fi: "Koti") (M06)
├── [Library 1] … [Library N]   (UserViews; ASSUMPTION max 5, the rest go on a "Libraries" (fi: "Kirjastot") tab)
├── Search (fi: "Haku")  — Tab(role: .search) (M09)
└── Settings (fi: "Asetukset") (M10)
In each tab, a NavigationStack:
  Library → Detail (M07) → Season/episodes (M07) → Playback (M08, fullScreenCover)
```
- Menu button: back in a nested view, to the tab bar at a tab's root, and exit from the tab bar (system).
- iOS (M11): the same `TabView` (iOS 26's glass tab bar) and `Tab(role: .search)`. `tabViewStyle(.sidebarAdaptable)` on iPad and `tabBarMinimizeBehavior` on iPhone (⚠️ iOS only).

## Acceptance criteria
- [ ] Glass surfaces match the §2 table (code review): no glass on cards or subtitles, and custom glass elements are always inside a `GlassEffectContainer`.
- [ ] Custom backgrounds on controls and navigation are not allowed (a SwiftLint rule or review).
- [ ] Snapshot tests at 1080p and 4K: default, Reduce Transparency, Increase Contrast, and Reduce Motion (a CI artifact for the Tester).
- [ ] Contrast is AA on three test backgrounds (L-3).
- [ ] XCUITest: `MediaRow` focus memory, the HeroHeader overview does not receive focus, and "Play" (fi: "Toista") is the default focus.
- [ ] Performance G-4 has been measured on an Apple TV 4K 2nd generation and an Apple TV HD (recorded for the release).
- [ ] The ⚠️ items (glass on the card style, AVPlayerViewController's glass, A8/A10X rendering, `interactive()` on tvOS) have been resolved with a prototype and recorded in ADR M05-1 before M06.

## Clarifications v1.3.3 (22.10.2026)
- **Q5-01:** Increase Contrast wins. The border ban in §1.3 applies to the default state. When `colorSchemeContrast == .increased`, custom glass surfaces get a thin `.separator` border (§5). The snapshot test covers both states.
