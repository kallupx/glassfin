# M06 canonical test coverage

The only test plan is [spec/TESTPLAN-M06.md](../spec/TESTPLAN-M06.md), copied verbatim from the binding Testaaja plan. IDs below use its numbering. A supplied Apple test is not evidence of an executed Apple build. Tests assert catalog keys or accessibility identifiers; metadata assertions compare literal payloads.

## Automated tests and checks

| Canonical ID | Test source |
|---|---|
| T06-01 | `T06HomeUITests.testT06_01_resumeFirstCardHasDefaultFocusAndDetailBackRestoresIt` |
| T06-02 | `T06HomeUITests.testT06_02_nextUpGetsDefaultFocusWhenResumeIsEmpty` |
| T06-04 | `T06HomeTests.testT06_04_emptyAndUnknownLibraries`; `T06HomeUITests.testT06_04_emptyLibraryHasGuidanceAndRetry` |
| T06-06 | `T06HomeServiceTests.testT06_06_homeEndpointParametersMatchSpec` |
| T06-07 | `T06HomeServiceTests.testT06_06_homeEndpointParametersMatchSpec` |
| T06-08 | `T06HomeTests.testT06_08_videoLibrariesKeepServerOrderAndSeparateLatestRows` |
| T06-09 | `T06HomeUITests.testT06_09_allRowsAndLibraryTabsExist` |
| T06-12 | `T06HomeTests.testT06_12_slowResumeDoesNotBlockOtherRows` |
| T06-13 | `T06HomeTests.testT06_13_latestFailureIsIsolatedToItsLibrary`; `T06HomeUITests.testT06_13_partialErrorKeepsOtherRowsAndHasSectionRetry` |
| T06-14 | `T06HomeTests.testT06_14_sectionFailureAndTargetedRetryLeaveOtherRowsVisible` |
| T06-16 | `T06HomeTests.testT06_16_rowsAreBoundedAndDuplicateIDsAreRemoved` |
| T06-19 | `T06HomeTests.testT06_19_decodeFailureFinishesWithoutAnEndlessSkeleton` |
| T06-24 | `T06HomeTests.testT06_24_backdropDebouncePublishesOnlyTheLastFocusAndCancels` |
| T06-31 | `T06HomeUITests.testT06_01_resumeFirstCardHasDefaultFocusAndDetailBackRestoresIt` |
| T06-32 | `T06HomeTests.testT06_32_playRequestUsesSafeResumePosition`; `T06HomeUITests.testT06_32_playPauseUsesFocusedResumePosition` |
| T06-34 | `T06HomeUITests.testT06_34_longPressShowsContextActions` |
| T06-37 | `DockerIntegrationTests.testT06_37_homeEndpointsAndResetPosition` |
| T06-41 | `T06HomeTests.testT06_41_actionsCommitAndFailedEditsRestoreTheRow` |
| T06-44 | `T06HomeTests.testT06_44_snapshotPreservesLibraryGroupingAndRejectsOtherUser` |
| T06-46 | `T06HomeTests.testT06_46_noContentUsesExistingServerDownTitleKey`; `T06HomeUITests.testT06_46_serverDownStillAllowsSettingsAndSignOut` |
| T06-48 | `T06HomeTests.testT06_48_pingRecoversAndKeepsCachedContent`; `T06HomeTests.testT06_48_automaticPingRunsAtTenSecondsAndRecovers` |
| T06-49 | `T06HomeTests.testT06_49_serverDownRetainsVisibleContentAndBanner` |
| T06-51 | `T06SessionTests.testT06_51_image401CancelsOtherRequestsAndDoesNotRetry`; `T06HomeTests.testT06_51_latest401EndsSessionOnceEvenWhenOtherRowsSucceed`; `T06SocketTests.testT06_51_socket401StopsWithoutReconnect` |
| T06-56 | `T06HomeUITests.testT06_56_cachedServerDownKeepsCardsAndNonFocusableBanner` |
| T06-57 | `T06HomeTests.testT06_57_playbackStopProjectsImmediatelyAndRefetchesPersonalRows`; `T06HomeTests.testT06_57_playedItemStaysRemovedDuringAStaleServerResponse` |
| T06-60 | `T06HomeTests.testT06_60_remoteUserDataProjectsOnAllRows` |
| T06-61 | `T06HomeTests.testT06_61_libraryChangeIsDebouncedAndRefetchesLatestOnly` |
| T06-62 | `T06HomeTests.testT06_62_foregroundRefreshOnlyAfterSixtySeconds` |
| T06-64 | `T06HomeUITests.testT06_64_backgroundRefreshKeepsTheFocusedItem` |
| T06-65 | `T06HomeTests.testT06_65_focusRemainsOnSameItemOrSameRowNeighbor` |
| T06-66 | `T06HomeTests.testT06_66_cancelledLoadCannotPublishLateResults`; `T06HomeTests.testT06_66_disappearanceAlsoCancelsSectionRetry` |
| T06-70 | `T06HomeUITests.testT06_70_accessibilityScreenshots`; `T06HomeSnapshotTests.testT06_70_homeDefaultAndOpaqueBannerAt1080And4K` |
| T06-71 | `T06ImageTests.testT06_71_imageURLHasNoCredentialQueryAndRequestHasAuthorization`; `T06ImageTests.testT06_71_inheritedCredentialQueriesAreRejected` |
| T06-72 | `T06ImageStoreTests.testT06_72_diskFilenameIsTheStableSHA256AndBytesRoundTrip`; `T06ImageTests.testT06_72_imageCacheKeyIsStableSHA256OfIdentityTuple` |
| T06-73 | `T06HomeTests.testT06_73_metadataIsCleanedThroughLiveAndCachedViewModels`; `T06MetadataTests.testT06_73_metadataPreservesLiteralMarkupAndEntities`; `T06MetadataTests.testT06_73_limitsCountCleanedGraphemeClusters` |
| T06-80 | `T06ImageDecodeTests.testT06_80_decoderDownsamplesToDisplayedPixelSize` |
| T06-82 | `T06ImageStoreTests.testT06_82_loaderAndDiskRejectOversizedImageWithoutCaching`; `T06ImageTests.testT06_82_imageByteLimitRejectsOversize` |

## Not automated

This table records absent automation and portions of scenarios that still need platform, integration, or manual evidence. The follow-up implementation updates these entries as checks are added.

| Canonical ID | Remaining evidence / reason |
|---|---|
| T06-03 | tvOS Latest-only default focus scenario has no dedicated UI fixture yet. |
| T06-05 | System Menu-to-tab-to-exit routing requires Apple TV / XCUITest evidence. |
| T06-09 | UI assertions exist; exact visual row ordering still needs Apple execution. |
| T06-10 | Separate-row owner decision needs an explicit episode fixture test. |
| T06-11 | Resume/Next Up overlap needs explicit de-duplication and a test. |
| T06-12 | Gate test proves independent publishing; the plan's 1 s per section / <1.5 s timing still needs measurement. |
| T06-14 | Targeted refetch covered in logic; section focus after retry needs tvOS UI execution. |
| T06-15 | Empty row visibility requires rendered snapshot review. |
| T06-17 | Catalog key checks run globally; dedicated Home row-title assertions remain to add. |
| T06-18 | Lossy item decoding has baseline M01 coverage; no dedicated M06 malformed-row fixture yet. |
| T06-20 | Progress fixtures and screenshot inspection require Apple snapshot rendering. |
| T06-21 | Episode card layout requires Apple snapshot rendering. |
| T06-22 | Grouped series response/card fixture is not automated yet. |
| T06-23 | 250 ms debounce is tested through T06-24; crossfade appearance needs device review. |
| T06-24 | State debounce covered; image-request count across ten focus changes needs a dedicated fixture. |
| T06-25 | Reduce Motion duration asserted in T06-24; visual transition requires Apple execution. |
| T06-26 | Missing-backdrop fallback requires a snapshot fixture and visual review. |
| T06-27 | Design-system script enforces glass placement; final appearance requires snapshot review. |
| T06-28 | Readability on bright/dark/busy backdrops requires snapshot review. |
| T06-29 | Image URL dimensions covered by T06-71; all displayed geometries need Apple review. |
| T06-30 | Cross-row focus memory needs tvOS remote automation. |
| T06-31 | Detail destination is an M07 handoff stub; UI back restoration test supplied, execution requires Xcode. |
| T06-33 | Zero-position Play/Pause fixture not yet dedicated. |
| T06-35 | Mark-played success and <=2 s Next Up replacement need an explicit action test / M08 UI integration. |
| T06-36 | 500 rollback fixture not yet dedicated (403 rollback is T06-41). |
| T06-37 | Reset payload and disposable-server test supplied; staying absent from real Resume after refetch needs Docker matrix evidence. |
| T06-38 | M07 series destination and season picker are outside this branch; Home only passes a series handoff. |
| T06-39 | Favorite success covered in T06-41; DELETE and failure rollback need dedicated assertions. |
| T06-40 | Context dismissal focus needs tvOS remote automation. |
| T06-42 | Baseline M02 path/banner state coverage; Home offline playback blocking needs dedicated UI evidence. |
| T06-43 | Network return, refetch, and stable focus need a Home UI fixture. |
| T06-44 | Snapshot ownership tested; same-user immediate stale display and focus need explicit coverage. |
| T06-45 | Cache-purge cold-start fixture not yet dedicated. |
| T06-46 | Shared key and Settings escape tested; default retry focus and Change server need Apple UI execution. |
| T06-47 | Change server UI path requires XCUITest execution and token retention assertion. |
| T06-50 | Server-dependent action while unreachable needs a dedicated inline-error and focus fixture. |
| T06-51 | Logic/API/image/socket 401 tests supplied; real UI sign-in transition requires Apple execution. |
| T06-52 | Retry/status classification is covered by M02 baseline; no dedicated M06 HTTP retry fixture yet. |
| T06-53 | Network Link Conditioner requires Apple tooling / device. |
| T06-54 | M02 handles server lifecycle events; dedicated Home content/no-content cases remain to add. |
| T06-55 | Transport config uses 15 s; dedicated Home timeout fixture remains to add. |
| T06-56 | UI fixture supplied; cold cached launch logic and actual UI execution remain. |
| T06-58 | End-of-playback UI latency needs M08 integration and an Apple player. |
| T06-59 | Two-client WebSocket delivery <=5 s needs a disposable Docker server matrix. |
| T06-60 | Remote projection tested; event winning over a pending optimistic edit needs a dedicated race fixture. |
| T06-61 | Debounce covered with two events; five-event burst fixture remains to add. |
| T06-62 | Age threshold covered; old-content/focus assertion needs explicit fixture. |
| T06-63 | Threshold covered within T06-62; dedicated <60 s test remains to add. |
| T06-64 | UI test supplied; execution requires tvOS Xcode / simulator. |
| T06-65 | Neighbor policy unit tested; rendered focus change needs tvOS remote evidence. |
| T06-67 | Cold-start and row-loading budgets require A15/oldest hardware and LAN measurements. |
| T06-68 | 60 fps / hitches / glass G-4 require Instruments on supported Apple TVs. |
| T06-69 | Memory budget and warning behavior require Apple memory profiling. |
| T06-70 | Snapshot/UI sources supplied; PNG matrix and tab chrome review require Xcode. |
| T06-73 | Literal/grapheme policy and Home name/overview fixtures supplied; all field layouts require M07 snapshots. |
| T06-74 | Global ci-grep covers source logging; runtime diagnostic/artifact scan needs Apple CI artifacts. |
| T06-75 | Mock screenshots supplied; final artifact secret scan requires generated CI artifacts. |
| T06-76 | Streaming byte-count enforcement and missing-length transport fixture required by this follow-up. |
| T06-77 | Lying-length stream transport fixture required by this follow-up. |
| T06-78 | Early Content-Length rejection transport fixture required by this follow-up. |
| T06-79 | Compressed 30k image regression and P11 / +50 MB peak need ImageIO and hardware profiling. |
| T06-80 | Apple thumbnail test supplied; portable option-builder assertion required by this follow-up. |
| T06-81 | Dedicated forbidden-image-source check required by this follow-up. |
| T06-82 | Buffered oversize and no-cache tests supplied; rendered placeholder/focus requires Apple UI evidence. |

## Verification

Linux: export `LD_LIBRARY_PATH=~/.local/lib/swiftcompat`, source `~/.local/share/swiftly/env.sh`, then run the build, test, strict formatter and repository scripts specified in the task. Apple UI/snapshot tests require Xcode; live tests require disposable Jellyfin containers. Performance claims require supported Apple TV hardware.
