# M09 canonical test mapping

The only binding plan is [spec/TESTPLAN-M09.md](../spec/TESTPLAN-M09.md), copied verbatim from the supplied plan. Test names and comments use exactly its IDs. Multiple tests may exercise one canonical scenario; no additional IDs are allocated.

Linux tests run in GlassfinCore. Apple UI and ImageIO tests are present but cannot run on this Linux host. “Not automated” records missing automation or environment-dependent acceptance evidence, not a passing result. Supplemental IDs refer to explicit assertions in a shared regression.

| ID | Automated entry points | Scope / not automated |
|---|---|---|
| T09-01 | `testT09_01_openTabShowsFocusedSystemInputAndRecentSearches` | Apple UI: native Search tab, input/keyboard focus, populated recents below the field and immediate typing. Unrun on Linux. |
| T09-02 | `testT09_02_debounceAndCancellationBeforeRequest` | Linux regression test. |
| T09-03 | `testT09_03_oneLatinCharacterKeepsRecentsWithoutSearching`; `testT09_03_singleLatinCharacterKeepsRecentSearchesVisible` | Linux minimum-length regression retained. New Apple UI test also selects a visible recent query after one Latin character; unrun locally. |
| T09-04 | `testT09_04_twoCharactersSearch` | Linux regression test. |
| T09-05 | `testT09_05_minimumLengthAndCJK` | Linux regression test. |
| T09-06 | `testT09_06_whitespaceIsIgnoredForEligibilityAndTransmission` | Linux regression test. |
| T09-07 | `testT09_07_twentyCharactersDebounceToOneRequest`; `testT09_07_fastTypingRetainsAllTwentyCharacters` | Deterministic Linux clock verifies one final request for 20 characters. Apple UI typing test implemented, unrun locally. |
| T09-08 | `testT09_08_longQueryIsCappedBeforeRequest` | Linux regression test. |
| T09-09 | `testT09_09_clearDiscardsLateResultsAndShowsRecents`; `testT09_09_clearFieldRemovesRowsAndRestoresRecentSearches` | Linux late-response/cancellation regression retained. New Apple UI test clears the native field and checks row/header removal and restored recents; unrun locally. |
| T09-10 | — | Not automated: Siri dictation and iPhone keyboard input require physical Apple TV. |
| T09-11 | `testT09_11_keyboardToRowsAndVerticalFocusSections`; `testT09_11_downReachesResultsAndUpReturnsToKeyboard` | Apple UI: Down reaches results, Up returns to the native keyboard, and typing still works. Unrun locally; physical remote confirmation remains. |
| T09-12 | `testT09_12_backKeepsTextResultsAndFocus`; `testT09_12_tabRoundTripKeepsQueryAndResults` | Linux state retention retained. New Apple UI test switches Home/Search in the native LibraryTabShell with an isolated session fixture; unrun locally. |
| T09-13 | `testT09_60_cancelledQueryDoesNotRetryAfterBackoff`; `testT09_14_reverseResponsesOnlyLatestWins` | Linux reverse-response and cancelled retry tests cover prior-task cancellation. Immediate child cancellation also covered by T09-17. |
| T09-14 | `testT09_14_reverseResponsesOnlyLatestWins` | Linux regression test. |
| T09-15 | `testT09_09_clearDiscardsLateResultsAndShowsRecents` | The T09-09 regression clears during a request, releases its late response and verifies recents stay visible. |
| T09-16 | `testT09_16_cancelledResponseIsSilent` | Linux regression test. |
| T09-17 | `testT09_17_parallelRequestsAreCancelledTogether` | Linux regression test. |
| T09-18 | `testT09_18_disappearCancelsAndResumesPendingSearch`; `testT09_18_cancelledImageStreamStopsTheTransfer` | Linux covers disappearing search tasks and cancellation of an active counted image stream. |
| T09-19 | `testT09_19_sameTermABAAndWrongResponseTermAreRejected`; `testT09_19_debouncedABAReturnsIdenticalResultsWithOneFinalRequest` | Linux ABA/stale-response coverage retained. New deterministic debounce test sends one final star request after sta/star and checks identical results. |
| T09-20 | `testT09_20_refreshKeepsFocusOnSurvivingReorderedItem`; `testT09_20_removedFocusedItemFallsBackToSurvivingResult` | Apple UI: an explicit fixture refresh reorders surviving IDs/updates labels without stealing focus; a separate removal case checks fallback. Unrun locally. |
| T09-21 | `testT09_21_searchBackendLatencyAndResultCounts` | Opt-in Docker benchmark compiled; not executed locally because Docker/live servers are unavailable. Cross-version artifact evidence pending. |
| T09-22 | `testT09_22_searchFindsUmlautSeedWithBothBackends` | Opt-in Docker test compiled; uses canonical Hämärä/hämä fixture/query. Not executed locally: Docker unavailable. |
| T09-23 | `testT09_23_threeItemsRequestsStartInParallelWithIndependentLimits` | Linux regression test. |
| T09-24 | `testT09_24_hintsGroupInServerOrderRetainImagesAndPageByType` | Linux regression test. |
| T09-25 | `scripts/check-m09.py` | Source check ties the production ItemsSearchBackend default to ADR-M09-1. No endpoint switch claimed. |
| T09-26 | `testT09_26_bothBackendsPassSpecialTermsAsQueryItems`; `testT09_26_sdkQueryBuilderPreservesSpecialTerms`; `testT09_26_queryEncodingRoundTripsSpecialCharactersAndSubpath` | Linux regression test. |
| T09-27 | `scripts/check-m09.py` | Source check rejects query interpolation in search paths; T09-26 tests exact URLQueryItem round trips. |
| T09-28 | `testT09_28_pagingDeduplicatesAndRetainsServerOrder`; `testT09_28_serverOrderAndLiteralMetadataArePreserved` | Linux regression test. |
| T09-29 | `testT09_29_errorAndRetry`; `testT09_29_failedSiblingIsHiddenWhileSuccessfulRowsRemain`; `testT09_29_errorShowsRetryAndSharedCoreKey`; `testT09_29_failedSeriesRequestKeepsMoviesAndEpisodesVisible` | Linux sibling failure/retry coverage and existing retry UI retained. New Apple UI test verifies successful movie/episode rows and no failed Series header; unrun locally. |
| T09-30 | `testT09_61_brokenItemsAreSkippedAndP1KindsAreExcluded`; `testT09_30_onlyMovieSeriesAndEpisodeRowsInCanonicalOrder` | Existing backend P1 exclusion retained. New Linux view-model test explicitly excludes Person/BoxSet/Audio and checks P0 group order. |
| T09-31 | `testT09_31_groupedResultsHaveMoviesSeriesAndEpisodesHeaders`; `testT09_31_groupedRowsAt1080And4K` | Apple UI headers and 1080p/4K grouped-screen recordings added; unrun locally. Linux group-order regression also passes. Snapshot references need macOS recording/review. |
| T09-32 | `testT09_32_emptySeriesGroupHasNoHeader`; `testT09_32_emptyGroupAt1080And4K` | Apple UI checks a successful empty group has no row/header; 1080p/4K recording tests added. Both unrun locally; reference comparison is skipped until baselines exist. |
| T09-33 | `testT09_33_emptyStateUsesCatalogKey`; `testT09_33_literalEmptyQueryAt1080And4K` | Existing Apple UI catalog-key assertion retained. New empty-state recordings include a literal Markdown query at both sizes; unrun locally; references pending. |
| T09-34 | `testT09_34_loadingThenEmptyAndInvalidTermClearsRows`; `testT09_34_loadingAt1080And4K` | Existing Linux loading/reset regression retained. New Apple recordings start with loaded content then a pending query, checking skeleton state and empty groups at both sizes; unrun locally; references pending. |
| T09-35 | `testT09_35_posterTitleIncludesYearAndHandlesMissingYear`; `testT09_35_movieAndSeriesPostersAt1080And4K` | New Linux tests verify movie/series title and optional year. Production poster-face recordings at both sizes are Apple-only and await reviewed references. Missing year presentation is fixed. |
| T09-36 | `testT09_36_episodeTitleIncludesSeriesSeasonEpisodeAndName`; `testT09_36_missingEpisodeMetadataKeepsTheEpisodeName`; `testT09_36_episodeLandscapeAt1080And4K` | New Linux DTO/model/cache tests verify SeriesName, SxEy, episode name and missing metadata. Production landscape recordings at both sizes are Apple-only and await reviewed references. Missing labels are fixed. |
| T09-37 | `testT09_37_backRestoresTextResultsAndSelectedCardFocus` | Partial: Apple back/focus UI test implemented, unrun. Full M07 destination integration is pending (Q9-12). |
| T09-38 | — | Not automated: M07 episode/season destination is absent on this stack (Q9-12). |
| T09-39 | — | Not automated: direct playback action awaits M07/M08 integration. |
| T09-40 | `testT09_40_verticalNavigationRestoresEachRowsRememberedItem` | Apple UI moves repeatedly between rows with different remembered horizontal positions. Unrun locally; physical remote confirmation remains. |
| T09-41 | `testT09_41_all24ResultsRemainInServerOrderWithoutAnotherPage`; `testT09_41_all24CardsAreReachableWithoutSeeMore` | Linux real-backend/view-model regression preserves all 24 final-page IDs in server order, no cursor or extra page. Apple UI traverses all 24 and checks no See more control; unrun locally. Automatic paging for larger totals remains Q9-16. |
| T09-42 | `testT09_42_searchGlassAndOpaqueBannerAt1080And4K` | Existing design-system source surface checks pass. New Apple screen recordings show native chrome/banner and Reduce Transparency at 1080p/4K; unrun locally; reference comparison awaits reviewed baselines. |
| T09-43 | `testT09_43_historyRecordsOnlyResultSelection`; `testT09_43_onlyOpeningAResultAddsTheQueryToRecents` | Existing Linux deliberate-selection history regression retained. New Apple UI test checks typing/clearing does not save, then opening a result saves exactly one recent query; unrun locally. |
| T09-44 | `testT09_44_historyCapRecencyAndDeduplication` | Linux verifies eviction at 20, recency and uniqueness. |
| T09-45 | `testT09_46_historyDeduplicatesTrimmedTextIgnoringCase`; `testT09_44_historyCapRecencyAndDeduplication` | Linux checks most-recent-first order in both cap and duplicate regressions. |
| T09-46 | `testT09_46_historyDeduplicatesTrimmedTextIgnoringCase` | Linux verifies trimmed, case-insensitive comparison while preserving the most recently selected display spelling. |
| T09-47 | `testT09_47_historyIsScopedByBothServerAndUserAndSurvivesRestart` | Linux verifies both server/user isolation and persistence across store recreation. |
| T09-48 | `testT09_48_historyUsesApplicationSupportAndExcludesBackup` | Linux verifies Application Support location. Apple backup resource-value assertions implemented, unrun locally. |
| T09-49 | `testT09_49_onlyQueryTextInApplicationSupportNoPreferencesOrKeychainWrites` | Linux decodes the persisted file as query text only; IDs/addresses/credentials are absent from the payload. |
| T09-50 | `testT09_66_queriesNeverReachLogs` | Linux view-model log capture covers saving and reading on selection. Store has no logger dependency. HTTP privacy capture is also retained. |
| T09-51 | `testT09_51_signOutDeletesOnlyThatUsersHistory` | Linux regression test. |
| T09-52 | `testT09_52_serverRemovalDeletesAllItsUsersOnly` | Linux regression test. |
| T09-53 | `testT09_53_userClearRemovesDiskHistoryAndViewState`; `testT09_53_recentSearchesAreUserClearable` | Linux clears view and disk state. Apple clear-recent UI test implemented, unrun locally. |
| T09-54 | `scripts/check-m09.py` | Source check forbids cloud, preference, Keychain and network dependencies in RecentSearchStore. |
| T09-55 | `testT09_55_corruptAndOversizeHistoryStartEmpty` | Linux covers corruption, oversize-file discard, recovery writes and persistence across store recreation. |
| T09-56 | `testT09_56_offlineSearchKeepsRecentsAndDoesNotSend`; `testT09_56_offlineBannerKeepsRecentQueryUsable` | Linux no-request/offline preflight regression retained. New Apple UI test checks shared banner, recent-query selection and editable input; unrun locally. |
| T09-57 | `testT09_57_serverDownKeepsContentSharedKeyAndTenSecondRecovery`; `testT09_57_serverDownRefreshKeepsResultsAndShowsBanner` | Linux retained-content/recovery scheduling coverage retained. New Apple UI refresh failure test checks retained cards/focus, shared banner and no blocking error; unrun locally. |
| T09-58 | `testT09_57_serverDownKeepsContentSharedKeyAndTenSecondRecovery`; `testT09_58_serverDownWithoutContentKeepsSearchInputEditable` | Existing Linux no-content shared-key coverage retained. New Apple UI test checks inline error/retry and continued editing of the native input; unrun locally. |
| T09-59 | `testT09_59_errorsNeverSignOutExcept401`; `testT09_59_stale401EndsSessionOnceCancelsWorkAndClearsHistory`; `testT09_59_sessionClientCancelsAllRequestsAndNeverRetries401`; `testT09_59_bothBackendsPropagateEveryFailureWithoutRetry`; `testT09_59_streamingImage401IsNotHiddenByItsBody` | Linux covers stale 401, token/history cleanup, one session-expiry transition, cancellation of scoped work and no retry. Oversized 401 body cannot hide auth failure. |
| T09-60 | `testT09_60_gatewayFailuresRetryTwiceWithSharedBackoff`; `testT09_60_cancelledQueryDoesNotRetryAfterBackoff` | Linux verifies both retry delays for 502/503/504 and no retry after query cancellation. |
| T09-61 | `testT09_61_brokenItemsAreSkippedAndP1KindsAreExcluded` | Linux search fixture skips one broken item and retains valid P0 items. |
| T09-62 | — | Not automated: LAN timing on A15/oldest hardware and a 10,000-item fixture are unavailable. |
| T09-63 | — | Not automated: 60 fps/hitch and P11 memory metrics require Apple hardware/Instruments. |
| T09-64 | `testT09_64_metadataIsLiteralThroughViewModel`; `testT09_64_viewModelBoundsNamesAndOverviewByGraphemes`; `testT09_64_allLimitsCountGraphemesAfterCleaning`; `testT09_64_literalMediaAndSanitizedDisplayNames`; `testT09_64_seriesNameIsLiteralCleanedAndBoundedByGraphemes`; `testT09_64_literalMetadataLayoutAt1080And4K` | Existing metadata/grapheme regressions retained. New Linux tests bound/clean SeriesName at DTO and cached-item boundaries without parsing literal markup. New production-card layout recordings at both sizes are Apple-only, references pending. |
| T09-65 | `testT09_65_imageCacheUsesStableSHA256TupleAsActualFilename`; `testT09_65_exactStreamBoundaryIsAccepted`; `testT09_65_imageURLHasNoCredentialAndRequestCarriesAuthorization`; `scripts/check-m09.py` | Linux covers header-only auth, SHA-256 tuple filename/cache restart and exact byte boundary. Production request carries the streaming cap through CoreNetworking; source check bans full-bitmap APIs. |
| T09-66 | `testT09_66_queriesNeverReachLogs`; `testT09_66_transportFailureLogsNoSearchTextOrRawImageURL` | Linux captured logs contain no private query or raw image URL. Search signpost uses the fixed search.results event. |
| T09-67 | `scripts/scan_benchmark_artifacts.py` (manual) | Main's retained integration workflow does not scan or upload search benchmarks. Scan the complete three-version JSON set before manual retention; automated artifact evidence remains pending. |
| T09-68 | `testT09_68_thumbnailOptionsUseTheDisplayedPixelSizeOnAllPlatforms`; `testT09_68_decodeDownsamplesOffMainThread`; `scripts/check-m09.py` | Portable production option dictionary is tested on Linux. Actual off-main ImageIO downsampling test implemented, unrun locally because ImageIO is unavailable. |
| T09-69 | `testT09_69_oversizedImagesRejectedBeforeCachingOrDecode`; `testT09_69_oversizedStreamsAreCancelledWithoutReadingTheTail`; `testT09_69_imageFailureLeavesRowAndFocusUsable` | Existing Linux real-stream/loader/cache oversize regressions retained. New tvOS UI fixture injects responseTooLarge, waits for the failure marker, then checks sibling navigation/focus. Unrun locally. Real decompression-bomb/device P11 memory acceptance remains unverified. |


## MVP additions (2026-10-28)

[TEST-COVERAGE-M09-MVP.md](TEST-COVERAGE-M09-MVP.md) maps the 24 supplemented rows to all 32 new test methods, recording instructions and environment limits. Existing tests and the canonical plan are unchanged.

## Validation

2026-10-28, keyboard-container follow-up for head `b0be7a5`: fetched origin; main `d720120` and M05 `d2d780b` are already ancestors, so no new merge is needed. Main's workflows, project.yml and app Info.plists still match exactly.

Run [40633679965](https://github.com/kallupx/glassfin/actions/runs/40633679965) introduces a new M09 test-helper regression, superseding the previous validation's key-focus assumption:

- [full-ui, job 122636093060](https://github.com/kallupx/glassfin/actions/runs/40633679965/job/122636093060): all six search UI cases (T09-07, T09-11, T09-29, T09-33, T09-37 and T09-53) fail at the helper's first typing call with `Search keyboard did not receive focus before typing`. The first case takes 30.606 seconds; the job's test step exits 65 after 20 minutes 52 seconds, within the 25-minute job limit.
- [test-tvos, job 122636093066](https://github.com/kallupx/glassfin/actions/runs/40633679965/job/122636093066): the same six cases fail at the same guard. The first case takes 27.047 seconds; the test step exits 65 after 20 minutes 44 seconds, within the same limit.

Both exported `xcresult-tests.json` files contain 31 leaf test cases: six search failures and 25 passes. The Release build, Release binary scan and package tests pass in both jobs. Missing text/results and subsequent runner restarts follow the rejected typing operation; these are not compile failures, job timeouts or evidence of a pure CI flake. T09-53 still fails, but it never reaches its original post-detail Delete operation in this run. No M05 or upstream main fix is required.

The T09-07 accessibility hierarchies in the downloadable artifacts (`full-ui-results/readable/screenshots/0C0E47EF-BDD0-4A64-88BD-E3058AA09B08.txt` and `tvos-results/readable/screenshots/640CD53D-00E4-4B33-AE1D-AB022E57F15E.txt`) show the search field as `Keyboard Focused` and the `Keyboard` container as `Focused`, with **no focused Key descendants**. Waiting for a focused key can therefore never recognize this ready input state, even after 24 Up presses.

Unavoidable test-helper change: only the tvOS branch of `typeSearchText` in `Apps/Shared/UITests/T09SearchUITests.swift`. Check the keyboard container's `hasFocus`, and use [XCUIElement.wait(for:toEqual:timeout:)](https://developer.apple.com/documentation/xcuiautomation/xcuielement/wait(for:toequal:timeout:)) to wait up to one second for focus after each Up press. The existing 24-press bound and failure guard remain. Every scenario assertion and existing scenario timeout is unchanged; there are no new tests, sleeps, production changes, UI strings or upstream patches.

With `LD_LIBRARY_PATH=~/.local/lib/swiftcompat` and the swiftly environment sourced, the requested Linux coverage gate passes: **489 tests**, **9 opt-in live-server skips**, no failures, **92.38%** line coverage (8178/8853). Strict `swift-format lint --recursive --strict Package.swift Sources Tests ../../Apps`, the design-system, string-catalog, debug-only-string and ci-grep checks, and `git diff --check` pass. On macOS, run `bash scripts/macos-ci.sh tvOS` to exercise the corrected helper, including T09-37 focus restoration and T09-53 post-detail clearing. Apple SDKs and simulators are unavailable on this Linux host, so a green Apple UI run is not claimed. Live-server and physical-device limits above remain.

2026-10-28, stack base v6: merged main `d720120` with merge commit `19d3b3a` (`Merge main d720120 (stack base v6)`). M05 `d2d780b` was already an ancestor; its remote branch had no newer commits. Main's workflows, project.yml and app Info.plists are retained exactly.

Run [40627723371](https://github.com/kallupx/glassfin/actions/runs/40627723371), head `03202ed`, has the same M09 test-helper failure in both failed jobs:

- [full-ui, job 122617415912](https://github.com/kallupx/glassfin/actions/runs/40627723371/job/122617415912): `testT09_53_recentSearchesAreUserClearable` fails after 18.995 seconds when its helper sends Delete keys at line 120. The Full UI suite step exits with code 65 after about 17 minutes, within the 25-minute job limit.
- [test-tvos, job 122617415986](https://github.com/kallupx/glassfin/actions/runs/40627723371/job/122617415986): the same test fails after 20.305 seconds with the same event-synthesis error. The test step exits with code 65 after about 19 minutes, within the 25-minute job limit. The Release build, Release binary scan and package tests pass.

The full job logs report `Neither element nor any descendant has keyboard focus`. The exported tvOS accessibility hierarchy confirms that the first result card is focused after returning from detail, while the inline keyboard remains visible without a focused key. T09-37 passes in both jobs and requires that card-focus restoration. These are reproducible test-harness errors, with no evidence of a CI timeout or flake. Neither M05 nor upstream main needs a corrective patch.

Unavoidable test change: only `Apps/Shared/UITests/T09SearchUITests.swift`, in the tvOS branch of `typeSearchText`. Keyboard visibility alone does not satisfy [XCTest's typing precondition](https://developer.apple.com/documentation/xcuiautomation/xcuielement/typetext(_:)). The helper now uses bounded Up navigation until a keyboard key has focus, and adds a failure guard if focus cannot be acquired. Every existing scenario assertion and timeout value is preserved; production focus restoration is preserved. The authorized main merge also imports PR #31's existing changes to `CorePlaybackTests/PlaybackCoordinatorTests.swift` and `CorePlaybackTests/ADRM08PrototypeTests.swift` unchanged; no local playback-test edits were made.

With `LD_LIBRARY_PATH=~/.local/lib/swiftcompat` and the swiftly environment sourced, `bash scripts/coverage-gate.sh` passes: **489 tests**, **9 opt-in live-server skips**, no failures, **92.38%** line coverage (8178/8853). Strict `swift-format lint --recursive --strict Package.swift Sources Tests ../../Apps`, all requested design-system, catalog, debug-only-string and ci-grep checks, and `git diff --check` pass. Apple SDKs and simulators are unavailable locally: rerun `bash scripts/macos-ci.sh tvOS` on macOS, or inspect the new PR CI run, to verify the corrected UI interaction. Live-server and physical-device acceptance limits recorded above remain.

2026-10-28, stack base v5: merged main `45e21b4`, including squash-merged M04 `b0f0f22` and HLS auth `924888d`, then M05 `d2d780b`. Main's workflows, project.yml and app Info.plists are retained exactly. Main's authentication surface is preserved with the M09 search tab, using M05's authentication source-check exception. The existing native search input, image EOF fixture and actor-isolation fixes are preserved; no tests or assertions changed in this update.

With `LD_LIBRARY_PATH=~/.local/lib/swiftcompat` and the swiftly environment sourced, `bash scripts/coverage-gate.sh` passed: **487 tests**, **9 opt-in live-server skips**, no failures, **92.40%** line coverage (8170/8842). Strict `swift-format lint --recursive --strict Package.swift Sources Tests ../../Apps` and all requested design-system, catalog, debug-only-string and ci-grep checks passed. Apple builds/UI tests and live-server benchmarks remain unverified locally. Main's project does not include the M05 app unit/snapshot test targets, and its integration workflow does not retain search benchmark artifacts.

2026-10-27, Swift 6.4.1 on Linux: the exact required `swift build && swift test && swift-format lint --recursive --strict Package.swift Sources Tests ../../Apps` command passed. The suite contains **381 tests**, with **7 opt-in live-server tests skipped** and no failures. Both sides of the integration merge compile. The package has 60 M09 test functions in source, including two Docker tests and one Apple-only ImageIO test; 57 M09 tests execute on Linux.

The required root checks passed: `check-design-system.py`, `check-string-catalogs.py` (both catalogs), `check-debug-only-strings.py`, and `ci-grep.sh`. The latter now invokes `check-m09.py`. Shell syntax and Python compilation passed. Temporary negative probes confirmed that `check-m09.py` rejects each forbidden image API; those probes were removed. `cmp` confirms the copied canonical plan is byte-for-byte identical to the supplied file.

`bash scripts/docker-integration.sh 10.10.7` reports that Docker is unavailable. No live-server performance result, Apple UI/snapshot result, actual ImageIO decode result, or physical-device memory/timing result is claimed. Info.plists, entitlements, project.yml and workflows were not edited during this follow-up.

## Owner decisions

Q6-20 is resolved: Continue Watching and Next Up are separate M06 rows. Q7-25 is resolved: M07 shows one season at a time with a season picker. This branch contains neither feature implementation; no matching TODO markers remain. Search destination integration is tracked under Q9-12.
