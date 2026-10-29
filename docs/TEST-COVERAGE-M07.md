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
| T07-32 | L: `testT07_32_defaultVideoResolutionAndHDRLabels` checks first-default selection, 4K/1080p, HDR10/HDR10+/Dolby Vision/HLG, SDR/unknown suppression and first-video fallback (Q7-22). |
| T07-33 | L: `testT07_33_defaultAudioCodecAndChannelLabels` checks first-default DTS-HD MA 7.1, Dolby Atmos and AAC 2.0, with first-audio fallback and all tracks retained for selection. |
| T07-34 | L: `testT07_34_subtitleLanguagesAreStableAndDeduplicatedWithoutDownloadingFiles` checks embedded/external metadata, stable language order, deduplication and exact item/similar requests with no subtitle download. |
| T07-35 | Partial L: `testT07_35_technicalFixtureShowsHDRDVAndLosslessAudio` is unchanged. T07-32/T07-33 add SDR, unknown-range and default-stream fixtures; a dedicated DV 8.1 fixture remains. |
| T07-36 | L: `testT07_36_multipleMediaSourcesUseOnlyTheFirstSourcesTechRow` checks two sources with conflicting top-level streams; only the first source reaches the P0 presentation model, exactly as with one source (Q7-06). No version picker is added. |
| T07-37 | Not automated: absence of trailer UI needs an Apple assertion (Q7-18). |
| T07-38 | Partial K: design-system checks forbid link/openURL rendering. An ExternalUrls fixture assertion remains. |
| T07-39 | Not automated: movie focus order needs Apple UI tests. |
| T07-40 | Partial K: design-system checks enforce glass placement. Visual budget requires snapshots. |
| T07-41 | L: `testT07_41_openingSeriesStartsItemAndSeasonsConcurrently` gates both requests before releasing either, checks GET paths and query items including enableUserData=true, then verifies loaded detail/seasons. |
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
| T07-79 | L: `testT07_79_specialCharacterGenresAreEncodedAndRoundTripWithoutChangingThePath` captures real HTTP URL requests for &, =, #, /, Unicode and spaces, checks query round-trips, the base path, sort/parent parameters and absence of a fragment (S6.5). |
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

There are 79 authored M07-ID tests: 65 Linux tests and 14 Apple ImageIO/UI tests.
Linux executed IDs T07-01, T07-05–T07-07, T07-09, T07-11, T07-13, T07-21,
T07-25, T07-27–T07-29, T07-32–T07-36, T07-41, T07-43–T07-45, T07-48, T07-50–T07-52,
T07-63–T07-64, T07-67–T07-68, T07-71, T07-77–T07-81.
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

At the v2 merge there were 73 authored M07-ID tests: 59 Linux and 14 Apple tests;
the four new Home-ID tests and one identity-only extra are listed separately above.

No Apple UI/snapshot execution is claimed. Xcode and Docker are unavailable in
this environment. The merge imports v2's existing project.yml lines verbatim;
the M07 reactivation change edits no plist, project.yml or workflow.

## Stack v5 CI diagnosis and merge validation

The main merge is `5ed7534`, with message
`Merge main 45e21b4 (stack base v5)`. It includes the M04 squash `b0f0f22`,
M08 HLS authentication fix `924888d`, and specification update `45e21b4`.
M05 `da38a26` was already an ancestor. The later M05 head `d2d780b` is included
by merge commit `d027a23` (`Merge M05 d2d780b (stack base v5)`).
No history was rebased or force-pushed.

Main's M04 authentication behavior and M08 playback implementation were retained.
M07's library tabs, feature-client composition, DEBUG scenarios, screen
reactivation hooks, and literal library metadata policy were preserved.
`MetadataSanitizer.plainText` and `displayName` use main's authentication
sanitization; M07 continues to use `displayText` for literal library metadata.
The workflows, `project.yml`, and app plists now match main exactly, including
the configuration adopted by the newer M05 merge. No configuration was authored
for this follow-up. Main's project does not include the additional app unit and
snapshot test targets previously inherited from M05.

### CI run 40622939835 at c3258f1

Diagnosis used `gh run view 40622939835 -R kallupx/glassfin --log-failed`,
`gh run download` for both `ios-results` and `tvos-results`, the workflow files,
and `scripts/macos-ci.sh`. The workflow uploads readable xcresult exports and
redacted logs, not raw xcresult bundles. The downloaded `xcresult-tests.json`,
`junit.xml`, `failed-tests.txt`, and build/test logs were inspected.

- **iOS: M05 compile error.** In `DesignSystemFocusTests.swift`, the iOS-only
  `selectTab` helper is not isolated to the main actor but calls the main-actor
  `require` helper at lines 274 and 277. The app UI test target does not compile.
  Package tests and the Release build/binary scan passed. An empty app failure
  list in the xcresult export does not establish that app tests ran.
- **tvOS: M05 focus failure.**
  `testT05_29_upLeavesTheHeroForAnotherTarget` reached the hero, pressed Up and
  Down, then timed out waiting for `design.hero.play` to regain focus at line
  211. The same run's separate `full-ui` job passed with the same tvOS script
  and head, which is evidence of an intermittent focus failure. The available
  evidence does not establish an infrastructure outage or its precise focus
  race. This belongs to M05, whose focus code and assertions were left intact.
- All 13 M07 tvOS library UI tests and the M07 artwork test passed in the
  downloaded tvOS results. M07 package tests passed in the iOS package results.
  No M07 production defect was identified in this run.

Both reported failures remain in M05 `d2d780b`; this M07 follow-up does not
claim to fix them or to establish a green Apple CI run.

### Explicit test and assertion reconciliation

The merge exposed incompatible expectations between main's auth sanitizer and
M07's library display policy. These test changes were necessary to preserve
both contracts; no assertion was deleted or weakened to hide a failure.

- `T07MetadataTests.testT07_77_metadataBoundariesAndDisplayNamesUseTheSharedConstants`:
  the literal-markup assertion now calls `displayText(literal, limit: .max)`
  instead of `plainText(literal)`. Its expected literal string is unchanged.
- `SecurityDiscoveryTests.testT03_24_forgedDiscoveryDoesNotAutoConnect`:
  restored main's two `XCTAssertFalse` expectations for `<` and `alert` in the
  discovered server name. Authentication/discovery sanitization belongs to M04.
- `SecurityContentTests.testT03_14_plainTextLinksSubtitlesAndSearch`:
  restored main's `plainText` expectation,
  `Hello Tom & Jerry **bold** [x](http://e.test)`. The existing M07 DTO assertions
  still require literal `<b>North</b>` and `<p>A quiet film.</p>`.
- `T04AuthFlowTests.testT04_59_launchFailureLoadsCachedHomeAndKeepsToken`:
  retained the pre-merge M07 fixture with `[Sample.movie()]` in Resume, rather
  than main's empty snapshot. Every assertion is unchanged: retained-content
  behavior requires actual content. The existing M07
  `testT02_35a_returningToAuthHomeKeepsBannerWithCachedContent` and
  `testT02_35b_returningToAuthHomeWithoutContentShowsFullScreen` were preserved
  with their original assertions, including the empty-snapshot blocking case.

Conflict resolution also adopts main's existing `SecurityNameTests`,
`T04ProbeTests`, and M04 portions of `T04AuthTests` and `T04AuthUITests`.
This imports main's decoded-entity/control/bidi expectations, host fallback for
markup-only names, markup removal on mutated/decoded names and discovery/server
names, and class-level main-actor annotations. Their upstream assertions were
not rewritten. Main's playback and Docker integration test changes were also
imported unchanged, in `AVFoundationMediaSessionTests`,
`HLSCredentialQueryTests`, `MediaLoaderSecurityTests`,
`PlaybackCoordinatorTests`, and `DockerIntegrationTests`.

### Linux verification

With `LD_LIBRARY_PATH=~/.local/lib/swiftcompat` and
`source ~/.local/share/swiftly/env.sh`, `bash scripts/coverage-gate.sh` passed:
491 tests, zero failures, seven live Jellyfin integration skips; line coverage
91.70% (8,390/9,149), above the 80% threshold. Strict recursive `swift-format`
lint, `check-design-system.py`, `check-string-catalogs.py`,
`check-debug-only-strings.py`, and `ci-grep.sh` passed. English and Finnish
catalog checks remain enabled; no UI copy was added or changed.

To verify on Apple runners, run `bash scripts/macos-ci.sh iOS` and
`bash scripts/macos-ci.sh tvOS`. Xcode/simulator execution and live Jellyfin
integration were not performed in this Linux workspace. The M05 failures above
and main's app test-target configuration limit the Apple coverage claim.

## Stack v6 CI diagnosis and fix

Main `d720120` is included by merge commit `99d98df`
(`M07 CI: merge main d720120 (stack base v6)`). After `git fetch origin`,
M05 `origin/cursor/m05-design-system-c0c2` remained at `d2d780b`, already an
ancestor of this branch, so no additional M05 merge was necessary. No rebase
or force-push was used. Workflows, `project.yml`, and app plists match main
exactly; the workflow update was inherited unchanged from main.

### CI run 40627954138 at 41b4d43

The only failing job was `test-ios` (job `122617923282`). Lint, `test-tvos`,
and `full-ui` succeeded. Diagnosis used `gh run view --log-failed`, the complete
job log from `gh api repos/kallupx/glassfin/actions/jobs/122617923282/logs`, and
the uploaded `ios-results` artifact. The abbreviated failed log stops during
Release compilation and omits the actual failure. The full log and uploaded
`app-test.log` report two compiler errors in
`Apps/Shared/UITests/DesignSystemFocusTests.swift` at lines 274 and 277:
`selectTab` synchronously calls main-actor-isolated `require` without its own
actor isolation. Testing was cancelled because the build failed; xcodebuild
returned exit code 65. This was not a CI timeout or a runtime focus failure.

The Release build and binary scan passed, as did the iOS package suite
(489 passed, seven skipped). The app xcresult export has an empty `testNodes`
array and screenshot manifest. Its `failed-tests.txt` says `no failed tests`
because the app tests never ran. This run therefore cannot demonstrate the
M04 Quick Connect device-code display race reported by M06/M10.

The defect is in the integration of an M05 UI-test helper with M07's retained
method-level actor isolation. M05's current file isolates the entire class;
M07 isolates individual methods and had missed the imported `selectTab`
helper. The minimal required fix adds `@MainActor` to that helper. No M07
library/detail production defect was found, and no M04 behavior was changed.

### Explicit test and assertion changes

- Authored change: `DesignSystemFocusTests.selectTab` receives `@MainActor`
  so the iOS test target can compile. Its body, callers, queries, assertions,
  timeouts, and scenarios are unchanged. No assertions were added, removed,
  or weakened for this fix.
- Main's `d720120` playback test changes were imported unchanged by the merge:
  `ADRM08PrototypeTests.swift` adds a credential-URL wrap rejection assertion;
  `PlaybackCoordinatorTests.swift` adds the two T08P-103 missing-server-query
  tests and updates the existing credential-query assertions for server-issued
  HLS URLs. These are upstream changes, with no local edits.

### Linux verification and Apple limits

With `LD_LIBRARY_PATH=~/.local/lib/swiftcompat` and
`source ~/.local/share/swiftly/env.sh`, `bash scripts/coverage-gate.sh` passed:
493 tests, zero failures, seven live Jellyfin integration skips; line coverage
91.72% (8,402/9,160), above the 80% threshold. Strict recursive `swift-format`
lint, `check-design-system.py`, `check-string-catalogs.py`,
`check-debug-only-strings.py`, and `ci-grep.sh` all passed. No UI strings changed.

Run `bash scripts/macos-ci.sh iOS` on an Apple runner to verify the app test
target now compiles and execute the existing UI assertions, including
`T04AuthUITests.testT04_03_quickConnectReachesHome` and
`T07LibraryUITests.testT07_43_singleSeasonPickerStaysVisible`. Run
`bash scripts/macos-ci.sh tvOS` for the tvOS suite. Xcode/simulator execution
and live Jellyfin integration were not performed in this Linux workspace;
no claim is made that the separate M04 race is fixed or that Apple CI is green.

## CI run 40636746467: iOS Settings hidden by library tabs

The new failure at `7e0fac1` is in `test-ios`, job `122646096582`.
The complete job log and the uploaded `ios-results` artifact identify exactly
one failing app test:
`T04AuthUITests.testT04_68_settingsSignOutDefaultsToCancelAndKeepsServer`.
It signs in and finds `home.root`, then fails on its first attempt to open
Settings, before entering the sign-out confirmation. The query waits ten
seconds, then reports no matching Settings element at `UIInteraction.swift:10`.
The job finishes with xcodebuild exit code 65 after about seventeen minutes,
within its twenty-five-minute limit. This is a tab-layout failure, not a
compile error, remote-focus race, or job timeout.

The exported failure hierarchy
(`readable/bundle-1/screenshots/7282EEC3-B1D7-4726-B9EF-C4725FE084FC.txt`)
shows Home, Library 1, Series, Library 3, and More in the iPhone tab bar, with
no Settings element. The retained Home screenshot shows the same layout.
M07 adds five direct library tabs and a library-overflow tab before Settings
in `AuthRootView.home`. The DEBUG fixture returns seven libraries. iPhone's
native five-item tab bar consequently moves Settings into More. Waiting longer
cannot make the Settings query find a destination behind that menu.

The fix puts Settings immediately after Home on iOS, before M07's dynamic
library tabs. It follows the primary-destinations-first approach already used
by M05's `LibraryTabShell`. The extracted Settings content is unchanged, and
tvOS retains its existing tab order. Libraries remain accessible through the
native More menu and the existing Libraries destination. No sleep, test-only
layout, or new UI copy is needed.

Although the host file belongs to the M04 authentication surface, this defect
comes from M07's library-tab integration: main's host has only Home and
Settings, and M05's own shell already places Settings before libraries on
iOS. No inherited M05 or upstream-main defect requires a separate repair.

### Comparison with M06 and M10

- M06 `63a497f` fixes scheduler-dependent producer-byte assertions in its
  image-stream tests. M07's seven `T07ImageTests`, including both cancellation
  tests, passed in this iOS run. The package xcresult export records 491 passed
  tests and seven live-server skips, with no failures. No image assertion is
  changed on evidence from another module's run.
- M10 `88acbdc` adds DEBUG synchronization between the Quick Connect fixture
  and its code-display test. `testT04_03_quickConnectReachesHome` passed here,
  with the login-method, quick-connect, and home screenshots retained. Its
  code-display assertions did not fail, so this run does not justify importing
  M10's backend hook or test changes.
- The earlier M05 `selectTab` actor-isolation repair compiled successfully:
  all three iOS design-system UI tests passed. The app suite records fourteen
  passed tests and the single Settings failure described above.

### Other jobs and final run status

Lint, `full-ui`, and `dependabot-macos` passed. The completed `full-ui` job
(`122646096541`) passed all 38 tvOS UI tests, including T04-03, T04-68, and
the thirteen M07 UI tests.

The separate `test-tvos` job (`122646096716`) was cancelled at 05:44:46 UTC
after the remote branch advanced to the M05 merge commit `7fffedc` and started
run `40639689209`. Its API conclusion is `cancelled`; the only error line is
`The operation was canceled.` Its final logs and uploaded `tvos-results`
artifact show a successful Release build and binary scan, successful package
tests (including both image-stream cancellation tests), and a passed T04-03.
Cancellation interrupts T04-68 before a result, with no compiler error or
failing test reported. This is workflow-concurrency cancellation, not a
twenty-five-minute timeout or evidence of another code defect. The original
run's final overall conclusion is therefore `cancelled`, while its completed
iOS job retains the real Settings failure diagnosed above.

### Merge and test-change audit

After `git fetch origin`, main remained at `d720120`, already an ancestor.
M05 advanced to `b8c6349`; merge commit `7fffedc` includes that tip using a
merge commit. Its updated `scripts/ci-path-filter.py` is imported unchanged.
Main's `project.yml` is explicitly retained as requested, rather than importing
M05's new hosted unit-test targets. All Info.plist files and workflows also
match main. No rebase or force-push is used.

No test or assertion changes are authored or imported by this repair. The
existing sign-out test remains the regression check, with every interaction,
assertion, screenshot, and timeout preserved. There are no catalog changes.

### Verification and remaining limits

All requested Linux checks pass with the specified Swift environment:
`coverage-gate.sh` runs 493 tests with zero failures and seven existing
live-server skips; line coverage is 91.72% (8,402/9,160). Strict recursive
`swift-format` lint, `check-design-system.py`, `check-string-catalogs.py`,
`check-debug-only-strings.py`, and `ci-grep.sh` pass. `git diff --check` passes.

On an Apple runner, run `bash scripts/macos-ci.sh iOS` for the complete failing
job's checks, or run this focused regression after `xcodegen generate`:

```sh
xcodebuild test -scheme Glassfin-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Glassfin-iOSUITests/T04AuthUITests/testT04_68_settingsSignOutDefaultsToCancelAndKeepsServer \
  CODE_SIGNING_ALLOWED=NO
```

Run `bash scripts/macos-ci.sh tvOS` for tvOS. Linux cannot execute SwiftUI or
Apple simulator tests, so the iOS layout fix still needs simulator confirmation.
Live Jellyfin integration remains unexecuted. Keeping main's project file also
means M05's hosted logic and snapshot targets remain outside the app schemes.

## PoC follow-up unit tests

Six new Linux XCTest methods automate T07-32, T07-33, T07-34, T07-36,
T07-41 and T07-79. The current total is 79 authored M07-ID tests: 65 Linux
and 14 Apple tests. The executed-ID summary above includes these six IDs.

| ID | Package test file and function |
| --- | --- |
| T07-32 | `Tests/CoreModelsTests/T07TechnicalRowTests.swift`: `testT07_32_defaultVideoResolutionAndHDRLabels` |
| T07-33 | `Tests/CoreModelsTests/T07TechnicalRowTests.swift`: `testT07_33_defaultAudioCodecAndChannelLabels` |
| T07-34 | `Tests/CoreStateTests/T07PoCFollowupTests.swift`: `testT07_34_subtitleLanguagesAreStableAndDeduplicatedWithoutDownloadingFiles` |
| T07-36 | `Tests/CoreModelsTests/T07TechnicalRowTests.swift`: `testT07_36_multipleMediaSourcesUseOnlyTheFirstSourcesTechRow` |
| T07-41 | `Tests/CoreStateTests/T07PoCFollowupTests.swift`: `testT07_41_openingSeriesStartsItemAndSeasonsConcurrently` |
| T07-79 | `Tests/CoreServicesTests/T07FilterEncodingTests.swift`: `testT07_79_specialCharacterGenresAreEncodedAndRoundTripWithoutChangingThePath` |

The JSON fixtures are `Tests/Fixtures/m07-technical-items.json` and
`Tests/Fixtures/m07-subtitles.json` at the repository root, following the
existing fixture-loading convention. The concurrency fake suspends requests
with continuations and uses XCTest expectations with two-second bounds; it
releases requests even if a sequential regression fails the start assertions.
No sleeps or dependencies are added. URLComponents legally leaves `/` inside
query values unescaped; the URL test accepts that representation or `%2F` and
requires an unchanged path and an exact parsed genre value in both cases.

### Production bugs exposed by the tests

An initial focused run failed on stream selection/labels, subtitle language
projection, first-source precedence and sequential series loading; URL encoding
already passed. These are the minimal production corrections:

| File | Reason |
| --- | --- |
| `Packages/GlassfinCore/Sources/CoreModels/ItemMetadata.swift` | Preserve IsDefault and project default video/audio labels plus stable distinct subtitle languages without removing selectable tracks. |
| `Packages/GlassfinCore/Sources/CoreModels/Mappers.swift` | Carry IsDefault and prefer the first source's streams over conflicting top-level streams (Q7-06). |
| `Packages/GlassfinCore/Sources/CoreState/ItemDetailViewModel.swift` | Start known-series detail and seasons together through the same entry point exercised by the gated test. |
| `Apps/Shared/Sources/Library/ItemDetailScreen.swift` | Use the tested loading entry point and technical-row projection, and carry known kinds to related-item destinations. |
| `Apps/Shared/Sources/Library/LibraryGridView.swift` | Carry the grid item's known kind to detail so a series need not wait for item decoding before requesting seasons. |
| `Apps/Shared/Sources/Library/LibraryDebugHost.swift` | Supply the known series kind in the existing DEBUG series scenarios. |

All existing tests and assertions, including T07-35's raw technical values, are
unchanged. No version picker is introduced. Apple UI execution is still required
to verify rendered labels, navigation/focus and visual absence of a version picker;
the Linux tests verify the shared presentation data and actual request construction.

### Follow-up verification

With Swift 6.4.1 on Linux, `swift test` and `bash scripts/coverage-gate.sh`
pass: 499 tests, zero failures, seven existing live-server skips (492 passed).
Line coverage is 91.78% (8,480/9,239), above the 80% threshold.
Strict recursive swift-format and SwiftLint 0.65.1 pass, as do CI greps
(including design-system, String Catalog and image-pipeline checks), DEBUG-string
checks/self-test, artifact-redaction self-test, license checks/self-test and
entitlements. The lint job's 33 Python bootstrap/HLS probe tests, shell syntax
check and 22 Docker integration script self-test cases also pass.
All 82 canonical coverage rows and the 65 Linux/14 Apple M07-ID method counts
are checked against source. `git diff --check` passes. Live Jellyfin and Apple
simulator/UI execution are not claimed.
