# M06 implementation test map

The original Testaaja plan was unavailable. These IDs are derived from `06-home.md` in spec order, Q4-10, and the binding spec PR #18 security updates. They are local M06 implementation IDs, not a claim to reconstruct the lost numbering.

All tests use mock metadata and credentials. UI tests find accessibility identifiers; copy assertions compare catalog keys. Metadata tests compare literal payloads where the requirement is preservation or truncation.

| ID | Requirement | Test / status |
|---|---|---|
| T06-01 | Resume, Next Up, separate Latest per video library, endpoint parameters, library order/tabs | `T06HomeTests.testT06_01_videoLibrariesKeepServerOrderAndSeparateLatestRows`; `T06HomeServiceTests.testT06_01_homeEndpointParametersMatchSpec`; `T06HomeUITests.testT06_01_allRowsAndLibraryTabsExist`; `LiveServerTests.testT06_01_homeEndpointsAndResetPosition` (Docker) |
| T06-02 | Parallel loading; a slow row does not block others | `T06HomeTests.testT06_02_slowResumeDoesNotBlockOtherRows` |
| T06-03 | Empty rows hidden; all-empty guidance | `T06HomeTests.testT06_03_emptyAndUnknownLibraries`, `testT06_03_decodeFailureFinishesWithoutAnEndlessSkeleton`; `T06HomeUITests.testT06_03_emptyLibraryHasGuidanceAndRetry` |
| T06-04 | Row 500 preserves other rows; row-specific retry | `T06HomeTests.testT06_04_sectionFailureAndTargetedRetryLeaveOtherRowsVisible`, `testT06_04_latestFailureIsIsolatedToItsLibrary`; `T06HomeUITests.testT06_04_partialErrorKeepsOtherRowsAndHasSectionRetry` |
| T06-05 | Playback stop removes played episode and refreshes personal rows within 2 s | `T06HomeTests.testT06_05_playbackStopProjectsImmediatelyAndRefetchesPersonalRows`; `testT06_05_playedItemStaysRemovedDuringAStaleServerResponse`. Actual playback/end-to-end timing blocked on M08 integration; UserDataStore playback notification hook is implemented. |
| T06-06 | WebSocket UserDataChanged projects all cards; real-client latency ≤5 s | `T06HomeTests.testT06_06_remoteUserDataProjectsOnAllRows`. Real server two-client timing is blocked on Docker/Apple socket execution in this workspace (Q6-04). |
| T06-07 | Foreground refresh only after >60 s, keeping content | `T06HomeTests.testT06_07_foregroundRefreshOnlyAfterSixtySeconds` |
| T06-08 | LibraryChanged refreshes Latest after 2 s debounce | `T06HomeTests.testT06_08_libraryChangeIsDebouncedAndRefetchesLatestOnly` |
| T06-09 | Default focus, stable item/neighbor, back restoration, background refresh | `T06HomeTests.testT06_09_focusRemainsOnSameItemOrSameRowNeighbor`; `T06HomeUITests.testT06_09_resumeFirstCardHasDefaultFocusAndDetailBackRestoresIt`, `testT06_09_nextUpGetsDefaultFocusWhenResumeIsEmpty`, `testT06_09_backgroundRefreshKeepsTheFocusedItem` |
| T06-10 | Play/Pause uses the focused item's resume position | `T06HomeTests.testT06_10_playRequestUsesSafeResumePosition`; `T06HomeUITests.testT06_10_playPauseUsesFocusedResumePosition`. Player request routing covered; actual video starts after M08. |
| T06-11 | Disappearance cancels work; late responses cannot publish | `T06HomeTests.testT06_11_cancelledLoadCannotPublishLateResults`, `testT06_11_disappearanceAlsoCancelsSectionRetry` |
| T06-12 | Cached grouped Home survives a relaunch; account isolation | `T06HomeTests.testT06_12_snapshotPreservesLibraryGroupingAndRejectsOtherUser`; existing M02 snapshot round-trip tests remain green |
| T06-13 | Server failure keeps content + banner, session remains signed in | `T06HomeTests.testT06_13_serverDownRetainsVisibleContentAndBanner`; `T06HomeUITests.testT06_13_cachedServerDownKeepsCardsAndNonFocusableBanner` |
| T06-14 | No content → existing server-down key, retry; shell/Settings usable | `T06HomeTests.testT06_14_noContentUsesExistingServerDownTitleKey`; `T06HomeUITests.testT06_14_serverDownStillAllowsSettingsAndSignOut` |
| T06-15 | Existing 10 s ping recovers without discarding content | `T06HomeTests.testT06_15_pingRecoversAndKeepsCachedContent`, `testT06_15_automaticPingRunsAtTenSecondsAndRecovers`; existing `T02BehaviorTests.testT02_26_serverRestartDoesNotLogOutAndInvalidatesCaches` and M02 ping tests |
| T06-16 | Any API/image 401 cancels siblings, signs in once, no retry | `T06HomeTests.testT06_16_latest401EndsSessionOnceEvenWhenOtherRowsSucceed`; `T06SessionTests.testT06_16_image401CancelsOtherRequestsAndDoesNotRetry`; `T06SocketTests.testT06_16_socket401StopsWithoutReconnect`; existing `T02BehaviorTests.testT02_07_authenticated401LogsOutOnce` |
| T06-17 | Played/favorite/reset actions, optimistic rollback, context menu | `T06HomeTests.testT06_17_actionsCommitAndFailedEditsRestoreTheRow`; `T06HomeUITests.testT06_17_longPressShowsContextActions`; `LiveServerTests.testT06_01_homeEndpointsAndResetPosition` also tagged T06-17 |
| T06-18 | Menu chain and tab reachability | Back/Settings portions covered by T06-09/T06-14 UI tests. Manual: full library → detail → root → tab → exit chain requires M07. |
| T06-19 | 1080p/4K default and Reduce Transparency; screenshot artifacts | `T06HomeSnapshotTests.testT06_19_homeDefaultAndOpaqueBannerAt1080And4K`; `T06HomeUITests.testT06_19_accessibilityScreenshots`. Snapshot content/banner at both scales; XCUITest captures real tab chrome. Execution blocked on Xcode and the separate M05 compile fixes. |
| T06-20 | Image URLs contain no credential query; Authorization header present | `T06ImageTests.testT06_20_imageURLHasNoCredentialQueryAndRequestHasAuthorization`; `testT06_20_inheritedCredentialQueriesAreRejected` |
| T06-21 | Stable SHA-256 tuple key; only hashed disk filename | `T06ImageTests.testT06_21_imageCacheKeyIsStableSHA256OfIdentityTuple`; `T06ImageStoreTests.testT06_21_diskFilenameIsTheStableSHA256AndBytesRoundTrip` |
| T06-22 | >20 MB rejected before decode/cache; downsample to display pixels on worker | `T06ImageTests.testT06_22_imageByteLimitRejectsOversize`; `T06ImageStoreTests.testT06_22_loaderAndDiskRejectOversizedImageWithoutCaching`; `T06ImageDecodeTests.testT06_22_decoderDownsamplesToDisplayedPixelSize` (Apple-only). Worker execution is explicit `Task.detached`; device profiling remains manual. |
| T06-23 | Control/bidi stripping, literal tags/entities through view models/cache | `T06MetadataTests.testT06_23_metadataPreservesLiteralMarkupAndEntities`; `T06HomeTests.testT06_23_metadataIsCleanedThroughLiveAndCachedViewModels`; existing security/name tests updated to PR #18 |
| T06-24 | Grapheme boundaries, shared limits for all metadata categories | `T06MetadataTests.testT06_24_limitsCountCleanedGraphemeClusters`; existing `SecurityNameTests` cover the 64-grapheme server/user limit. Tagline/genre field presentation belongs to M07. |
| T06-25 | Row caps and duplicate-ID handling; lazy cells | `T06HomeTests.testT06_25_rowsAreBoundedAndDuplicateIDsAreRemoved`; source review: LazyVStack + LazyHStack and fixed API row cap |
| T06-26 | 250 ms focus debounce, 300 ms fade, Reduce Motion immediate | `T06HomeTests.testT06_26_backdropDebouncePublishesOnlyTheLastFocusAndCancels`; manual visual transition/Reduce Motion on Apple TV |
| T06-27 | P1/P2/P3 and G-4 performance | Manual/blocked: Instruments on A12/A15/A8 and LAN timing. Existing cold-start/row signposts are retained, with cold-start ending on first content. No hardware claim from Linux. |
| T06-28 | tvOS/iOS build, localization, design rules, DEBUG-only mocks | Linux build/test and all source scripts pass. Apple app builds blocked here by environment and the known M05 compile errors, intentionally not repaired in M06. `project.yml` already recursively includes the new UITests and tvOS snapshot source directories. |
| T06-29 | Later scope is disabled TODO stubs | Source review: `HomeFutureFeatures`, `HomeRootView`; P1 favorites/combined rows/custom order/iOS layout and P2 DisplayPreferences remain disabled. |

## Commands and execution

Linux logic and source checks:

```sh
export LD_LIBRARY_PATH=~/.local/lib/swiftcompat
source ~/.local/share/swiftly/env.sh
cd Packages/GlassfinCore
swift build
swift test
swift-format lint --recursive --strict Package.swift Sources Tests ../../Apps
cd ../..
python3 scripts/check-design-system.py
python3 scripts/check-string-catalogs.py
bash scripts/ci-grep.sh
python3 scripts/check-debug-only-strings.py
```

On a Mac, after integrating the separate M05 compile fixes: `bash scripts/macos-ci.sh tvOS` and `bash scripts/macos-ci.sh iOS`. The existing XcodeGen source directories automatically include `T06HomeUITests.swift` in both UI test targets and `T06HomeSnapshotTests.swift` in the tvOS snapshot target. No CI, signing, bundle-ID, entitlement, or Info.plist changes are required.

DEBUG direct launch: `-uitest-mock-server -uitest-reset -uitest-home`. Optional scenarios: `-uitest-home-empty`, `-uitest-home-partial`, `-uitest-home-next-only`, `-uitest-home-down`, `-uitest-home-cached-down`, `-uitest-home-refresh`, `-uitest-home-reduce-transparency`, `-uitest-home-reduce-motion`. These switches are stripped from Release builds.

Disposable live matrix: `bash scripts/docker-integration.sh` (requires Docker + ffmpeg; covers the existing live suite plus the T06 Home endpoint/reset test). Never use a personal server for these tests.

## Local verification result (2026-10-27)

- Swift 6.4.1 on Linux: `swift build` passed; `swift test` passed **263 tests**, with **3 live integration tests skipped** and zero failures. This includes **36 passing M06 logic/security tests**.
- CI's native-driver `scripts/coverage-gate.sh` passed: **90.44%** line coverage (5,838/6,455; minimum 80%).
- Exact required recursive strict swift-format command passed with zero findings.
- Design-system, string-catalog, source-grep, DEBUG-only-string (including self-test), license, and entitlement scripts passed. `git diff --check` passed.
- Apple-only downsampling, XCUITests, snapshot rendering, real Jellyfin/Docker execution, and hardware performance were not executed here. Xcode and Docker are absent. This is recorded as pending evidence, not a successful platform build or visual review.
