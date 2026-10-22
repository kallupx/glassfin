# M11 – iOS UI (P1)

**Spec version:** v1.3.3 (22.10.2026). Changes are shown in SPEC.md's change history.

**Ruling (team consensus on 21.10.2026):** one shared Swift package from day one (API, models, view models and state, playback logic, auth, and networking, see M01–M02). Only the UI layer is platform-specific. **The iOS target exists and builds from day one**, and CI runs unit tests for both platforms (M00). The tvOS UI is primary.

## Schedule
- Implementation of the iOS UI starts once **the tvOS MVP's foundation (M04 auth, M06 home, M07 library) is stable**, meaning their acceptance criteria have been checked off. After that the iOS UI is done one module at a time in the same order: Auth → Home → Library/Detail → Playback → Search → Settings.
- The iOS UI of every MVP module is **P1**.
- Effort estimate: **+30–50%** on top of the tvOS UI. ⚠️ **ASSUMPTION:** this is the Researcher's own estimate, and it has not been measured.

## Principles
- The same name and the same features as on tvOS (the user's goal). On iOS, navigation is `TabView` and `NavigationSplitView` on iPad, and custom components are made for touch (no `.card` style).
- Playback: `AVPlayerViewController` (iOS) and PiP. AirPlay to Apple TV is native.
- **Liquid Glass on iOS 26:** the same M05 principles (glass in navigation and controls, content opaque). On iOS also `Glass.interactive()` for custom touch controls, `tabBarMinimizeBehavior` (⚠️ check the API), and `tabViewStyle(.sidebarAdaptable)` on iPad.
- P2 features that come only to iOS: downloads (M18) and full admin (M17).
- No iOS-specific branches are made in view models or services. If a branch is needed, it is made in the UI layer or in an `#if os(iOS)` adapter at the edge of GlassfinCore.

## Acceptance criteria (per module)
- [ ] The iOS view uses the same ViewModel as tvOS (code review; no duplicated logic).
- [ ] The module's tvOS acceptance criteria apply where they fit (touch in place of focus).
- [ ] An XCUITest on the iPhone and iPad simulators in CI.
