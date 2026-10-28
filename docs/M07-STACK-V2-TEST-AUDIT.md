# M07 stack v2 conflict and test audit

Baseline: `c7837d7` (the feature head before this work). Merge: `68d1c02`,
`Merge stack base v2 (#14 981d632 + #13 7477ffc + main abc2017)`.

## Conflict resolutions

Every conflicted file was compared with `origin/stack/m04-m05-main-base`.
Files unchanged by M07 use v2 verbatim, with the catalog union and its exact-key
validation as the two necessary exceptions. Both catalogs retain the union of
keys and translated en/fi entries. No Info.plist or workflow edits were made;
`project.yml` is byte-for-byte v2 (the six upstream lines are inherited).

| Conflicted file | Resolution |
| --- | --- |
| `Apps/Shared/Resources/Localizable.xcstrings` | Union of keys from both parents, preserving en+fi; seven legacy CoreModels keys are retained alongside v2 shared keys. |
| `Apps/Shared/Sources/AuthRootView.swift` | Merge both deltas against the old base; preserve v2 APIs/behavior and M07 feature additions. |
| `Apps/Shared/Sources/DesignSystem/Cards.swift` | Merge both deltas against the old base; preserve v2 APIs/behavior and M07 feature additions. |
| `Apps/Shared/Sources/DesignSystem/Copy.swift` | Keep feature version: v2 has no delta from the old base. |
| `Apps/Shared/Sources/DesignSystem/Demo.swift` | Merge both deltas against the old base; preserve v2 APIs/behavior and M07 feature additions. |
| `Apps/Shared/Sources/DesignSystem/GlassBanner.swift` | Keep v2 accessibility containment and M07 literal localized message/label. |
| `Apps/Shared/Sources/DesignSystem/Panels.swift` | Merge both deltas against the old base; preserve v2 APIs/behavior and M07 feature additions. |
| `Apps/Shared/Sources/DesignSystem/Rows.swift` | Merge both deltas against the old base; preserve v2 APIs/behavior and M07 feature additions. |
| `Apps/Shared/Sources/DesignSystem/Shell.swift` | Merge both deltas against the old base; preserve v2 APIs/behavior and M07 feature additions. |
| `Apps/Shared/Sources/DesignSystem/Tokens.swift` | Merge both deltas against the old base; preserve v2 APIs/behavior and M07 feature additions. |
| `Apps/Shared/Sources/GlassfinRootView.swift` | Keep feature version: v2 has no delta from the old base. |
| `Apps/Shared/Tests/Logic/DesignSystemLogicTests.swift` | Keep v2 contrast assertions and 0.001 color accuracy; preserve M07 method-level actor isolation, including the two new v2 methods. |
| `Apps/Shared/Tests/Snapshots/DesignSystemSnapshotTests.swift` | Merge both deltas against the old base; preserve v2 APIs/behavior and M07 feature additions. |
| `Apps/Shared/UITests/DesignSystemFocusTests.swift` | Merge both deltas against the old base; preserve v2 APIs/behavior and M07 feature additions. |
| `Apps/Shared/UITests/T04AuthUITests.swift` | Keep v2 pending Quick Connect fixture and symbolic key assertions; retain M07 method-level actor isolation; drop obsolete literal-key helper. |
| `Packages/GlassfinCore/Package.swift` | v2 verbatim: feature did not change this file from the old base. |
| `Packages/GlassfinCore/Sources/CoreModels/AppError.swift` | v2 verbatim: feature did not change this file from the old base. |
| `Packages/GlassfinCore/Sources/CoreModels/AuthCopy.swift` | v2 verbatim: feature did not change this file from the old base. |
| `Packages/GlassfinCore/Sources/CoreModels/LinuxStringLocalization.swift` | v2 verbatim: feature did not change this file from the old base. |
| `Packages/GlassfinCore/Sources/CoreModels/Localizable.xcstrings` | Union of keys from both parents, preserving en+fi; seven legacy CoreModels keys are retained alongside v2 shared keys. |
| `Packages/GlassfinCore/Sources/CoreModels/MetadataSanitizer.swift` | Keep #7's displayText and control/bidi helper exactly; remove the duplicate; keep M07's literal display policy and MetadataPolicy limits. plainText delegates to displayText without stripping tags or decoding entities. |
| `Packages/GlassfinCore/Sources/CoreModels/ResilientItems.swift` | Keep feature version: v2 has no delta from the old base. |
| `Packages/GlassfinCore/Sources/CoreNetworking/ServerProbe.swift` | v2 verbatim: feature did not change this file from the old base. |
| `Packages/GlassfinCore/Sources/CoreNetworking/ServerTransportPolicy.swift` | v2 verbatim: feature did not change this file from the old base. |
| `Packages/GlassfinCore/Sources/CoreNetworking/SessionTermination.swift` | v2 verbatim: feature did not change this file from the old base. |
| `Packages/GlassfinCore/Sources/CoreServices/Services.swift` | Keep feature version: v2 has no delta from the old base. |
| `Packages/GlassfinCore/Sources/CoreState/AppState.swift` | v2 verbatim: feature did not change this file from the old base. |
| `Packages/GlassfinCore/Sources/CoreState/AuthFlow.swift` | Merge both deltas against the old base; preserve v2 APIs/behavior and M07 feature additions. |
| `Packages/GlassfinCore/Sources/CoreState/Caches.swift` | Keep feature version: v2 has no delta from the old base. |
| `Packages/GlassfinCore/Sources/CoreState/RetryingClient.swift` | Keep feature version: v2 has no delta from the old base. |
| `Packages/GlassfinCore/Sources/CoreState/UserDataStore.swift` | Keep feature version: v2 has no delta from the old base. |
| `Packages/GlassfinCore/Sources/CoreState/ViewModels.swift` | Keep v2 Home/Player content-provider APIs; retain M07 split Library/Series models with matching conformance and accurate hasContent; discard duplicate monolithic definitions. |
| `Packages/GlassfinCore/Tests/CoreModelsTests/CoreModelsTests.swift` | v2 verbatim: feature did not change this file from the old base. |
| `Packages/GlassfinCore/Tests/CoreModelsTests/SecurityNameTests.swift` | Keep feature version: v2 has no delta from the old base. |
| `Packages/GlassfinCore/Tests/CoreNetworkingTests/StringCatalogTests.swift` | Keep v2 accessors and strict key/translation assertions; add the exact seven retained legacy keys to the expected union. |
| `Packages/GlassfinCore/Tests/CoreNetworkingTests/T04ProbeTests.swift` | Keep feature version: v2 has no delta from the old base. |
| `Packages/GlassfinCore/Tests/CoreStateTests/Support.swift` | Merge both deltas against the old base; preserve v2 APIs/behavior and M07 feature additions. |
| `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift` | Keep v2 AppState/String-key assertions, canonical IDs and added regressions; preserve method-level @MainActor async isolation for every imported method. |
| `Packages/GlassfinCore/Tests/CoreStateTests/T02FoundationTests.swift` | Merge both deltas against the old base; preserve v2 APIs/behavior and M07 feature additions. |
| `Packages/GlassfinCore/Tests/CoreStateTests/T04AuthTests.swift` | Merge both deltas against the old base; preserve v2 APIs/behavior and M07 feature additions. |
| `docs/ADR-M05-1.md` | Merge both deltas against the old base; preserve v2 APIs/behavior and M07 feature additions. |
| `scripts/ci-grep.sh` | Keep feature version: v2 has no delta from the old base. |
| `scripts/jellyfin_bootstrap.py` | Keep v2 readiness, path verification/repair, retry and diagnostics; parameterize library creation with compatible defaults and retain both M07 movie/series fixtures and the two-season wait. |

## Screen ownership

HomeViewModel, LibraryViewModel and ItemDetailViewModel register themselves in
`onAppear()`. The grid and item-detail SwiftUI screens call those hooks on every
appearance, including retained NavigationStack and tab returns. This branch’s
actual Home tab is rendered by AuthFlow, which now also provides accurate
`hasContent` and registers on tab appearance. An empty snapshot counts as empty.

SeriesViewModel provides a standalone `onAppear()` hook. In this branch it is
embedded inside ItemDetailScreen; loading its seasons does not replace the
detail provider. The series hero therefore remains displayable even if seasons
and episodes are empty or fail. No standalone series SwiftUI screen exists here.

## Signature and isolation changes

No XCTestCase class has class-level `@MainActor`. Existing feature methods keep
method-level isolation. The following newly imported v2 methods receive it:

| Method | Signature adjustment from v2 |
| --- | --- |
| `testT02_35a_serverDownWithContentKeepsContentAndShowsBanner` | Add method-level @MainActor; retain async throws. |
| `testT02_35b_serverDownWithoutContentShowsFullScreen` | Add method-level @MainActor; retain async throws. |
| `testT02_36_bannerTextResolvesFromKey` | Add method-level @MainActor; retain async throws. |
| `testT02_37_sessionNoticeTextResolvesFromKey` | Add method-level @MainActor; retain async throws. |
| `testT02_38_stallMessageTextResolvesFromKey` | Add method-level @MainActor; retain async throws. |
| `testServerDownUsesOnlyCurrentViewContent` | Add method-level @MainActor; retain async throws. |
| `testStoredUnparseableVersionIsCleanedAndCappedBeforeFormatting` | Add method-level @MainActor and async; retain throws. |
| `testT05_32_contrastFixtureMatchesHeroTokens` | Add method-level @MainActor and async. |
| `testT05_32_upperHeroTextUsesConservativeScrimOpacity` | Add method-level @MainActor and async. |

Upstream canonical renames retained (existing actor/async behavior preserved):

- `testT02_08_network403And5xxDoNotLogOut` → `testT02_31_network403And5xxDoNotLogOut`.
- `testT02_09_forbiddenKeepsTheSession` → `testT02_32_forbiddenKeepsTheSession`.
- `testT02_19_libraryPagesAndCacheTTL` → `testT02_34_libraryPagesAndCacheTTL`.
- `testT02_18_xctMetricRecordsPlaybackFirstFrame` → `testT02_33_xctMetricRecordsPlaybackFirstFrame` (Apple metric class also becomes `T02_33_AppleSignpostMetricTests`).

All 12 newly authored lifecycle methods use `@MainActor async`; the identity-only
extra does not throw and the other 11 use `async throws`. Their exact names and
assertions are listed below. No other pre-existing feature test signature changed.

## Test and assertion deltas

Each changed test is listed below. “v2 assertions adopted verbatim” means the
assertion expressions match v2 exactly; it does not imply Apple execution.
For locally adapted or newly authored tests, every added/removed assertion
expression is shown. Multiline calls are folded onto one line. Shared assertion
helpers are listed separately. Existing tests without assertion deltas are called
out when their setup, fixture, or signature changed.

## `Apps/Shared/Tests/Logic/DesignSystemLogicTests.swift`

### `testT05_32_scrimContrastOnThreeBackgrounds`

`@MainActor func testT05_32_scrimContrastOnThreeBackgrounds() async`

v2 assertions adopted verbatim.

### `testT05_32_contrastFixtureMatchesHeroTokens`

`@MainActor func testT05_32_contrastFixtureMatchesHeroTokens() async`

v2 assertions adopted verbatim.

### `testT05_32_upperHeroTextUsesConservativeScrimOpacity`

`@MainActor func testT05_32_upperHeroTextUsesConservativeScrimOpacity() async`

v2 assertions adopted verbatim.

### `testT05_35_reduceTransparencyUsesOneFallbackToken`

`@MainActor func testT05_35_reduceTransparencyUsesOneFallbackToken() async`

v2 assertions adopted verbatim.

## `Apps/Shared/UITests/DesignSystemFocusTests.swift`

### `testT05_22_demoIdentifiersExist`

`@MainActor func testT05_22_demoIdentifiersExist() async`

v2 assertions adopted verbatim.

### `testT05_10_longPressOpensTheContextMenu`

`@MainActor func testT05_10_longPressOpensTheContextMenu() async`

v2 assertions adopted verbatim.

### `testT05_21_retryIncrementsTheAttemptCount`

`@MainActor func testT05_21_retryIncrementsTheAttemptCount() async`

v2 assertions adopted verbatim.

### `testT05_28_menuWalksBackToTheTabBar`

`@MainActor func testT05_28_menuWalksBackToTheTabBar() async`

v2 assertions adopted verbatim.

## `Apps/Shared/UITests/T04AuthUITests.swift`

### `testT04_01_welcomeIsTheConnectButton`

`@MainActor func testT04_01_welcomeIsTheConnectButton() async`

v2 assertions adopted verbatim.

### `testT04_11_explicitPublicHTTPShowsTheKey`

`@MainActor func testT04_11_explicitPublicHTTPShowsTheKey() async`

v2 assertions adopted verbatim.

### `testT04_49_backFromQuickConnectReturnsToTheMethodScreen`

`@MainActor func testT04_49_backFromQuickConnectReturnsToTheMethodScreen() async`

v2 assertions adopted verbatim.

Upstream setup change: launch with `-uitest-qc-pending`.

### `testT04_40_expiredCodeOffersFocusedNewCodeButton`

`@MainActor func testT04_40_expiredCodeOffersFocusedNewCodeButton() async`

v2 assertions adopted verbatim.

### `testT04_68_settingsSignOutDefaultsToCancelAndKeepsServer`

`@MainActor func testT04_68_settingsSignOutDefaultsToCancelAndKeepsServer() async`

v2 assertions adopted verbatim.

## `Packages/GlassfinCore/Tests/CoreModelsTests/CoreModelsTests.swift`

### `testSharedAuthErrorKeysReuseAppErrorMessageConstants`

`func testSharedAuthErrorKeysReuseAppErrorMessageConstants()`

v2 assertions adopted verbatim.

## `Packages/GlassfinCore/Tests/CoreModelsTests/MetadataSanitizerTests.swift`

### `testServerVersionSanitizerStripsControlAndBidiAndCapsAt200Graphemes`

`func testServerVersionSanitizerStripsControlAndBidiAndCapsAt200Graphemes()`

v2 assertions adopted verbatim.

## `Packages/GlassfinCore/Tests/CoreNetworkingTests/StringCatalogTests.swift`

### `testNetworkingCatalogKeysAndLocalizedAccessors`

`func testNetworkingCatalogKeysAndLocalizedAccessors() throws`

v2 assertions adopted verbatim.

### `testModelsCatalogKeysAndLocalizedAccessor`

`func testModelsCatalogKeysAndLocalizedAccessor() throws`

```diff
+ XCTAssertEqual(Set(englishValues.keys), Set(AuthCopy.Key.allCases.map(\.rawValue)).union(retainedCatalogKeys))
```

## `Packages/GlassfinCore/Tests/CorePlaybackTests/MediaLoaderSecurityTests.swift`

### `testBoundedBodyChunkAppendHonorsExactRangeLimit`

`func testBoundedBodyChunkAppendHonorsExactRangeLimit() throws`

v2 assertions adopted verbatim.

### `testBoundedBodyAccumulatesChunksUpToProgressiveLimit`

`func testBoundedBodyAccumulatesChunksUpToProgressiveLimit() throws`

v2 assertions adopted verbatim.

### `testBoundedBodyChunkAppendPreservesPlaylistSniffingAndLimit`

`func testBoundedBodyChunkAppendPreservesPlaylistSniffingAndLimit() throws`

v2 assertions adopted verbatim.

## `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift`

### `testT02_10_oldServerBlocksWithoutDroppingTheToken`

`@MainActor func testT02_10_oldServerBlocksWithoutDroppingTheToken() async throws`

v2 assertions adopted verbatim.

### `testT02_04_offlineBannerBlocksPlaybackAndRestores`

`@MainActor func testT02_04_offlineBannerBlocksPlaybackAndRestores() async throws`

v2 assertions adopted verbatim.

### `testT02_05_degradedAfterThreeSecondsNotAtTheBoundary`

`@MainActor func testT02_05_degradedAfterThreeSecondsNotAtTheBoundary() async throws`

v2 assertions adopted verbatim.

### `testT02_06_serverDownPingRecoversWithoutLogout`

`@MainActor func testT02_06_serverDownPingRecoversWithoutLogout() async throws`

v2 assertions adopted verbatim.

### `testT02_35a_serverDownWithContentKeepsContentAndShowsBanner`

`@MainActor func testT02_35a_serverDownWithContentKeepsContentAndShowsBanner() async throws`

v2 assertions adopted verbatim.

### `testT02_35b_serverDownWithoutContentShowsFullScreen`

`@MainActor func testT02_35b_serverDownWithoutContentShowsFullScreen() async throws`

v2 assertions adopted verbatim.

### `testT02_36_bannerTextResolvesFromKey`

`@MainActor func testT02_36_bannerTextResolvesFromKey() async throws`

v2 assertions adopted verbatim.

### `testT02_37_sessionNoticeTextResolvesFromKey`

`@MainActor func testT02_37_sessionNoticeTextResolvesFromKey() async throws`

v2 assertions adopted verbatim.

### `testT02_38_stallMessageTextResolvesFromKey`

`@MainActor func testT02_38_stallMessageTextResolvesFromKey() async throws`

v2 assertions adopted verbatim.

### `testServerDownUsesOnlyCurrentViewContent`

`@MainActor func testServerDownUsesOnlyCurrentViewContent() async throws`

v2 assertions adopted verbatim.

Setup change: replace direct `app.currentView = home` with `home.onAppear()` for the retained-screen return.

### `testStoredUnparseableVersionIsCleanedAndCappedBeforeFormatting`

`@MainActor func testStoredUnparseableVersionIsCleanedAndCappedBeforeFormatting() async throws`

v2 assertions adopted verbatim.

### `testT02_07_authenticated401LogsOutOnce`

`@MainActor func testT02_07_authenticated401LogsOutOnce() async throws`

v2 assertions adopted verbatim.

### `testT02_28_concurrent401StillLogsOutOnce`

`@MainActor func testT02_28_concurrent401StillLogsOutOnce() async throws`

v2 assertions adopted verbatim.

### `testT02_31_network403And5xxDoNotLogOut`

`@MainActor func testT02_31_network403And5xxDoNotLogOut() async throws`

v2 assertions adopted verbatim.

### `testT02_32_forbiddenKeepsTheSession`

`@MainActor func testT02_32_forbiddenKeepsTheSession() async throws`

v2 assertions adopted verbatim.

### `testT02_26_serverRestartDoesNotLogOutAndInvalidatesCaches`

`@MainActor func testT02_26_serverRestartDoesNotLogOutAndInvalidatesCaches() async throws`

v2 assertions adopted verbatim.

### `testT02_34_libraryPagesAndCacheTTL`

`@MainActor func testT02_34_libraryPagesAndCacheTTL() async throws`

v2 assertions adopted verbatim.

### `testSeriesKeepsPreviousSeasonOnFailure`

`@MainActor func testSeriesKeepsPreviousSeasonOnFailure() async throws`

v2 assertions adopted verbatim.

Setup change: call `series.onAppear()` before loading the standalone test host.

### `testT02_29_playbackInstrumentationStallAndStop`

`@MainActor func testT02_29_playbackInstrumentationStallAndStop() async throws`

v2 assertions adopted verbatim.

### `testT02_30_signedInColdStartDoesNotProbeUntilAsked`

`@MainActor func testT02_30_signedInColdStartDoesNotProbeUntilAsked() async throws`

v2 assertions adopted verbatim.

## `Packages/GlassfinCore/Tests/CoreStateTests/T02FoundationTests.swift`

### `testT02_09_userFacingCopyAndDiagnosticsOmitTokens`

`func testT02_09_userFacingCopyAndDiagnosticsOmitTokens()`

v2 assertions adopted verbatim.

### `testAppErrorMessageKeysCoverEveryCase`

`func testAppErrorMessageKeysCoverEveryCase()`

v2 assertions adopted verbatim.

### `testRequestScopeCancelsTrackedWork`

`func testRequestScopeCancelsTrackedWork() async`

v2 assertions adopted verbatim.

### `testT02_33_xctMetricRecordsPlaybackFirstFrame`

`func testT02_33_xctMetricRecordsPlaybackFirstFrame()`

v2 assertions adopted verbatim.

## `Packages/GlassfinCore/Tests/CoreStateTests/T04AuthTests.swift`

### `testT04_61_usersMeFailuresKeepTheToken`

`@MainActor func testT04_61_usersMeFailuresKeepTheToken() async throws`

v2 assertions adopted verbatim.

### `testT04_59_launchFailureLoadsCachedHomeAndKeepsToken`

`@MainActor func testT04_59_launchFailureLoadsCachedHomeAndKeepsToken() async throws`

v2 assertions adopted verbatim.

Fixture change: the saved snapshot now contains `[Sample.movie()]` in Resume, so its existing nonblocking assertions describe displayable content. A separate new test covers absent and empty snapshots.

### `testT02_35a_returningToAuthHomeKeepsBannerWithCachedContent`

`@MainActor func testT02_35a_returningToAuthHomeKeepsBannerWithCachedContent() async throws`

```diff
+ XCTAssertTrue(rig.harness.app.snapshots.save(snapshot))
+ XCTAssertTrue(rig.harness.app.currentView === rig.flow)
+ XCTAssertTrue(rig.harness.app.currentView === other)
+ XCTAssertTrue(rig.harness.app.currentView === rig.flow)
+ XCTAssertTrue(rig.flow.hasContent)
+ XCTAssertFalse(rig.harness.app.showsServerDown)
+ XCTAssertNil(rig.flow.homeErrorKey)
+ XCTAssertEqual(rig.flow.cachedHome, snapshot)
+ XCTAssertEqual(rig.harness.app.connectivity, .serverUnreachable)
+ XCTAssertEqual(rig.harness.app.bannerKey, AppErrorMessage.serverDownKey)
```

### `testT02_35b_returningToAuthHomeWithoutContentShowsFullScreen`

`@MainActor func testT02_35b_returningToAuthHomeWithoutContentShowsFullScreen() async throws`

```diff
+ XCTAssertTrue(rig.harness.app.snapshots.save(HomeSnapshot(resume: [], nextUp: [], latest: [])))
+ XCTAssertFalse(rig.harness.app.showsServerDown)
+ XCTAssertTrue(rig.harness.app.currentView === rig.flow)
+ XCTAssertFalse(rig.flow.hasContent)
+ XCTAssertTrue(rig.harness.app.showsServerDown)
+ XCTAssertEqual(rig.flow.homeErrorKey, .serverUnreachable)
+ XCTAssertEqual(rig.harness.app.connectivity, .serverUnreachable)
+ XCTAssertEqual(rig.harness.app.serverDownTitleKey, AppErrorMessage.serverDownKey)
```

### `testT04_63_noCacheShowsHomeErrorAndRetryAndStillAllowsLogout`

`@MainActor func testT04_63_noCacheShowsHomeErrorAndRetryAndStillAllowsLogout() async throws`

v2 assertions adopted verbatim.

### `testT04_87_launchFailurePingsEveryTenSecondsRecoversAndLater401SignsOut`

`@MainActor func testT04_87_launchFailurePingsEveryTenSecondsRecoversAndLater401SignsOut() async throws`

v2 assertions adopted verbatim.

## `Packages/GlassfinCore/Tests/CoreStateTests/T07DetailTests.swift`

### `testT07_68_forbiddenActionRollsBackAndUsesTheCatalogKey`

`@MainActor func testT07_68_forbiddenActionRollsBackAndUsesTheCatalogKey() async throws`

```diff
- XCTAssertEqual(actions.lastError.flatMap(AppErrorMessage.key), .forbidden)
+ XCTAssertEqual(actions.lastError.flatMap(AppErrorMessage.messageKey), AppErrorMessage.forbiddenKey)
```

### `testT07_63_movieDetailRetainsContentWhenTheServerBecomesUnreachable`

`@MainActor func testT07_63_movieDetailRetainsContentWhenTheServerBecomesUnreachable() async throws`

```diff
- XCTAssertEqual(model.state.presentedError.flatMap(AppErrorMessage.key), .serverUnreachable)
+ XCTAssertEqual(model.state.presentedError.flatMap(AppErrorMessage.messageKey), AppErrorMessage.serverDownKey)
- XCTAssertEqual(rig.app.bannerKey, .serverUnreachable)
+ XCTAssertEqual(rig.app.bannerKey, AppErrorMessage.serverDownKey)
```

### `testT07_64_emptyDetailUsesTheSharedServerDownKey`

`@MainActor func testT07_64_emptyDetailUsesTheSharedServerDownKey() async throws`

```diff
- XCTAssertEqual(model.state.presentedError.flatMap(AppErrorMessage.key), .serverUnreachable)
+ XCTAssertEqual(model.state.presentedError.flatMap(AppErrorMessage.messageKey), AppErrorMessage.serverDownKey)
```

### `testT07_63_episodeFailureKeepsPreviousSeasonAndContent`

`@MainActor func testT07_63_episodeFailureKeepsPreviousSeasonAndContent() async throws`

```diff
- XCTAssertEqual(rig.app.bannerKey, .serverUnreachable)
+ XCTAssertEqual(rig.app.bannerKey, AppErrorMessage.serverDownKey)
```

### `testT07_27_playedIsOptimisticAndFailureRollsBackAndShowsAKey`

`@MainActor func testT07_27_playedIsOptimisticAndFailureRollsBackAndShowsAKey() async throws`

```diff
- XCTAssertEqual(actions.lastError.flatMap(AppErrorMessage.key), .serverError)
+ XCTAssertEqual(actions.lastError.flatMap(AppErrorMessage.messageKey), AppErrorMessage.serverErrorKey)
```

## `Packages/GlassfinCore/Tests/CoreStateTests/T07LibraryTests.swift`

### `testT07_63_downMidBrowseKeepsContentBannerAndTenSecondRecovery`

`@MainActor func testT07_63_downMidBrowseKeepsContentBannerAndTenSecondRecovery() async throws`

```diff
- XCTAssertEqual(model.errorKey, .serverUnreachable)
+ XCTAssertEqual(model.errorKey, AppErrorMessage.serverDownKey)
- XCTAssertEqual(rig.app.bannerKey, .serverUnreachable)
+ XCTAssertEqual(rig.app.bannerKey, AppErrorMessage.serverDownKey)
```

### `testT07_63_filterFailureKeepsPreviousQueryContent`

`@MainActor func testT07_63_filterFailureKeepsPreviousQueryContent() async throws`

```diff
- XCTAssertEqual(model.errorKey, .serverUnreachable)
- XCTAssertEqual(rig.app.bannerKey, .serverUnreachable)
+ XCTAssertEqual(model.errorKey, AppErrorMessage.serverDownKey)
+ XCTAssertEqual(rig.app.bannerKey, AppErrorMessage.serverDownKey)
```

### `testT07_64_downWithoutContentUsesTheExistingServerDownKey`

`@MainActor func testT07_64_downWithoutContentUsesTheExistingServerDownKey() async throws`

```diff
- XCTAssertEqual(model.errorKey, .serverUnreachable)
+ XCTAssertEqual(model.errorKey, AppErrorMessage.serverDownKey)
```

## `Packages/GlassfinCore/Tests/CoreStateTests/T07ScreenLifecycleTests.swift`

### `testOnAppearRegistersEachFeatureViewModel`

`@MainActor func testOnAppearRegistersEachFeatureViewModel() async`

```diff
+ XCTAssertTrue(rig.app.currentView === home)
+ XCTAssertTrue(rig.app.currentView === grid)
+ XCTAssertTrue(rig.app.currentView === detail)
+ XCTAssertTrue(rig.app.currentView === series)
+ XCTAssertTrue(rig.app.currentView === home)
+ XCTAssertFalse(series.hasContent)
+ XCTAssertFalse(home.hasContent)
+ XCTAssertFalse(grid.hasContent)
+ XCTAssertFalse(detail.hasContent)
+ XCTAssertEqual(rig.library.resumeCallCount(), 0)
+ XCTAssertEqual(rig.library.itemCallCount(), 0)
```

### `testT02_35a_returningToHomeKeepsBannerWithContent`

`@MainActor func testT02_35a_returningToHomeKeepsBannerWithContent() async throws`

```diff
+ assertReturningContent(model, onAppear: model.onAppear, rig: rig)
+ assertReturningContent(model, onAppear: model.onAppear, rig: rig)
+ XCTAssertEqual(sections[section], items)
+ XCTAssertEqual(rig.library.resumeCallCount(), 2)
+ XCTAssertEqual(rig.library.nextCallCount(), 2)
+ XCTAssertEqual(rig.library.latestIdentifiers(), [Sample.library, Sample.library])
```

### `testT07_63_returningToLibraryKeepsBannerWithContent`

`@MainActor func testT07_63_returningToLibraryKeepsBannerWithContent() async throws`

```diff
+ assertReturningContent(model, onAppear: model.onAppear, rig: rig)
+ assertReturningContent(model, onAppear: model.onAppear, rig: rig)
+ XCTAssertEqual(model.state, .failed(.serverUnreachable, previous: items))
+ XCTAssertEqual(rig.library.itemCallCount(), 2)
```

### `testT07_63_returningToDetailKeepsBannerWithContent`

`@MainActor func testT07_63_returningToDetailKeepsBannerWithContent() async throws`

```diff
+ XCTUnwrap(model.state.value)
+ assertReturningContent(model, onAppear: model.onAppear, rig: rig)
+ XCTAssertEqual(returnedCalls, loadedCalls)
+ assertReturningContent(model, onAppear: model.onAppear, rig: rig)
+ XCTAssertEqual(model.state, .failed(.serverUnreachable, previous: previous))
+ XCTAssertEqual(failedCalls, loadedCalls + 1)
```

### `testT02_35b_returningToEmptyHomeShowsFullScreen`

`@MainActor func testT02_35b_returningToEmptyHomeShowsFullScreen() async throws`

```diff
+ XCTAssertFalse(rig.app.showsServerDown)
+ assertEmptyScreen(model, app: rig.app)
```

### `testT07_64_returningToEmptyLibraryShowsFullScreen`

`@MainActor func testT07_64_returningToEmptyLibraryShowsFullScreen() async throws`

```diff
+ XCTAssertFalse(rig.app.showsServerDown)
+ assertEmptyScreen(model, app: rig.app)
```

### `testT07_64_returningToEmptyDetailShowsFullScreen`

`@MainActor func testT07_64_returningToEmptyDetailShowsFullScreen() async throws`

```diff
+ XCTAssertFalse(rig.app.showsServerDown)
+ assertEmptyScreen(model, app: rig.app)
+ XCTAssertEqual(model.state, .failed(.serverUnreachable, previous: nil))
```

### `testT07_63_returningToSeriesKeepsBannerWithContent`

`@MainActor func testT07_63_returningToSeriesKeepsBannerWithContent() async throws`

```diff
+ assertReturningContent(model, onAppear: model.onAppear, rig: rig)
+ assertReturningContent(model, onAppear: model.onAppear, rig: rig)
+ XCTAssertEqual(model.seasons.value, rig.library.seasons)
+ XCTAssertEqual(model.episodes.value, rig.library.episodes)
```

### `testT07_64_returningToEmptySeriesShowsFullScreen`

`@MainActor func testT07_64_returningToEmptySeriesShowsFullScreen() async throws`

```diff
+ XCTAssertFalse(rig.app.showsServerDown)
+ assertEmptyScreen(model, app: rig.app)
```

### `testT07_63_seriesSectionDoesNotReplaceDetailContentProvider`

`@MainActor func testT07_63_seriesSectionDoesNotReplaceDetailContentProvider() async throws`

```diff
+ XCTAssertFalse(section.hasContent)
+ XCTAssertEqual(rig.app.connectivity, .serverUnreachable)
+ XCTAssertTrue(rig.app.currentView === model)
+ XCTAssertTrue(model.hasContent)
+ XCTAssertFalse(rig.app.showsServerDown)
+ XCTAssertEqual(rig.app.bannerKey, AppErrorMessage.serverDownKey)
```

### `assertReturningContent`

`@MainActor private func assertReturningContent(`

```diff
+ assertReturningContent( _ model: any ViewContentProviding, onAppear: () -> Void, rig: Harness, file: StaticString = #filePath, line: UInt = #line )
+ XCTAssertTrue(rig.app.currentView === model, file: file, line: line)
+ XCTAssertTrue(rig.app.currentView === other, file: file, line: line)
+ XCTAssertTrue(rig.app.showsServerDown, file: file, line: line)
+ XCTAssertTrue(rig.app.currentView === model, file: file, line: line)
+ XCTAssertTrue(model.hasContent, file: file, line: line)
+ XCTAssertEqual(rig.app.connectivity, .serverUnreachable, file: file, line: line)
+ XCTAssertEqual(rig.app.bannerKey, AppErrorMessage.serverDownKey, file: file, line: line)
+ XCTAssertEqual( rig.app.banner, AppErrorMessage.localized(AppErrorMessage.serverDownKey), file: file, line: line)
+ XCTAssertFalse(rig.app.showsServerDown, file: file, line: line)
```

### `assertEmptyScreen`

`@MainActor private func assertEmptyScreen(`

```diff
+ assertEmptyScreen( _ model: any ViewContentProviding, app: AppState, file: StaticString = #filePath, line: UInt = #line )
+ XCTAssertTrue(app.currentView === model, file: file, line: line)
+ XCTAssertFalse(model.hasContent, file: file, line: line)
+ XCTAssertEqual(app.connectivity, .serverUnreachable, file: file, line: line)
+ XCTAssertTrue(app.showsServerDown, file: file, line: line)
+ XCTAssertEqual(app.serverDownTitleKey, AppErrorMessage.serverDownKey, file: file, line: line)
+ XCTAssertEqual(app.retryTitleKey, AppErrorMessage.retryKey, file: file, line: line)
+ XCTAssertEqual(app.changeServerTitleKey, AppErrorMessage.changeServerKey, file: file, line: line)
```

## `Packages/GlassfinCore/Tests/CoreStateTests/T07SecurityStateTests.swift`

### `testT07_67_401CancelsAllRequestsEndsSessionOnceAndNeverRetries`

`@MainActor func testT07_67_401CancelsAllRequestsEndsSessionOnceAndNeverRetries() async throws`

```diff
- XCTAssertEqual(rig.app.sessionNoticeKey, .sessionExpired)
+ XCTAssertEqual(rig.app.sessionNoticeKey, AppErrorMessage.sessionExpiredKey)
```

### `testT07_68_non401ErrorsKeepSessionAndCancellationIsNotPresented`

`@MainActor func testT07_68_non401ErrorsKeepSessionAndCancellationIsNotPresented() async throws`

```diff
- XCTAssertNil(AppErrorMessage.key(for: .cancelled))
+ XCTAssertNil(AppErrorMessage.messageKey(for: .cancelled))
```

## Catalog helper adjustment

`catalogEnglishValues` retains its exact orphan-key and translated en/fi checks.
Its expected CoreModels key set now unions the following seven keys; the
`testModelsCatalogKeysAndLocalizedAccessor` equality uses the same union:

- `Playback is unavailable because the server cannot be reached`
- `Playback is unavailable without a network connection`
- `Server version %@ is too old (required ≥ %@)`
- `Switch server`
- `The server certificate is not trusted`
- `This file could not be played`
- `You do not have permission for this action`

`testNetworkingCatalogKeysAndLocalizedAccessors` also uses that helper. Each
retained key is checked for a nonempty translated string unit in both languages;
other unexpected keys still fail the orphan-key assertion.

## Bootstrap tests

All ten `BootstrapTests` methods from v2 are imported unchanged, including their
assertions and signatures. They passed locally. `add_library` keeps v2-compatible
defaults while production setup passes the M07 movie and series paths explicitly.

## Final validation

The coverage gate executed 400 tests with zero failures and five live Docker
skips; 395 passed. Line coverage is 91.71% (7,581/8,266), above the 80% gate.
Strict recursive swift-format, design-system lint, String Catalog validation,
DEBUG-string validation and CI grep all passed. The ten inherited bootstrap
unit tests passed. Apple UI and snapshot tests were not executed on Linux.

## T07-81: distinguish received bytes from fixture-sent bytes

Applies to `T07ImageTests.testT07_81_lyingContentLengthStreamIsCancelledAtTheCap`
and `testT07_81_missingContentLengthStreamIsCancelledAtTheCap`, through their
shared `assertStreamIsCancelled` helper. Test IDs and signatures are unchanged.

Slow CI observed 21,299,200 fixture-sent bytes against the old 21,233,664-byte
bound (20 MiB + four 64 KiB chunks). Cancellation can reach the fixture one
chunk later even though the downloader has already rejected the response.
Producer progress therefore cannot establish the receive-side memory limit.

```diff
- XCTAssertGreaterThan(count, MetadataPolicy.imageMaxBytes)
- XCTAssertLessThanOrEqual(count, MetadataPolicy.imageMaxBytes + 4 * ImageStreamProtocol.chunkSize)
+ XCTAssertGreaterThan(received, MetadataPolicy.imageMaxBytes)
+ XCTAssertLessThanOrEqual(received, MetadataPolicy.imageMaxBytes + ImageStreamProtocol.chunkSize)
+ XCTAssertGreaterThan(sent, MetadataPolicy.imageMaxBytes)
+ XCTAssertLessThanOrEqual(sent, MetadataPolicy.imageMaxBytes + 1024 * 1024)
```

`received` now comes from a lock-protected internal downloader counter. It counts
the delegate chunks processed before stopping, including the rejecting chunk,
and excludes callbacks discarded after cancellation. The counter survives buffer
cleanup so the test can inspect it after the download fails. A test hook is needed
because the downloader is final, creates its own URLSession delegate, and clears
its private buffer on completion; fixture-side instrumentation only measures
sent bytes. The counter observes receipt without changing the production byte
limit, buffering, or cancellation behavior.

The new strict receive bound is 21,037,056 bytes (20 MiB + one 64 KiB chunk).
Only the send bound is relaxed, to 22,020,096 bytes (20 MiB + 1 MiB), still well
before the fixture's extra 8 MiB. The decoding-error, cancellation expectation,
and unfinished-fixture assertions remain unchanged. This separates the security
property from producer cancellation latency.

Linux validation passed: `swift build --build-system native`, all seven
`T07ImageTests`, the coverage gate (493 tests, seven live-server skips, zero
failures; 91.73% line coverage), strict recursive swift-format, and source checks.
A temporary receive-cap mutation failed both strict receive assertions as
expected; a temporary five-chunk queued-send simulation passed both tests.
Neither temporary change is retained. This branch has no
`scripts/check-unit-test-targets.py`; the existing checker from the adjacent
`wt-ut-guard` worktree passed its self-test against this branch's `project.yml`.
Apple simulator tests were not run on Linux.

## Main #28 (M10 Settings) merge — 2026-10-28

Pre-merge M07 head: `3ac7b1a`. Incoming `origin/main`: `eaf26b5`
(`M10 Settings (PoC) — stacked on #14 + #13 (#28)`). This update uses
`git fetch origin` and a merge commit; no rebase or force-push.

The five conflicts combine M07's library session, library/overflow destinations,
feature client, and optional hero content with M10's Settings app state, shared
tab selection, sign-out confirmation and `isSigningOut` guard, and focus
restoration. `SettingsView.swift` and `SettingsViewModel.swift` remain identical
to main. Both catalogs contain the exact union of the parents' keys, with every
parent's English and Finnish localization preserved (89 app keys, 57 model keys).

### Exact test-file changes relative to the pre-merge M07 head

No test edits, assertion changes, or signature fixes were authored during this
merge. The complete test-file delta consists of these four files inherited
byte-for-byte from `origin/main`:

| File | Change and rationale |
| --- | --- |
| `Apps/Shared/Tests/Logic/T10SettingsLogicTests.swift` | Added unchanged from #28; preserves bundle-version and English/Finnish Settings catalog coverage. |
| `Apps/Shared/UITests/T04AuthUITests.swift` | Updated unchanged from #28; inherits its `notify` import and cancellation flow. Main removes the old Home assertion and Settings re-entry because cancelling sign-out now returns directly to Settings; the subsequent sign-out-row assertion is preserved. No assertion was edited to make this merge pass. |
| `Apps/Shared/UITests/T10SettingsUITests.swift` | Added unchanged from #28; preserves Settings contents, cancel/Menu focus restoration, and sign-out/sign-in coverage. |
| `Packages/GlassfinCore/Tests/CoreStateTests/T10SettingsTests.swift` | Added unchanged from #28; preserves offline content, credential handling, sign-out re-entry guard, failure, and fresh-launch coverage. |

Every other existing test file remains identical to the pre-merge M07 head.

### Download security

`HTTPClient` and `BoundedResponseDownload` retain their cache disabling and
certificate-pin forwarding. `BoundedImageDownload` now also sets
`configuration.urlCache = nil` itself before creating its session, so it does
not depend on the caller's configuration. Both bounded downloaders retain
their per-chunk checks before appending bytes and their pinned trust delegates.

### Validation

On Linux with Swift 6.4.1, `bash scripts/coverage-gate.sh` runs
`swift test --enable-code-coverage --build-system native`: 567 tests,
559 passed, eight existing live-server integration skips, zero failures.
Line coverage is 91.15% (9,130 / 10,016), above the 80% gate.

SwiftLint 0.65.1, strict recursive swift-format lint, CI source greps,
design-system, image-pipeline, string-catalog, entitlements, DEBUG-string,
unit-test-target, license, and artifact-redaction checks pass, including their
available self-tests. SwiftLint reports the expected Linux SourceKit custom-rule
skip; the repository's source-check scripts pass. All 33 bootstrap/HLS Python
unit tests and 22 Docker harness self-test cases pass; both integration shell
scripts pass syntax checks. `git diff --check` passes.

Apple simulator UI, logic, and snapshot tests were not executed on Linux.

## Main #43 merge and complete test inventory — 2026-10-28

Pre-merge M07 head: `5d12fd15b1a5bb2b8ed79b9fbcf89c11b0446e6b`.
Incoming `origin/main`: `4f81fedff7271eca4897404951678dd704e4026f`
(`test: forgetting a server clears a corrupted pin (#43)`). This update uses
`git fetch origin` and a merge commit, without rebasing or force-pushing.

Changes are additive only: both parents' tests and every existing assertion
are retained. No assertion is weakened, deleted, or changed. No new feature or
test is authored for this merge; the inventory below includes tests already
present on M07 and tests imported from main. Existing fixture and lifecycle
setup differences relative to main are identified explicitly.

### This merge's conflict resolution and imported tests

The only conflicted file is
`Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift`, in
`testColdStartWithoutSnapshotEndsAfterTheFetch`. The resolution keeps M07's
`XCTAssertEqual(ended(harness.signposter.snapshot(), .coldStartHomeFirstRow), 1)`
and both signpost waits, including main's wait for `.homeSectionsLoaded` before
checking Latest. M07's shared Resume/Latest gate and wait for two blocked
requests remain intact. The resolved file is byte-for-byte identical to the
pre-merge M07 head: no test body or assertion changes are needed beyond removing
the conflict markers.

`Packages/GlassfinCore/Tests/CoreStateTests/PinForgetRecoveryTests.swift` is
imported byte-for-byte from main: four existing tests cover malformed and
undecodable pins through both server-removal paths, including credential
cleanup, explicit trust, and fresh sign-in. It is the only test file with a net
change relative to the pre-merge M07 head (191 added lines). It has no diff
relative to main and is therefore listed separately from the branch inventory.

### Every test file changed relative to main `4f81fed`

The following 13 files are the complete diff under `Tests/` and `UITests/`.
All changes in this table predate this merge; existing main assertions remain
intact. Added files refer to existing M07 coverage, not tests authored now.

| File | Existing M07 change retained relative to main |
| --- | --- |
| `Apps/Shared/Tests/Logic/T07ArtworkTests.swift` | Added artwork downsampling test (one method). |
| `Apps/Shared/UITests/T07LibraryUITests.swift` | Added library/detail navigation, season/episode focus, actions, sanitization, and back-navigation coverage (13 methods; platform conditions remain unchanged). |
| `Packages/GlassfinCore/Tests/CoreModelsTests/T07MetadataTests.swift` | Added literal metadata, control/bidi removal, grapheme limits, mapping, and technical metadata coverage (eight methods). |
| `Packages/GlassfinCore/Tests/CoreNetworkingTests/T07ImageTests.swift` | Added image URL/cache-key, thumbnail, and bounded-download coverage (seven methods), preserving the existing receive-side and producer-side byte assertions. |
| `Packages/GlassfinCore/Tests/CoreStateTests/PinFailureTests.swift` | Preserves the merged M07 and M09 pin tests: main's nine tests, including Search factory pin-read failure and missing-pin coverage, plus M07's existing `testFeatureClientPropagatesPinReadFailure` and its `.tls` and retained-session assertions. No merge-time edit. |
| `Packages/GlassfinCore/Tests/CoreStateTests/Support.swift` | Preserves `StubLibrary.latestGate` and its extra asynchronous wait in `latest(in:limit:)`, sharing the result/gate snapshot under the lock. Also retains the `nextUp(series:)` fixture adapter. No assertions or timeouts change. |
| `Packages/GlassfinCore/Tests/CoreStateTests/T02BehaviorTests.swift` | Preserves the extra Latest gate setup and wait for two blocked requests, both completion waits, and one additional cold-start signpost assertion. Retains `home.onAppear()` in place of direct current-view assignment and `series.onAppear()` before standalone loading. The sole conflict is resolved as described above; all assertions from both parents survive unchanged. |
| `Packages/GlassfinCore/Tests/CoreStateTests/T02FoundationTests.swift` | Preserves the additional `testT07_77_cachedAndProjectedMetadataKeepsDisplayLimits` for cached/projected metadata. Existing methods and assertions are unchanged. |
| `Packages/GlassfinCore/Tests/CoreStateTests/T04AuthTests.swift` | Preserves two additional Auth Home lifecycle methods and the populated Resume fixture in `testT04_59_launchFailureLoadsCachedHomeAndKeepsToken`; every original assertion is unchanged. |
| `Packages/GlassfinCore/Tests/CoreStateTests/T07DetailTests.swift` | Added detail, season/episode, focus, optimistic-action, stale-response, and outage coverage (21 methods). |
| `Packages/GlassfinCore/Tests/CoreStateTests/T07LibraryTests.swift` | Added grid paging, caching, query persistence, sanitization, navigation, and outage/recovery coverage (11 methods). |
| `Packages/GlassfinCore/Tests/CoreStateTests/T07ScreenLifecycleTests.swift` | Added screen registration and retained/empty-content lifecycle coverage (ten methods). |
| `Packages/GlassfinCore/Tests/CoreStateTests/T07SecurityStateTests.swift` | Added session cancellation, non-401 error handling, request cancellation, and image-cache limit coverage (four methods). |

The additional test-support source
`Packages/GlassfinCore/Sources/CoreTestSupport/LibraryFixtures.swift` is also
retained as an added M07 file relative to main. It provides deterministic movie,
series, season, episode, and malformed-record fixtures and contains no test
methods. No other test or test-support file differs from main.

### Linux validation

With Swift 6.4.1 and the existing Swift compatibility-library environment,
`swift test --package-path Packages/GlassfinCore --build-system native` passes:
648 tests executed, 638 passed, ten existing integration skips, zero failures.
The four imported `PinForgetRecoveryTests`, all ten `PinFailureTests`, and all
34 `T02BehaviorTests` pass. Strict swift-format lint passes for the conflicted
and imported test files, and `git diff --check` passes.

The inventory is checked against the complete test/test-support path diff from
main. Main's existing assertion lines are retained, the resolved T02 file
matches the M07 parent, and the imported pin-recovery file matches main.
Apple simulator verification is delegated to PR #23's CI checks after pushing.

### Main advanced during CI: #44 reconciliation

Merge `45de3ec` passed every check in CI run `40747825750`: lint, iOS, tvOS,
full UI, and the macOS gate. Linux ran 648 tests (638 passed, ten integration
skips); iOS recorded 716 passed and ten skips; each tvOS job recorded 750
passed and ten skips. No infrastructure rerun was needed.

While that run was in progress, main advanced to
`085582bdcc5154753beeb48cf1d2d4d122dcc365` (#44, M08a playback tracks), making
PR #23 conflict again. A second merge includes that current main tip. Its only
conflict is `Packages/GlassfinCore/Sources/CoreModels/DTOs.swift`: retain M07's
person/studio and technical metadata fields alongside main's playback-user
configuration and track fields, with one shared `Channels` declaration.
No test file conflicts in this second merge.

The complete 13-file test inventory and additional `LibraryFixtures.swift`
test-support entry above also apply unchanged relative to current main
`085582b`. Changes remain additive only: both parents' existing tests and
assertions are preserved; no new feature or test is authored for either merge.

The only test-file changes relative to `45de3ec` are these imports, all
byte-for-byte identical to current main:

| File | Existing upstream change imported unchanged |
| --- | --- |
| `Packages/GlassfinCore/Tests/CorePlaybackTests/DefaultAudioSelectionTests.swift` | Five existing default-audio selection regressions. |
| `Packages/GlassfinCore/Tests/CorePlaybackTests/FullPlaybackTests.swift` | 29 existing runtime-profile, playback negotiation, track, subtitle, and fallback tests. |
| `Packages/GlassfinCore/Tests/CorePlaybackTests/PlaybackCoordinatorTests.swift` | Existing rig explicitly selects `configuration: .poc`; all 50 test methods and every assertion remain unchanged. This is an upstream setup change, not a local assertion edit. |

After this reconciliation, the same Linux `swift test` command passes:
682 executed, 672 passed, ten existing integration skips, zero failures.
The current-main test inventory and unchanged upstream assertion lines are
verified again. Strict swift-format for the resolved DTO file, both String
Catalog checks, and `git diff --check` pass. Final Apple verification runs on
the new merge head in PR #23 CI.
