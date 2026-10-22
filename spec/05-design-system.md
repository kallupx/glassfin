# M05 – Design system: Liquid Glass (P0)

**Dependencies:** M00. Can be done in parallel with M01–M04.
**User decision 21 Oct 2026:** the Glassfin UI follows the **Liquid Glass** design language that Apple introduced with iOS 26 and tvOS 26. The minimum OS is 26, so **there is no fallback for versions older than 26**.

## 0. Verified facts (Apple documentation, checked 21 Oct 2026)
- **APIs and their tvOS 26.0 availability** (Apple docs JSON metadata): `View.glassEffect(_:in:)`, `Glass` (`.regular`, `.clear`, `.identity`, `.tint(_:)`, `.interactive(_:)`), `GlassEffectContainer`, `View.glassEffectID(_:in:)`, `View.glassEffectUnion(id:namespace:)`, `PrimitiveButtonStyle.glass` and `.glassProminent`, `View.backgroundExtensionEffect()`, `ConcentricRectangle`, and `View.scrollEdgeEffectStyle(_:for:)`. All are available from tvOS 26.0 and iOS 26.0, so they work in shared code without `#available` checks.
- **Apple's "Adopting Liquid Glass" guidance, tvOS:**
  - "standard buttons and controls take on a Liquid Glass appearance **when focus moves to them**." For custom controls, add the glass effect on focus through the standard focus APIs (`focusable()`, `isFocused`, `@FocusState`).
  - "Apple TV 4K (2nd generation) and newer models support Liquid Glass effects. **On older devices, your app maintains its current appearance.**"
- **Device support** (Apple Support and MacRumors): tvOS 26 installs on **every Apple TV HD and Apple TV 4K model**, including the 2015 Apple TV HD (A8). Liquid Glass is used only on **Apple TV 4K 2nd generation (A12, 2021) and 3rd generation (A15, 2022)**. Apple TV HD (A8) and 4K 1st generation (A10X) keep the previous appearance.
- **Apple's guidance:**
  - Glass belongs on the **navigation layer** (tab bar, sidebar, toolbars, and controls), not on content.
  - Use glass sparingly on custom controls ("Avoid overusing").
  - Group nearby glass elements in a `GlassEffectContainer`, because "glass can not sample other glass" and grouping improves performance.
  - Do not add custom backgrounds to controls or navigation elements.
  - Use a semantic `Tab(role: .search)` tab for search.
  - Test with Reduce Transparency, Reduce Motion, and contrast settings, because standard components adapt automatically and custom elements must be tested.
- **Unverified:**
  - Does `.buttonStyle(.card)` on tvOS 26 get a glass treatment on focus, or does it keep the traditional lift and parallax?
  - Do `AVPlayerViewController`'s transport bar and info panel become Liquid Glass automatically? Press materials describe the system player as glass, but the AVKit documentation was not checked.
  - Does `Glass.interactive()` do anything on tvOS? WWDC25 session 323 says it is for iOS touch.
  - How does `glassEffect` render on A8 and A10X devices ("maintains its current appearance"): as a blur material, or as opaque?
  - Does tvOS have a Liquid Glass "tinted/clear" appearance setting like iOS 26.1?

## 1. Principles
1. **Content is the stage, glass is the frame.** Background images (Backdrop), posters, and video are fully opaque content. Glass is used only in navigation, controls, and overlays that float over content.
2. **System components before custom ones.** `TabView` (glass automatically), `.searchable` and `Tab(role: .search)`, `.buttonStyle(.glass)` and `.glassProminent`, the native `AVPlayerViewController`, `Menu`, and `.contextMenu`. Custom glass is built only when the system does not offer the equivalent, and then always inside a `GlassEffectContainer`.
3. **No custom backgrounds, shadows, or borders on controls** (Apple's guidance). Do not add extra blur layers on top of glass.
4. **Color sparingly:** `Glass.tint` only to convey meaning, for example the primary Play button in the system accent color. Not for decoration.
5. **Concentric shapes:** `ConcentricRectangle` and `containerConcentric` on cards and panels, so corners line up with glass panels.
6. **Typography:** the system font (SF) and Dynamic Type (the tvOS 27 Dynamic Text setting). On glass, SwiftUI uses vibrant text color automatically, and that is not overridden with hard-coded colors.

## 2. Which surfaces are glass and which are content
| Surface | Material | Implementation | Notes |
|---|---|---|---|
| Top tabs (tab bar) | **Glass (system)** | `TabView` and `Tab`, search as `Tab(role: .search)` | No custom background |
| Action buttons on detail (Play, Resume, Played, Favorite, More) | **Glass** | Play uses `.buttonStyle(.glassProminent)`, the others `.buttonStyle(.glass)`, all inside a `GlassEffectContainer` | Focus shows the system glass highlight |
| Season picker | **Glass** | `.glass` buttons or `Picker(.segmented)` (check the tvOS 26 glass style) in one container | `glassEffectID`: the selection change morphs |
| Sort and filter bar (library) | **Glass** | `.glass` buttons and `Menu`, one `GlassEffectContainer` | |
| Poster cards and episode cards | **Content (NOT glass)** | `.buttonStyle(.card)` (native lift and parallax). If tvOS 26 adds a glass highlight to card, accept the system default | The image is opaque. Text (name, progress) is under the image, not on glass |
| Backdrop (home, detail) | **Content** | Full image and `backgroundExtensionEffect()` at the edges if a glass panel covers part of it | A gradient at the bottom for readability |
| Offline and error banner | **Glass** | `glassEffect(.regular, in: .capsule)` | Not focusable |
| Context menu, track and settings menus | **System** | `.contextMenu`, `Menu`, and `transportBarCustomMenuItems` | |
| Playback: transport bar and info panel | **System (glass assumed, to be verified)** | `AVPlayerViewController` | No custom chrome |
| Playback: "Skip intro" and "Next episode" card | **System** (`contextualActions`) or custom **glass** | Prefer native `contextualActions`. The next-episode card is a custom `glassEffect` (`.regular`, ConcentricRectangle) with a thumbnail and a `.glassProminent` "Play now" button | See 08-playback.md |
| Subtitles over video | **NOT glass** | A custom SubtitleOverlay (PB5): text and a semi-transparent dark background or an outline | Glass would hurt readability and cost GPU time during playback |
| Quick Connect code, sign-in form | **Glass panel** over a Backdrop or brand image | `glassEffect(.regular, in: ConcentricRectangle())` and system text fields | |
| Settings | **System** | `Form` and `List` (system default style) | |

## 3. Focus behavior on tvOS
- Standard buttons get a glass appearance on focus automatically (verified). Custom focusable elements (`focusable()`) get glass on focus only when a system component does not fit:
  ```swift
  // illustrative
  @Environment(\.isFocused) var isFocused
  content.glassEffect(isFocused ? .regular : .identity, in: .capsule)
  ```
- Focus moves inside a `GlassEffectContainer` morph (`glassEffectID`). Containers are also `.focusSection()` regions.
- All previous focus rules still apply: a default focus per view, per-row focus memory, and a description that is not focusable (M07 rules 1–6).
- Play/Pause on a browse view starts playback of the focused item (Infuse-style).

## 4. Readability and contrast
- **L-1** Text is not placed directly on a bright Backdrop without a glass panel or a bottom gradient (black 0 → 60%, the bottom 40% of the height).
- **L-2** On glass, use the system's vibrant and semantic colors (`.primary`, `.secondary`). Custom text colors are not used on glass.
- **L-3** Contrast is at least WCAG AA (4.5:1 for body text, 3:1 for large text and icons). Checked with snapshot tests on three backgrounds: a bright Backdrop, a dark Backdrop, and a busy poster.
- **L-4** Every icon has an `accessibilityLabel` (Apple's guidance).
- **L-5** `scrollEdgeEffectStyle` (the system default) keeps the tab bar readable when content scrolls under it.

## 5. Accessibility
| Setting | Environment value | Behavior |
|---|---|---|
| Reduce Transparency | `accessibilityReduceTransparency` | System components adapt automatically. **Custom glass surfaces** (banner, next-episode card, sign-in panel) switch to an opaque background (a semantic color of the `Color(.secondarySystemBackground)` kind; the exact tvOS semantic color is chosen during implementation). |
| Increase Contrast | `colorSchemeContrast == .increased` | Custom glass surfaces get a thin border (`.separator`), text uses `.primary`, and tint is removed. |
| Reduce Motion | `accessibilityReduceMotion` | Glass morphing (`glassEffectID` transitions), parallax, and background crossfade are removed or replaced with an immediate change. |
| Bold Text / Dynamic Type | – | Layout flexes, and text is not truncated at critical points. |

## 6. Performance budget
Glass samples the background and computes refraction in real time, and Apple limited it to A12 devices and newer.
- **G-1** At most **one tab bar and two `GlassEffectContainer`s are visible at the same time** (for example the detail button row and the season picker). Each container has at most 8 elements.
- **G-2** **Glass is not used in scrolling cells** (cards and grids), because hundreds of sampling surfaces during a scroll would cause hitches.
- **G-3** During playback, glass is only the system transport bar and a single overlay (segment or next-up card). There are no continuously visible custom glass elements.
- **G-4** Metrics (in addition to the P3 row in M02):
  - Apple TV 4K 2nd generation (A12, oldest glass device): **detail and home focus scrolling hitch ratio < 10 ms/s, 60 fps**.
  - A15: < 5 ms/s.
  - Apple TV HD (A8, oldest tvOS 26 device, no glass): < 10 ms/s.
  - Measured with Instruments Hitches and Core Animation before every release.
- **G-5** If the A12 metric is missed, reduce glass surfaces first, not content.

## 7. Components
| Component | Description | Focus |
|---|---|---|
| `PosterCard` | 2:3 poster, name below (on focus), progress bar, played mark, and episode count. ConcentricRectangle corners. | `.buttonStyle(.card)`, context menu on a long press |
| `LandscapeCard` | 16:9 Thumb or Backdrop, progress, and "32 min left" | Same as above |
| `MediaRow` | Title and `LazyHStack`, `.focusSection()`, focus memory | – |
| `HeroHeader` | Full Backdrop and `backgroundExtensionEffect`, Logo, meta row, and a **glass button row** in a `GlassEffectContainer` (Play = `.glassProminent`) | The Play button is the default focus. The description is not focusable, and "More" opens the full text |
| `GlassActionBar` | Reusable button row: `GlassEffectContainer` and `.glass` / `.glassProminent` buttons | `.focusSection()` |
| `GlassBanner` | Offline and error notice (capsule glass, Reduce Transparency fallback) | Not focusable |
| `AsyncPoster` | Blurhash placeholder → image (fade 150 ms) | – |
| `SkeletonRow` | Shimmer, the same size as the final row | – |
| `ErrorStateView` | Icon, message, and a `.glassProminent` "Try again" | Default focus |

## 8. Navigation and screen hierarchy (tvOS)
```
TabView (Liquid Glass tab bar, system)
├── Home (M06)
├── [Library 1] … [Library N]   (UserViews; DEFAULT max 5, the rest go on a "Libraries" tab)
├── Search  — Tab(role: .search) (M09)
└── Settings (M10)
In each tab, a NavigationStack:
  Library → Detail (M07) → Season/episodes (M07) → Playback (M08, fullScreenCover)
```
- Menu button: back in a nested view, to the tab bar at the root of a tab, and leaving from the tab bar (system).
- iOS (M11): the same `TabView` (the iOS 26 glass tab bar) and `Tab(role: .search)`. `tabViewStyle(.sidebarAdaptable)` on iPad and `tabBarMinimizeBehavior` on iPhone (iOS only).

## Acceptance criteria
- [ ] Glass surfaces match the §2 table (code review): no glass on cards or subtitles, and custom glass is always inside a `GlassEffectContainer`.
- [ ] Custom backgrounds on controls and navigation are not allowed (a SwiftLint rule or review).
- [ ] Snapshot tests at 1080p and 4K: default, Reduce Transparency, Increase Contrast, and Reduce Motion (CI artifact for the Tester).
- [ ] Contrast is AA on three test backgrounds (L-3).
- [ ] XCUITest: `MediaRow` focus memory, the HeroHeader description does not take focus, and Play is the default focus.
- [ ] Performance G-4 is measured on Apple TV 4K 2nd generation and Apple TV HD (recorded for the release).
- [ ] The open items (card-style glass, AVPlayerViewController glass, A8/A10X rendering, `interactive()` on tvOS) are settled with a prototype and written into ADR M05-1 before M06.
