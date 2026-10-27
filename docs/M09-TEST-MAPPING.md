# M09 canonical test mapping

The only binding plan is [spec/TESTPLAN-M09.md](../spec/TESTPLAN-M09.md), copied verbatim from the supplied plan. Test names and comments use its IDs. Multiple tests may exercise the same canonical scenario. No additional IDs are allocated.

Linux tests run in GlassfinCore. Apple UI and ImageIO tests are present but cannot run on this Linux host. “Not automated” records missing automation or environment-dependent acceptance evidence, not a passing result.

| ID | Automated entry points | Scope / not automated |
|---|---|---|
| T09-01 | — | Not automated: initial field focus and populated recents need an Apple UI test. |
| T09-02 | `testT09_02_debounceAndCancellationBeforeRequest` | Linux regression test. |
| T09-03 | — | Not automated separately yet: eligibility is exercised in the CJK policy test. |
| T09-04 | — | Not automated separately yet: two-character eligibility is exercised in the CJK policy test. |
| T09-05 | `testT09_05_minimumLengthAndCJK` | Linux policy coverage; separate request eligibility tests will be added. |
| T09-06 | — | Not automated separately yet: whitespace eligibility is exercised in the CJK policy test. |
| T09-07 | `testT09_07_fastTypingRetainsAllTwentyCharacters` | Apple UI typing test implemented, unrun here; request-count assertion needs a deterministic clock test. |
| T09-08 | — | Not automated: query length is an unresolved policy; current input is uncapped (Q9-03). |
| T09-09 | — | Not automated: a dedicated clear-during-request regression is pending. |
| T09-10 | — | Not automated: Siri dictation and iPhone keyboard require physical Apple TV. |
| T09-11 | `testT09_11_keyboardToRowsAndVerticalFocusSections` | Apple UI test implemented, unrun: no Xcode/tvOS simulator; keyboard return needs device confirmation. |
| T09-12 | `testT09_12_backKeepsTextResultsAndFocus` | Linux state retention covered; tab navigation UI requires Apple simulator. |
| T09-13 | — | Not automated separately: cancellation is observed after reverse responses; immediate cancellation needs a dedicated test. |
| T09-14 | `testT09_14_reverseResponsesOnlyLatestWins` | Linux regression test. |
| T09-15 | — | Not automated: dedicated stale response after clear regression pending. |
| T09-16 | — | Not automated: dedicated cancelled-error suppression regression pending. |
| T09-17 | — | Not automated: cancellation of all three child requests needs a transport gate test. |
| T09-18 | `testT09_18_disappearCancelsAndResumesPendingSearch` | Linux regression test. |
| T09-19 | `testT09_19_sameTermABAAndWrongResponseTermAreRejected` | Linux rejects same-text ABA stale results; debounce request count for this sequence is pending. |
| T09-20 | — | Not automated: response arrival during focus requires tvOS UI fixture and simulator. |
| T09-21 | `testT09_21_searchBackendLatencyAndResultCounts` | Opt-in Docker test compiled; skipped locally because Docker/live servers are unavailable. Artifact retention requires CI run. |
| T09-22 | `testT09_22_searchFindsUmlautSeedWithBothBackends` | Opt-in Docker test compiled; skipped locally. Existing umlaut seed differs from canonical Hämärä/hämä; align in follow-up. |
| T09-23 | `testT09_23_threeItemsRequestsStartInParallelWithIndependentLimits` | Linux regression test. |
| T09-24 | `testT09_24_hintsGroupInServerOrderRetainImagesAndPageByType` | Linux regression test. |
| T09-25 | — | Not automated: ADR/default factory source check pending. |
| T09-26 | `testT09_26_bothBackendsPassSpecialTermsAsQueryItems`; `testT09_26_sdkQueryBuilderPreservesSpecialTerms`; `testT09_26_queryEncodingRoundTripsSpecialCharactersAndSubpath` | Linux regression test. |
| T09-27 | — | Not automated: URL interpolation source check pending. |
| T09-28 | `testT09_28_pagingDeduplicatesAndRetainsServerOrder`; `testT09_28_serverOrderAndLiteralMetadataArePreserved` | Linux regression test. |
| T09-29 | `testT09_29_errorAndRetry`; `testT09_29_errorShowsRetryAndSharedCoreKey` | Partial: whole-request error/retry covered; successful sibling rows currently fail together (Q9-05). |
| T09-30 | — | Not automated separately: P0 SearchKind has only movies, series, episodes; exclusion regression pending. |
| T09-31 | — | Not automated: grouped-row UI and 1080p/4K snapshots require Apple runners. |
| T09-32 | — | Not automated: hidden empty row requires Apple UI/snapshot; state regression pending. |
| T09-33 | `testT09_33_emptyStateUsesCatalogKey` | Apple UI key assertion implemented, unrun; snapshot requires Apple runner. |
| T09-34 | `testT09_34_loadingThenEmptyAndInvalidTermClearsRows` | Linux loading/empty state covered; old content clearing and snapshots pending. |
| T09-35 | — | Not automated: poster title/year snapshots require Apple runner; year presentation is pending. |
| T09-36 | — | Not automated: episode landscape/series/season label snapshots require Apple runner; labels are pending. |
| T09-37 | `testT09_37_backRestoresTextResultsAndSelectedCardFocus` | Partial: Apple back/focus UI test implemented, unrun; full M07 destination awaits dependency integration (Q9-12). |
| T09-38 | — | Not automated: M07 episode/season destination is absent on this stack (Q9-12). |
| T09-39 | — | Not automated: direct playback action awaits M07/M08 integration. |
| T09-40 | — | Not automated: physical remote focus restoration and row scroll need tvOS UI/device validation. |
| T09-41 | — | Not automated: dedicated 24-card assertion pending; automatic pagination is current behavior (Q9-16). |
| T09-42 | — | Not automated: 1080p/4K glass review needs snapshots; check-design-system.py enforces surface restrictions. |
| T09-43 | — | Not automated: current policy records completed queries; canonical assumption records selection (Q9-06). |
| T09-44 | `testT09_44_historyCapRecencyAndDeduplication` | Linux cap test also checks recency and exact-text deduplication. |
| T09-45 | — | Not automated separately: checked by history-cap test. |
| T09-46 | — | Not automated: exact-text deduplication differs from the canonical case-insensitive assumption (Q9-07). |
| T09-47 | `testT09_47_historyIsScopedByBothServerAndUserAndSurvivesRestart` | Linux regression test. |
| T09-48 | — | Not automated separately: storage location checked by query-content test; Apple backup exclusion needs resource-value assertion. |
| T09-49 | `testT09_49_onlyQueryTextInApplicationSupportNoPreferencesOrKeychainWrites` | Linux regression test. |
| T09-50 | — | Not automated separately: view-model and HTTP log capture cover query privacy; store read/write capture pending. |
| T09-51 | `testT09_51_signOutDeletesOnlyThatUsersHistory` | Linux regression test. |
| T09-52 | `testT09_52_serverRemovalDeletesAllItsUsersOnly` | Linux regression test. |
| T09-53 | `testT09_53_userClearRemovesDiskHistoryAndViewState`; `testT09_53_recentSearchesAreUserClearable` | Linux regression test. |
| T09-54 | — | Not automated: source check for cloud/preferences/network dependencies pending. |
| T09-55 | — | Not automated: persistence covered in scoped-store test; corruption and oversize recovery pending. |
| T09-56 | — | Not automated: offline preflight and usable recents require regression/UI test (Q9-09). |
| T09-57 | `testT09_57_serverDownKeepsContentSharedKeyAndTenSecondRecovery` | Linux test also covers empty-state shared key and ping recovery. |
| T09-58 | — | Not automated separately: no-content shared key covered by server-down test; UI environment unavailable. |
| T09-59 | `testT09_59_errorsNeverSignOutExcept401`; `testT09_59_stale401EndsSessionOnceCancelsWorkAndClearsHistory`; `testT09_59_sessionClientCancelsAllRequestsAndNeverRetries401`; `testT09_59_bothBackendsPropagateEveryFailureWithoutRetry` | Linux session expiry tests cover stale 401, scope cancellation, token/history cleanup and no retry; other errors preserve session. |
| T09-60 | — | Not automated in M09: shared retry policy exists, current-query retry cancellation needs dedicated coverage. |
| T09-61 | — | Not automated in M09: shared resilient DTO decoding exists; search fixture regression pending. |
| T09-62 | — | Not automated: LAN timing on A15/oldest hardware and 10,000-item fixture unavailable. |
| T09-63 | — | Not automated: 60 fps/hitch and P11 memory metrics require Apple hardware/Instruments. |
| T09-64 | `testT09_64_metadataIsLiteralThroughViewModel`; `testT09_64_viewModelBoundsNamesAndOverviewByGraphemes`; `testT09_64_allLimitsCountGraphemesAfterCleaning` | Linux grapheme/literal metadata coverage; all-platform boundary expansion pending. Layout snapshots require Apple runner. |
| T09-65 | `testT09_65_imageCacheUsesStableSHA256TupleAsActualFilename`; `testT09_65_imageURLHasNoCredentialAndRequestCarriesAuthorization` | Linux header/hash/cache coverage; streaming cap is addressed by T09-69 in follow-up. |
| T09-66 | `testT09_66_queriesNeverReachLogs`; `testT09_66_transportFailureLogsNoSearchTextOrRawImageURL` | Linux captured logs contain no private query/image URL; static signpost review pending. |
| T09-67 | — | Not automated: artifact scanner exists; a complete M09 CI artifact set requires CI execution. |
| T09-68 | `testT09_68_decodeDownsamplesOffMainThread` | Apple ImageIO test implemented, unrun (Linux has no ImageIO). Portable option-dictionary coverage pending. |
| T09-69 | `testT09_69_oversizedImagesRejectedBeforeCachingOrDecode` | Partial: cache/loader post-download size rejection covered; streaming abort tests and device decompression-bomb/memory check pending. |


## Validation

Merge resolution: `swift build --build-tests` passed on Linux, retaining both sides of the integration suite. Full follow-up validation will be recorded after the pipeline changes.

## Owner decisions

Q6-20 is resolved: Continue Watching and Next Up are separate M06 rows. Q7-25 is resolved: M07 shows one season at a time with a season picker. This branch contains neither feature implementation; there are no matching TODO markers or unresolved entries to remove. Search destination integration remains tracked under Q9-12.
