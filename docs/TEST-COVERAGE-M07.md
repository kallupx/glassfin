# M07 canonical coverage

`spec/TESTPLAN-M07.md` is copied verbatim from `/workspace/jellyfin-tvos/test/TESTPLAN-M07.md`.
It is the only M07 test plan. The table below maps its IDs to implementation
evidence; it does not redefine the scenarios. Test names use `testT07_NN_` and
comments cite the matching ID. Extra assertions under an ID are regression
coverage, not additional plan IDs.

L = Linux package tests; A = authored Apple tests, not executed on Linux;
K = source checks. A partial entry explicitly identifies the part not automated.
The final merged module spec takes precedence over older focus wording in the
plan: initial focus is Play/Resume, Down targets the first unplayed episode,
and finishing playback may advance focus. The canonical file is unchanged.

| ID | Evidence and automation limits |
| --- | --- |
| T07-01 | Partial L: `T07LibraryTests` covers library tabs and movie query fields with saved choices. Default request needs a dedicated assertion. |
| T07-02 | Partial L: `testT07_13_choicesPersistPerServerUserAndLibraryAndAllSortsMap` checks the Series type; default TV request not automated yet. |
| T07-03 | Not automated: six-column poster layout needs Apple snapshot artifacts at 1080p/4K. |
| T07-04 | A: `testT07_19_detailBackRestoresTheSameGridCardAndScrollPosition`; initial grid focus needs Apple verification. |
| T07-05 | L: `testT07_05_pagesTwoThousandItemsAtTenRemainingWithoutDuplicateRequests`; stable focus requires Apple UI execution. |
| T07-06 | Partial L: concurrent threshold calls in T07-05; `testT07_06_disappearCancelsTheActivePageAndIgnoresItsResult`. A gated repeated-threshold assertion remains. |
| T07-07 | L: `testT07_07_cacheIncludesTheQueryAndUserAndStopsAtShortPage`, T07-05 and T07-71 check terminal paging. |
| T07-08 | Not automated: current fixture exercises 2,000 items; 5,000-item memory and frame-rate measurements require Instruments/hardware. |
| T07-09 | Partial L: all sort queries reset in T07-07; `testT07_09_staleQueryResponseCannotReplaceNewQuery`. Focus and exact release-date contract need follow-up. |
| T07-10 | Not automated: ascending/descending and hidden random order control need dedicated assertions; Q7-01 remains open. |
| T07-11 | Partial L: `testT07_11_browseRequestIncludesPagingSortFiltersAndUserData` checks unplayed/favorite parameters. Watched filter lacks coverage. |
| T07-12 | Partial L: T07-11 checks Filters2 genres/years and selected query values. Menu rendering needs Apple tests. |
| T07-13 | L: `testT07_13_choicesPersistPerServerUserAndLibraryAndAllSortsMap`; uses the same settings namespace after store recreation. Q7-14 remains open. |
| T07-14 | Not automated: plural catalog forms and count rendering require dedicated catalog/UI assertions (Q7-13). |
| T07-15 | Not automated: empty filter state and default focus require UI/snapshot tests (Q7-02). |
| T07-16 | Not automated: empty-library snapshot requires Apple SDK (Q7-02). |
| T07-17 | Not automated: mixed-library query assertion remains; implementation uses Movie,Series (Q7-03). |
| T07-18 | Not automated: watched/progress badge snapshots require Apple SDK. |
| T07-19 | A: `testT07_19_detailBackRestoresTheSameGridCardAndScrollPosition`; series return path still needs dedicated UI coverage. |
| T07-20 | Not automated: display-scale request sizing and offscreen cancellation need dedicated image lifecycle tests. |
| T07-21 | Partial L: `testT07_21_movieSeriesSeasonAndEpisodeDetailRequests` checks mapped kinds; exact fields and request count need assertions. |
| T07-22 | Not automated: HeroHeader snapshots require Apple SDK. |
| T07-23 | Not automated: movie buttons without progress need a dedicated UI test. |
| T07-24 | Partial L: T07-25 checks resume intent; button label and remaining-time focus need Apple UI coverage. |
| T07-25 | L: `testT07_25_viewModelsSanitizeProtocolValuesAndDetailCanResumeAndStartOver` checks the resume position. |
| T07-26 | L: T07-25 checks zero start intent and verifies both detail and shared-store UserData remain unchanged. |
| T07-27 | L: `testT07_27_playedIsOptimisticAndFailureRollsBackAndShowsAKey`; T07-28 checks POST/DELETE; UI label not executed on Linux. |
| T07-28 | L: `testT07_28_favoriteAndPlayedTogglesUsePOSTAndDELETE` checks optimistic favorite state and endpoints. |
| T07-29 | Partial L: `testT07_29_storeRefreshAndReloadPreserveEpisodeFocusAndSeason` checks shared-store projection. Full grid/home propagation requires M06 UI integration. |
| T07-30 | Not automated: Overview sheet opening, dismissal and focus need Apple UI coverage. |
| T07-31 | Not automated: cast portraits, initials and focus need Apple snapshots/UI (Q7-16). |
| T07-32 | Partial L: T07-35 covers HDR10 resolution; default-stream/HDR variants need more fixtures (Q7-22). |
| T07-33 | Partial L: T07-35 covers DTS-HD MA 7.1; AAC/Atmos/default-stream cases need fixtures. |
| T07-34 | Partial L: T07-35 covers a subtitle language; deduplication/no-download assertions remain. |
| T07-35 | Partial L: `testT07_35_technicalFixtureShowsHDRDVAndLosslessAudio`; separate DV 8.1/SDR/unknown fixtures remain. |
| T07-36 | Not automated: first-source selection needs a multiple-source fixture (Q7-06). |
| T07-37 | Not automated: absence of trailer UI needs an Apple assertion (Q7-18). |
| T07-38 | Partial K: design-system checks forbid link/openURL rendering. An ExternalUrls fixture assertion remains. |
| T07-39 | Not automated: movie focus order needs Apple UI tests. |
| T07-40 | Partial K: design-system checks enforce glass placement. Visual budget requires snapshots. |
| T07-41 | Not automated: parallel item/seasons start needs a gated service test. |
| T07-42 | L: T07-43 asserts seasonId, enableUserData and Overview,PrimaryImageAspectRatio fields, following the merged module spec. |
| T07-43 | L: `testT07_43_fiveSeasonsFetchAndShowOnlyTheSelectedSeason` verifies no all-season episode request, series-scoped Next Up discovery, and replacement of the displayed season. `testT07_43_singleSeasonKeepsPickerVisibleAndItsEpisodesSelected` and `testT07_43_noSeasonsHidesPicker` enforce the Q7-25 follow-up. A: `testT07_43_singleSeasonPickerStaysVisible` checks visibility and Down/Up focus with one season. |
| T07-44 | L: `testT07_44_switchingSeasonCancelsPreviousRequestAndReusesCachedRows` uses a suspended request, proves cancellation, and verifies a completed season is reused without another request. `testT07_44_twoSeasonsReplaceEpisodesAndKeepFocusInTheSelectedSeason` checks the two-second S2E1 fixture, season-scoped requests, row replacement, cache reuse and picker/episode focus. A: `testT07_44_twoSeasonPickerReplacesEpisodesAndKeepsFocus`. |
| T07-45 | L: `testT07_45_seriesOpensAtInProgressSeasonTwoEpisodeFiveAndSpecialsLast`; no-progress default needs another fixture. |
| T07-46 | A: `testT07_46_playIsDefaultAndInProgressEpisodeIsVisible`; follows final module spec Play/Resume default focus. |
| T07-47 | Not automated: fully watched series needs a dedicated fixture (Q7-07). |
| T07-48 | L and A: `testT07_48_downTargetsFirstUnplayedAndUpReturnsToSelectedSeason`, `testT07_48_downFromSeasonTargetsThatSeasonsFirstUnplayedEpisode`. |
| T07-49 | L: T07-48; A: `testT07_49_upFromEpisodeReturnsToSelectedSeason`. |
| T07-50 | L: `testT07_50_seasonFocusDebouncesAndLatestSelectionWinsWithoutMovingToEpisodes`; A: `testT07_50_focusOnSeasonChangesRowWithoutSelectingOrLeavingPicker`. |
| T07-51 | L/A: same-episode and next-episode playback-return hook tests, including next-season transition. L: `testT07_51_shortFinalSeasonReturnsToItsOnlyEpisode` covers finishing the only episode of the final season. A: `testT07_51_shortSecondSeasonEpisodeDetailReturnsToSameEpisode` checks detail return, the selected season and Up/Down focus. Real player return awaits M08 presentation (Q7-08). |
| T07-52 | Partial L/A: `testT07_52_selectedOverviewFollowsFocusedEpisodeAsLiteralText`, `testT07_52_episodeOverviewNeverReceivesFocus`. Card snapshots require Apple SDK. |
| T07-53 | A: `testT07_53_episodeCardNavigatesToEpisodeDetail`; direct Play/Pause uses the M08 hook (Q7-20). |
| T07-54 | Partial L: T07-45 checks Specials last. Localized name snapshot requires Apple SDK (Q7-17). |
| T07-55 | Not automated: hiding virtual/empty seasons needs a decision/fixture (Q7-09). |
| T07-56 | Not automated: 150-episode paging behavior remains undefined (Q7-10); frame rate requires hardware. |
| T07-57 | Not automated: season-wide mutation and Next Up propagation require service/UI integration coverage. |
| T07-58 | Partial L: T07-45 checks the in-progress play target. Series playback intent needs an explicit assertion. |
| T07-59 | Not automated: loading skeleton/layout snapshots require Apple SDK. |
| T07-60 | Partial K: design-system glass rules; series Reduce Transparency snapshots require Apple SDK. |
| T07-61 | Not automated: bright/dark series backdrop and logo snapshots require Apple SDK. |
| T07-62 | Not automated: series snapshot matrix requires Apple SDK/artifacts. |
| T07-63 | L: grid outage/filter failure/recovery and episode outage tests; A: retained-content/banner UI test. `testT07_63_movieDetailRetainsContentWhenTheServerBecomesUnreachable` covers movie detail. `T07ScreenLifecycleTests` now covers retained grid, movie/series/season/episode detail, standalone series and embedded series hero returns; it verifies AppState banner/full-screen decisions before and after an outage without reloading. |
| T07-64 | L: `testT07_64_downWithoutContentUsesTheExistingServerDownKey` and `testT07_64_emptyDetailUsesTheSharedServerDownKey`; `T07ScreenLifecycleTests` adds empty grid, failed first detail request and empty standalone series returns, proving a retained populated screen cannot suppress AppState.showsServerDown. Shared title/retry/change-server keys are checked; full-screen buttons require Apple UI execution. |
| T07-65 | Partial L: T07-63 checks loaded pages survive and retry resumes the offset. 500/timeout/no-loop retry card assertions remain (Q7-04). |
| T07-66 | Not automated: deleted-item removal and return routing need dedicated tests (Q7-11). |
| T07-67 | L: `testT07_67_401CancelsAllRequestsEndsSessionOnceAndNeverRetries`. |
| T07-68 | L: `testT07_68_non401ErrorsKeepSessionAndCancellationIsNotPresented` and `testT07_68_forbiddenActionRollsBackAndUsesTheCatalogKey` cover session preservation, optimistic rollback and the forbidden catalog key. Inline rendering requires Apple UI execution. |
| T07-69 | Not automated: network transition within two seconds and blocked playback require device/UI integration. |
| T07-70 | Not automated: Filters2-only failure fallback needs a dedicated fixture (Q7-12). |
| T07-71 | L: `testT07_71_malformedRecordsAdvanceServerOffsetAndDuplicatesAreRemoved`. |
| T07-72 | Not automated in M07: shared retry-client tests exist; M07-specific 502/503/504 exhaustion assertions remain. |
| T07-73 | Not automated: LAN launch percentiles require device measurements. |
| T07-74 | Not automated: scrolling hitch/frame-rate budgets require Instruments on A15 and oldest supported Apple TV. |
| T07-75 | Not automated: detail/backdrop latency budgets require device measurements. |
| T07-76 | Not automated: grid/movie snapshot matrix requires Apple SDK/artifacts. |
| T07-77 | Partial L: `T07MetadataTests` covers literal markup, controls/bidi, graphemes and shared limits; T07-25 covers protocol values. The limit-1/limit/limit+1 matrix covers multi-scalar emoji and combining sequences, plus ServerInfo/PublicUser limits and 15 taglines/40 genres. Layout snapshots require Apple SDK. |
| T07-78 | L: `T07ImageTests` and `T07SecurityStateTests` cover header-only auth, SHA-256 tuple keys, cache filenames and byte limits. Streaming regression tracked by T07-81. |
| T07-79 | Not automated: special-character genre URL round-trip needs an explicit assertion. |
| T07-80 | L: `testT07_80_thumbnailOptionsUseDisplayedPixelsAndImmediateTransformedThumbnailOnly` tests the actual dictionary consumed by the decoder; on Apple it also checks the SDK constant keys. A: `testT07_80_artworkIsDownsampledToDisplayedPixels` checks real thumbnail dimensions. K: `scripts/check-image-pipeline.py` forbids AsyncImage, encoded-data UIImage/NSImage constructors and full ImageIO bitmap decoding; included in ci-grep.sh. |
| T07-81 | L: `testT07_81_missingContentLengthStreamIsCancelledAtTheCap` and `testT07_81_lyingContentLengthStreamIsCancelledAtTheCap` exercise the real URLSession delegate with paced 64 KB chunks and absent/false 1 MB headers. They assert cancellation at the 20 MB boundary, before EOF; T07-78 asserts failed data is not cached. Visual fallback/focus requires Apple UI execution. |
| T07-82 | Not automated: decompression-bomb memory/no-crash and fallback need Apple ImageIO/device tests. |

## Earlier M07 validation

The pre-existing merge `632af36` is complete. Both parents' integration tests and
helpers are retained with duplicate helpers removed. Linux `swift build` and
`swift test` passed before this follow-up; five live Docker tests were skipped
because `GLASSFIN_INTEGRATION` was not enabled.

Final Linux validation passed: `swift build`, `swift test` (364 passed,
including 47 M07 tests; five live Docker tests skipped), and
`swift-format lint --recursive --strict Package.swift Sources Tests ../../Apps`.
The design-system, String Catalog, DEBUG-string and CI grep checks passed.
The image source check is part of CI grep and its forbidden-pattern detection
was also verified. The canonical copy, all 82 mapping rows, and every authored
M07 test's ID/comment were checked for consistency.

The Q7-25 single-season follow-up also passed `scripts/coverage-gate.sh`
(91.72% line coverage), license and entitlement checks, DEBUG-string and artifact
redaction self-tests. The Docker seed generation was exercised locally with
`ffmpeg`/`ffprobe`: one movie, two S1 episodes and one two-second S2 episode.
The bootstrap's TV-library fallback and incomplete-scan retry passed with mock
responses. Docker and Xcode are unavailable here; live integration and Apple UI
tests were not executed. No plist, workflow or `project.yml` changes were made.

The DEBUG scenarios `series-single-season` and `series-two-seasons` exercise the
same service/view-model path as the app. The picker uses the existing en/fi
catalog entries and appears for every series with at least one season.

There are 61 authored M07 tests: 47 Linux tests and 14 Apple ImageIO/UI tests.
Linux executed IDs T07-01, T07-05–T07-07, T07-09, T07-11, T07-13, T07-21,
T07-25, T07-27–T07-29, T07-35, T07-43–T07-45, T07-48, T07-50–T07-52,
T07-63–T07-64, T07-67–T07-68, T07-71, T07-77–T07-78, and T07-80–T07-81.
Supporting assertions cover T07-26, T07-42, T07-49 and T07-54 as described above.
Apple-only tests use IDs T07-19, T07-43–T07-44, T07-46, T07-48–T07-53, T07-63 and T07-80;
they were not executed on Linux. Every remaining ID has a not-automated or
partial-coverage explanation in the table. No PNGs, device performance results
or live-server compatibility results are claimed.

The unchanged `MetadataPolicy.swift` constants are the only limits used by the
metadata/image paths: Overview 2,000; Taglines 3 × 200; Genres 10 × 64; other
strings 200; ServerName/PublicUser.name 64; recent searches 20; image bytes
20 × 1,024 × 1,024. Cleaning strips only control/bidi scalars and preserves tags,
entities, Markdown and URL-looking text literally. No renderer or link opener
is involved.


## Stack v2 and screen reactivation validation

The v2 stack merge is `68d1c02` with the requested message. Conflict resolutions,
every changed test, exact locally changed assertion expressions, upstream test
adoption, and every new signature adjustment are recorded in
[M07-STACK-V2-TEST-AUDIT.md](M07-STACK-V2-TEST-AUDIT.md).

There are 12 new Linux lifecycle tests. The seven new M07 methods map directly
to T07-63 or T07-64; four Home methods use T02-35a/b. The remaining identity-only
method is extra coverage, not a new canonical plan ID:

| Test | Plan mapping and assertions |
| --- | --- |
| `testOnAppearRegistersEachFeatureViewModel` | Extra: exact currentView identity for Home, grid, detail, standalone series and Home again; initially empty content; no Home or grid requests. |
| `testT02_35a_returningToHomeKeepsBannerWithContent` | T02-35a: each Home section independently counts as content; loaded and failed-with-previous states; return before and after outage; identities, connectivity, localized banner, no full-screen state and unchanged request counts. |
| `testT02_35b_returningToEmptyHomeShowsFullScreen` | T02-35b: loaded empty sections; another populated screen retained; return switches identity and shows the full-screen state with the shared title/retry/change-server keys. |
| `testT02_35a_returningToAuthHomeKeepsBannerWithCachedContent` | T02-35a: the current AuthFlow-rendered Home tab restores its identity and cached Latest content; banner with no blocking Home error. |
| `testT02_35b_returningToAuthHomeWithoutContentShowsFullScreen` | T02-35b: both absent and empty snapshots are empty; another detail screen can remain populated; returning Home selects the full-screen state and shared error key. |
| `testT07_63_returningToLibraryKeepsBannerWithContent` | T07-63: loaded grid and failed reload retaining its page; identity restoration before/after outage; shared localized banner and no full-screen state; no return-time fetch. |
| `testT07_64_returningToEmptyLibraryShowsFullScreen` | T07-64: a loaded empty grid uses the full-screen state even with a populated Home retained; shared title/retry/change-server keys. |
| `testT07_63_returningToDetailKeepsBannerWithContent` | T07-63: movie, series, season and episode item content, including failed reloads with previous values; identities, banner/full-screen decision and unchanged return-time request counts. |
| `testT07_64_returningToEmptyDetailShowsFullScreen` | T07-64: a failed first request has no content; a populated Home cannot suppress the full-screen state; exact failure and shared title/retry/change-server keys. |
| `testT07_63_returningToSeriesKeepsBannerWithContent` | T07-63: standalone series keeps seasons/episodes after a failed reload, restores identity and chooses the banner in both outage/return orders. |
| `testT07_64_returningToEmptySeriesShowsFullScreen` | T07-64: standalone series with no seasons/episodes uses the full-screen state while a loaded detail is retained; shared title/retry/change-server keys. |
| `testT07_63_seriesSectionDoesNotReplaceDetailContentProvider` | T07-63: empty/failed embedded seasons do not replace the loaded detail provider; series hero content selects the banner. |

The actual Home tab calls AuthFlow.onAppear; the library and detail screens call
their own view-model hooks. HomeViewModel also exposes the hook for its future
feature screen. SeriesViewModel is embedded in ItemDetailScreen here, so the
detail provider owns the complete screen; standalone hosts have an explicit hook.
All hasContent implementations include retained previous values. Home and grid
require a nonempty section/list; detail requires an item; standalone series
requires seasons or episodes. Empty Home snapshots now count as empty.

Current Linux validation: `bash scripts/coverage-gate.sh` passed, executing 400
tests with zero failures and five live Docker skips (395 passed). Line coverage
is 91.71% (7,581/8,266), above the 80% threshold. The 12 new lifecycle tests pass.
Strict swift-format, design-system, en/fi String Catalog, DEBUG-string and CI grep
checks also passed. All ten inherited bootstrap unit tests passed.

There are now 73 authored M07-ID tests: 59 Linux and 14 Apple tests; the four new
Home-ID tests and one identity-only extra are listed separately above.

No Apple UI/snapshot execution is claimed. Xcode and Docker are unavailable in
this environment. The merge imports v2's existing project.yml lines verbatim;
the M07 reactivation change edits no plist, project.yml or workflow.
