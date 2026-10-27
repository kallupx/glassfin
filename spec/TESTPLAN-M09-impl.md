# M09 implementation test mapping

Date: 2026-10-27. The original M09 test plan was unavailable; these IDs are derived from SR1–SR5, the acceptance criteria, spec PR #18 and S6.1/S6.5/S6.6/S6.7. T09-22 retains the requested umlaut integration identifier.

L = Linux Swift package test; A = Apple package test; U = XCUITest; I = Docker integration; M = manual. Unit assertions use enum states/catalog keys. AuthCopy's English identifiers are catalog keys, including the existing shared server-down key. U tests live in `Apps/Shared/UITests/T09SearchUITests.swift`, automatically included by the existing whole-directory source entries in **both** UI-test targets/schemes in project.yml; no project generation/signing changes are needed.

| ID | Requirement | Test name / evidence | Environment / local status |
|---|---|---|---|
| T09-01 | Default /Items x3, parallel and independent row limits | `testT09_01_threeItemsRequestsStartInParallelWithIndependentLimits`; default construction in SearchFeature | L passed |
| T09-02 | 300 ms debounce, cancellation before dispatch | `testT09_02_debounceAndCancellationBeforeRequest` | L passed |
| T09-03 | Reverse responses and cancellation after dispatch | `testT09_03_reverseResponsesOnlyLatestWins` (non-cooperative backend) | L passed |
| T09-04 | Native searchable preserves all 20 rapidly typed characters | `testT09_04_fastTypingRetainsAllTwentyCharacters` | U implemented; blocked locally: no Xcode |
| T09-05 | Minimum two non-CJK characters | `testT09_05_andT09_06_minimumLengthAndCJK` | L passed |
| T09-06 | Single-character CJK | `testT09_05_andT09_06_minimumLengthAndCJK` | L passed |
| T09-07 | &, #, ä, 日本 and query injection characters, SDK adapter, subpath and literal plus encoding | `testT09_07_bothBackendsPassSpecialTermsAsQueryItems`, `testT09_07_queryEncodingRoundTripsSpecialCharactersAndSubpath`, `testT09_07_sdkQueryBuilderPreservesSpecialTerms` | L passed; generated SDK branch needs A |
| T09-08 | Loading, zero results, clearing invalid input | `testT09_08_loadingThenEmptyAndInvalidTermClearsRows`; `testT09_08_emptyStateUsesCatalogKey` | L passed; U implemented/unrun |
| T09-09 | Failure and explicit retry | `testT09_09_errorAndRetry`; `testT09_09_errorShowsRetryAndSharedCoreKey` | L passed; U implemented/unrun |
| T09-10 | Back keeps text, results and focus | `testT09_10_backKeepsTextResultsAndFocus`; `testT09_10_backRestoresTextResultsAndSelectedCardFocus` | L passed; U implemented/unrun |
| T09-11 | Keyboard to grouped focusSection rows, up/down movement | `testT09_11_keyboardToRowsAndVerticalFocusSections` | tvOS U implemented; blocked locally: no simulator |
| T09-12 | Row paging, no duplicate fetches/items | `testT09_12_pagingDeduplicatesAndRetainsServerOrder` | L passed |
| T09-13 | Cancel on disappear, preserve completed state, resume incomplete search | `testT09_13_disappearCancelsAndResumesPendingSearch`; T09-10 | L passed |
| T09-14 | Preserve server result order and literal DTO metadata | `testT09_14_serverOrderAndLiteralMetadataArePreserved` | L passed |
| T09-15 | 401/403/404/500/timeout/decoding behavior, session survives non-401 | `testT09_15_bothBackendsPropagateEveryFailureWithoutRetry`, `testT09_15_errorsNeverSignOutExcept401` | L passed |
| T09-16 | Bidi/control removal, literal HTML/entities/Markdown through view model | `testT09_16_metadataIsLiteralThroughViewModel` | L passed; Text(verbatim:) source review |
| T09-17 | Shared caps, grapheme boundaries after cleaning | `testT09_17_allLimitsCountGraphemesAfterCleaning`, `testT09_17_viewModelBoundsNamesAndOverviewByGraphemes` | L passed; identical MetadataPolicy checked against M06/M07 |
| T09-18 | Image request Authorization header, no credential URL, URLCache disabled | `testT09_18_imageURLHasNoCredentialAndRequestCarriesAuthorization` | L passed |
| T09-19 | Stable SHA-256 tuple key, actual disk filename, restart | `testT09_19_imageCacheUsesStableSHA256TupleAsActualFilename` | L passed |
| T09-20 | Reject >MetadataPolicy.imageMaxBytes before disk/decode; exact boundary allowed | `testT09_20_oversizedImagesRejectedBeforeCachingOrDecode`; T09-31 decoder guard | L passed; A decoder check unrun |
| T09-21 | Compare endpoint latency, row counts and image tags on 5,000 items, retain evidence | `testT09_21_searchBackendLatencyAndResultCounts`; ADR-M09-1; integration.yml artifact | I implemented/compiled; skipped locally: Docker absent |
| T09-22 | Live search finds dummy item containing ä via both endpoints | `testT09_22_searchFindsUmlautSeedWithBothBackends`; search-seed.json | I implemented/compiled; skipped locally: Docker absent |
| T09-23 | History isolated by server AND user, survives relaunch | `testT09_23_historyIsScopedByBothServerAndUserAndSurvivesRestart` | L passed |
| T09-24 | History max 20, most recent first, deduplicated | `testT09_24_historyCapRecencyAndDeduplication` | L passed |
| T09-25 | Only query text in Application Support; never log query text/raw image URLs | `testT09_25_onlyQueryTextInApplicationSupportNoPreferencesOrKeychainWrites`, `testT09_25_queriesNeverReachLogs`, `testT09_25_transportFailureLogsNoSearchTextOrRawImageURL` | L passed; store has no preferences/Keychain/logger dependency |
| T09-26 | Sign-out and authenticated expiry delete only that user's history | `testT09_26_signOutDeletesOnlyThatUsersHistory` | L passed |
| T09-27 | Server removal deletes all its users' history, leaves other servers | `testT09_27_serverRemovalDeletesAllItsUsersOnly` | L passed |
| T09-28 | User can clear history in search UI and on disk | `testT09_28_userClearRemovesDiskHistoryAndViewState`; `testT09_28_recentSearchesAreUserClearable` | L passed; U implemented/unrun |
| T09-29 | Stale 401 signs in once, cancels all content/image/detail work, no retry | `testT09_29_stale401EndsSessionOnceCancelsWorkAndClearsHistory`, `testT09_29_sessionClientCancelsAllRequestsAndNeverRetries401` | L passed |
| T09-30 | Server-down preserves content/banner; blocking shared key only when empty; 10 s recovery | `testT09_30_serverDownKeepsContentSharedKeyAndTenSecondRecovery` | L passed; existing M02 ping scheduler regression also retained |
| T09-31 | Actual ImageIO decode off main thread, 128×96 → 32×24 | `testT09_31_decodeDownsamplesOffMainThread` | A implemented; blocked locally: no ImageIO |
| T09-32 | Hints alternative groups without sorting, keeps image tags, pages by type | `testT09_32_hintsGroupInServerOrderRetainImagesAndPageByType` | L passed |
| T09-33 | Same-text ABA race and response-term mismatch | `testT09_33_sameTermABAAndWrongResponseTermAreRejected` | L passed |
| T09-34 | P10 ≤500 ms after debounce on LAN | Manual: run 5,000-item library from Apple TV on LAN; inspect search.results signposts, record device/server/version and first rendered results | M pending: no Apple TV/LAN server available; Docker endpoint timing alone cannot establish this |

## Commands

```sh
export LD_LIBRARY_PATH=~/.local/lib/swiftcompat
source ~/.local/share/swiftly/env.sh
cd Packages/GlassfinCore
swift build
swift test
swift test --filter T09
swift-format lint --recursive --strict Package.swift Sources Tests ../../Apps
cd ../..
python3 scripts/check-design-system.py
python3 scripts/check-string-catalogs.py
python3 scripts/check-debug-only-strings.py
bash scripts/ci-grep.sh
bash scripts/docker-integration.sh
```

On macOS, generate/run the existing tvOS/iOS schemes with `scripts/macos-ci.sh tvOS` / `scripts/macos-ci.sh iOS`. Search UI tests launch an in-process DEBUG protocol fixture with `-uitest-search -uitest-mock-server -uitest-reset`; `-uitest-search-empty` and `-uitest-search-error` select the failure fixtures. The production auth home now exposes a semantic Search tab. All flags/fixtures remain inside DEBUG guards.

Manual follow-up: dictation and iPhone keyboard input, VoiceOver labels, Reduce Transparency/Reduce Motion, physical Siri Remote focus movement and scroll restoration. These inherit M05 component behavior but need real-device review. M05's known Demo/GlassChrome/Shell compile failures are owned by the separate fix branch; those files are untouched.

## Local validation record

2026-10-27, Swift 6.4.1 on Linux: `swift build` passed; the full `swift test` run passed **261 tests**, with four opt-in live-server tests skipped (T01-20, T01-30, T09-21, T09-22). The passing set contains **34 M09 test functions**. Strict recursive swift-format lint, design-system checks, both string catalogs, DEBUG-only string checks, `ci-grep.sh`, shell syntax and Python compilation passed. MetadataPolicy is byte-for-byte identical to the M06 and M07 copies. The seed smoke check validated exactly 5,000 items, hard links, an umlaut title and a decodable poster. No Apple test or live-server timing result is claimed.
