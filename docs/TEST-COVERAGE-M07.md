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
| T07-26 | Partial L: T07-25 checks zero start intent; unchanged UserData needs an explicit assertion. |
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
| T07-42 | Not automated: exact selected-season episode query needs a dedicated assertion. |
| T07-43 | Not automated yet: current row shows one season, but initial all-season discovery must be replaced and tested against Q7-25. |
| T07-44 | Not automated yet: selected-season cancellation/cache need implementation and gated tests. |
| T07-45 | L: `testT07_45_seriesOpensAtInProgressSeasonTwoEpisodeFiveAndSpecialsLast`; no-progress default needs another fixture. |
| T07-46 | A: `testT07_46_playIsDefaultAndInProgressEpisodeIsVisible`; follows final module spec Play/Resume default focus. |
| T07-47 | Not automated: fully watched series needs a dedicated fixture (Q7-07). |
| T07-48 | L and A: `testT07_48_downTargetsFirstUnplayedAndUpReturnsToSelectedSeason`, `testT07_48_downFromSeasonTargetsThatSeasonsFirstUnplayedEpisode`. |
| T07-49 | L: T07-48; A: `testT07_49_upFromEpisodeReturnsToSelectedSeason`. |
| T07-50 | L: `testT07_50_seasonFocusDebouncesAndLatestSelectionWinsWithoutMovingToEpisodes`; A: `testT07_50_focusOnSeasonChangesRowWithoutSelectingOrLeavingPicker`. |
| T07-51 | L/A: same-episode and next-episode playback-return hook tests, including next-season transition. Real player return awaits M08 presentation (Q7-08). |
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
| T07-63 | L: grid outage/filter failure/recovery and episode outage tests; A: retained-content/banner UI test. Movie detail outage needs an explicit fixture. |
| T07-64 | L: `testT07_64_downWithoutContentUsesTheExistingServerDownKey`; full-screen buttons require Apple UI execution. |
| T07-65 | Partial L: T07-63 checks loaded pages survive and retry resumes the offset. 500/timeout/no-loop retry card assertions remain (Q7-04). |
| T07-66 | Not automated: deleted-item removal and return routing need dedicated tests (Q7-11). |
| T07-67 | L: `testT07_67_401CancelsAllRequestsEndsSessionOnceAndNeverRetries`. |
| T07-68 | Partial L: `testT07_68_non401ErrorsKeepSessionAndCancellationIsNotPresented`; action rollback and forbidden key need dedicated assertions. |
| T07-69 | Not automated: network transition within two seconds and blocked playback require device/UI integration. |
| T07-70 | Not automated: Filters2-only failure fallback needs a dedicated fixture (Q7-12). |
| T07-71 | L: `testT07_71_malformedRecordsAdvanceServerOffsetAndDuplicatesAreRemoved`. |
| T07-72 | Not automated in M07: shared retry-client tests exist; M07-specific 502/503/504 exhaustion assertions remain. |
| T07-73 | Not automated: LAN launch percentiles require device measurements. |
| T07-74 | Not automated: scrolling hitch/frame-rate budgets require Instruments on A15 and oldest supported Apple TV. |
| T07-75 | Not automated: detail/backdrop latency budgets require device measurements. |
| T07-76 | Not automated: grid/movie snapshot matrix requires Apple SDK/artifacts. |
| T07-77 | Partial L: `T07MetadataTests` covers literal markup, controls/bidi, graphemes and shared limits; T07-25 covers protocol values. Boundary matrix and layout snapshots remain. |
| T07-78 | L: `T07ImageTests` and `T07SecurityStateTests` cover header-only auth, SHA-256 tuple keys, cache filenames and byte limits. Streaming regression tracked by T07-81. |
| T07-79 | Not automated: special-character genre URL round-trip needs an explicit assertion. |
| T07-80 | A: `testT07_80_artworkIsDownsampledToDisplayedPixels`; cross-platform options-builder test still needed. |
| T07-81 | Not automated yet: missing/lying Content-Length streams must exercise the actual delegate and cancellation at the cap. |
| T07-82 | Not automated: decompression-bomb memory/no-crash and fallback need Apple ImageIO/device tests. |

## Validation

The pre-existing merge `632af36` is complete. Both parents' integration tests and
helpers are retained with duplicate helpers removed. Linux `swift build` and
`swift test` passed before this follow-up; five live Docker tests were skipped
because `GLASSFIN_INTEGRATION` was not enabled.

Run the commands in the user request for each implementation pass. Apple
ImageIO/UI tests are authored but cannot run in this Linux worktree. No PNGs,
device performance results or live-server compatibility results are claimed.
