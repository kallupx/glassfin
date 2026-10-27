# ADR M05-1: Liquid Glass on tvOS

Status: open

This note records what M05 implemented and which warnings still need screenshot or device evidence. It does not close those warnings. Q5-01 is the only decided item.

## Q5-01 Increase Contrast border

Decided. `GlassContrastChrome.showsSeparator` is the only switch. When `colorSchemeContrast` is `.increased`, own glass surfaces draw a 1 pt `Color(.separator)` stroke. The no-border rule applies in the default contrast mode only. Snapshots render both states.

## Q5-02 Banner container

Unresolved. `GlassBanner` calls `ownGlassSurface` and is not wrapped in `GlassEffectContainer`. `ScreenGlassPlan.detail()` counts the hero actions and the season picker only. Whether the spec should count the banner is still open.

## Q5-03 Contrast measurement

Unresolved. Scrim geometry is the specified 60% black over the bottom 40% of height. The numeric check composites that scrim. Dark and colorful fixtures clear WCAG AA for white text. A white backdrop under a 60% black scrim does not. The pixel or vibrant method, and any snapshot diff tolerance, are not locked. Stored PNG baselines are not compared.

## Q5-04 Dynamic Type on tvOS 26

Unresolved. Play, error, and code text use a nil line limit. The largest content size is rendered in a snapshot. CI builds with the Xcode 27 image only, so tvOS 26 behavior is not compared here.

## Q5-05 Reduce Transparency color

Unresolved as a spec confirmation. `ReduceTransparencyFallback.color(for:)` in `Tokens.swift` uses opaque black in dark appearance and opaque white in light appearance. UIKit's system background colors are unavailable on tvOS. The token is shared by both platforms and can change without call-site edits.

## Q5-06 Which warnings belong in this ADR

Unresolved. This file lists the acceptance-criteria warnings plus the tinted/clear setting and the segmented picker, because the test plan treats that set as the open question.

## Q5-07 Eight elements per container

Unresolved. `GlassBudget.exceedsElementLimit` reports a count above 8. `displayedCount` returns the proposed count, so nine actions still render. Enforcement is not decided.

## Q5-08 Poster load failure and the fade

Unresolved. A failed `AsyncPoster` keeps the blurhash placeholder and adds no error chrome. `MotionToken.imageFade` is 0.15 s, and Reduce Motion returns 0 so the still matches the reduce-motion rule. Whether that fade should ignore Reduce Motion is still open.

## Q5-09 Five library tabs

Unresolved. `LibraryTabModel.maximumInlineLibraries` is 5, matching the written default. Zero libraries produce Home, Search, and Settings only. Seven libraries produce five inline tabs plus a Libraries overflow. The user has not confirmed the cap.

## Q5-10 Device hitch tests

Unresolved. No A8, A10X, A12, or A15 run is in CI. The simulator grid test records an `XCTOSSignpostMetric` with one iteration and does not assert a hitch budget.

## Q5-11 Artifact retention

Unresolved. This change does not edit the workflow. The tvOS job uploads readable artifacts, including screenshots, with the retention already configured there.

## Q5-12 Spec version labels

Unresolved. This checkout titles `spec/SPEC.md` v1.2 on both the heading and the version line. The question that cites v1.3.3 against a v1.3 meta line is not present in these files. `spec/` was not rewritten.

## T05-47 Card focus style

Unresolved. tvOS posters use the system `.buttonStyle(.card)`. iOS posters use `.plain`. No second scale or parallax is added. Whether the system card draws glass or a lift is not decided from a screenshot review yet. Samples: `card-idle.png`, `card-focused.png`, and the focus-demo screenshots.

## T05-48 AVPlayerViewController

Unresolved. This change does not present `AVPlayerViewController`. Playback glass during playback is not observed. The playback plan allows one custom overlay, `nextUp`, beside the system transport bar.

## T05-49 Glass.interactive() on tvOS

Unresolved. `InteractiveGlassProbe` calls `Glass.regular.interactive()` so a screenshot can be taken. Production tvOS buttons do not use it. The visual result is not reviewed yet. Sample: `interactive-probe.png`.

## T05-50 A8 and A10X rendering

Unresolved. No Apple TV HD or first-generation 4K device was available. Contrast without glass is covered by the scrim math and the scrim samples only.

## T05-51 Segmented season picker

Unresolved. `SeasonPickerBar` uses `.pickerStyle(.segmented)` inside a glass container. Whether tvOS 26 draws that picker as glass is not reviewed. Sample: `season-picker.png`.

## T05-52 Tinted or clear appearance

Unresolved. This change cannot read a system tinted or clear setting, so it does not branch on one.
