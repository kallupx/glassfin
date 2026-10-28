# M06 v2 re-stack and test change inventory

Comparison baseline: feature head `370e398`. Merge: `52b37cf`, with second parent `a22db4a` (v2). This inventory includes inherited base test changes so they can be distinguished from M06 adaptations and the subsequent re-entry fix. Assertions are listed as complete calls; a call inside a loop applies to every fixture described by its test. Unlisted assertions in an existing test are unchanged.

## Conflict resolution

The original merge reported 43 conflicted paths. Files unchanged by M06 relative to `8ad4357` were taken verbatim from v2; this was checked by comparing their file bytes. Shared changes were reapplied using the old stack base as the three-way ancestor, then reviewed against v2.

- `AppState.swift` is byte-identical to v2, retaining #7’s weak `currentView`, `ViewContentProviding`, presentation decision and string-key APIs. Home’s extracted implementation retains that content-provider integration. Library/Series retain the base APIs.
- `MetadataSanitizer.displayText(_:limit:)` and its `isControl` helper match #7 (`981d632`) exactly. The duplicate M06 implementation was removed. Display names/overviews use the shared cleaner without tag stripping or entity decoding; M06 names/titles still use `MetadataPolicy.nameMax == 200`.
- Catalogs retain the union of feature/v2 keys and en/fi localizations: 51 app keys and 52 CoreModels keys. Auth/error localization uses v2’s shared String keys and accessors.
- Design-system accessibility containers, identifiers, contrast tokens and stricter base contrast assertions were retained. Home-specific labels, DEBUG accessibility overrides, capped literal text and image limits remain. Banner overrides label the icon inside the base `.contain` accessibility structure.
- The extracted M06 Home class replaces the legacy inline class in `ViewModels.swift`; Library, Series, Player and Search preserve v2 structures. Auth composition, scoped caches, bounded image transport and session changes from M06 remain.
- The base T02-35a cached fixture now supplies M06 library grouping (`libraries` and `latestByLibrary`) without changing its assertions. Latest failure preserves `previous: nil` when no row has ever loaded. All inherited test scenarios and skip conditions remain.
- `project.yml` changes come exclusively from v2 and match it verbatim. No feature edits to Info.plist, project configuration or workflows were made.

| Original conflict | Resolution in the merge |
|---|---|
| `Apps/Shared/Resources/Localizable.xcstrings` | Feature version retained (v2 equivalent or unchanged here) |
| `Apps/Shared/Sources/AuthRootView.swift` | v2 structure/APIs plus feature changes |
| `Apps/Shared/Sources/DesignSystem/Cards.swift` | v2 structure/APIs plus feature changes |
| `Apps/Shared/Sources/DesignSystem/Copy.swift` | Feature version retained (v2 equivalent or unchanged here) |
| `Apps/Shared/Sources/DesignSystem/Demo.swift` | v2 verbatim |
| `Apps/Shared/Sources/DesignSystem/GlassBanner.swift` | v2 structure/APIs plus feature changes |
| `Apps/Shared/Sources/DesignSystem/Panels.swift` | v2 verbatim |
| `Apps/Shared/Sources/DesignSystem/PlainText.swift` | Feature version retained (v2 equivalent or unchanged here) |
| `Apps/Shared/Sources/DesignSystem/Rows.swift` | v2 structure/APIs plus feature changes |
| `Apps/Shared/Sources/DesignSystem/Shell.swift` | v2 structure/APIs plus feature changes |
| `Apps/Shared/Sources/DesignSystem/Tokens.swift` | v2 verbatim |
| `Apps/Shared/Tests/Logic/DesignSystemLogicTests.swift` | v2 structure/APIs plus feature changes |
| `Apps/Shared/Tests/Snapshots/DesignSystemSnapshotTests.swift` | Feature version retained (v2 equivalent or unchanged here) |
| `Apps/Shared/UITests/DesignSystemFocusTests.swift` | v2 structure/APIs plus feature changes |
| `Apps/Shared/UITests/T04AuthUITests.swift` | v2 structure/APIs plus feature changes |
| `Packages/GlassfinCore/Package.swift` | v2 verbatim |
| `Packages/GlassfinCore/Sources/CoreModels/AppError.swift` | v2 structure/APIs plus feature changes |
| `Packages/GlassfinCore/Sources/CoreModels/AuthCopy.swift` | v2 verbatim |
| `Packages/GlassfinCore/Sources/CoreModels/LinuxStringLocalization.swift` | v2 verbatim |
| `Packages/GlassfinCore/Sources/CoreModels/Localizable.xcstrings` | v2 verbatim |
| `Packages/GlassfinCore/Sources/CoreModels/MetadataSanitizer.swift` | v2 structure/APIs plus feature changes |
| `Packages/GlassfinCore/Sources/CoreModels/ResilientItems.swift` | Feature version retained (v2 equivalent or unchanged here) |
| `Packages/GlassfinCore/Sources/CoreNetworking/HTTPClient.swift` | Feature version retained (v2 equivalent or unchanged here) |
| `Packages/GlassfinCore/Sources/CoreNetworking/PublicInfoClient.swift` | Feature version retained (v2 equivalent or unchanged here) |
| `Packages/GlassfinCore/Sources/CoreNetworking/ServerProbe.swift` | v2 verbatim |
| `Packages/GlassfinCore/Sources/CoreNetworking/ServerTransportPolicy.swift` | v2 verbatim |
| `Packages/GlassfinCore/Sources/CoreNetworking/SessionTermination.swift` | v2 verbatim |
| `Packages/GlassfinCore/Sources/CoreState/AppState.swift` | v2 verbatim |
| `Packages/GlassfinCore/Sources/CoreState/AuthFlow.swift` | v2 structure/APIs plus feature changes |
| `Packages/GlassfinCore/Sources/CoreState/Caches.swift` | Feature version retained (v2 equivalent or unchanged here) |
| `Packages/GlassfinCore/Sources/CoreState/RetryingClient.swift` | Feature version retained (v2 equivalent or unchanged here) |
| `Packages/GlassfinCore/Sources/CoreState/UserDataStore.swift` | Feature version retained (v2 equivalent or unchanged here) |
| `Packages/GlassfinCore/Sources/CoreState/ViewModels.swift` | v2 structure/APIs plus feature changes |
| `Packages/GlassfinCore/Tests/CoreModelsTests/CoreModelsTests.swift` | v2 verbatim |
| `Packages/GlassfinCore/Tests/CoreModelsTests/SecurityNameTests.swift` | Feature version retained (v2 equivalent or unchanged here) |
| `Packages/GlassfinCore/Tests/CoreNetworkingTests/StringCatalogTests.swift` | v2 verbatim |
| `Packages/GlassfinCore/Tests/CoreNetworkingTests/T04ProbeTests.swift` | Feature version retained (v2 equivalent or unchanged here) |
| `Packages/GlassfinCore/Tests/CoreStateTests/Support.swift` | v2 structure/APIs plus feature changes |
| `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift` | v2 structure/APIs plus feature changes |
| `Packages/GlassfinCore/Tests/CoreStateTests/T02FoundationTests.swift` | v2 verbatim |
| `Packages/GlassfinCore/Tests/CoreStateTests/T04AuthTests.swift` | v2 structure/APIs plus feature changes |
| `docs/ADR-M05-1.md` | v2 verbatim |
| `scripts/ci-grep.sh` | Feature version retained (v2 equivalent or unchanged here) |

## Signature and identity changes

No existing test signature changed beyond the four inherited canonical renames below. New inherited actor-isolated tests use method-level `@MainActor`; existing M06 method isolation was preserved rather than restoring base class-level annotations.

- `testT02_08_network403And5xxDoNotLogOut` → `testT02_31_network403And5xxDoNotLogOut` (inherited canonical rename).
- `testT02_09_forbiddenKeepsTheSession` → `testT02_32_forbiddenKeepsTheSession` (inherited canonical rename).
- `testT02_19_libraryPagesAndCacheTTL` → `testT02_34_libraryPagesAndCacheTTL` (inherited canonical rename).
- `testT02_18_xctMetricRecordsPlaybackFirstFrame` → `testT02_33_xctMetricRecordsPlaybackFirstFrame` (inherited canonical rename).
- Apple signpost test class: `T02_18_AppleSignpostMetricTests` → `T02_33_AppleSignpostMetricTests` (inherited canonical rename).

Newly inherited tests with isolation adapted from v2 (each declaration shown below, including all seven `T02BehaviorTests` additions and both `DesignSystemLogicTests` additions):

- `DesignSystemLogicTests.testT05_32_contrastFixtureMatchesHeroTokens`: `func testT05_32_contrastFixtureMatchesHeroTokens()` → `@MainActor func testT05_32_contrastFixtureMatchesHeroTokens() async`.
- `DesignSystemLogicTests.testT05_32_upperHeroTextUsesConservativeScrimOpacity`: `func testT05_32_upperHeroTextUsesConservativeScrimOpacity()` → `@MainActor func testT05_32_upperHeroTextUsesConservativeScrimOpacity() async`.
- `T02BehaviorTests.testT02_35a_serverDownWithContentKeepsContentAndShowsBanner`: `func testT02_35a_serverDownWithContentKeepsContentAndShowsBanner() async throws` → `@MainActor func testT02_35a_serverDownWithContentKeepsContentAndShowsBanner() async throws`.
- `T02BehaviorTests.testT02_35b_serverDownWithoutContentShowsFullScreen`: `func testT02_35b_serverDownWithoutContentShowsFullScreen() async throws` → `@MainActor func testT02_35b_serverDownWithoutContentShowsFullScreen() async throws`.
- `T02BehaviorTests.testT02_36_bannerTextResolvesFromKey`: `func testT02_36_bannerTextResolvesFromKey() async throws` → `@MainActor func testT02_36_bannerTextResolvesFromKey() async throws`.
- `T02BehaviorTests.testT02_37_sessionNoticeTextResolvesFromKey`: `func testT02_37_sessionNoticeTextResolvesFromKey() async throws` → `@MainActor func testT02_37_sessionNoticeTextResolvesFromKey() async throws`.
- `T02BehaviorTests.testT02_38_stallMessageTextResolvesFromKey`: `func testT02_38_stallMessageTextResolvesFromKey() async throws` → `@MainActor func testT02_38_stallMessageTextResolvesFromKey() async throws`.
- `T02BehaviorTests.testServerDownUsesOnlyCurrentViewContent`: `func testServerDownUsesOnlyCurrentViewContent() async throws` → `@MainActor func testServerDownUsesOnlyCurrentViewContent() async throws`.
- `T02BehaviorTests.testStoredUnparseableVersionIsCleanedAndCappedBeforeFormatting`: `func testStoredUnparseableVersionIsCleanedAndCappedBeforeFormatting() throws` → `@MainActor func testStoredUnparseableVersionIsCleanedAndCappedBeforeFormatting() async throws`.

The nine new re-entry tests and their complete signatures/assertions are listed below. Seven are documented extras in `TEST-COVERAGE-M06.md`; Home presentation uses T06-46/T06-49. The new `assertBanner` helper asserts `.serverUnreachable`, the shared banner key, its localized value and `showsServerDown == false`; `assertFullScreen` asserts `.serverUnreachable`, `showsServerDown == true` and the shared full-screen title key. Factory helpers contain no assertions.

## Every changed or added test and assertion

A test marked “inherited” exists in v2. Local adaptations are described above and in the notes below. New inherited tests retain all their v2 assertions except where a feature-specific adaptation is explicitly identified.

### `DesignSystemLogicTests.testT05_32_scrimContrastOnThreeBackgrounds`

Source: `Apps/Shared/Tests/Logic/DesignSystemLogicTests.swift`. Inherited from v2.

Signature: `@MainActor func testT05_32_scrimContrastOnThreeBackgrounds() async` (unchanged).

- Removed: `XCTAssertLessThan(bright, ContrastFixture.largeMinimum)`.
- Removed: `XCTAssertGreaterThan(bright, 2)`.
- Added: `XCTAssertGreaterThanOrEqual(bright, ContrastFixture.bodyMinimum)`.
- Added: `XCTAssertGreaterThanOrEqual(bright, ContrastFixture.largeMinimum)`.
- Added: `XCTAssertLessThan(text.contrast(against: ContrastFixture.bright), ContrastFixture.largeMinimum)`.

### `DesignSystemLogicTests.testT05_32_contrastFixtureMatchesHeroTokens`

Source: `Apps/Shared/Tests/Logic/DesignSystemLogicTests.swift`. Inherited from v2.

Added signature: `@MainActor func testT05_32_contrastFixtureMatchesHeroTokens() async`.

- Added: `XCTAssertTrue(resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha))`.
- Added: `XCTAssertEqual(alpha, 1, accuracy: 0.0001)`.
- Added: `XCTAssertEqual(ContrastFixture.text, text)`.
- Added: `XCTAssertEqual(ContrastFixture.scrim, scrim)`.
- Added: `XCTAssertEqual(gradient, ScrimGradient())`.
- Added: `XCTAssertEqual( ContrastFixture.scrimmed(background, at: gradient.end), scrim.composited(over: background, alpha: gradient.endOpacity) )`.

### `DesignSystemLogicTests.testT05_32_upperHeroTextUsesConservativeScrimOpacity`

Source: `Apps/Shared/Tests/Logic/DesignSystemLogicTests.swift`. Inherited from v2.

Added signature: `@MainActor func testT05_32_upperHeroTextUsesConservativeScrimOpacity() async`.

- Added: `XCTAssertEqual(ContrastFixture.scrimmed(background, at: gradient.clearUntil), background)`.
- Added: `XCTAssertLessThan(bright, ContrastFixture.largeMinimum)`.
- Added: `XCTAssertLessThan(bright, ContrastFixture.bodyMinimum)`.
- Added: `XCTAssertGreaterThanOrEqual(dark, ContrastFixture.bodyMinimum)`.
- Added: `XCTAssertGreaterThanOrEqual(dark, ContrastFixture.largeMinimum)`.
- Added: `XCTAssertLessThan(colorful, ContrastFixture.bodyMinimum)`.
- Added: `XCTAssertGreaterThanOrEqual(colorful, ContrastFixture.largeMinimum)`.

### `DesignSystemLogicTests.testT05_35_reduceTransparencyUsesOneFallbackToken`

Source: `Apps/Shared/Tests/Logic/DesignSystemLogicTests.swift`. Inherited from v2.

Signature: `@MainActor func testT05_35_reduceTransparencyUsesOneFallbackToken() async` (unchanged).

- Removed: `XCTAssertEqual(alpha, 1)`.
- Removed: `XCTAssertEqual(white, scheme == .dark ? 0 : 1)`.
- Added: `XCTAssertEqual(alpha, 1, accuracy: 0.001)`.
- Added: `XCTAssertEqual(white, scheme == .dark ? 0 : 1, accuracy: 0.001)`.

### `DesignSystemFocusTests.testT05_22_demoIdentifiersExist`

Source: `Apps/Shared/UITests/DesignSystemFocusTests.swift`. Inherited from v2.

Signature: `@MainActor func testT05_22_demoIdentifiersExist() async` (unchanged).

- Added: `XCTAssertEqual(app.descendants(matching: .any).matching(identifier: identifier).count, 1, identifier)`.

### `DesignSystemFocusTests.testT05_10_longPressOpensTheContextMenu`

Source: `Apps/Shared/UITests/DesignSystemFocusTests.swift`. Inherited from v2.

Signature: `@MainActor func testT05_10_longPressOpensTheContextMenu() async` (unchanged).

Assertions unchanged; setup, comments, identifiers or signature changed as inherited from v2.

### `DesignSystemFocusTests.testT05_21_retryIncrementsTheAttemptCount`

Source: `Apps/Shared/UITests/DesignSystemFocusTests.swift`. Inherited from v2.

Signature: `@MainActor func testT05_21_retryIncrementsTheAttemptCount() async` (unchanged).

- Added: `XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "design.error.root").count, 1)`.
- Added: `XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "design.error.attempts").count, 1)`.

### `DesignSystemFocusTests.testT05_28_menuWalksBackToTheTabBar`

Source: `Apps/Shared/UITests/DesignSystemFocusTests.swift`. Inherited from v2.

Signature: `@MainActor func testT05_28_menuWalksBackToTheTabBar() async` (unchanged).

Assertions unchanged; setup, comments, identifiers or signature changed as inherited from v2.

### `T04AuthUITests.testT04_01_welcomeIsTheConnectButton`

Source: `Apps/Shared/UITests/T04AuthUITests.swift`. Inherited from v2.

Signature: `@MainActor func testT04_01_welcomeIsTheConnectButton() async` (unchanged).

Assertions unchanged; setup, comments, identifiers or signature changed as inherited from v2.

### `T04AuthUITests.testT04_11_explicitPublicHTTPShowsTheKey`

Source: `Apps/Shared/UITests/T04AuthUITests.swift`. Inherited from v2.

Signature: `@MainActor func testT04_11_explicitPublicHTTPShowsTheKey() async` (unchanged).

- Removed: `XCTAssertEqual(error.value as? String, publicHTTPSKey)`.
- Added: `XCTAssertEqual(error.value as? String, AuthCopy.Key.publicAddressRequiresHTTPS.rawValue)`.

### `T04AuthUITests.testT04_49_backFromQuickConnectReturnsToTheMethodScreen`

Source: `Apps/Shared/UITests/T04AuthUITests.swift`. Inherited from v2.

Signature: `@MainActor func testT04_49_backFromQuickConnectReturnsToTheMethodScreen() async` (unchanged).

Assertions unchanged; setup, comments, identifiers or signature changed as inherited from v2.

### `T04AuthUITests.testT04_40_expiredCodeOffersFocusedNewCodeButton`

Source: `Apps/Shared/UITests/T04AuthUITests.swift`. Inherited from v2.

Signature: `@MainActor func testT04_40_expiredCodeOffersFocusedNewCodeButton() async` (unchanged).

- Removed: `XCTAssertEqual(app.descendants(matching: .any)["address.error"].value as? String, "The code expired")`.
- Added: `XCTAssertEqual( app.descendants(matching: .any)["address.error"].value as? String, AuthCopy.Key.quickConnectExpired.rawValue )`.

### `T04AuthUITests.testT04_68_settingsSignOutDefaultsToCancelAndKeepsServer`

Source: `Apps/Shared/UITests/T04AuthUITests.swift`. Inherited from v2.

Signature: `@MainActor func testT04_68_settingsSignOutDefaultsToCancelAndKeepsServer() async` (unchanged).

Assertions unchanged; setup, comments, identifiers or signature changed as inherited from v2.

### `CoreModelsTests.testSharedAuthErrorKeysReuseAppErrorMessageConstants`

Source: `Packages/GlassfinCore/Tests/CoreModelsTests/CoreModelsTests.swift`. Inherited from v2.

Added signature: `func testSharedAuthErrorKeysReuseAppErrorMessageConstants()`.

- Added: `XCTAssertEqual(authKey.rawValue, errorKey)`.
- Added: `XCTAssertEqual(Set(authKeys).count, authKeys.count)`.

### `MetadataSanitizerTests.testServerVersionSanitizerStripsControlAndBidiAndCapsAt200Graphemes`

Source: `Packages/GlassfinCore/Tests/CoreModelsTests/MetadataSanitizerTests.swift`. Inherited from v2.

Added signature: `func testServerVersionSanitizerStripsControlAndBidiAndCapsAt200Graphemes()`.

- Added: `XCTAssertEqual(sanitized, "10.11.11")`.
- Added: `XCTAssertFalse(sanitized.unicodeScalars.contains(scalar))`.
- Added: `XCTAssertGreaterThan(cleaned.count, 200)`.
- Added: `XCTAssertEqual(capped.count, 200)`.
- Added: `XCTAssertGreaterThan(capped.unicodeScalars.count, 200)`.
- Added: `XCTAssertEqual(capped, String(repeating: graphemePair, count: 100))`.
- Added: `XCTAssertTrue(cleaned.hasPrefix(capped))`.
- Added: `XCTAssertEqual(Array(capped), Array(cleaned.prefix(200)))`.

### `T06MetadataTests.testT06_73_displayTextCaps500GraphemesWithoutSplittingEmojiOrCombiningMarks`

Source: `Packages/GlassfinCore/Tests/CoreModelsTests/T06MetadataTests.swift`. Existing feature test adapted to v2.

Signature: `func testT06_73_displayTextCaps500GraphemesWithoutSplittingEmojiOrCombiningMarks()` (unchanged).

- Removed: `XCTAssertEqual(MetadataSanitizer.displayText(raw, limit: -1), "")`.
- Added: `XCTAssertEqual(MetadataSanitizer.displayText(raw, limit: .max), raw)`.

### `StringCatalogTests.testNetworkingCatalogKeysAndLocalizedAccessors`

Source: `Packages/GlassfinCore/Tests/CoreNetworkingTests/StringCatalogTests.swift`. Inherited from v2.

Added signature: `func testNetworkingCatalogKeysAndLocalizedAccessors() throws`.

Assertions unchanged; setup, comments, identifiers or signature changed as inherited from v2.

### `StringCatalogTests.testModelsCatalogKeysAndLocalizedAccessor`

Source: `Packages/GlassfinCore/Tests/CoreNetworkingTests/StringCatalogTests.swift`. Inherited from v2.

Added signature: `func testModelsCatalogKeysAndLocalizedAccessor() throws`.

- Added: `XCTAssertEqual(Set(englishValues.keys), Set(AuthCopy.Key.allCases.map(\.rawValue)))`.

### `MediaLoaderSecurityTests.testBoundedBodyChunkAppendHonorsExactRangeLimit`

Source: `Packages/GlassfinCore/Tests/CorePlaybackTests/MediaLoaderSecurityTests.swift`. Inherited from v2.

Added signature: `func testBoundedBodyChunkAppendHonorsExactRangeLimit() throws`.

- Added: `XCTAssertEqual(exact.data, expected)`.
- Added: `XCTAssertEqual(exact.data, expected)`.
- Added: `XCTAssertThrowsError(try exact.append(contentsOf: Data([2])))`.
- Added: `XCTAssertEqual($0 as? APIError, .decoding)`.
- Added: `XCTAssertEqual(exact.data, expected)`.
- Added: `XCTAssertThrowsError(try oversized.append(contentsOf: expected + Data([2])))`.
- Added: `XCTAssertEqual($0 as? APIError, .decoding)`.
- Added: `XCTAssertEqual(oversized.data, expected)`.

### `MediaLoaderSecurityTests.testBoundedBodyAccumulatesChunksUpToProgressiveLimit`

Source: `Packages/GlassfinCore/Tests/CorePlaybackTests/MediaLoaderSecurityTests.swift`. Inherited from v2.

Added signature: `func testBoundedBodyAccumulatesChunksUpToProgressiveLimit() throws`.

- Added: `XCTAssertEqual(body.data, expected)`.
- Added: `XCTAssertEqual(body.data.count, MediaLoaderLimits.chunkBytes)`.
- Added: `XCTAssertThrowsError(try body.append(contentsOf: Data([0])))`.
- Added: `XCTAssertEqual($0 as? APIError, .decoding)`.
- Added: `XCTAssertEqual(body.data, expected)`.

### `MediaLoaderSecurityTests.testBoundedBodyChunkAppendPreservesPlaylistSniffingAndLimit`

Source: `Packages/GlassfinCore/Tests/CorePlaybackTests/MediaLoaderSecurityTests.swift`. Inherited from v2.

Added signature: `func testBoundedBodyChunkAppendPreservesPlaylistSniffingAndLimit() throws`.

- Added: `XCTAssertEqual(body.data, prefix + padding)`.
- Added: `XCTAssertThrowsError(try body.append(contentsOf: Data([32])))`.
- Added: `XCTAssertEqual($0 as? APIError, .decoding)`.
- Added: `XCTAssertEqual(body.data.count, MediaLoaderLimits.playlistBytes)`.
- Added: `XCTAssertThrowsError(try short.append(contentsOf: prefix))`.
- Added: `XCTAssertEqual($0 as? APIError, .decoding)`.
- Added: `XCTAssertEqual(short.data, Data("#E".utf8))`.

### `ScreenReentryTests.testHomeOnAppearSelectsCurrentView`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/ScreenReentryTests.swift`. M06 re-entry addition.

Added signature: `@MainActor func testHomeOnAppearSelectsCurrentView() async`.

- Added: `XCTAssertNil(h.app.currentView)`.
- Added: `XCTAssertTrue(h.app.currentView === home)`.
- Added: `XCTAssertFalse(home.hasContent)`.
- Added: `XCTAssertEqual(h.library.resumeCallCount(), 0)`.

### `ScreenReentryTests.testLibraryOnAppearSelectsCurrentView`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/ScreenReentryTests.swift`. M06 re-entry addition.

Added signature: `@MainActor func testLibraryOnAppearSelectsCurrentView() async`.

- Added: `XCTAssertNil(h.app.currentView)`.
- Added: `XCTAssertTrue(h.app.currentView === library)`.
- Added: `XCTAssertFalse(library.hasContent)`.
- Added: `XCTAssertEqual(h.library.itemCallCount(), 0)`.

### `ScreenReentryTests.testSeriesOnAppearSelectsCurrentView`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/ScreenReentryTests.swift`. M06 re-entry addition.

Added signature: `@MainActor func testSeriesOnAppearSelectsCurrentView() async`.

- Added: `XCTAssertNil(h.app.currentView)`.
- Added: `XCTAssertTrue(h.app.currentView === series)`.
- Added: `XCTAssertFalse(series.hasContent)`.

### `ScreenReentryTests.testT06_49_homeReentryKeepsContentAndShowsBanner`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/ScreenReentryTests.swift`. M06 re-entry addition.

Added signature: `@MainActor func testT06_49_homeReentryKeepsContentAndShowsBanner() async throws`.

- Added: `XCTAssertTrue(home.hasContent, row)`.
- Added: `XCTAssertTrue(h.app.currentView === other)`.
- Added: `XCTAssertTrue(h.app.currentView === home)`.
- Added: `assertBanner(h.app)`.
- Added: `XCTAssertNil(home.serverDownTitleKey)`.
- Added: `XCTAssertTrue(h.app.showsServerDown)`.
- Added: `assertBanner(h.app)`.
- Added: `XCTAssertNil(home.serverDownTitleKey)`.
- Added: `XCTAssertEqual(home.resume, resume)`.
- Added: `XCTAssertEqual(home.nextUp, nextUp)`.
- Added: `XCTAssertEqual(home.latestRows.map(\.state), latest)`.
- Added: `XCTAssertEqual(h.library.resumeCallCount(), calls)`.

### `ScreenReentryTests.testT06_46_homeReentryWithoutContentShowsFullScreen`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/ScreenReentryTests.swift`. M06 re-entry addition.

Added signature: `@MainActor func testT06_46_homeReentryWithoutContentShowsFullScreen() async throws`.

- Added: `XCTAssertTrue(other.hasContent)`.
- Added: `XCTAssertTrue(h.app.currentView === other)`.
- Added: `XCTAssertTrue(h.app.currentView === home)`.
- Added: `XCTAssertFalse(home.hasContent)`.
- Added: `assertFullScreen(h.app)`.
- Added: `XCTAssertEqual(home.serverDownTitleKey, h.app.serverDownTitleKey)`.

### `ScreenReentryTests.testLibraryReentryKeepsContentAndShowsBanner`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/ScreenReentryTests.swift`. M06 re-entry addition.

Added signature: `@MainActor func testLibraryReentryKeepsContentAndShowsBanner() async throws`.

- Added: `XCTAssertTrue(library.hasContent)`.
- Added: `XCTAssertTrue(h.app.currentView === other)`.
- Added: `XCTAssertTrue(h.app.currentView === library)`.
- Added: `assertBanner(h.app)`.
- Added: `XCTAssertTrue(h.app.showsServerDown)`.
- Added: `assertBanner(h.app)`.
- Added: `XCTAssertEqual(library.state, state)`.
- Added: `XCTAssertEqual(h.library.itemCallCount(), calls)`.

### `ScreenReentryTests.testLibraryReentryWithoutContentShowsFullScreen`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/ScreenReentryTests.swift`. M06 re-entry addition.

Added signature: `@MainActor func testLibraryReentryWithoutContentShowsFullScreen() async throws`.

- Added: `XCTAssertTrue(other.hasContent)`.
- Added: `XCTAssertTrue(h.app.currentView === other)`.
- Added: `XCTAssertTrue(h.app.currentView === library)`.
- Added: `XCTAssertFalse(library.hasContent)`.
- Added: `assertFullScreen(h.app)`.

### `ScreenReentryTests.testSeriesReentryKeepsContentAndShowsBanner`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/ScreenReentryTests.swift`. M06 re-entry addition.

Added signature: `@MainActor func testSeriesReentryKeepsContentAndShowsBanner() async throws`.

- Added: `XCTAssertTrue(series.hasContent)`.
- Added: `XCTAssertTrue(h.app.currentView === other)`.
- Added: `XCTAssertTrue(h.app.currentView === series)`.
- Added: `assertBanner(h.app)`.
- Added: `XCTAssertTrue(h.app.showsServerDown)`.
- Added: `assertBanner(h.app)`.
- Added: `XCTAssertEqual(series.seasons, seasons)`.
- Added: `XCTAssertEqual(series.episodes, episodes)`.

### `ScreenReentryTests.testSeriesReentryWithoutContentShowsFullScreen`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/ScreenReentryTests.swift`. M06 re-entry addition.

Added signature: `@MainActor func testSeriesReentryWithoutContentShowsFullScreen() async throws`.

- Added: `XCTAssertTrue(other.hasContent)`.
- Added: `XCTAssertTrue(h.app.currentView === other)`.
- Added: `XCTAssertTrue(h.app.currentView === series)`.
- Added: `XCTAssertFalse(series.hasContent)`.
- Added: `assertFullScreen(h.app)`.

### `T02BehaviorTests.testT02_10_oldServerBlocksWithoutDroppingTheToken`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift`. Inherited from v2.

Signature: `@MainActor func testT02_10_oldServerBlocksWithoutDroppingTheToken() async throws` (unchanged).

- Removed: `XCTAssertEqual(AppErrorMessage.key(for: .unsupportedServer(version: "10.9.11")), .unsupportedServerDetail)`.
- Removed: `XCTAssertEqual(ServerVersionGate.dotted(.minimumJellyfin), "10.10.0")`.
- Removed: `XCTUnwrap(AppErrorMessage.userFacing(.unsupportedServer(version: "10.9.11")))`.
- Added: `XCTUnwrap(harness.app.blockingError)`.
- Added: `XCTAssertEqual(AppErrorMessage.messageKey(for: error), AppErrorMessage.unsupportedServerKey)`.
- Added: `XCTUnwrap(AppErrorMessage.messageKey(for: error))`.
- Added: `XCTAssertTrue(key.contains("%@"))`.
- Added: `XCTUnwrap(AppErrorMessage.userFacing(error))`.
- Added: `XCTAssertNotEqual(message, key)`.
- Added: `XCTAssertFalse(message.contains("%@"))`.
- Added: `XCTAssertEqual( message, String( format: try englishCatalogText(for: key), "10.9.11", ServerVersionGate.dotted(.minimumJellyfin)))`.
- Added: `XCTAssertEqual(ServerVersionGate.dotted(.minimumJellyfin), "10.10.0")`.
- Added: `XCTUnwrap(message.range(of: "10.9.11"))`.
- Added: `XCTUnwrap(message.range(of: ServerVersionGate.dotted(.minimumJellyfin)))`.
- Added: `XCTAssertLessThan(serverVersionRange.lowerBound, minimumVersionRange.lowerBound)`.

### `T02BehaviorTests.testT02_04_offlineBannerBlocksPlaybackAndRestores`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift`. Inherited from v2.

Signature: `@MainActor func testT02_04_offlineBannerBlocksPlaybackAndRestores() async throws` (unchanged).

- Removed: `XCTAssertEqual(harness.app.bannerKey, .noNetworkConnection)`.
- Added: `XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.offlineKey)`.
- Added: `assertEnglishCopy(harness.app.banner, key: AppErrorMessage.offlineKey, expected: "No network connection")`.
- Removed: `XCTAssertEqual(harness.app.playbackBlockedKey, .playbackOffline)`.
- Added: `XCTAssertEqual(harness.app.playbackBlockedMessageKey, AppErrorMessage.playbackOfflineKey)`.
- Added: `assertEnglishCopy(harness.app.banner, key: AppErrorMessage.offlineKey, expected: "No network connection")`.
- Removed: `XCTAssertEqual(harness.app.playbackBlockedKey, .playbackOffline)`.
- Added: `XCTAssertEqual(harness.app.playbackBlockedMessageKey, AppErrorMessage.playbackOfflineKey)`.

### `T02BehaviorTests.testT02_05_degradedAfterThreeSecondsNotAtTheBoundary`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift`. Inherited from v2.

Signature: `@MainActor func testT02_05_degradedAfterThreeSecondsNotAtTheBoundary() async throws` (unchanged).

- Removed: `XCTAssertEqual(harness.app.playbackBlockedKey, .playbackUnreachable)`.
- Removed: `XCTAssertEqual(harness.app.bannerKey, .serverUnreachable)`.
- Added: `XCTAssertEqual(harness.app.playbackBlockedMessageKey, AppErrorMessage.playbackUnreachableKey)`.
- Added: `XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.serverDownKey)`.
- Added: `assertEnglishCopy( harness.app.banner, key: AppErrorMessage.serverDownKey, expected: "Can't reach the server")`.
- Added: `XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.offlineKey)`.
- Added: `assertEnglishCopy(harness.app.banner, key: AppErrorMessage.offlineKey, expected: "No network connection")`.

### `T02BehaviorTests.testT02_06_serverDownPingRecoversWithoutLogout`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift`. Inherited from v2.

Signature: `@MainActor func testT02_06_serverDownPingRecoversWithoutLogout() async throws` (unchanged).

- Removed: `XCTAssertEqual(harness.app.bannerKey, .serverUnreachable)`.
- Removed: `XCTAssertEqual(AuthCopy.Key.tryAgain.rawValue, "Try again")`.
- Removed: `XCTAssertEqual(AuthCopy.Key.switchServer.rawValue, "Switch server")`.
- Added: `XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.serverDownKey)`.
- Added: `assertEnglishCopy( harness.app.banner, key: AppErrorMessage.serverDownKey, expected: "Can't reach the server")`.
- Added: `XCTAssertEqual(harness.app.serverDownTitleKey, AppErrorMessage.serverDownKey)`.
- Added: `XCTAssertEqual(harness.app.retryTitleKey, AppErrorMessage.retryKey)`.
- Added: `XCTAssertEqual(harness.app.changeServerTitleKey, AppErrorMessage.changeServerKey)`.
- Added: `XCTAssertNil(harness.app.bannerKey)`.
- Added: `XCTAssertNil(harness.app.banner)`.
- Added: `XCTAssertFalse(harness.app.showsServerDown)`.
- Added: `XCTAssertNil(harness.app.bannerKey)`.
- Added: `XCTAssertNil(harness.app.banner)`.

### `T02BehaviorTests.testT02_35a_serverDownWithContentKeepsContentAndShowsBanner`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift`. Inherited from v2.

Added signature: `@MainActor func testT02_35a_serverDownWithContentKeepsContentAndShowsBanner() async throws`.

- Added: `XCTAssertTrue(harness.app.snapshots.save(snapshot))`.
- Added: `XCTAssertFalse(harness.app.showsServerDown)`.
- Added: `XCTAssertEqual(home.resume.value, resume)`.
- Added: `XCTAssertEqual(home.nextUp.value, next)`.
- Added: `XCTAssertEqual(home.latest.value, latest)`.
- Added: `XCTAssertEqual(home.resume, .failed(.serverUnreachable, previous: resume))`.
- Added: `XCTAssertEqual(home.nextUp, .failed(.serverUnreachable, previous: next))`.
- Added: `XCTAssertEqual(home.latest, .failed(.serverUnreachable, previous: latest))`.
- Added: `XCTAssertEqual(home.resume.presentedError, .serverUnreachable)`.
- Added: `XCTAssertEqual(harness.app.connectivity, .serverUnreachable)`.
- Added: `XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.serverDownKey)`.
- Added: `assertEnglishCopy( harness.app.banner, key: AppErrorMessage.serverDownKey, expected: "Can't reach the server")`.
- Added: `XCTAssertFalse(harness.app.showsServerDown)`.
- Added: `XCTAssertEqual(harness.library.favorites().map(\.0), [Sample.movie])`.
- Added: `XCTAssertEqual(editor.lastError, .serverUnreachable)`.
- Added: `XCTUnwrap(editor.lastError)`.
- Added: `assertEnglishCopy( AppErrorMessage.userFacing(actionError), key: AppErrorMessage.serverDownKey, expected: "Can't reach the server")`.
- Added: `XCTFail("action failure must keep the session")`.
- Added: `XCTAssertEqual(try harness.secure.data(for: Sample.account()), Data(Sample.token.utf8))`.
- Added: `XCTAssertTrue(harness.secure.removed().isEmpty)`.
- Added: `XCTAssertFalse(harness.app.showsServerDown)`.
- Added: `XCTAssertEqual(harness.pinger.calls(), 0)`.
- Added: `XCTAssertEqual(harness.app.connectivity, .online)`.
- Added: `XCTAssertEqual(harness.pinger.calls(), 1)`.
- Added: `XCTAssertNil(harness.app.bannerKey)`.
- Added: `XCTAssertNil(harness.app.banner)`.
- Added: `XCTAssertFalse(harness.app.showsServerDown)`.
- Added: `XCTAssertEqual(home.resume.value, resume)`.
- Added: `XCTAssertEqual(home.nextUp.value, next)`.
- Added: `XCTAssertEqual(home.latest.value, latest)`.
- Added: `XCTFail("recovery must keep the session")`.
- Added: `XCTAssertEqual(try harness.secure.data(for: Sample.account()), Data(Sample.token.utf8))`.
- Added: `XCTAssertTrue(harness.secure.removed().isEmpty)`.
- Added: `XCTAssertEqual(harness.log.messages(level: "debug").filter { $0 == "Signed in." }.count, 1)`.

### `T02BehaviorTests.testT02_35b_serverDownWithoutContentShowsFullScreen`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift`. Inherited from v2.

Added signature: `@MainActor func testT02_35b_serverDownWithoutContentShowsFullScreen() async throws`.

- Added: `XCTAssertNil(harness.app.snapshots.load())`.
- Added: `XCTAssertNil(home.resume.value)`.
- Added: `XCTAssertNil(home.nextUp.value)`.
- Added: `XCTAssertNil(home.latest.value)`.
- Added: `XCTAssertEqual(harness.library.resumeCallCount(), 1)`.
- Added: `XCTAssertEqual(harness.library.nextCallCount(), 1)`.
- Added: `XCTAssertEqual(harness.library.latestIdentifiers(), [Sample.library])`.
- Added: `XCTAssertEqual(home.resume, .failed(.serverUnreachable, previous: nil))`.
- Added: `XCTAssertEqual(home.nextUp, .failed(.serverUnreachable, previous: nil))`.
- Added: `XCTAssertEqual(home.latest, .failed(.serverUnreachable, previous: nil))`.
- Added: `XCTAssertFalse(home.hasContent)`.
- Added: `XCTAssertEqual(harness.app.connectivity, .serverUnreachable)`.
- Added: `XCTAssertTrue(harness.app.showsServerDown)`.
- Added: `XCTAssertEqual(harness.app.serverDownTitleKey, AppErrorMessage.serverDownKey)`.
- Added: `XCTAssertEqual(harness.app.retryTitleKey, AppErrorMessage.retryKey)`.
- Added: `XCTAssertEqual(harness.app.changeServerTitleKey, AppErrorMessage.changeServerKey)`.
- Added: `assertEnglishCopy( harness.app.serverDownTitle, key: AppErrorMessage.serverDownKey, expected: "Can't reach the server")`.
- Added: `assertEnglishCopy(harness.app.retryTitle, key: AppErrorMessage.retryKey, expected: "Try again")`.
- Added: `assertEnglishCopy( harness.app.changeServerTitle, key: AppErrorMessage.changeServerKey, expected: "Change server")`.
- Added: `XCTFail("first fetch failure must keep the session")`.
- Added: `XCTAssertEqual(try harness.secure.data(for: Sample.account()), Data(Sample.token.utf8))`.
- Added: `XCTAssertTrue(harness.secure.removed().isEmpty)`.
- Added: `XCTAssertEqual(harness.pinger.calls(), 0)`.
- Added: `XCTAssertEqual(harness.app.connectivity, .online)`.
- Added: `XCTAssertEqual(harness.pinger.calls(), 1)`.
- Added: `XCTAssertFalse(harness.app.showsServerDown)`.
- Added: `XCTAssertNil(harness.app.bannerKey)`.
- Added: `XCTAssertNil(harness.app.banner)`.
- Added: `XCTFail("automatic recovery must keep the session")`.
- Added: `XCTAssertEqual(try harness.secure.data(for: Sample.account()), Data(Sample.token.utf8))`.
- Added: `XCTAssertTrue(harness.secure.removed().isEmpty)`.
- Added: `XCTAssertEqual(harness.log.messages(level: "debug").filter { $0 == "Signed in." }.count, 1)`.

### `T02BehaviorTests.testT02_36_bannerTextResolvesFromKey`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift`. Inherited from v2.

Added signature: `@MainActor func testT02_36_bannerTextResolvesFromKey() async throws`.

- Added: `XCTAssertEqual(harness.app.connectivity, .offline)`.
- Added: `XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.offlineKey)`.
- Added: `assertEnglishCopy(harness.app.banner, key: AppErrorMessage.offlineKey, expected: "No network connection")`.
- Added: `XCTAssertEqual(harness.app.connectivity, .online)`.
- Added: `XCTAssertNil(harness.app.banner)`.
- Added: `XCTAssertEqual(harness.app.connectivity, .serverUnreachable)`.
- Added: `XCTAssertTrue(home.hasContent)`.
- Added: `XCTAssertFalse(harness.app.showsServerDown)`.
- Added: `XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.serverDownKey)`.
- Added: `assertEnglishCopy( harness.app.banner, key: AppErrorMessage.serverDownKey, expected: "Can't reach the server")`.
- Added: `XCTAssertEqual(harness.app.connectivity, .online)`.
- Added: `XCTAssertNil(harness.app.bannerKey)`.
- Added: `XCTAssertNil(harness.app.banner)`.

### `T02BehaviorTests.testT02_37_sessionNoticeTextResolvesFromKey`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift`. Inherited from v2.

Added signature: `@MainActor func testT02_37_sessionNoticeTextResolvesFromKey() async throws`.

- Added: `XCTAssertNil(harness.app.sessionNotice)`.
- Added: `XCTFail("authenticated 401 must end the session")`.
- Added: `XCTAssertEqual(home.resume.presentedError, .unauthorized)`.
- Added: `XCTAssertEqual(harness.app.sessionNoticeKey, AppErrorMessage.sessionExpiredKey)`.
- Added: `assertEnglishCopy( harness.app.sessionNotice, key: AppErrorMessage.sessionExpiredKey, expected: "Session expired, please sign in again")`.
- Added: `XCTFail("expected a new session")`.
- Added: `XCTAssertNil(harness.app.sessionNoticeKey)`.
- Added: `XCTAssertNil(harness.app.sessionNotice)`.

### `T02BehaviorTests.testT02_38_stallMessageTextResolvesFromKey`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift`. Inherited from v2.

Added signature: `@MainActor func testT02_38_stallMessageTextResolvesFromKey() async throws`.

- Added: `XCTAssertEqual(player.state.value, harness.playback.source)`.
- Added: `XCTAssertNil(player.stallMessageKey)`.
- Added: `XCTAssertNil(player.stallMessage)`.
- Added: `XCTAssertEqual(player.stallMessageKey, AppErrorMessage.bufferingKey)`.
- Added: `assertEnglishCopy( player.stallMessage, key: AppErrorMessage.bufferingKey, expected: "Buffering is taking longer than usual")`.
- Added: `XCTAssertNil(player.stallMessageKey)`.
- Added: `XCTAssertNil(player.stallMessage)`.

### `T02BehaviorTests.testServerDownUsesOnlyCurrentViewContent`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift`. Inherited from v2.

Added signature: `@MainActor func testServerDownUsesOnlyCurrentViewContent() async throws`.

- Added: `XCTAssertTrue(harness.app.showsServerDown)`.
- Added: `XCTAssertFalse(harness.app.showsServerDown)`.
- Added: `XCTAssertNil(library.state.value)`.
- Added: `XCTAssertEqual(library.state.presentedError, .serverUnreachable)`.
- Added: `XCTAssertTrue(harness.app.showsServerDown)`.
- Added: `XCTAssertEqual(home.resume.value, [Sample.movie()])`.
- Added: `XCTAssertFalse(harness.app.showsServerDown)`.
- Added: `XCTAssertEqual(library.state.value, items)`.
- Added: `XCTAssertEqual(library.state.presentedError, .serverUnreachable)`.
- Added: `XCTAssertFalse(harness.app.showsServerDown)`.
- Added: `XCTAssertEqual(library.state.value, items)`.
- Added: `XCTAssertFalse(harness.app.showsServerDown)`.
- Added: `XCTAssertNil(library.state.value)`.
- Added: `XCTAssertTrue(harness.app.showsServerDown)`.
- Added: `XCTAssertFalse(harness.app.showsServerDown)`.
- Added: `XCTAssertTrue(harness.app.showsServerDown)`.
- Added: `XCTAssertEqual(harness.app.connectivity, .serverUnreachable)`.
- Added: `XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.serverDownKey)`.
- Added: `assertEnglishCopy( harness.app.banner, key: AppErrorMessage.serverDownKey, expected: "Can't reach the server")`.

### `T02BehaviorTests.testStoredUnparseableVersionIsCleanedAndCappedBeforeFormatting`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift`. Inherited from v2.

Added signature: `@MainActor func testStoredUnparseableVersionIsCleanedAndCappedBeforeFormatting() async throws`.

- Added: `XCTAssertGreaterThan(raw.count, 200)`.
- Added: `XCTFail("expected a blocking login screen")`.
- Added: `XCTUnwrap(harness.app.blockingError)`.
- Added: `XCTUnwrap(AppErrorMessage.messageKey(for: error))`.
- Added: `XCTAssertEqual(key, AppErrorMessage.unsupportedServerKey)`.
- Added: `XCTUnwrap(AppErrorMessage.userFacing(error))`.
- Added: `XCTAssertEqual( message, String( format: try englishCatalogText(for: key), expectedVersion, ServerVersionGate.dotted(.minimumJellyfin)))`.
- Added: `XCTUnwrap(message.range(of: " is not supported."))`.
- Added: `XCTAssertEqual(embedded, expectedVersion)`.
- Added: `XCTAssertEqual(embedded.count, 200)`.
- Added: `XCTAssertLessThanOrEqual(embedded.count, 200)`.
- Added: `XCTAssertGreaterThan(embedded.unicodeScalars.count, embedded.count)`.
- Added: `XCTAssertTrue(embedded.contains("<b>**"))`.
- Added: `XCTAssertFalse(message.unicodeScalars.contains { $0.properties.generalCategory == .control })`.
- Added: `XCTAssertTrue(bidi.isDisjoint(with: message.unicodeScalars.map(\.value)))`.
- Added: `XCTAssertFalse(message.contains("%@"))`.
- Added: `XCTAssertNotNil(try harness.secure.data(for: Sample.account()))`.

### `T02BehaviorTests.testT02_07_authenticated401LogsOutOnce`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift`. Inherited from v2.

Signature: `@MainActor func testT02_07_authenticated401LogsOutOnce() async throws` (unchanged).

- Removed: `XCTAssertEqual(harness.app.sessionNoticeKey, .sessionExpired)`.
- Added: `XCTAssertEqual(harness.app.sessionNoticeKey, AppErrorMessage.sessionExpiredKey)`.
- Added: `assertEnglishCopy( harness.app.sessionNotice, key: AppErrorMessage.sessionExpiredKey, expected: "Session expired, please sign in again")`.

### `T02BehaviorTests.testT02_28_concurrent401StillLogsOutOnce`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift`. Inherited from v2.

Signature: `@MainActor func testT02_28_concurrent401StillLogsOutOnce() async throws` (unchanged).

- Removed: `XCTAssertEqual(harness.app.sessionNoticeKey, .sessionExpired)`.
- Added: `XCTAssertEqual(harness.app.sessionNoticeKey, AppErrorMessage.sessionExpiredKey)`.
- Added: `assertEnglishCopy( harness.app.sessionNotice, key: AppErrorMessage.sessionExpiredKey, expected: "Session expired, please sign in again")`.

### `T02BehaviorTests.testT02_31_network403And5xxDoNotLogOut`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift`. Inherited from v2.

Signature: `@MainActor func testT02_08_network403And5xxDoNotLogOut() async throws` → `@MainActor func testT02_31_network403And5xxDoNotLogOut() async throws`.

- Added: `XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.serverDownKey)`.
- Added: `assertEnglishCopy( harness.app.banner, key: AppErrorMessage.serverDownKey, expected: "Can't reach the server")`.

### `T02BehaviorTests.testT02_32_forbiddenKeepsTheSession`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift`. Inherited from v2.

Signature: `@MainActor func testT02_09_forbiddenKeepsTheSession() async throws` → `@MainActor func testT02_32_forbiddenKeepsTheSession() async throws`.

- Removed: `XCTAssertEqual(AppErrorMessage.key(for: .forbidden), .forbidden)`.
- Added: `XCTAssertEqual(AppErrorMessage.messageKey(for: .forbidden), AppErrorMessage.forbiddenKey)`.

### `T02BehaviorTests.testT02_26_serverRestartDoesNotLogOutAndInvalidatesCaches`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift`. Inherited from v2.

Signature: `@MainActor func testT02_26_serverRestartDoesNotLogOutAndInvalidatesCaches() async throws` (unchanged).

- Added: `XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.serverDownKey)`.
- Added: `assertEnglishCopy( harness.app.banner, key: AppErrorMessage.serverDownKey, expected: "Can't reach the server")`.

### `T02BehaviorTests.testT02_34_libraryPagesAndCacheTTL`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift`. Inherited from v2.

Signature: `@MainActor func testT02_19_libraryPagesAndCacheTTL() async throws` → `@MainActor func testT02_34_libraryPagesAndCacheTTL() async throws`.

Assertions unchanged; setup, comments, identifiers or signature changed as inherited from v2.

### `T02BehaviorTests.testSeriesKeepsPreviousSeasonOnFailure`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift`. Inherited from v2.

Signature: `@MainActor func testSeriesKeepsPreviousSeasonOnFailure() async throws` (unchanged).

- Added: `XCTAssertFalse(harness.app.showsServerDown)`.
- Added: `XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.serverDownKey)`.
- Added: `assertEnglishCopy( harness.app.banner, key: AppErrorMessage.serverDownKey, expected: "Can't reach the server")`.

### `T02BehaviorTests.testT02_29_playbackInstrumentationStallAndStop`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift`. Inherited from v2.

Signature: `@MainActor func testT02_29_playbackInstrumentationStallAndStop() async throws` (unchanged).

- Removed: `XCTAssertEqual(player.stallMessageKey, .buffering)`.
- Added: `XCTAssertEqual(player.stallMessageKey, AppErrorMessage.bufferingKey)`.
- Added: `assertEnglishCopy( player.stallMessage, key: AppErrorMessage.bufferingKey, expected: "Buffering is taking longer than usual")`.
- Added: `XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.serverDownKey)`.
- Added: `assertEnglishCopy( harness.app.banner, key: AppErrorMessage.serverDownKey, expected: "Can't reach the server")`.
- Added: `XCTAssertEqual(harness.app.sessionNoticeKey, AppErrorMessage.sessionExpiredKey)`.
- Added: `assertEnglishCopy( harness.app.sessionNotice, key: AppErrorMessage.sessionExpiredKey, expected: "Session expired, please sign in again")`.

### `T02BehaviorTests.testT02_30_signedInColdStartDoesNotProbeUntilAsked`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift`. Inherited from v2.

Signature: `@MainActor func testT02_30_signedInColdStartDoesNotProbeUntilAsked() async throws` (unchanged).

- Added: `XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.serverDownKey)`.
- Added: `assertEnglishCopy( harness.app.banner, key: AppErrorMessage.serverDownKey, expected: "Can't reach the server")`.

### `T02FoundationTests.testT02_09_userFacingCopyAndDiagnosticsOmitTokens`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T02FoundationTests.swift`. Inherited from v2.

Signature: `func testT02_09_userFacingCopyAndDiagnosticsOmitTokens()` (unchanged).

- Removed: `XCTAssertEqual(AppErrorMessage.key(for: .offline), .noNetworkConnection)`.
- Removed: `XCTAssertEqual(AppErrorMessage.key(for: .serverUnreachable), .serverUnreachable)`.
- Removed: `XCTAssertEqual(AppErrorMessage.key(for: .forbidden), .forbidden)`.
- Removed: `XCTAssertEqual(AppErrorMessage.key(for: .unauthorized), .sessionExpired)`.
- Removed: `XCTAssertEqual(AppErrorMessage.key(for: .invalidCredentials), .invalidCredentials)`.
- Removed: `XCTAssertEqual(AppErrorMessage.key(for: .insecureRedirect), .insecureRedirect)`.
- Removed: `XCTAssertEqual(AppErrorMessage.key(for: .notFound), .itemNotFound)`.
- Removed: `XCTAssertEqual(AppErrorMessage.key(for: .serverError(status: 500)), .serverError)`.
- Removed: `XCTAssertEqual(AppErrorMessage.key(for: .playback(.itemFailed(code: "NoCompatibleStream"))), .playbackFailed)`.
- Removed: `XCTAssertEqual(AppErrorMessage.key(for: .unsupportedServer(version: "10.9.11")), .unsupportedServerDetail)`.
- Added: `XCTAssertEqual(AppErrorMessage.messageKey(for: .offline), AppErrorMessage.offlineKey)`.
- Added: `XCTAssertEqual(AppErrorMessage.messageKey(for: .serverUnreachable), AppErrorMessage.serverDownKey)`.
- Added: `XCTAssertEqual(AppErrorMessage.messageKey(for: .forbidden), AppErrorMessage.forbiddenKey)`.
- Added: `XCTAssertEqual(AppErrorMessage.messageKey(for: .unauthorized), AppErrorMessage.sessionExpiredKey)`.
- Added: `XCTAssertEqual(AppErrorMessage.messageKey(for: .invalidCredentials), AppErrorMessage.invalidCredentialsKey)`.
- Added: `XCTAssertEqual(AppErrorMessage.messageKey(for: .insecureRedirect), AppErrorMessage.insecureRedirectKey)`.
- Added: `XCTAssertEqual(AppErrorMessage.messageKey(for: .notFound), AppErrorMessage.notFoundKey)`.
- Added: `XCTAssertEqual(AppErrorMessage.messageKey(for: .serverError(status: 500)), AppErrorMessage.serverErrorKey)`.
- Added: `XCTAssertEqual( AppErrorMessage.messageKey(for: .playback(.itemFailed(code: "NoCompatibleStream"))), AppErrorMessage.playbackFailedKey)`.
- Added: `XCTAssertEqual( AppErrorMessage.messageKey(for: .unsupportedServer(version: "10.9.11")), AppErrorMessage.unsupportedServerKey )`.

### `T02FoundationTests.testAppErrorMessageKeysCoverEveryCase`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T02FoundationTests.swift`. Inherited from v2.

Signature: `func testAppErrorMessageKeysCoverEveryCase()` (unchanged).

Assertions unchanged; setup, comments, identifiers or signature changed as inherited from v2.

### `T02FoundationTests.testT02_33_xctMetricRecordsPlaybackFirstFrame`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T02FoundationTests.swift`. Inherited from v2.

Signature: `func testT02_18_xctMetricRecordsPlaybackFirstFrame()` → `func testT02_33_xctMetricRecordsPlaybackFirstFrame()`.

Assertions unchanged; setup, comments, identifiers or signature changed as inherited from v2.

### `T04AuthTests.testT04_61_usersMeFailuresKeepTheToken`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T04AuthTests.swift`. Inherited from v2.

Signature: `@MainActor func testT04_61_usersMeFailuresKeepTheToken() async throws` (unchanged).

- Added: `XCTAssertEqual(rig.harness.app.bannerKey, AppErrorMessage.serverDownKey)`.
- Added: `XCTAssertEqual(rig.flow.bannerKey?.rawValue, rig.harness.app.bannerKey)`.

### `T04AuthTests.testT04_59_launchFailureLoadsCachedHomeAndKeepsToken`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T04AuthTests.swift`. Inherited from v2.

Signature: `@MainActor func testT04_59_launchFailureLoadsCachedHomeAndKeepsToken() async throws` (unchanged).

- Added: `XCTAssertEqual(rig.harness.app.bannerKey, AppErrorMessage.serverDownKey)`.
- Added: `XCTAssertEqual(rig.flow.bannerKey?.rawValue, rig.harness.app.bannerKey)`.
- Added: `XCTAssertEqual(rig.flow.bannerKey, .noNetworkConnection)`.
- Added: `XCTAssertEqual(rig.flow.bannerKey?.rawValue, rig.harness.app.bannerKey)`.
- Added: `XCTAssertEqual(rig.flow.cachedHome, snapshot)`.
- Added: `XCTAssertNil(rig.flow.homeErrorKey)`.
- Added: `XCTAssertEqual(rig.flow.connectivity, .offline)`.
- Added: `XCTAssertEqual(rig.flow.bannerKey, .noNetworkConnection)`.
- Added: `XCTAssertEqual(rig.flow.bannerKey?.rawValue, rig.harness.app.bannerKey)`.
- Added: `XCTAssertEqual(rig.flow.bannerKey, .serverUnreachable)`.
- Added: `XCTAssertEqual(rig.flow.connectivity, .online)`.
- Added: `XCTAssertNil(rig.flow.bannerKey)`.
- Added: `XCTAssertNil(rig.harness.app.bannerKey)`.

### `T04AuthTests.testT04_63_noCacheShowsHomeErrorAndRetryAndStillAllowsLogout`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T04AuthTests.swift`. Inherited from v2.

Signature: `@MainActor func testT04_63_noCacheShowsHomeErrorAndRetryAndStillAllowsLogout() async throws` (unchanged).

- Added: `XCTAssertNil(rig.harness.app.bannerKey)`.

### `T04AuthTests.testT04_87_launchFailurePingsEveryTenSecondsRecoversAndLater401SignsOut`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T04AuthTests.swift`. Inherited from v2.

Signature: `@MainActor func testT04_87_launchFailurePingsEveryTenSecondsRecoversAndLater401SignsOut() async throws` (unchanged).

- Added: `XCTAssertNil(rig.harness.app.bannerKey)`.

### `T06HomeTests.testT06_14_sectionFailureAndTargetedRetryLeaveOtherRowsVisible`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T06HomeTests.swift`. Existing feature test adapted to v2.

Signature: `@MainActor func testT06_14_sectionFailureAndTargetedRetryLeaveOtherRowsVisible() async throws` (unchanged).

- Removed: `XCTAssertEqual(AppErrorMessage.key(for: try XCTUnwrap(home.resume.presentedError)), .serverError)`.
- Added: `XCTAssertEqual( AppErrorMessage.messageKey(for: try XCTUnwrap(home.resume.presentedError)), AppErrorMessage.serverErrorKey)`.

### `T06HomeTests.testT06_19_bodyDecodeFailureShowsSectionRetryAndKeepsOtherRows`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T06HomeTests.swift`. Existing feature test adapted to v2.

Signature: `@MainActor func testT06_19_bodyDecodeFailureShowsSectionRetryAndKeepsOtherRows() async throws` (unchanged).

- Removed: `XCTAssertEqual(HomePolicy.sectionErrorKey(for: home.resume), .serverError)`.
- Added: `XCTAssertEqual(HomePolicy.sectionErrorKey(for: home.resume), AppErrorMessage.serverErrorKey)`.

### `T06HomeTests.testT06_49_serverDownRetainsVisibleContentAndBanner`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T06HomeTests.swift`. Existing feature test adapted to v2.

Signature: `@MainActor func testT06_49_serverDownRetainsVisibleContentAndBanner() async throws` (unchanged).

- Removed: `XCTAssertEqual(home.bannerKey, .serverUnreachable)`.
- Added: `XCTAssertEqual(home.bannerKey, AppErrorMessage.serverDownKey)`.

### `T06HomeTests.testT06_46_noContentUsesExistingServerDownTitleKey`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T06HomeTests.swift`. Existing feature test adapted to v2.

Signature: `@MainActor func testT06_46_noContentUsesExistingServerDownTitleKey() async throws` (unchanged).

- Removed: `XCTAssertEqual(home.serverDownTitleKey, AppErrorMessage.key(for: .serverUnreachable))`.
- Added: `XCTAssertEqual(home.serverDownTitleKey, AppErrorMessage.messageKey(for: .serverUnreachable))`.

### `T06HomeTests.testT06_51_latest401EndsSessionOnceEvenWhenOtherRowsSucceed`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T06HomeTests.swift`. Existing feature test adapted to v2.

Signature: `@MainActor func testT06_51_latest401EndsSessionOnceEvenWhenOtherRowsSucceed() async throws` (unchanged).

- Removed: `XCTAssertEqual(h.app.sessionNoticeKey, .sessionExpired)`.
- Added: `XCTAssertEqual(h.app.sessionNoticeKey, AppErrorMessage.sessionExpiredKey)`.

### `T06HomeTests.testT06_50_unreachableActionKeepsContentUntilPingRecovery`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T06HomeTests.swift`. Existing feature test adapted to v2.

Signature: `@MainActor func testT06_50_unreachableActionKeepsContentUntilPingRecovery() async throws` (unchanged).

- Removed: `XCTAssertEqual(home.bannerKey, .serverUnreachable)`.
- Added: `XCTAssertEqual(home.bannerKey, AppErrorMessage.serverDownKey)`.

### `T06HomeTests.testT06_56_cachedColdStartKeepsContentAndServerUnreachableBanner`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T06HomeTests.swift`. Existing feature test adapted to v2.

Signature: `@MainActor func testT06_56_cachedColdStartKeepsContentAndServerUnreachableBanner() async throws` (unchanged).

- Removed: `XCTAssertEqual(home.bannerKey, .serverUnreachable)`.
- Added: `XCTAssertEqual(home.bannerKey, AppErrorMessage.serverDownKey)`.

### `T06SessionTests.testT06_51_image401CancelsOtherRequestsAndDoesNotRetry`

Source: `Packages/GlassfinCore/Tests/CoreStateTests/T06SessionTests.swift`. Existing feature test adapted to v2.

Signature: `@MainActor func testT06_51_image401CancelsOtherRequestsAndDoesNotRetry() async throws` (unchanged).

- Removed: `XCTAssertEqual(h.app.sessionNoticeKey, .sessionExpired)`.
- Added: `XCTAssertEqual(h.app.sessionNoticeKey, AppErrorMessage.sessionExpiredKey)`.

## Adaptation notes

- `T06MetadataTests.testT06_73_displayTextCaps500GraphemesWithoutSplittingEmojiOrCombiningMarks`: replaced the negative-limit assertion with `displayText(raw, limit: .max) == raw`. #7 delegates to `Collection.prefix`, whose limit must be nonnegative; all production policy limits are nonnegative. The zero-limit assertion, 500-to-200 grapheme checks and scalar-boundary checks remain.
- `T06HomeTests` and `T06SessionTests`: typed `AuthCopy.Key` expectations became equivalent #7 `AppErrorMessage` String constants. Home decode assertions now call `messageKey(for:)`, preserving the `.serverError` expectation for the actual `.serverError` fixture.
- `T02BehaviorTests.testT02_35a_serverDownWithContentKeepsContentAndShowsBanner`: only its cached fixture was adapted beyond isolation; all v2 assertions remain. Its `HomeSnapshot` now includes `Library(id: Sample.library, name: "Library")` and `[Sample.library: latest]` grouping.
- `T02BehaviorTests.testOptimisticEditsCommitRollbackAndRefreshHome`: the existing M06 assertion `home.resume.value == []` is retained because played titles leave Continue Watching; v2’s pre-M06 assertion expected the played item to remain.
- `DesignSystemLogicTests.testT05_15_overviewIsPlainText`: existing M06 literal-markup assertions remain; v2’s old stripped/decoded expectations were not restored.
- `T04AuthUITests.testT04_49_backFromQuickConnectReturnsToTheMethodScreen`: retains the v2 pending Quick Connect launch fixture with the existing M06 async method isolation. Settings navigation continues to use the feature shell’s `design.tab.settings` identifier.
- No test scenario was deleted, no skip condition was added, and no existing test signature changed in the re-entry commit.
