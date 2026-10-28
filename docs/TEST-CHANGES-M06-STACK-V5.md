# M06 stack base v5 merge and test inventory

Baseline: `9a75f0a`. Main merge: `0f301bd` (`45e21b4`, including
M04 squash `b0f0f22` and M08 HLS segment authentication `924888d`).
M05 merge: `2c0411c` (`d2d780b`, newer than `da38a26`).

## Cause and resolution

M04 was already present in the feature history through its original commits.
Its squash merge onto main produced add/add and content conflicts. Main's
M04 authentication and server-name sanitization behavior wins; M06 keeps its
Home composition, bounded image transport, literal media metadata, session
hooks, and Home focus behavior. The M05 wrapper conflict uses M05's version.
The M05 source-check exception permits main's authentication surface.

`project.yml`, both app `Info.plist` files, and every workflow match main
verbatim. Their changes only restore main's versions. No new UI strings or
catalog changes were needed. Main's M08 playback sources remain unchanged.

The files changed by `9a75f0a` remain byte-identical to that commit:

- `Apps/Shared/Sources/HomeView.swift`: concurrent row loading respects initial
  focus priority; remembered focus remains intact.
- `Apps/Shared/UITests/T06HomeUITests.swift`: native iOS tab queries and tvOS
  identifiers/focus assertions remain intact.
- `Packages/GlassfinCore/Tests/CoreStateTests/T06ImageDecodeTests.swift`:
  `CoreNetworking` remains imported for the Apple-only image decoder test.

## Explicit test and assertion changes

These are all test-file changes relative to `9a75f0a`:

| File | Change and reason |
| --- | --- |
| `Apps/Shared/UITests/T04AuthUITests.swift` | Take main verbatim, including its class-level `@MainActor` and synchronous UI methods. Assertions are unchanged. This resolves the M04 add/add conflict using its owner's version. |
| `Packages/GlassfinCore/Tests/CoreModelsTests/SecurityNameTests.swift` | Take main verbatim. Main restores entity decoding/control removal expectations, the whitespace-only HTML fallback fixture, and stripped-markup expectations for mutation and stored-name decoding. This matches main's M04 sanitizer. |
| `Packages/GlassfinCore/Tests/CoreNetworkingTests/T04ProbeTests.swift` | Restore main's `XCTAssertFalse(parsed.name.contains("<"))` in the discovery-name test. Retain the existing `maximumBytes` transport-stub argument because M06's bounded image transport requires it. No other assertions change. |
| `Packages/GlassfinCore/Tests/CoreStateTests/T04AuthTests.swift` | Restore main's `testT04_16_serverNameDropsMarkupAndCapsAt64` name and three assertions: the displayed name has no `<`, equals `"Home" + String(repeating: "n", count: 60)`, and has no `<` on the address/user-picker path. Retain the existing per-method `@MainActor` and asynchronous entry points for Linux XCTest compatibility. Main's flow-state waits and other assertions remain intact. |
| `Packages/GlassfinCore/Tests/CoreNetworkingTests/SecurityTests.swift` | Restore three assertions verbatim from main: discovery names contain neither `<` nor `alert`, and `MetadataSanitizer.plainText(raw)` equals `"Hello Tom & Jerry **bold** [x](http://e.test)"`. The first post-merge run reported these three failures because Git auto-merged the older assertions. Existing M06 literal DTO-name/overview assertions and transport-stub adaptation remain unchanged. |
| `Packages/GlassfinCore/Tests/CoreModelsTests/T06MetadataTests.swift` | In `testT06_73_metadataPreservesLiteralMarkupAndEntities`, test `MetadataSanitizer.displayText(source, limit: .max)` instead of `plainText(source)`, keeping the same fixture and exact expected literal value. Home's metadata policy uses `displayText`; main's M04 `plainText` now strips markup and decodes entities. The companion `MetadataPolicy.clean` assertion is unchanged. |

No test was removed, disabled, or newly skipped. No expected Home behavior,
focus assertion, timeout, coverage threshold, or fixture limit was relaxed.

## Linux validation

With `export LD_LIBRARY_PATH=~/.local/lib/swiftcompat` and
`source ~/.local/share/swiftly/env.sh`:

```sh
bash scripts/coverage-gate.sh
(cd Packages/GlassfinCore && swift-format lint --recursive --strict Package.swift Sources Tests ../../Apps)
python3 scripts/check-design-system.py
python3 scripts/check-string-catalogs.py
python3 scripts/check-debug-only-strings.py
bash scripts/ci-grep.sh
```

All commands pass. The coverage gate executes 492 tests with zero failures and
eight existing live-server skips. Line coverage is 91.39% (8037/8794), above
the 80% threshold. `ci-grep.sh` also runs the image-pipeline source check.

Linux cannot run Apple SDK builds, simulator UI/focus tests, snapshots, or the
ImageIO-specific decoder tests. Live Jellyfin integration requires its
configured server matrix and was not enabled for this run.
