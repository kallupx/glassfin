# M07 reconstructed implementation test plan

Derived from `07-library-detail.md` P0, M05 focus/navigation requirements, binding spec PR #18 S6.1/S6.6, and M02 v1.3.4. These are newly reconstructed IDs, not a claim to reproduce the lost Testaaja numbering. Tests use English code/comments and compare localization keys for user-facing messages.

**L**: Linux SwiftPM. **A**: Apple SDK unit test. **U**: tvOS XCUITest, DEBUG fixtures, screenshot attached and optionally exported through `GLASSFIN_SCREENSHOT_DIR`. **M**: manual hardware/review. L tests were run locally; A/U are authored but cannot run in this Linux workspace. Existing Docker integration tests skip without their generated environment/credentials.

| ID | Requirement | Test / status |
| --- | --- | --- |
| T07-01 | Listing endpoint, movie type, page 50, recursive, sort/direction, combined filters, genre/year, user data, total, fields; Filters2 | L `T07LibraryTests.testT07_01_browseRequestIncludesPagingSortFiltersAndUserData` |
| T07-02 | All five sorts and choices isolated by server/user/library | L `testT07_02_choicesPersistPerServerUserAndLibraryAndAllSortsMap` |
| T07-03 | 2,000-item paging, ten remaining, concurrent prefetch suppression | L `testT07_03_pagesTwoThousandItemsAtTenRemainingWithoutDuplicateRequests` |
| T07-04 | Query-specific response caching and short-page termination | L `testT07_04_cacheIncludesTheQueryAndUserAndStopsAtShortPage` |
| T07-05 | Malformed records consume server offsets; duplicate IDs do not duplicate cards | L `testT07_05_malformedRecordsAdvanceServerOffsetAndDuplicatesAreRemoved` |
| T07-06 | Focus rule 1; resume S2E5, selected season 2, initial episode scroll; specials last | L `testT07_06_seriesOpensAtInProgressSeasonTwoEpisodeFiveAndSpecialsLast`; U `testT07_06_playIsDefaultAndInProgressEpisodeIsVisible` (PNG) |
| T07-07 | Focus rule 2; season changes on focus, debounce 200 ms, cancellation, focus stays in picker | L `testT07_07_seasonFocusDebouncesAndLatestSelectionWinsWithoutMovingToEpisodes`; U `testT07_07_focusOnSeasonChangesRowWithoutSelectingOrLeavingPicker` (PNG) |
| T07-08 | Focus rule 3; down selects first unplayed, or first if all played | L `testT07_08_downTargetsFirstUnplayedAndUpReturnsToSelectedSeason`; U `testT07_08_downFromSeasonTargetsThatSeasonsFirstUnplayedEpisode` (PNG) |
| T07-09 | Focus rule 5; playback dismissal retains episode or advances after completion | L `testT07_09_playbackReturnKeepsEpisodeOrAdvancesToNextUnplayed`, `testT07_09_finishedLastEpisodeCanAdvanceToTheNextSeason`; U `testT07_09_playbackReturnHookRestoresSameEpisode`, `testT07_09_finishedPlaybackReturnHookMovesToNextEpisode` (PNGs). Actual AVPlayer dismissal blocked: M08 is unmerged. |
| T07-10 | Focus rule 6; selected overview updates and never receives focus | L `testT07_10_selectedOverviewFollowsFocusedEpisodeAsLiteralText`; U `testT07_10_episodeOverviewNeverReceivesFocus` (PNG) |
| T07-11 | Failed season switch retains prior content and correct season label | L `testT07_11_episodeFailureKeepsPreviousSeasonAndContent` |
| T07-12 | Played mutation is optimistic; failure rolls back and exposes a message key | L `testT07_12_playedIsOptimisticAndFailureRollsBackAndShowsAKey` |
| T07-13 | Favorite/played POST and DELETE toggle paths | L `testT07_13_favoriteAndPlayedTogglesUsePOSTAndDELETE` |
| T07-14 | Movie, series, season, episode detail; card navigation | L `testT07_14_movieSeriesSeasonAndEpisodeDetailRequests`; U `testT07_14_episodeCardNavigatesToEpisodeDetail` (PNG) |
| T07-15 | Back restores same grid card and scroll position | U `testT07_15_detailBackRestoresTheSameGridCardAndScrollPosition` (PNG); authored, blocked locally on Apple SDK |
| T07-16 | Any authenticated 401 cancels siblings, signs in once, uses session-expired key, never retries | L `testT07_16_401CancelsAllRequestsEndsSessionOnceAndNeverRetries` |
| T07-17 | Resolution, HDR10, DV profile 8, DTS-HD MA 7.1 technical metadata | L `T07MetadataTests.testT07_17_technicalFixtureShowsHDRDVAndLosslessAudio` (realistic codec/profile pair) |
| T07-18 | Server down mid-browse: content, banner, automatic ten-second recovery, retry offset; filter failure | L `testT07_18_downMidBrowseKeepsContentBannerAndTenSecondRecovery`, `testT07_18_filterFailureKeepsPreviousQueryContent`, `testT07_18_automaticTenSecondPingRecoversAndKeepsContent`; U `testT07_18_serverDownMidBrowseKeepsCardsAndShowsBanner` (PNG) |
| T07-19 | No content: shared server-down key and blocking error; preserve sign-in | L `testT07_19_downWithoutContentUsesTheExistingServerDownKey`; UI uses M05 ErrorStateView with core message override |
| T07-20 | Literal tags/entities/Markdown, controls/bidi removed across metadata | L `T07MetadataTests.testT07_20_metadataKeepsMarkupLiteralAndStripsControlsAndBidi`; existing Q4-16/S4.7 regression tests updated to binding S6.1 |
| T07-21 | Clean before grapheme truncation: overview, tagline count/length, genre count/length, names, people, studios | L `testT07_21_limitsCountExtendedGraphemesAfterCleaning`; family emoji and combining marks; tests reference MetadataPolicy |
| T07-22 | Image URL has no credential parameter; Authorization present; base URL/redirect credential-query rejection | L `T07ImageTests.testT07_22_imageURLHasNoCredentialQueryAndRequestUsesAuthorization`, `testT07_22_imageRequestsRejectCredentialParametersIncludingBaseURLAndRedirects` |
| T07-23 | Stable SHA-256 tuple key; server/type/tag/size change the digest | L `testT07_23_cacheKeyIsStableSHA256OfTheWholeTuple` |
| T07-24 | Image >20 MB rejected by transport, loader, disk; exact hashed filename, disk reuse | L `T07ImageTests.testT07_24_HTTPClientRejectsOversizeImage`; `T07SecurityStateTests.testT07_24_imageLoaderAndDiskRejectOversizeAndUseTheExactHashFilename` |
| T07-25 | ImageIO downsampling to display pixels off main actor | A `T07ArtworkTests.testT07_25_artworkIsDownsampledToDisplayedPixels`; detached decoding also reviewed in source. Blocked locally: no ImageIO/Apple SDK. |
| T07-26 | View-model sanitation including protocol mocks; resume/start-over, track intent, similar items | L `testT07_26_viewModelsSanitizeProtocolValuesAndDetailCanResumeAndStartOver` |
| T07-27 | Five direct library tabs, overflow, playback-intent boundary | L `testT07_27_directTabsAndOverflowAndSanitizedLibraryNames` |
| T07-28 | Late result cannot overwrite a newer query | L `testT07_28_staleQueryResponseCannotReplaceNewQuery` |
| T07-29 | 403/404/500/timeout/network/TLS/decoding/cancellation never sign out; cancellation hidden | L `testT07_29_non401ErrorsKeepSessionAndCancellationIsNotPresented` |
| T07-30 | Focus rule 4; up returns to selected season | L T07-08; U `testT07_30_upFromEpisodeReturnsToSelectedSeason` (PNG) |
| T07-31 | 60 fps, hitch/memory budgets, 2,000-item grid on A8/A12/A15 | M; blocked locally: physical Apple TV and Instruments required. Linux paging tests are functional evidence, not frame-rate measurements. |
| T07-32 | Live Jellyfin 10.10/10.11/12.x endpoint compatibility and mutation/image authentication | Blocked locally: Docker/seeded server credentials unavailable. Existing `scripts/docker-integration.sh` and IntegrationTests remain unchanged; dedicated M07 live matrix follow-up is still required. |
| T07-33 | Collections/person linking/alphabet jump/version choice/trailers/continuous season row/iOS layout | Deferred P1; outside requested P0 scope |
| T07-34 | Accessibility, glass budget, visual layout 1080p/4K, Reduce Motion/Transparency/Contrast | Source checks: `check-design-system.py`, `check-string-catalogs.py`, `ci-grep.sh`; M visual review on Apple SDK/hardware remains blocked locally. Uses M05 tokens/components, six columns, lazy content rows, at most action bar + season picker containers. |
| T07-35 | Disappear cancels active paging; cancelled result is not rendered | L `testT07_35_disappearCancelsTheActivePageAndIgnoresItsResult` |

| T07-36 | UserDataStore event refresh and recovery retain selected season and episode focus | L `testT07_36_storeRefreshAndReloadPreserveEpisodeFocusAndSeason`; visible views observe AppState user-data generation |

## Run

From the repository root:

```bash
export LD_LIBRARY_PATH=~/.local/lib/swiftcompat
source ~/.local/share/swiftly/env.sh
cd Packages/GlassfinCore
swift build
swift test
swift-format lint --recursive --strict Package.swift Sources Tests ../../Apps
cd ../..
python3 scripts/check-design-system.py
python3 scripts/check-string-catalogs.py
python3 scripts/check-debug-only-strings.py
bash scripts/ci-grep.sh
```

On macOS after the separately owned M05 compile fixes land:

```bash
xcodegen generate
xcodebuild test -scheme Glassfin-tvOS \
  -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
  -only-testing:Glassfin-tvOSTests/T07ArtworkTests \
  -only-testing:Glassfin-tvOSUITests/T07LibraryUITests \
  CODE_SIGNING_ALLOWED=NO
```

`project.yml` already includes the new shared test files in the existing targets and schemes. DEBUG launch examples are `-uitest-library grid`, `-uitest-library series`, `-uitest-library down`, `-uitest-library series-return`, and `-uitest-library series-finished`. All fixtures and flags compile out of Release. The last two exercise integration hooks and do not instantiate a player.

## Local validation result

Linux validation passed: `swift build`, `swift test` (261 passed, including 34 M07 cases; two existing Docker cases skipped), and the exact strict swift-format command above. All requested design-system, catalog, DEBUG-only-string and CI grep checks passed. Changed SwiftUI sources passed parser validation. Ten tvOS UI tests and one ImageIO unit test are wired into the existing Apple targets but were not executed here. No screenshots or device-performance results are claimed.

The M05 files explicitly excluded by the task (`Demo.swift`, `GlassChrome.swift`, `Shell.swift`) and all CI workflows, plists, signing, entitlements, and bundle identifiers are unchanged.
