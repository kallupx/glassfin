# M09 canonical test mapping

The only binding plan is [spec/TESTPLAN-M09.md](../spec/TESTPLAN-M09.md), copied verbatim from the supplied plan. Test names and comments use exactly its IDs. Multiple tests may exercise one canonical scenario; no additional IDs are allocated.

Linux tests run in GlassfinCore. Apple UI and ImageIO tests are present but cannot run on this Linux host. “Not automated” records missing automation or environment-dependent acceptance evidence, not a passing result. Supplemental IDs refer to explicit assertions in a shared regression.

| ID | Automated entry points | Scope / not automated |
|---|---|---|
| T09-01 | — | Not automated: initial field focus/populated recent searches require an Apple UI fixture and simulator. |
| T09-02 | `testT09_02_debounceAndCancellationBeforeRequest` | Linux regression test. |
| T09-03 | `testT09_03_oneLatinCharacterKeepsRecentsWithoutSearching` | Linux regression test. |
| T09-04 | `testT09_04_twoCharactersSearch` | Linux regression test. |
| T09-05 | `testT09_05_minimumLengthAndCJK` | Linux regression test. |
| T09-06 | `testT09_06_whitespaceIsIgnoredForEligibilityAndTransmission` | Linux regression test. |
| T09-07 | `testT09_07_twentyCharactersDebounceToOneRequest`; `testT09_07_fastTypingRetainsAllTwentyCharacters` | Deterministic Linux clock verifies one final request for 20 characters. Apple UI typing test implemented, unrun locally. |
| T09-08 | `testT09_08_longQueryIsCappedBeforeRequest` | Linux regression test. |
| T09-09 | `testT09_09_clearDiscardsLateResultsAndShowsRecents` | Linux regression test. |
| T09-10 | — | Not automated: Siri dictation and iPhone keyboard input require physical Apple TV. |
| T09-11 | `testT09_11_keyboardToRowsAndVerticalFocusSections` | Apple UI test implemented, unrun: no Xcode/tvOS simulator. Keyboard return needs device confirmation. |
| T09-12 | `testT09_12_backKeepsTextResultsAndFocus` | Linux state retention covered. Tab navigation UI still needs Apple simulator. |
| T09-13 | `testT09_60_cancelledQueryDoesNotRetryAfterBackoff`; `testT09_14_reverseResponsesOnlyLatestWins` | Linux reverse-response and cancelled retry tests cover prior-task cancellation. Immediate child cancellation also covered by T09-17. |
| T09-14 | `testT09_14_reverseResponsesOnlyLatestWins` | Linux regression test. |
| T09-15 | `testT09_09_clearDiscardsLateResultsAndShowsRecents` | The T09-09 regression clears during a request, releases its late response and verifies recents stay visible. |
| T09-16 | `testT09_16_cancelledResponseIsSilent` | Linux regression test. |
| T09-17 | `testT09_17_parallelRequestsAreCancelledTogether` | Linux regression test. |
| T09-18 | `testT09_18_disappearCancelsAndResumesPendingSearch`; `testT09_18_cancelledImageStreamStopsTheTransfer` | Linux covers disappearing search tasks and cancellation of an active counted image stream. |
| T09-19 | `testT09_19_sameTermABAAndWrongResponseTermAreRejected` | Linux rejects same-text ABA stale responses and mismatched response terms. General debounce request count is covered by T09-07. |
| T09-20 | — | Not automated: arrivals while a card is focused require a tvOS UI fixture and simulator. |
| T09-21 | `testT09_21_searchBackendLatencyAndResultCounts` | Opt-in Docker benchmark compiled; not executed locally because Docker/live servers are unavailable. Cross-version artifact evidence pending. |
| T09-22 | `testT09_22_searchFindsUmlautSeedWithBothBackends` | Opt-in Docker test compiled; uses canonical Hämärä/hämä fixture/query. Not executed locally: Docker unavailable. |
| T09-23 | `testT09_23_threeItemsRequestsStartInParallelWithIndependentLimits` | Linux regression test. |
| T09-24 | `testT09_24_hintsGroupInServerOrderRetainImagesAndPageByType` | Linux regression test. |
| T09-25 | `scripts/check-m09.py` | Source check ties the production ItemsSearchBackend default to ADR-M09-1. No endpoint switch claimed. |
| T09-26 | `testT09_26_bothBackendsPassSpecialTermsAsQueryItems`; `testT09_26_sdkQueryBuilderPreservesSpecialTerms`; `testT09_26_queryEncodingRoundTripsSpecialCharactersAndSubpath` | Linux regression test. |
| T09-27 | `scripts/check-m09.py` | Source check rejects query interpolation in search paths; T09-26 tests exact URLQueryItem round trips. |
| T09-28 | `testT09_28_pagingDeduplicatesAndRetainsServerOrder`; `testT09_28_serverOrderAndLiteralMetadataArePreserved` | Linux regression test. |
| T09-29 | `testT09_29_errorAndRetry`; `testT09_29_failedSiblingIsHiddenWhileSuccessfulRowsRemain`; `testT09_29_errorShowsRetryAndSharedCoreKey` | Linux covers successful sibling rows when one fails (failed row hidden), whole-query retry, and failedRows bookkeeping. Apple retry UI test unrun. |
| T09-30 | `testT09_61_brokenItemsAreSkippedAndP1KindsAreExcluded` | T09-61 excludes Person, BoxSet and Audio from P0 results. |
| T09-31 | — | Not automated: grouped-row UI and 1080p/4K snapshots require Apple runners. |
| T09-32 | — | Not automated: hidden-empty-header layout needs Apple UI/snapshot coverage. SearchView filters empty groups in its ForEach. |
| T09-33 | `testT09_33_emptyStateUsesCatalogKey` | Apple UI catalog-key assertion implemented, unrun; snapshots need Apple runner. |
| T09-34 | `testT09_34_loadingThenEmptyAndInvalidTermClearsRows` | Linux covers loading and no results. New query clears previous groups before debounce. Snapshot portion not automated: Apple runner unavailable. |
| T09-35 | — | Not automated: poster title/year snapshots require Apple runner; year presentation remains pending. |
| T09-36 | — | Not automated: episode landscape/series/season label snapshots require Apple runner; full episode labels remain pending. |
| T09-37 | `testT09_37_backRestoresTextResultsAndSelectedCardFocus` | Partial: Apple back/focus UI test implemented, unrun. Full M07 destination integration is pending (Q9-12). |
| T09-38 | — | Not automated: M07 episode/season destination is absent on this stack (Q9-12). |
| T09-39 | — | Not automated: direct playback action awaits M07/M08 integration. |
| T09-40 | — | Not automated: row scroll/focus memory requires tvOS UI and physical remote validation. |
| T09-41 | — | Not automated: dedicated 24-card UI assertion pending. Page size is 24; there is no See more button; rows fetch further pages on scroll (Q9-16). |
| T09-42 | — | Not automated for snapshots: 1080p/4K glass review needs Apple runner. check-design-system.py enforces source surface restrictions. |
| T09-43 | `testT09_43_historyRecordsOnlyResultSelection` | Linux verifies that completion does not record a query and result selection does (canonical default for Q9-06). |
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
| T09-56 | `testT09_56_offlineSearchKeepsRecentsAndDoesNotSend` | Linux offline preflight sends no request and preserves usable recent-query text and the existing banner key. UI/device confirmation pending. |
| T09-57 | `testT09_57_serverDownKeepsContentSharedKeyAndTenSecondRecovery` | Linux covers retained content/banner, background ping scheduling and recovery with no logout. |
| T09-58 | `testT09_57_serverDownKeepsContentSharedKeyAndTenSecondRecovery` | The same regression verifies the existing blocking server-unreachable key when content is empty. Apple full-screen rendering not automated. |
| T09-59 | `testT09_59_errorsNeverSignOutExcept401`; `testT09_59_stale401EndsSessionOnceCancelsWorkAndClearsHistory`; `testT09_59_sessionClientCancelsAllRequestsAndNeverRetries401`; `testT09_59_bothBackendsPropagateEveryFailureWithoutRetry`; `testT09_59_streamingImage401IsNotHiddenByItsBody` | Linux covers stale 401, token/history cleanup, one session-expiry transition, cancellation of scoped work and no retry. Oversized 401 body cannot hide auth failure. |
| T09-60 | `testT09_60_gatewayFailuresRetryTwiceWithSharedBackoff`; `testT09_60_cancelledQueryDoesNotRetryAfterBackoff` | Linux verifies both retry delays for 502/503/504 and no retry after query cancellation. |
| T09-61 | `testT09_61_brokenItemsAreSkippedAndP1KindsAreExcluded` | Linux search fixture skips one broken item and retains valid P0 items. |
| T09-62 | — | Not automated: LAN timing on A15/oldest hardware and a 10,000-item fixture are unavailable. |
| T09-63 | — | Not automated: 60 fps/hitch and P11 memory metrics require Apple hardware/Instruments. |
| T09-64 | `testT09_64_metadataIsLiteralThroughViewModel`; `testT09_64_viewModelBoundsNamesAndOverviewByGraphemes`; `testT09_64_allLimitsCountGraphemesAfterCleaning`; `testT09_64_literalMediaAndSanitizedDisplayNames` | Linux verifies constants and below/at/above grapheme boundaries, literal media tags/entities, controls/bidi, M04-sanitized ServerName/PublicUser and literal DTO/view-model paths. Taglines/genres are not rendered in this search destination; their constants are locked by test. Layout snapshots need Apple runner. |
| T09-65 | `testT09_65_imageCacheUsesStableSHA256TupleAsActualFilename`; `testT09_65_exactStreamBoundaryIsAccepted`; `testT09_65_imageURLHasNoCredentialAndRequestCarriesAuthorization`; `scripts/check-m09.py` | Linux covers header-only auth, SHA-256 tuple filename/cache restart and exact byte boundary. Production request carries the streaming cap through CoreNetworking; source check bans full-bitmap APIs. |
| T09-66 | `testT09_66_queriesNeverReachLogs`; `testT09_66_transportFailureLogsNoSearchTextOrRawImageURL` | Linux captured logs contain no private query or raw image URL. Search signpost uses the fixed search.results event. |
| T09-67 | `scripts/scan_benchmark_artifacts.py` (manual) | Main's retained integration workflow does not scan or upload search benchmarks. Scan the complete three-version JSON set before manual retention; automated artifact evidence remains pending. |
| T09-68 | `testT09_68_thumbnailOptionsUseTheDisplayedPixelSizeOnAllPlatforms`; `testT09_68_decodeDownsamplesOffMainThread`; `scripts/check-m09.py` | Portable production option dictionary is tested on Linux. Actual off-main ImageIO downsampling test implemented, unrun locally because ImageIO is unavailable. |
| T09-69 | `testT09_69_oversizedImagesRejectedBeforeCachingOrDecode`; `testT09_69_oversizedStreamsAreCancelledWithoutReadingTheTail` | Linux real URLSession data-delegate fixture rejects missing/lying length at the first excess 64 KiB chunk, stops the tail, and verifies loader/cache rejection. Physical-device placeholder/focus and decompression-bomb P11 memory measurement are not automated: Apple hardware unavailable. |


## Validation

2026-10-28, stack base v5: merged main `45e21b4`, including squash-merged M04 `b0f0f22` and HLS auth `924888d`, then M05 `d2d780b`. Main's workflows, project.yml and app Info.plists are retained exactly. Main's authentication surface is preserved with the M09 search tab, using M05's authentication source-check exception. The existing native search input, image EOF fixture and actor-isolation fixes are preserved; no tests or assertions changed in this update.

With `LD_LIBRARY_PATH=~/.local/lib/swiftcompat` and the swiftly environment sourced, `bash scripts/coverage-gate.sh` passed: **487 tests**, **9 opt-in live-server skips**, no failures, **92.40%** line coverage (8170/8842). Strict `swift-format lint --recursive --strict Package.swift Sources Tests ../../Apps` and all requested design-system, catalog, debug-only-string and ci-grep checks passed. Apple builds/UI tests and live-server benchmarks remain unverified locally. Main's project does not include the M05 app unit/snapshot test targets, and its integration workflow does not retain search benchmark artifacts.

2026-10-27, Swift 6.4.1 on Linux: the exact required `swift build && swift test && swift-format lint --recursive --strict Package.swift Sources Tests ../../Apps` command passed. The suite contains **381 tests**, with **7 opt-in live-server tests skipped** and no failures. Both sides of the integration merge compile. The package has 60 M09 test functions in source, including two Docker tests and one Apple-only ImageIO test; 57 M09 tests execute on Linux.

The required root checks passed: `check-design-system.py`, `check-string-catalogs.py` (both catalogs), `check-debug-only-strings.py`, and `ci-grep.sh`. The latter now invokes `check-m09.py`. Shell syntax and Python compilation passed. Temporary negative probes confirmed that `check-m09.py` rejects each forbidden image API; those probes were removed. `cmp` confirms the copied canonical plan is byte-for-byte identical to the supplied file.

`bash scripts/docker-integration.sh 10.10.7` reports that Docker is unavailable. No live-server performance result, Apple UI/snapshot result, actual ImageIO decode result, or physical-device memory/timing result is claimed. Info.plists, entitlements, project.yml and workflows were not edited during this follow-up.

## Owner decisions

Q6-20 is resolved: Continue Watching and Next Up are separate M06 rows. Q7-25 is resolved: M07 shows one season at a time with a season picker. This branch contains neither feature implementation; no matching TODO markers remain. Search destination integration is tracked under Q9-12.
