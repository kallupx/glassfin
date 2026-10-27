import CoreModels
import CoreNetworking
import CoreState
import Foundation
import GlassfinServices
import XCTest

final class T06HomeTests: XCTestCase {
    // T06-08: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_08_videoLibrariesKeepServerOrderAndSeparateLatestRows() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        h.library.viewItems = [
            Library(id: Sample.library, name: "<b>1</b>", collectionType: "movies"),
            Library(id: Sample.other, name: "2", collectionType: "tvshows"),
            Library(id: Sample.season, name: "3", collectionType: "music"),
        ]
        h.library.resumeItems = [Sample.movie()]
        h.library.nextItems = [Sample.movie(id: Sample.other)]
        h.library.latestByID[Sample.library] = .success([Sample.movie()])
        h.library.latestByID[Sample.other] = .success([Sample.movie(id: Sample.other)])
        let home = h.home()
        await home.load()
        XCTAssertEqual(home.latestRows.map(\.id), [Sample.library, Sample.other])
        XCTAssertEqual(home.latestRows.first?.library.name, "<b>1</b>")
        XCTAssertEqual(home.latestRows.map { $0.state.value?.count }, [1, 1])
        XCTAssertEqual(home.resume.value?.count, 1)
        XCTAssertEqual(home.nextUp.value?.count, 1)
    }

    // T06-12: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_12_slowResumeDoesNotBlockOtherRows() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        h.library.gate = ResumeGate()
        h.library.viewItems = [Library(id: Sample.library, name: "1", collectionType: "movies")]
        h.library.nextItems = [Sample.movie()]
        h.library.latestByID[Sample.library] = .success([Sample.movie()])
        let home = h.home()
        home.start()
        await waitUntil { home.latestRows.first?.state.value?.count == 1 && home.nextUp.value?.count == 1 }
        XCTAssertTrue(home.resume.isLoading)
        h.library.gate?.releaseAll()
        await waitUntil { !home.resume.isLoading }
    }

    // T06-04: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_04_emptyAndUnknownLibraries() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        let home = h.home()
        XCTAssertFalse(home.isEmpty)
        await home.load()
        XCTAssertTrue(home.isEmpty)
        XCTAssertFalse(home.hasContent)
        XCTAssertFalse(HomeMetadata.isVideoLibrary(Library(id: Sample.library, name: "", collectionType: "books")))
    }

    // T06-14: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_14_sectionFailureAndTargetedRetryLeaveOtherRowsVisible() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        h.library.resumeError = .server(status: 500)
        h.library.nextItems = [Sample.movie()]
        let home = h.home()
        await home.reload(libraryIDs: [])
        XCTAssertEqual(home.resume.presentedError, .serverError(status: 500))
        XCTAssertEqual(
            AppErrorMessage.messageKey(for: try XCTUnwrap(home.resume.presentedError)), AppErrorMessage.serverErrorKey)
        XCTAssertTrue(home.hasContent)
        XCTAssertNil(home.serverDownTitleKey)
        let calls = h.library.nextCallCount()
        h.library.resumeError = nil
        h.library.resumeItems = [Sample.movie()]
        await home.retry(rowID: "resume")
        XCTAssertNil(home.resume.presentedError)
        XCTAssertEqual(h.library.nextCallCount(), calls)
    }

    // T06-13: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_13_latestFailureIsIsolatedToItsLibrary() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        h.library.latestByID[Sample.library] = .failure(.server(status: 500))
        h.library.latestByID[Sample.other] = .success([Sample.movie()])
        let home = h.home()
        await home.reload(libraryIDs: [Sample.library, Sample.other])
        XCTAssertEqual(home.latestRows[0].state.presentedError, .serverError(status: 500))
        XCTAssertEqual(home.latestRows[1].state.value?.first?.id, Sample.movie)
        XCTAssertTrue(home.hasContent)
        h.library.latestByID[Sample.library] = .success([Sample.movie(id: Sample.season)])
        await home.retry(rowID: Sample.library)
        XCTAssertNil(home.latestRows[0].state.presentedError)
        XCTAssertEqual(home.latestRows[1].state.value?.first?.id, Sample.movie)
    }

    // T06-19: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_19_bodyDecodeFailureShowsSectionRetryAndKeepsOtherRows() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        h.library.resumeError = .decoding
        h.library.nextItems = [Sample.movie()]
        let home = h.home()
        await home.load()
        XCTAssertFalse(home.isLoading)
        XCTAssertFalse(home.isEmpty)
        XCTAssertEqual(HomePolicy.sectionErrorKey(for: home.resume), AppErrorMessage.serverErrorKey)
        XCTAssertEqual(home.nextUp.value?.first?.id, Sample.movie)
        h.library.resumeError = nil
        await home.retry(rowID: "resume")
        XCTAssertNil(HomePolicy.sectionErrorKey(for: home.resume))
    }

    // T06-57: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_57_playbackStopProjectsImmediatelyAndRefetchesPersonalRows() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        h.library.resumeItems = [Sample.movie()]
        let home = h.home()
        await home.reload(libraryIDs: [])
        await h.app.userData.recordPlayback(id: Sample.movie, position: .seconds(3600), played: true, log: h.log)
        h.library.resumeItems = []
        h.library.nextItems = [Sample.movie(id: Sample.other)]
        let started = ContinuousClock.now
        await home.userDataDidChange()
        XCTAssertEqual(home.resume.value, [])
        XCTAssertEqual(home.nextUp.value?.first?.id, Sample.other)
        XCTAssertLessThan(started.duration(to: .now), .seconds(2))
    }

    // T06-60: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_60_remoteUserDataWinsOverPendingOptimisticChange() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        h.library.resumeItems = [Sample.movie()]
        h.library.latestByID[Sample.library] = .success([Sample.movie()])
        let home = h.home()
        await home.reload(libraryIDs: [Sample.library])
        var optimistic = Sample.movie().userData
        optimistic.isFavorite = true
        await h.app.userData.applyOptimistic(id: Sample.movie, next: optimistic)
        await home.retry(rowID: "resume")
        XCTAssertEqual(home.resume.value?.first?.userData.isFavorite, true)
        let pending = await h.app.userData.isPending(id: Sample.movie)
        XCTAssertTrue(pending)
        let events = FakeEvents()
        h.app.watch(events)
        events.emit(
            .userDataChanged(items: [
                UserDataChange(itemID: Sample.movie, played: true, positionTicks: 0, isFavorite: false)
            ]))
        await waitUntil { h.app.userDataGeneration == 1 }
        await home.refreshFromStore()
        XCTAssertEqual(home.resume.value, [])
        XCTAssertTrue(home.latestRows.first?.state.value?.first?.userData.played == true)
        XCTAssertEqual(home.latestRows.first?.state.value?.first?.userData.isFavorite, false)
        let stillPending = await h.app.userData.isPending(id: Sample.movie)
        XCTAssertFalse(stillPending)
        events.stop()
    }

    // T06-62: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_62_foregroundRefreshOnlyAfterSixtySeconds() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        h.library.resumeItems = [Sample.movie()]
        let home = h.home()
        await home.load()
        home.rememberedIDs["resume"] = Sample.movie
        h.manual?.advance(by: HomePolicy.foregroundAge)
        home.foreground()
        XCTAssertEqual(h.library.resumeCallCount(), 1)
        h.manual?.advance(by: .seconds(1))
        home.foreground()
        await waitUntil { h.library.resumeCallCount() == 2 }
        XCTAssertEqual(home.resume.value?.first?.id, Sample.movie)
        XCTAssertEqual(home.rememberedIDs["resume"], Sample.movie)
    }

    // T06-61: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_61_libraryChangeIsDebouncedAndRefetchesLatestOnly() async throws {
        let h = Harness.make(suspendingClock: true)
        defer { h.cleanup() }
        try h.signIn()
        h.library.viewItems = [Library(id: Sample.library, name: "1")]
        let home = h.home()
        await home.load()
        for count in 1...5 {
            home.libraryDidChange()
            await h.suspending?.waitForSleeps(count)
        }
        XCTAssertEqual(h.suspending?.sleeps(), Array(repeating: HomePolicy.libraryDebounce, count: 5))
        XCTAssertEqual(h.library.latestIdentifiers().count, 1)
        h.suspending?.resumeAll()
        await waitUntil { h.library.latestIdentifiers().count == 2 }
        XCTAssertEqual(h.library.resumeCallCount(), 1)
    }

    // T06-65: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_65_focusRemainsOnSameItemOrSameRowNeighbor() async {
        let a = Sample.movie()
        let b = Sample.movie(id: Sample.other)
        let c = Sample.movie(id: Sample.season)
        XCTAssertEqual(HomeFocus.restoredID(b.id, old: [a, b, c], new: [c, b, a]), b.id)
        XCTAssertEqual(HomeFocus.restoredID(b.id, old: [a, b, c], new: [a, c]), c.id)
        XCTAssertEqual(HomeFocus.restoredID(c.id, old: [a, b, c], new: [a, b]), b.id)
        XCTAssertNil(HomeFocus.restoredID(a.id, old: [a], new: []))
    }

    // T06-32: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_32_playRequestUsesSafeResumePosition() async {
        var item = Sample.movie()
        item.userData.playbackPosition = .seconds(120)
        XCTAssertEqual(HomePlaybackRequest(item: item).position, .seconds(120))
        item.userData.playbackPosition = .seconds(-1)
        XCTAssertEqual(HomePlaybackRequest(item: item).position, .zero)
    }

    // T06-66: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_66_cancelledLoadCannotPublishLateResults() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        h.library.gate = ResumeGate()
        h.library.resumeItems = [Sample.movie()]
        let home = h.home()
        home.start(libraryIDs: [])
        await waitUntil { h.library.gate?.waiting() == 1 }
        home.onDisappear()
        h.library.gate?.releaseAll()
        await waitUntil { h.library.didFinishResume() }
        XCTAssertNil(home.resume.value)
    }

    // T06-66: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_66_disappearanceAlsoCancelsSectionRetry() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        let home = h.home()
        h.library.gate = ResumeGate()
        h.library.resumeItems = [Sample.movie()]
        home.perform { await $0.retry(rowID: "resume") }
        await waitUntil { h.library.gate?.waiting() == 1 }
        home.onDisappear()
        h.library.gate?.releaseAll()
        await waitUntil { h.library.didFinishResume() }
        XCTAssertNil(home.resume.value)
    }

    // T06-44: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_44_snapshotPreservesLibraryGroupingAndRejectsOtherUser() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        h.library.viewItems = [Library(id: Sample.library, name: "1")]
        h.library.latestByID[Sample.library] = .success([Sample.movie()])
        await h.home().load()
        let snapshot = try XCTUnwrap(h.app.snapshots.load())
        XCTAssertEqual(snapshot.libraries?.map(\.id), [Sample.library])
        XCTAssertEqual(snapshot.latestByLibrary?[Sample.library]?.first?.id, Sample.movie)
        XCTAssertEqual(snapshot.serverID, Sample.serverID)
        var wrongUser = snapshot
        wrongUser.userID = Sample.otherUserID
        h.app.snapshots.save(wrongUser)
        h.library.gate = ResumeGate()
        let home = h.home()
        home.start(libraryIDs: [])
        await waitUntil { h.library.gate?.waiting() == 1 }
        XCTAssertNil(home.latest.value)
        home.onDisappear()
        h.library.gate?.releaseAll()
    }

    // T06-49: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_49_serverDownRetainsVisibleContentAndBanner() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        h.library.resumeItems = [Sample.movie()]
        let home = h.home()
        await home.reload(libraryIDs: [])
        h.library.resumeError = .network
        await home.retry(rowID: "resume")
        XCTAssertTrue(home.hasContent)
        XCTAssertEqual(h.app.connectivity, .serverUnreachable)
        XCTAssertEqual(home.bannerKey, AppErrorMessage.serverDownKey)
        XCTAssertNil(home.serverDownTitleKey)
        XCTAssertEqual(home.resume.value?.first?.id, Sample.movie)
        guard case .signedIn = h.app.phase else { return XCTFail("network error ended session") }
    }

    // T06-46: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_46_noContentUsesExistingServerDownTitleKey() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        h.library.resumeError = .network
        h.library.nextError = .network
        let home = h.home()
        await home.reload(libraryIDs: [])
        XCTAssertEqual(home.serverDownTitleKey, AppErrorMessage.messageKey(for: .serverUnreachable))
        XCTAssertNotNil(try h.secure.data(for: Sample.account()))
    }

    // T06-48: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_48_pingRecoversAndKeepsCachedContent() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        h.library.resumeItems = [Sample.movie()]
        let home = h.home()
        await home.reload(libraryIDs: [])
        h.app.handle(.serverUnreachable)
        XCTAssertEqual(h.app.scheduledPingDelay, .seconds(10))
        await h.app.probeServer()
        XCTAssertEqual(h.app.connectivity, .online)
        XCTAssertNil(home.bannerKey)
        XCTAssertTrue(home.hasContent)
    }

    // T06-48: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_48_automaticPingRunsAtTenSecondsAndRecovers() async throws {
        let h = Harness.make(automaticPing: true, suspendingClock: true)
        defer { h.cleanup() }
        try h.signIn()
        h.app.handle(.serverUnreachable)
        await h.suspending?.waitForSleeps(1)
        XCTAssertEqual(h.suspending?.sleeps().first, NetworkThresholds.serverPingInterval)
        h.suspending?.resumeAll()
        await waitUntil { h.app.connectivity == .online }
        XCTAssertEqual(h.pinger.calls(), 1)
    }

    // T06-51: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_51_latest401EndsSessionOnceEvenWhenOtherRowsSucceed() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        h.library.latestByID[Sample.library] = .failure(.unauthorized)
        h.library.latestByID[Sample.other] = .success([Sample.movie()])
        await h.home().reload(libraryIDs: [Sample.library, Sample.other])
        XCTAssertEqual(h.app.sessionNoticeKey, AppErrorMessage.sessionExpiredKey)
        XCTAssertEqual(h.secure.removed().count, 1)
    }

    // T06-41: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_41_actionsCommitAndFailedEditsRestoreTheRow() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        let item = Sample.movie()
        h.library.resumeItems = [item]
        let home = h.home()
        await home.reload(libraryIDs: [])
        await home.setFavorite(item)
        XCTAssertEqual(h.library.favorites().first?.1, true)
        h.library.error = .forbidden
        await home.setPlayed(item, played: true)
        XCTAssertEqual(home.actionError, .forbidden)
        XCTAssertEqual(home.resume.value?.first?.id, item.id)
        h.library.error = nil
        await home.removeFromResume(item)
        XCTAssertEqual(h.library.userDataWrites().first?.1, .zero)
        XCTAssertEqual(h.library.userDataWrites().first?.2, false)
        XCTAssertEqual(home.resume.value, [])
    }

    // T06-57: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_57_playedItemStaysRemovedDuringAStaleServerResponse() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        let item = Sample.movie()
        h.library.resumeItems = [item]
        let home = h.home()
        await home.reload(libraryIDs: [])
        await h.app.userData.recordPlayback(id: item.id, position: .seconds(3600), played: true, log: h.log)
        await home.userDataDidChange()
        XCTAssertEqual(home.resume.value, [])
    }

    // T06-73: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_73_metadataIsCleanedThroughLiveAndCachedViewModels() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        let family = "👩‍👩‍👧‍👦e\u{0301}"
        var item = Sample.movie(
            name: "\u{202e}<b>x</b>\u{0007}" + String(repeating: family, count: MetadataPolicy.nameMax))
        item.overview = "\u{202e}&amp;" + String(repeating: family, count: MetadataPolicy.overviewMax)
        h.library.resumeItems = [item]
        let home = h.home()
        await home.reload(libraryIDs: [])
        let visible = try XCTUnwrap(home.resume.value?.first)
        XCTAssertTrue(visible.name.hasPrefix("<b>x</b>"))
        XCTAssertEqual(visible.name.count, MetadataPolicy.nameMax)
        XCTAssertEqual(visible.overview?.count, MetadataPolicy.overviewMax)
        XCTAssertFalse(visible.name.contains("\u{202e}"))
        XCTAssertFalse(visible.name.contains("\u{0007}"))
        var poisoned = try XCTUnwrap(h.app.snapshots.load())
        poisoned.resume = [item]
        h.app.snapshots.save(poisoned)
        h.library.gate = ResumeGate()
        let restored = h.home()
        restored.start(libraryIDs: [])
        await waitUntil { h.library.gate?.waiting() == 1 }
        XCTAssertEqual(restored.resume.value?.first, visible)
        restored.onDisappear()
        h.library.gate?.releaseAll()
    }

    // T06-24: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_24_backdropDebouncePublishesOnlyTheLastFocusAndCancels() async {
        let clock = SuspendingClock()
        let backdrop = HomeBackdropModel(clock: clock)
        backdrop.focus(Sample.movie())
        await clock.waitForSleeps(1)
        backdrop.focus(Sample.movie(id: Sample.other))
        await clock.waitForSleeps(2)
        XCTAssertNil(backdrop.item)
        XCTAssertEqual(clock.sleeps(), [HomePolicy.backdropDebounce, HomePolicy.backdropDebounce])
        clock.resumeAll()
        await waitUntil { backdrop.item?.id == Sample.other }
        backdrop.focus(Sample.movie(id: Sample.season))
        await clock.waitForSleeps(3)
        backdrop.cancel()
        clock.resumeAll()
        XCTAssertEqual(backdrop.item?.id, Sample.other)
        XCTAssertEqual(HomePolicy.backdropFade(reduceMotion: true), 0)
        XCTAssertEqual(HomePolicy.backdropFade(reduceMotion: false), HomePolicy.backdropFade)
    }

    // T06-16: canonical spec/TESTPLAN-M06.md.
    @MainActor
    func testT06_16_rowsAreBoundedAndDuplicateIDsAreRemoved() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        h.library.resumeItems = (0...HomePolicy.rowLimit).map { Sample.movie(id: String(format: "%032x", $0)) }
        h.library.resumeItems.append(h.library.resumeItems[0])
        let home = h.home()
        await home.reload(libraryIDs: [])
        XCTAssertEqual(home.resume.value?.count, HomePolicy.rowLimit)
    }
    // T06-10: the owner's P0 decision keeps in-progress and next episodes in separate rows.
    @MainActor
    func testT06_10_continueWatchingAndNextUpAreSeparateEpisodeRows() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        let resume = MediaItem(
            id: Sample.movie, kind: .episode, name: "Episode 3", seriesID: Sample.library,
            seasonID: Sample.season, indexNumber: 3, parentIndexNumber: 1,
            userData: UserItemState(playbackPosition: .seconds(120)))
        let next = MediaItem(
            id: Sample.other, kind: .episode, name: "Episode 4", seriesID: Sample.otherServerID,
            seasonID: Sample.season, indexNumber: 4, parentIndexNumber: 1)
        h.library.resumeItems = [resume]
        h.library.nextItems = [next]
        let home = h.home()
        await home.reload(libraryIDs: [])
        XCTAssertEqual(home.resume.value?.map(\.id), [resume.id])
        XCTAssertEqual(home.nextUp.value?.map(\.id), [next.id])
        XCTAssertFalse(HomeFutureFeatures.combinedUpNextEnabled)
        XCTAssertFalse(HomeFutureFeatures.favoritesRowEnabled)
    }

    // T06-33: an item without progress starts at the beginning.
    @MainActor
    func testT06_33_playWithoutProgressStartsAtZero() async {
        XCTAssertEqual(HomePlaybackRequest(item: Sample.movie()).position, .zero)
    }

    // T06-38: the M07 series handoff preserves the episode's season for the season picker.
    @MainActor
    func testT06_38_seriesHandoffPreservesSeasonAndIsHiddenForMovies() async throws {
        let episode = MediaItem(
            id: Sample.movie, kind: .episode, name: "<b>Episode</b>\u{202e}", seriesID: Sample.library,
            seasonID: Sample.season, indexNumber: 3, parentIndexNumber: 1)
        let series = try XCTUnwrap(HomeNavigation.seriesDestination(for: episode))
        XCTAssertEqual(series.id, Sample.library)
        XCTAssertEqual(series.kind, .series)
        XCTAssertEqual(series.seasonID, Sample.season)
        XCTAssertEqual(series.parentIndexNumber, 1)
        XCTAssertEqual(series.name, "<b>Episode</b>")
        XCTAssertNil(HomeNavigation.seriesDestination(for: Sample.movie()))
    }

    // T06-50: a server-dependent action fails inline while cards, focus and credentials remain.
    @MainActor
    func testT06_50_unreachableActionKeepsContentUntilPingRecovery() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        let item = Sample.movie()
        h.library.resumeItems = [item]
        let home = h.home()
        await home.reload(libraryIDs: [])
        home.rememberedIDs["resume"] = item.id
        h.app.handle(.serverUnreachable)
        h.library.error = .network
        await home.setFavorite(item)
        XCTAssertEqual(home.actionError, .serverUnreachable)
        XCTAssertEqual(home.bannerKey, AppErrorMessage.serverDownKey)
        XCTAssertNil(home.serverDownTitleKey)
        XCTAssertEqual(home.resume.value?.first?.id, item.id)
        XCTAssertEqual(home.rememberedIDs["resume"], item.id)
        XCTAssertNotNil(try h.secure.data(for: Sample.account()))
        await h.app.probeServer()
        XCTAssertNil(home.bannerKey)
        XCTAssertEqual(home.resume.value?.first?.id, item.id)
    }

    // T06-63: a foreground transition before 60 seconds makes no new Home request.
    @MainActor
    func testT06_63_foregroundBeforeSixtySecondsDoesNotFetch() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        let home = h.home()
        await home.load()
        let calls = h.library.resumeCallCount()
        h.manual?.advance(by: HomePolicy.foregroundAge - .seconds(1))
        home.foreground()
        XCTAssertEqual(h.library.resumeCallCount(), calls)
        XCTAssertFalse(home.isLoading)
    }

    // T06-56: cold launch restores a displayable snapshot even when its network refresh fails.
    @MainActor
    func testT06_56_cachedColdStartKeepsContentAndServerUnreachableBanner() async throws {
        let h = Harness.make()
        defer { h.cleanup() }
        try h.signIn()
        h.library.resumeItems = [Sample.movie()]
        await h.home().reload(libraryIDs: [])
        h.library.resumeError = .network
        h.library.nextError = .network
        let home = h.home()
        await home.reload(libraryIDs: [], coldStart: true)
        XCTAssertEqual(home.resume.value?.first?.id, Sample.movie)
        XCTAssertEqual(home.bannerKey, AppErrorMessage.serverDownKey)
        XCTAssertNil(home.serverDownTitleKey)
        XCTAssertNotNil(try h.secure.data(for: Sample.account()))
    }

}
