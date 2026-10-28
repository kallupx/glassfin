# M06 canonical test coverage

The only test plan is [spec/TESTPLAN-M06.md](../spec/TESTPLAN-M06.md), copied verbatim from the binding Testaaja plan. All test IDs below use its numbering. Partial automation is explicitly recorded below; supplied Apple tests are not evidence of executed Apple builds. Assertions use catalog keys or accessibility identifiers; metadata assertions compare literal payloads.

## Automated tests and checks

| Canonical ID | Test / check source |
|---|---|
| T06-01 | `T06HomeUITests.testT06_01_resumeFirstCardHasDefaultFocusAndDetailBackRestoresIt` |
| T06-02 | `T06HomeUITests.testT06_02_nextUpGetsDefaultFocusWhenResumeIsEmpty` |
| T06-04 | `T06HomeTests.testT06_04_emptyAndUnknownLibraries`; `T06HomeUITests.testT06_04_emptyLibraryHasGuidanceAndRetry` |
| T06-05 | U (tvOS): `T06HomeUITests.testT06_05_upAndMenuFromHomeContentReachTabBar` (system exit sub-step remains manual) |
| T06-06 | `T06HomeServiceTests.testT06_06_resumeEndpointParametersMatchSpec` |
| T06-07 | `T06HomeServiceTests.testT06_07_nextUpEndpointParametersMatchSpec` |
| T06-08 | `T06HomeServiceTests.testT06_08_latestEndpointParametersMatchSpec`; `T06HomeTests.testT06_08_videoLibrariesKeepServerOrderAndSeparateLatestRows` |
| T06-09 | `T06HomeUITests.testT06_09_allRowsAndLibraryTabsExist` |
| T06-10 | `T06HomeTests.testT06_10_continueWatchingAndNextUpAreSeparateEpisodeRows` |
| T06-12 | `T06HomeTests.testT06_12_slowResumeDoesNotBlockOtherRows` |
| T06-13 | `T06HomeTests.testT06_13_latestFailureIsIsolatedToItsLibrary`; `T06HomeUITests.testT06_13_partialErrorKeepsOtherRowsAndHasSectionRetry` |
| T06-14 | `T06HomeTests.testT06_14_sectionFailureAndTargetedRetryLeaveOtherRowsVisible` |
| T06-16 | `T06HomeTests.testT06_16_rowsAreBoundedAndDuplicateIDsAreRemoved` |
| T06-17 | `scripts/check-string-catalogs.py` (all Home keys have en/fi localizations) |
| T06-19 | `T06HomeTests.testT06_19_bodyDecodeFailureShowsSectionRetryAndKeepsOtherRows` |
| T06-23 | `T06HomeTests.testT06_24_backdropDebouncePublishesOnlyTheLastFocusAndCancels` (debounce constants; crossfade requires device review) |
| T06-24 | `T06HomeTests.testT06_24_backdropDebouncePublishesOnlyTheLastFocusAndCancels` |
| T06-25 | `T06HomeTests.testT06_24_backdropDebouncePublishesOnlyTheLastFocusAndCancels` (Reduce Motion duration) |
| T06-27 | `scripts/check-design-system.py` (glass placement) |
| T06-29 | `T06ImageTests.testT06_71_imageURLHasNoCredentialQueryAndRequestHasAuthorization` (dimension and auth assertions for all four image types) |
| T06-30 | U (tvOS): `T06HomeUITests.testT06_30_directionsAndCrossRowFocusMemoryReturnToFifthCard` |
| T06-31 | `T06HomeUITests.testT06_01_resumeFirstCardHasDefaultFocusAndDetailBackRestoresIt` |
| T06-32 | `T06HomeTests.testT06_32_playRequestUsesSafeResumePosition`; `T06HomeUITests.testT06_32_playPauseUsesFocusedResumePosition` |
| T06-33 | `T06HomeTests.testT06_33_playWithoutProgressStartsAtZero` |
| T06-34 | `T06HomeUITests.testT06_34_longPressShowsContextActions` |
| T06-37 | `LiveServerTests.testT06_37_homeEndpointsAndResetPosition` |
| T06-38 | `T06HomeTests.testT06_38_seriesHandoffPreservesSeasonAndIsHiddenForMovies` |
| T06-40 | U (tvOS): `T06HomeUITests.testT06_40_contextMenuDismissalRestoresSameCard` |
| T06-41 | `T06HomeTests.testT06_41_actionsCommitAndFailedEditsRestoreTheRow` |
| T06-42 | U (tvOS): `T06HomeUITests.testT06_42_networkDropShowsNonFocusableBannerAndKeepsCardsBrowsable` (also checks offline Play feedback) |
| T06-43 | U (tvOS): `T06HomeUITests.testT06_43_networkRecoveryRefreshesHomeWithoutMovingFocus` |
| T06-44 | `T06HomeTests.testT06_44_snapshotPreservesLibraryGroupingAndRejectsOtherUser` |
| T06-46 | `T06HomeTests.testT06_46_noContentUsesExistingServerDownTitleKey`; `ScreenReentryTests.testT06_46_homeReentryWithoutContentShowsFullScreen`; `T06HomeUITests.testT06_46_serverDownStillAllowsSettingsAndSignOut` |
| T06-48 | `T06HomeTests.testT06_48_pingRecoversAndKeepsCachedContent`; `T06HomeTests.testT06_48_automaticPingRunsAtTenSecondsAndRecovers` |
| T06-49 | `T06HomeTests.testT06_49_serverDownRetainsVisibleContentAndBanner`; `ScreenReentryTests.testT06_49_homeReentryKeepsContentAndShowsBanner` |
| T06-50 | `T06HomeTests.testT06_50_unreachableActionKeepsContentUntilPingRecovery` |
| T06-51 | `T06SocketTests.testT06_51_socket401StopsWithoutReconnect`; `T06HomeTests.testT06_51_latest401EndsSessionOnceEvenWhenOtherRowsSucceed`; `T06ImageStreamTests.testT06_51_image401TakesPrecedenceOverSizeHeader`; `T06SessionTests.testT06_51_image401CancelsOtherRequestsAndDoesNotRetry` |
| T06-56 | `T06HomeTests.testT06_56_cachedColdStartKeepsContentAndServerUnreachableBanner`; `T06HomeUITests.testT06_56_cachedServerDownKeepsCardsAndNonFocusableBanner` |
| T06-57 | `T06HomeTests.testT06_57_playbackStopProjectsImmediatelyAndRefetchesPersonalRows`; `T06HomeTests.testT06_57_playedItemStaysRemovedDuringAStaleServerResponse` |
| T06-60 | `T06HomeTests.testT06_60_remoteUserDataWinsOverPendingOptimisticChange` |
| T06-61 | `T06HomeTests.testT06_61_libraryChangeIsDebouncedAndRefetchesLatestOnly` |
| T06-62 | `T06HomeTests.testT06_62_foregroundRefreshOnlyAfterSixtySeconds` |
| T06-63 | `T06HomeTests.testT06_63_foregroundBeforeSixtySecondsDoesNotFetch` |
| T06-64 | `T06HomeUITests.testT06_64_backgroundRefreshKeepsTheFocusedItem` |
| T06-65 | `T06HomeTests.testT06_65_focusRemainsOnSameItemOrSameRowNeighbor` |
| T06-66 | `T06HomeTests.testT06_66_cancelledLoadCannotPublishLateResults`; `T06HomeTests.testT06_66_disappearanceAlsoCancelsSectionRetry` |
| T06-70 | `T06HomeUITests.testT06_70_accessibilityScreenshots`; `T06HomeSnapshotTests.testT06_70_homeDefaultAndOpaqueBannerAt1080And4K` |
| T06-71 | `T06ImageTests.testT06_71_imageURLHasNoCredentialQueryAndRequestHasAuthorization`; `T06ImageTests.testT06_71_inheritedCredentialQueriesAreRejected` |
| T06-72 | `T06ImageTests.testT06_72_imageCacheKeyIsStableSHA256OfIdentityTuple`; `T06ImageStoreTests.testT06_72_diskFilenameIsTheStableSHA256AndBytesRoundTrip` |
| T06-73 | `T06MetadataTests.testT06_73_metadataPreservesLiteralMarkupAndEntities`; `T06MetadataTests.testT06_73_limitsCountCleanedGraphemeClusters`; `T06MetadataTests.testT06_73_displayTextCaps500GraphemesWithoutSplittingEmojiOrCombiningMarks`; `T06MetadataTests.testT06_73_displayTextStripsEveryControlAndBidiScalarBeforeCapping`; `T06MetadataTests.testT06_73_allMappedNamesAreCappedAndKeepLiteralMarkup`; `T06HomeServiceTests.testT06_73_filterGenresUseLiteralTextAndPolicyLimits`; `T06HomeTests.testT06_73_metadataIsCleanedThroughLiveAndCachedViewModels`; `DesignSystemLogicTests.testT05_15_overviewIsPlainText` |
| T06-74 | `scripts/ci-grep.sh`; existing M03 redactor tests |
| T06-75 | `scripts/redact_artifacts.py --self-test` (redactor only; final artifacts pending) |
| T06-76 | `T06ImageStreamTests.testT06_76_missingContentLengthAbortsDuringDownload`; `T06ImageStreamTests.testT06_76_exactByteLimitIsAcceptedAndCached`; `T06ImageStreamTests.testT06_76_T06_77_deliveredByteLimitDoesNotTrustContentLength` |
| T06-77 | `T06ImageStreamTests.testT06_77_lyingContentLengthAbortsDuringDownload`; `T06ImageStreamTests.testT06_76_T06_77_deliveredByteLimitDoesNotTrustContentLength` |
| T06-78 | `T06ImageStreamTests.testT06_78_advertisedOversizeRejectsBeforeBody`; `T06ImageStreamTests.testT06_78_oversizedHeaderCancelsTheReceivingDelegate` |
| T06-80 | `T06ImageOptionsTests.testT06_80_thumbnailOptionsUseDisplayedPixelsOnEveryPlatform`; `T06ImageDecodeTests.testT06_80_decoderDownsamplesToDisplayedPixelSize` |
| T06-81 | `scripts/check-image-pipeline.py` and its `--self-test`, invoked by `scripts/ci-grep.sh` |
| T06-82 | `T06ImageTests.testT06_82_imageByteLimitRejectsOversize`; `T06ImageDecodeTests.testT06_82_invalidImageFailsBeforePublishingBitmap`; `T06ImageStoreTests.testT06_82_loaderAndDiskRejectOversizedImageWithoutCaching`; `T06ImageStreamTests.testT06_82_cancelledStreamCannotCachePartialImage` |

## Not automated

Each row identifies the missing part of the canonical scenario and why it remains unautomated or unexecuted. Some IDs have partial tests above; this section prevents those tests being mistaken for complete scenario evidence.

| Canonical ID | Remaining evidence / reason |
|---|---|
| T06-03 | Latest-only default focus still needs a dedicated tvOS UI scenario; the plan marks the fallback as an assumption pending Q6-01. |
| T06-05 | Only Menu on the tab bar exiting the app remains manual. Up and Menu from Home content reaching the native Home tab are automated. Simulator launcher / test-runner handling of system exit is not stable evidence of app behavior; check exit on Apple TV. |
| T06-09 | Row and tab identifiers are asserted; exact row order and Favorites absence need rendered UI review. |
| T06-11 | Pending Q6-03 overlap decision. Requests send enableResumable=false; explicit cross-row de-duplication has no implementation/test. |
| T06-12 | The deterministic gate test proves concurrent independent publishing; the exact 1 s per section / <1.5 s budget needs a timed Apple fixture. |
| T06-14 | Logic tests prove targeted retry. Focus after retry requires tvOS remote execution and the Q6-11 presentation decision. |
| T06-15 | Hidden empty headers need rendered snapshots; the state test alone does not verify view visibility. |
| T06-18 | M01 already covers lossy item decoding; a Home-specific malformed-row/log fixture is still pending. Whole-body failure is covered separately by T06-19. |
| T06-20 | Progress / unknown-duration layouts need Apple snapshot fixtures and visual inspection. |
| T06-21 | Series/episode card copy and layout need Apple snapshot rendering and M07 metadata model integration. |
| T06-22 | Pending Q6-06 presentation decision and grouped-series fixture; request groupItems=true is asserted by T06-08. |
| T06-23 | Debounce constants are automated; appearance and the 300 ms crossfade require tvOS visual review. |
| T06-24 | State debounce and cancellation are automated; the exact ten-focus image-request-count fixture is still pending Apple view integration. |
| T06-25 | Zero fade duration is automated; the rendered Reduce Motion transition requires Apple UI/snapshot execution. |
| T06-26 | Pending Q6-07 fallback decision; missing-backdrop visuals need an Apple snapshot fixture. |
| T06-27 | Glass placement is source-checked; final home rendering still requires snapshots. |
| T06-28 | Bright/dark/busy backdrop readability is a visual review requiring rendered snapshots. |
| T06-29 | Displayed-pixel request parameters are unit-tested; actual view geometry and scale require Apple rendering. |
| T06-30 | The UI test is supplied unchanged, but main's Next Up fixture has four cards while the test requires five. Focus-memory validation also requires Apple execution. |
| T06-31 | The back-restoration UI test is supplied but requires Xcode; the actual M07 detail destination is a separate module handoff. |
| T06-35 | Mark-played-to-next-episode UI timing requires M08 integration. A dedicated successful action fixture remains pending; playback-stop refresh is automated by T06-57. |
| T06-36 | A dedicated HTTP 500 mark-played rollback fixture is pending; the existing action test asserts rollback for 403 (T06-41). |
| T06-37 | Reset payload and a disposable-server test are supplied; actual absence from Resume after a real refetch requires the Docker version matrix and Q6-10 verification. |
| T06-38 | Season-preserving series handoff and movie exclusion are automated. M07 owns the per-season detail picker; UI navigation awaits that module and Xcode. |
| T06-39 | The action test asserts favorite POST success. DELETE/failure rollback still needs a dedicated fixture; no complete favorite-action claim is made. |
| T06-42 | The unchanged UI test requires network controls, a completed-request counter and offline playback feedback absent from main. It remains enabled and fails its missing-counter prerequisite. |
| T06-43 | The unchanged UI test requires network controls and a completed-request counter absent from main. It remains enabled and fails its missing-counter prerequisite. |
| T06-44 | Snapshot grouping, ownership, and account isolation are automated; immediate same-user stale display and focus need a dedicated cache-launch fixture. |
| T06-45 | Purged-cache launch needs a dedicated cold-start fixture. Cache loss is supported by the M02 stores, but that is not full Home scenario coverage. |
| T06-46 | The shared server-down key and Settings escape have tests; default retry focus and Change server still need Apple UI execution. |
| T06-47 | Change server navigation and token retention require an Apple UI flow fixture. |
| T06-51 | API/image/socket 401 behavior is automated; the visible sign-in transition requires Apple UI execution. |
| T06-52 | M02 baseline tests cover retry classification/backoff; a dedicated M06 HTTP-to-section retry fixture is pending. |
| T06-53 | Network Link Conditioner needs Apple tooling and device/simulator execution. |
| T06-54 | M02 handles lifecycle events; dedicated Home content/no-content event fixtures are still pending. |
| T06-55 | Production request configuration uses 15 s; the dedicated Home timeout-to-section fixture remains pending. |
| T06-56 | Cached cold-launch logic is automated; actual cached-down rendering and focus require the supplied UI test on Apple. |
| T06-58 | End-of-playback UI latency requires M08 integration and an Apple player. |
| T06-59 | Two-client WebSocket delivery <=5 s requires the disposable Docker Jellyfin matrix. |
| T06-62 | Foreground age/content/remembered-focus logic is automated; actual quiet refresh and focus require Apple UI execution. |
| T06-64 | UI test supplied; execution requires tvOS Xcode / simulator. |
| T06-65 | Neighbor policy unit-tested; rendered focus movement and Q6-09 whole-row fallback require tvOS remote evidence. |
| T06-67 | Cold-start and row-loading budgets need LAN measurements on A15 and the oldest supported Apple TV. |
| T06-68 | 60 fps / hitches / glass G-4 require Instruments on supported Apple TVs. |
| T06-69 | P11 memory and memory-warning behavior require Apple memory profiling. |
| T06-70 | Snapshot/UI sources supplied; the PNG matrix, full row coverage and opaque tab chrome need Xcode execution/review. |
| T06-73 | Literal metadata and grapheme boundaries are unit-tested; Taglines/Genres/people/studio field layout belongs to M07 and needs its fixtures/snapshots. |
| T06-74 | Source and baseline redaction tests pass; runtime diagnostics still need Apple CI artifact review. |
| T06-75 | Redactor self-test passes; final screenshot/JUnit/xcresult secret scanning requires generated Apple CI artifacts. |
| T06-79 | A <1 MB 30,000-pixel bomb fixture and <=50 MB peak/P11 validation need ImageIO plus Apple hardware profiling; Linux cannot supply this evidence. |
| T06-80 | Portable production option dictionary is tested. Real 3840x2160 backdrop / 2000x3000 poster thumbnail tests are supplied but require ImageIO on Apple. |
| T06-82 | Oversize/cancellation/no-cache logic and Apple invalid-decode test supplied. Rendered placeholder and stable focus require Apple UI execution. |

## PoC tvOS follow-ups (2026-10-28)

After merging `origin/main` at `b70aea1`, this branch retains the tests below unchanged and takes all app sources from main. The removed branch-only fixtures and app fixes are recorded in [TEST-CHANGES-M06-POC-MAIN.md](TEST-CHANGES-M06-POC-MAIN.md). T06-30, T06-42 and T06-43 have known unmet prerequisites in main; their assertions remain enabled and will fail until those prerequisites are supplied. Linux package results do not validate these tvOS scenarios.

The five U scenarios above are supplied in the existing [T06HomeUITests.swift](../Apps/Shared/UITests/T06HomeUITests.swift), which is already included by the `Glassfin-tvOSUITests` source directory in `project.yml`. All five methods and remote helpers are inside `#if os(tvOS)`; methods use `@MainActor async`, with no class-level actor isolation. The iOS target continues to include the same shared file. These are automated sources awaiting macOS execution, not a claim of a successful Apple build or UI run.

- T06-05 checks Up from row 1, Down back into Home, and Menu from row 2 to the native Home tab, while the app remains foreground. System exit is the only manual sub-step.
- T06-30 traverses the first five cards of both rows, checks Left/Right/Up/Down, and returns from row 2 item 5 to row 1 item 1 and back. A frame assertion ensures the remembered fifth card is horizontally away from the first card, so geometry alone cannot satisfy the scenario. Every press has a bounded focus wait and stops the test on failure; the navigation loops have four iterations each.
- T06-40 uses a nondefault card, a native long Select press, menu action existence, Menu dismissal, and same-card focus without a focus-restoring remote command.
- T06-42 asserts `home.banner` appears within a 2 s wait, carries `AppErrorMessage.offlineKey`, and is skipped when moving Up to the tab bar. It checks the banner and its descendants have no focus, retained cards remain navigable in both rows, and no full-screen error appears. Context-menu Play exercises the production block and checks `home.playback.blocked` against `AppErrorMessage.playbackOfflineKey`, with no playback destination.
- T06-43 asserts banner removal within a 2 s wait, then requires an increased fake-service Resume request count published only after Home finishes loading all sections. An inverted focus expectation runs alongside the refresh expectation for a bounded 5 s interval. No navigation or focus assignment follows the recovery command.

T06-42 and T06-43 require a deterministic network control: `-uitest-home-network-controls` must inject a `ConnectivityPath` stream consumed by `AppState.startPathUpdates()`, Play/Pause must toggle that stream without moving focus, and `home.test.resumeRequests` must publish actual Resume request counts only after Home finishes loading. Those hooks were present in this branch before the merge but are absent from main's app sources, which this branch now preserves verbatim. The tests therefore fail their initial counter prerequisite on the current app; they are not skipped or relaxed.

The retained tests also expose these outstanding fixture and app requirements:

- T06-30 needs five Next Up cards. Main's [HomeMockLibrary](../Apps/Shared/Sources/HomeMocks.swift) returns four, so the unchanged test cannot reach its fifth-card assertion. Main also retains its existing conditional default-focus preference for inactive rows; remembered cross-row focus still needs Apple Focus Engine validation.
- T06-42 requires visible, nonfocusable `home.playback.blocked` feedback using `AppErrorMessage.playbackOfflineKey`. Main's [HomeView.swift](../Apps/Shared/Sources/HomeView.swift) returns silently when playback is blocked. The test keeps the feedback assertion; this merge does not add that app behavior.

CI risks: Linux cannot type-check SwiftUI/XCUIRemote against the tvOS SDK or run the Focus Engine. Native tab focus identifiers, native context-menu cell focus, the geometry precondition, and the 2 s accessibility timing need macOS CI confirmation. The tests use the same identifiers/native-cell convention as the existing M05/M06 tests and bounded XCTest waits, without retrying navigation after a failed assertion.

Historical Linux verification before the main merge: `swift test` and `bash scripts/coverage-gate.sh` both passed (496 cases: 488 passed, eight existing live integration skips, zero failures). Coverage was 91.44% (8,051 / 8,805 lines; threshold 80%). Strict recursive `swift-format`, all four Python `check-*.py` checks, DEBUG-string and image-pipeline self-tests, `ci-grep`, license and entitlement checks, artifact-redactor self-test, 33 Python bootstrap/HLS tests, shell syntax checks, and the 22-case Docker script self-test passed. The portable Home mock/control source, with only its SwiftUI import replaced by Foundation in a temporary copy, also passed Swift 6 strict-concurrency type checking against the built core modules, including the path-injection expression. SwiftLint was unavailable for that run. Current merge validation is recorded in [TEST-CHANGES-M06-POC-MAIN.md](TEST-CHANGES-M06-POC-MAIN.md). Apple builds, UI execution, and the Release binary scan remain unexecuted here.

## Screen re-entry regression coverage

The v2 stack merge is `52b37cf`, with parents `370e398` and `a22db4a`. The complete conflict resolution and test/assertion/signature inventory is in [TEST-CHANGES-M06-RESTACK.md](TEST-CHANGES-M06-RESTACK.md), compared with the pre-merge branch and with v2 where isolation needed adaptation.

Home, Library and Series view models conform to #7's `ViewContentProviding` and expose `onAppear()` to select themselves as `app.currentView`. Home's real SwiftUI screen invokes it from `.onAppear`, including NavigationStack pops and tab returns. Library tabs and the M07 item destination remain placeholders in this branch; they have no corresponding Library/Series SwiftUI screens to wire. Series is the existing detail-oriented model; there is no separate item-detail view model here. Home uses #7's `AppState.showsServerDown` for the server-unreachable full-screen decision, while retaining its existing offline presentation.

All nine methods below are `@MainActor async` (the six state scenarios also `throws`), and `ScreenReentryTests` has no class-level actor annotation. Tests exercise actual models and `AppState.handle(.serverUnreachable)`, then inspect `AppState.showsServerDown` and the shared catalog key. Assertions compare keys and localized accessors, with no new UI copy.

| Test in `ScreenReentryTests` | ID / exact assertion coverage |
|---|---|
| `testHomeOnAppearSelectsCurrentView` | Extra: initially nil current view; `onAppear()` selects the identical Home instance; idle Home has no content; no Resume request occurs. |
| `testLibraryOnAppearSelectsCurrentView` | Extra: initially nil current view; selects the identical Library instance; idle Library has no content; no item-page request occurs. |
| `testSeriesOnAppearSelectsCurrentView` | Extra: initially nil current view; selects the identical Series instance; idle Series has no content. |
| `testT06_49_homeReentryKeepsContentAndShowsBanner` | T06-49: independently seeds Resume, Next Up and library Latest content; verifies content exists, the other VM identity, then the returning Home identity. Server failure must show the banner with no full-screen state or Home error title. Visiting the empty VM while already unreachable must show full-screen; returning Home restores the banner. Resume, Next Up and each Latest row retain their exact states, and Resume request count stays unchanged. |
| `testT06_46_homeReentryWithoutContentShowsFullScreen` | T06-46: repeats with idle and successfully loaded-empty Home; navigates through a Library VM with content, checks both identities, and verifies Home has no content. Failure must show the full-screen state with the shared title; Home's title equals AppState's title key. |
| `testLibraryReentryKeepsContentAndShowsBanner` | Extra, extends the T02-35a rule beyond its Home scenario: loaded Library has content; checks departing/returning identities; verifies the banner before and after a second navigation while unreachable, with full-screen only on the empty other VM. The exact Library state and item-page request count stay unchanged. |
| `testLibraryReentryWithoutContentShowsFullScreen` | Extra, extends T02-35b: idle and loaded-empty Library; visits Home with content, checks both identities, verifies no Library content, and requires full-screen after failure. |
| `testSeriesReentryKeepsContentAndShowsBanner` | Extra, extends T02-35a: repeats with seasons alone and seasons plus episodes; verifies content, departing/returning identities, banner before and after navigating while unreachable, and full-screen only on the empty other VM. Exact seasons/episodes states stay unchanged. |
| `testSeriesReentryWithoutContentShowsFullScreen` | Extra, extends T02-35b: idle and loaded-empty Series; visits Home with content, checks both identities, verifies no Series content, and requires full-screen after failure. |

The banner assertion helper checks exactly four things: `.serverUnreachable` connectivity, `bannerKey == AppErrorMessage.serverDownKey`, `banner == AppErrorMessage.localized(serverDownKey)`, and `showsServerDown == false`. The full-screen helper checks exactly three things: `.serverUnreachable`, `showsServerDown == true`, and `serverDownTitleKey == AppErrorMessage.serverDownKey`. These assertions also apply wherever their helpers are called in the table above.

The seven extra tests do not introduce or reuse canonical IDs: the M02 plan gives T02-35a/b to its existing Home scenarios, and identity-only entry checks have no separate canonical scenario. Home presentation regressions use the matching T06-46/T06-49 IDs. Temporarily removing only Home's `onAppear` registration makes the T06-49 re-entry test fail on identity and full-screen assertions; the hook was restored before final verification. Apple UI execution remains unverified on Linux.

Final v2/re-entry verification (2026-10-27): `bash scripts/coverage-gate.sh` passed with 401 tests, six existing live-integration skips, zero failures, and 91.34% line coverage (7,224 / 7,909; threshold 80%). The exact recursive strict `swift-format` lint, design-system check, string-catalog check, DEBUG-only-string check, `bash scripts/ci-grep.sh` and `git diff --check` passed. The v2 ancestry, byte-identical base-only files, exact #7 display sanitizer implementation, unchanged v2 `project.yml`, absence of class-level XCTest actor isolation, and async signatures for every actor-isolated test were also checked. No Apple build/UI/snapshot execution was available.

## Binding follow-up decisions

- Continue Watching and Next Up are separate P0 rows (owner decision Q6-20), asserted with distinct in-progress and next episode fixtures in T06-10. Favorites and the combined-row preference remain disabled P1 switches.
- Series detail uses one season at a time with a season picker (owner decision Q7-25). This branch supplies the M07 handoff, preserving the season ID/index (T06-38); it contains no alternative episode-list implementation.
- `MetadataPolicy.swift` contains Overview 2,000; Taglines 3 x 200; Genres 10 x 64; other strings 200; server/public-user display names 64; recent searches 20; image bytes 20 x 1,024 x 1,024. Cleaning removes only control/bidi scalars before truncating graphemes, preserving tags, entities and Markdown literally (T06-73). M09 owns recent-search persistence.
- `MetadataSanitizer.displayText(_:limit:)` is the shared capped display path. Mappers and Home's cache projection apply `MetadataPolicy.nameMax` to names, titles and other unbounded display text, including search hints, series/season/episode items, person/studio items, libraries, chapters and tracks. Fields not yet modeled (such as separate `SeriesName`, `SeasonName` and detail-page people/studio collections) are discarded rather than displayed; M07 must use the same sanitizer when introducing them. The design-system overview helper also preserves literal tags/entities and uses `overviewMax`.
- `JellyfinImageResource` names the CoreNetworking image request/cache identity without colliding with Apple's image resource type. Home UI test flags and snapshot renders use the DEBUG-only writable `designAccessibilityOverride`; `DesignAccessibility` falls back to the system settings when no override is supplied, and Home backdrop animation reads the same values.
- Image requests set a maximum response budget from `MetadataPolicy.imageMaxBytes`. The URLSession data delegate checks every chunk before appending and cancels immediately on overflow. Content-Length only permits early rejection. Overflow and cancellation cannot write a partial disk cache entry (T06-76 through T06-78, T06-82). The SDK adapter also routes bounded requests through CoreNetworking. Each capped download has independent redirect state and forwards certificate challenges to the existing trust policy; 401 takes precedence over size headers (T06-51).
- The portable option dictionary is passed directly to ImageIO thumbnail creation in a detached utility task. ImageIO code is guarded by `canImport(ImageIO)`. The source check scans all Apps and package source Swift files for forbidden framework networking/full-bitmap APIs (T06-80, T06-81).
- Loaded or cached content survives server failure with the existing `.serverUnreachable` banner. The existing full-screen title key is used only with no displayable content; failed server actions stay inline (T06-46, T06-49, T06-50, T06-56). Whole-body decode failures show a section retry instead of the empty-library guidance (T06-19).

## Verification

Run in `Packages/GlassfinCore` after exporting `LD_LIBRARY_PATH=~/.local/lib/swiftcompat` and sourcing `~/.local/share/swiftly/env.sh`:

```sh
bash ../../scripts/coverage-gate.sh
swift-format lint --recursive --strict Package.swift Sources Tests ../../Apps
```

From the root: design-system, string-catalog, DEBUG-only-string, image-pipeline (including self-test), ci-grep, entitlement, license, artifact-redactor self-test and coverage-gate checks. Apple build/UI/snapshot commands require Xcode; live tests require disposable Jellyfin containers; hardware metrics require supported Apple TVs.

## Linux verification result (2026-10-27)

- CI round 1: `bash scripts/coverage-gate.sh` (running `swift test --enable-code-coverage --build-system native`) and the exact recursive strict formatter command passed. The full suite executed 378 tests with six existing live integration skips and zero failures. Four new T06-73 test cases cover the capped display API, all control/bidi scalars, mapped names/titles and filter genres; its live T06-37 test still requires the server fixture.
- Passing Linux test IDs: T06-04, T06-06 through T06-08, T06-10, T06-12 through T06-14, T06-16, T06-19, T06-24, T06-32, T06-33, T06-38, T06-41, T06-44, T06-46, T06-48 through T06-51, T06-56, T06-57, T06-60 through T06-63, T06-65, T06-66, T06-71 through T06-73, T06-76 through T06-78, T06-80 and T06-82. Additional catalog/design/logging/image source checks are mapped above.
- The native coverage gate passed at 91.36% (7,062 / 7,730 lines; threshold 80%).
- Existing assertion changes are confined to `DesignSystemLogicTests.testT05_15_overviewIsPlainText`: the overview equals the original literal fixture, and `<`, `alert` and `example.com` remain present. These replace the obsolete decoded/tag-stripped expectation and three absence assertions. No tests were deleted and no skip conditions were added.
- All requested repository scripts passed, plus image-pipeline, DEBUG-string and artifact-redactor self-tests, entitlement and license checks. `git diff --check` passed.
- The canonical plan was byte-compared with `/workspace/jellyfin-tvos/test/TESTPLAN-M06.md`. A completeness check verified all 82 IDs are mapped and every M06 Swift test uses an in-range canonical ID with a matching comment.
- Xcode, Docker and Apple TV hardware are unavailable here. Apple app builds, actual ImageIO execution, remote UI/snapshots, the live server matrix and hardware performance were not executed. The Not automated table records the remaining fixture work and evidence for each affected ID.
