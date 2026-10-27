import CoreModels
import CoreNetworking
import CoreState
import Foundation
import XCTest

final class T02BehaviorTests: XCTestCase {
    @MainActor
    func testT02_01_phasesAndSignInDoNotLogTheToken() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        harness.app.bootstrap()
        XCTAssertEqual(harness.app.phase, .needsServer)

        try seed(harness, version: "10.11.11", token: nil)
        harness.app.bootstrap()
        guard case .needsLogin(let info) = harness.app.phase else {
            return XCTFail("expected login")
        }
        XCTAssertEqual(info.id, Sample.serverID)
        XCTAssertNil(harness.app.blockingError)

        try seed(harness, version: "not-a-version", token: Sample.token)
        harness.app.bootstrap()
        XCTAssertEqual(harness.app.blockingError, .unsupportedServer(version: "not-a-version"))
        guard case .needsLogin = harness.app.phase else { return XCTFail("expected login") }

        let previousWrites = harness.secure.writes().count
        try harness.signIn()
        guard case .signedIn(let session) = harness.app.phase else { return XCTFail("expected session") }
        XCTAssertEqual(session.userName, "Ada")
        XCTAssertEqual(
            harness.secure.writes().dropFirst(previousWrites).filter { $0.hasPrefix("token:") }, [Sample.account()])
        XCTAssertFalse(harness.secure.writes().contains { $0.hasPrefix("session-token/") })
        XCTAssertEqual(harness.app.activeServer?.id, Sample.serverID)
        XCTAssertNil(harness.app.blockingError)
        XCTAssertEqual(harness.log.messages(level: "debug"), ["Signed in."])
        XCTAssertFalse(harness.log.contains(Sample.token))
        let stored = try XCTUnwrap(try harness.secure.data(for: Sample.account()))
        XCTAssertEqual(String(decoding: stored, as: UTF8.self), Sample.token)
        XCTAssertFalse(Sample.account().contains(Sample.token))
        let snapshot = String(decoding: try XCTUnwrap(harness.app.preferencesSnapshotJSON()), as: UTF8.self)
        XCTAssertFalse(snapshot.contains(Sample.token))
        XCTAssertEqual(harness.pinger.calls(), 0)
    }

    @MainActor
    func testT02_10_oldServerBlocksWithoutDroppingTheToken() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try seed(harness, version: "10.9.11", token: Sample.token)
        harness.app.bootstrap()
        XCTAssertEqual(harness.app.blockingError, .unsupportedServer(version: "10.9.11"))
        let error = try XCTUnwrap(harness.app.blockingError)
        XCTAssertEqual(AppErrorMessage.messageKey(for: error), AppErrorMessage.unsupportedServerKey)
        let key = try XCTUnwrap(AppErrorMessage.messageKey(for: error))
        XCTAssertTrue(key.contains("%@"))
        // Version numbers are format arguments, not translated copy.
        let message = try XCTUnwrap(AppErrorMessage.userFacing(error))
        XCTAssertNotEqual(message, key)
        XCTAssertFalse(message.contains("%@"))
        XCTAssertEqual(
            message,
            String(
                format: try englishCatalogText(for: key), "10.9.11", ServerVersionGate.dotted(.minimumJellyfin)))
        XCTAssertTrue(message.contains("10.9.11"))
        XCTAssertTrue(message.contains(ServerVersionGate.dotted(.minimumJellyfin)))
        XCTAssertEqual(ServerVersionGate.dotted(.minimumJellyfin), "10.10.0")
        let serverVersionRange = try XCTUnwrap(message.range(of: "10.9.11"))
        let minimumVersionRange = try XCTUnwrap(message.range(of: ServerVersionGate.dotted(.minimumJellyfin)))
        XCTAssertLessThan(serverVersionRange.lowerBound, minimumVersionRange.lowerBound)
        guard case .needsLogin = harness.app.phase else { return XCTFail("expected login") }
        XCTAssertNotNil(try harness.secure.data(for: Sample.account()))
        harness.app.removeServer(id: Sample.serverID)
        XCTAssertEqual(harness.app.phase, .needsServer)
        XCTAssertNil(harness.app.activeServer)
    }

    @MainActor
    func testSignInRejectsOverBudgetAndKeychainFailureBeforeASession() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        var session = Sample.session()
        session.userName = String(repeating: "n", count: 60_000)
        XCTAssertThrowsError(try harness.app.didSignIn(session, token: Sample.token)) { error in
            guard let prefs = error as? PreferencesError, case .overBudget = prefs else {
                return XCTFail("expected overBudget")
            }
        }
        XCTAssertEqual(harness.app.phase, .launching)
        XCTAssertNil(try harness.secure.data(for: Sample.account()))
        XCTAssertFalse(harness.log.contains(Sample.token))

        harness.secure.failSet = true
        XCTAssertThrowsError(try harness.signIn()) { error in
            XCTAssertEqual(error as? PreferencesError, .keychainFailed)
        }
        XCTAssertEqual(harness.app.phase, .launching)
        XCTAssertTrue(harness.log.messages(level: "warning").contains("Non-fatal invariant failure"))
        XCTAssertFalse(harness.log.contains(Sample.token))
    }

    @MainActor
    func testT02_04_offlineBannerBlocksPlaybackAndRestores() async throws {
        let harness = Harness.make(online: false)
        defer { harness.cleanup() }
        XCTAssertEqual(harness.app.connectivity, .offline)
        XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.offlineKey)
        try assertEnglishCopy(harness.app.banner, key: AppErrorMessage.offlineKey, expected: "No network connection")
        XCTAssertTrue(harness.app.playbackBlocked)
        XCTAssertEqual(harness.app.playbackBlockedMessageKey, AppErrorMessage.playbackOfflineKey)
        try harness.signIn()
        XCTAssertTrue(harness.app.playbackBlocked)
        let box = Counter()
        harness.app.onReconnect = { box.value += 1 }
        harness.pinger.outcome = .ok
        harness.app.startPathUpdates()
        harness.path.setOnline(true)
        await waitUntil { box.value == 1 && harness.app.connectivity == .online }
        XCTAssertNil(harness.app.banner)
        XCTAssertFalse(harness.app.playbackBlocked)
        XCTAssertNil(harness.app.playbackBlockedMessage)
        guard case .signedIn = harness.app.phase else { return XCTFail("stayed signed in") }

        harness.path.setOnline(false)
        await waitUntil { harness.app.bannerKey == AppErrorMessage.offlineKey }
        try assertEnglishCopy(harness.app.banner, key: AppErrorMessage.offlineKey, expected: "No network connection")
        XCTAssertTrue(harness.app.playbackBlocked)
        XCTAssertEqual(harness.app.playbackBlockedMessageKey, AppErrorMessage.playbackOfflineKey)
        XCTAssertNotNil(try harness.secure.data(for: Sample.account()))
    }

    @MainActor
    func testT02_05_degradedAfterThreeSecondsNotAtTheBoundary() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        harness.app.noteRequestFinished(elapsed: .seconds(3))
        XCTAssertEqual(harness.app.connectivity, .online)
        harness.app.noteRequestFinished(elapsed: .seconds(3) + .nanoseconds(1))
        XCTAssertEqual(harness.app.connectivity, .degraded)
        XCTAssertFalse(harness.app.playbackBlocked)
        harness.app.noteRequestFinished(elapsed: .milliseconds(10))
        XCTAssertEqual(harness.app.connectivity, .online)
        harness.app.handle(.serverUnreachable)
        harness.app.noteRequestFinished(elapsed: .seconds(9))
        XCTAssertEqual(harness.app.connectivity, .serverUnreachable)
        XCTAssertEqual(harness.app.playbackBlockedMessageKey, AppErrorMessage.playbackUnreachableKey)
        XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.serverDownKey)
        try assertEnglishCopy(
            harness.app.banner, key: AppErrorMessage.serverDownKey, expected: "Can't reach the server")
        harness.app.handle(.offline)
        XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.offlineKey)
        try assertEnglishCopy(harness.app.banner, key: AppErrorMessage.offlineKey, expected: "No network connection")
        harness.app.noteRequestFinished(elapsed: .seconds(9))
        XCTAssertEqual(harness.app.connectivity, .offline)
    }

    @MainActor
    func testT02_06_serverDownPingRecoversWithoutLogout() async throws {
        let harness = Harness.make(automaticPing: true, suspendingClock: true)
        defer { harness.cleanup() }
        try harness.signIn()
        harness.app.handle(.serverUnreachable)
        XCTAssertTrue(harness.app.showsServerDown)
        XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.serverDownKey)
        try assertEnglishCopy(
            harness.app.banner, key: AppErrorMessage.serverDownKey, expected: "Can't reach the server")
        XCTAssertEqual(harness.app.serverDownTitleKey, AppErrorMessage.serverDownKey)
        XCTAssertEqual(harness.app.retryTitleKey, AppErrorMessage.retryKey)
        XCTAssertEqual(harness.app.changeServerTitleKey, AppErrorMessage.changeServerKey)
        await waitUntil { harness.suspending?.sleeps() == [.seconds(10)] }
        harness.pinger.outcome = .ok
        harness.suspending?.resumeAll()
        await waitUntil { harness.app.connectivity == .online }
        XCTAssertNil(harness.app.bannerKey)
        XCTAssertNil(harness.app.banner)
        XCTAssertFalse(harness.app.showsServerDown)
        guard case .signedIn = harness.app.phase else { return XCTFail("must stay signed in") }
        XCTAssertNotNil(try harness.secure.data(for: Sample.account()))
        XCTAssertGreaterThanOrEqual(harness.pinger.calls(), 1)

        harness.app.handle(.serverUnreachable)
        harness.pinger.outcome = .failed(.serverError(status: 401))
        await harness.app.retryNow()
        XCTAssertEqual(harness.app.connectivity, .online)
        XCTAssertNil(harness.app.bannerKey)
        XCTAssertNil(harness.app.banner)
        guard case .signedIn = harness.app.phase else { return XCTFail("public 401 is not logout") }
    }

    @MainActor
    func testT02_35a_serverDownWithContentKeepsContentAndShowsBanner() async throws {
        for cached in [false, true] {
            let harness = Harness.make(automaticPing: true, suspendingClock: true)
            defer { harness.cleanup() }
            try harness.signIn()
            let resume = [Sample.movie(name: "Resume")]
            let next = [Sample.movie(id: Sample.other, name: "Next")]
            let latest = [Sample.movie(id: Sample.season, name: "Latest")]
            let home = harness.home()
            if cached {
                XCTAssertTrue(harness.app.snapshots.save(HomeSnapshot(resume: resume, nextUp: next, latest: latest)))
            } else {
                harness.library.resumeItems = resume
                harness.library.nextItems = next
                harness.library.latestByID[Sample.library] = .success(latest)
                await home.reload(libraryIDs: [Sample.library])
                harness.app.handle(.serverUnreachable)
                XCTAssertFalse(harness.app.showsServerDown)
                // Exercise previous loaded values independently of both caches.
                harness.app.snapshots.purge()
                await harness.app.responses.invalidateAll()
            }

            harness.library.resumeError = .network
            harness.library.nextError = .network
            harness.library.latestByID[Sample.library] = .failure(.network)
            await home.reload(libraryIDs: [Sample.library])
            XCTAssertEqual(home.resume.value, resume)
            XCTAssertEqual(home.nextUp.value, next)
            XCTAssertEqual(home.latest.value, latest)
            XCTAssertEqual(home.resume, .failed(.serverUnreachable, previous: resume))
            XCTAssertEqual(home.nextUp, .failed(.serverUnreachable, previous: next))
            XCTAssertEqual(home.latest, .failed(.serverUnreachable, previous: latest))
            XCTAssertEqual(home.resume.presentedError, .serverUnreachable)
            XCTAssertEqual(harness.app.connectivity, .serverUnreachable)
            XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.serverDownKey)
            try assertEnglishCopy(
                harness.app.banner, key: AppErrorMessage.serverDownKey, expected: "Can't reach the server")
            XCTAssertFalse(harness.app.showsServerDown)

            let editor = UserDataEditor(
                store: harness.app.userData, library: harness.library, app: harness.app, log: harness.log)
            harness.library.error = .network
            await editor.setFavorite(id: Sample.movie, favorite: true)
            XCTAssertEqual(harness.library.favorites().map(\.0), [Sample.movie])
            XCTAssertEqual(editor.lastError, .serverUnreachable)
            let actionError = try XCTUnwrap(editor.lastError)
            try assertEnglishCopy(
                AppErrorMessage.userFacing(actionError), key: AppErrorMessage.serverDownKey,
                expected: "Can't reach the server")
            guard case .signedIn = harness.app.phase else { return XCTFail("action failure must keep the session") }
            XCTAssertEqual(try harness.secure.data(for: Sample.account()), Data(Sample.token.utf8))
            XCTAssertTrue(harness.secure.removed().isEmpty)
            XCTAssertFalse(harness.app.showsServerDown)

            await waitUntil { harness.suspending?.sleeps() == [.seconds(10)] }
            XCTAssertEqual(harness.pinger.calls(), 0)
            harness.pinger.outcome = .ok
            harness.suspending?.resumeAll()
            await waitUntil { harness.app.connectivity == .online }
            XCTAssertEqual(harness.app.connectivity, .online)
            XCTAssertEqual(harness.pinger.calls(), 1)
            XCTAssertNil(harness.app.bannerKey)
            XCTAssertNil(harness.app.banner)
            XCTAssertFalse(harness.app.showsServerDown)
            XCTAssertEqual(home.resume.value, resume)
            XCTAssertEqual(home.nextUp.value, next)
            XCTAssertEqual(home.latest.value, latest)
            guard case .signedIn = harness.app.phase else { return XCTFail("recovery must keep the session") }
            XCTAssertEqual(try harness.secure.data(for: Sample.account()), Data(Sample.token.utf8))
            XCTAssertTrue(harness.secure.removed().isEmpty)
            XCTAssertEqual(harness.log.messages(level: "debug").filter { $0 == "Signed in." }.count, 1)
        }
    }

    @MainActor
    func testT02_35b_serverDownWithoutContentShowsFullScreen() async throws {
        let harness = Harness.make(automaticPing: true, suspendingClock: true)
        defer { harness.cleanup() }
        try harness.signIn()
        XCTAssertNil(harness.app.snapshots.load())
        let home = harness.home()
        XCTAssertNil(home.resume.value)
        XCTAssertNil(home.nextUp.value)
        XCTAssertNil(home.latest.value)
        harness.library.resumeError = .network
        harness.library.nextError = .network
        harness.library.latestByID[Sample.library] = .failure(.network)

        await home.reload(libraryIDs: [Sample.library])
        XCTAssertEqual(harness.library.resumeCallCount(), 1)
        XCTAssertEqual(harness.library.nextCallCount(), 1)
        XCTAssertEqual(harness.library.latestIdentifiers(), [Sample.library])
        XCTAssertEqual(home.resume, .failed(.serverUnreachable, previous: nil))
        XCTAssertEqual(home.nextUp, .failed(.serverUnreachable, previous: nil))
        XCTAssertEqual(home.latest, .failed(.serverUnreachable, previous: nil))
        XCTAssertFalse(home.hasContent)
        XCTAssertEqual(harness.app.connectivity, .serverUnreachable)
        XCTAssertTrue(harness.app.showsServerDown)
        XCTAssertEqual(harness.app.serverDownTitleKey, AppErrorMessage.serverDownKey)
        XCTAssertEqual(harness.app.retryTitleKey, AppErrorMessage.retryKey)
        XCTAssertEqual(harness.app.changeServerTitleKey, AppErrorMessage.changeServerKey)
        try assertEnglishCopy(
            harness.app.serverDownTitle, key: AppErrorMessage.serverDownKey, expected: "Can't reach the server")
        try assertEnglishCopy(harness.app.retryTitle, key: AppErrorMessage.retryKey, expected: "Try again")
        try assertEnglishCopy(
            harness.app.changeServerTitle, key: AppErrorMessage.changeServerKey, expected: "Change server")
        guard case .signedIn = harness.app.phase else { return XCTFail("first fetch failure must keep the session") }
        XCTAssertEqual(try harness.secure.data(for: Sample.account()), Data(Sample.token.utf8))
        XCTAssertTrue(harness.secure.removed().isEmpty)

        await waitUntil { harness.suspending?.sleeps() == [.seconds(10)] }
        XCTAssertEqual(harness.pinger.calls(), 0)
        harness.pinger.outcome = .ok
        harness.suspending?.resumeAll()
        await waitUntil { harness.app.connectivity == .online }
        XCTAssertEqual(harness.app.connectivity, .online)
        XCTAssertEqual(harness.pinger.calls(), 1)
        XCTAssertFalse(harness.app.showsServerDown)
        XCTAssertNil(harness.app.bannerKey)
        XCTAssertNil(harness.app.banner)
        guard case .signedIn = harness.app.phase else { return XCTFail("automatic recovery must keep the session") }
        XCTAssertEqual(try harness.secure.data(for: Sample.account()), Data(Sample.token.utf8))
        XCTAssertTrue(harness.secure.removed().isEmpty)
        XCTAssertEqual(harness.log.messages(level: "debug").filter { $0 == "Signed in." }.count, 1)
    }

    @MainActor
    func testT02_36_bannerTextResolvesFromKey() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        harness.library.resumeItems = [Sample.movie()]
        let home = harness.home()
        await home.reload(libraryIDs: [])

        harness.app.handle(.offline)
        XCTAssertEqual(harness.app.connectivity, .offline)
        XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.offlineKey)
        try assertEnglishCopy(harness.app.banner, key: AppErrorMessage.offlineKey, expected: "No network connection")

        await harness.app.probeServer()
        XCTAssertEqual(harness.app.connectivity, .online)
        XCTAssertNil(harness.app.banner)
        harness.app.handle(.serverUnreachable)
        XCTAssertEqual(harness.app.connectivity, .serverUnreachable)
        XCTAssertTrue(home.hasContent)
        XCTAssertFalse(harness.app.showsServerDown)
        XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.serverDownKey)
        try assertEnglishCopy(
            harness.app.banner, key: AppErrorMessage.serverDownKey, expected: "Can't reach the server")

        await harness.app.probeServer()
        XCTAssertEqual(harness.app.connectivity, .online)
        XCTAssertNil(harness.app.bannerKey)
        XCTAssertNil(harness.app.banner)
    }

    @MainActor
    func testT02_37_sessionNoticeTextResolvesFromKey() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        XCTAssertNil(harness.app.sessionNotice)
        harness.library.resumeError = .unauthorized
        let home = harness.home()
        await home.reload(libraryIDs: [])

        guard case .needsLogin = harness.app.phase else { return XCTFail("authenticated 401 must end the session") }
        XCTAssertEqual(home.resume.presentedError, .unauthorized)
        XCTAssertEqual(harness.app.sessionNoticeKey, AppErrorMessage.sessionExpiredKey)
        try assertEnglishCopy(
            harness.app.sessionNotice, key: AppErrorMessage.sessionExpiredKey,
            expected: "Session expired, please sign in again")

        try harness.signIn()
        guard case .signedIn = harness.app.phase else { return XCTFail("expected a new session") }
        XCTAssertNil(harness.app.sessionNoticeKey)
        XCTAssertNil(harness.app.sessionNotice)
    }

    @MainActor
    func testT02_38_stallMessageTextResolvesFromKey() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        let player = PlayerViewModel(
            playback: harness.playback, reporting: harness.reporting, userData: harness.app.userData, app: harness.app,
            signposter: harness.signposter, log: harness.log)
        await player.load(itemID: Sample.movie)
        XCTAssertEqual(player.state.value, harness.playback.source)

        player.noteBuffering(elapsed: .seconds(5))
        XCTAssertNil(player.stallMessageKey)
        XCTAssertNil(player.stallMessage)
        player.noteBuffering(elapsed: .seconds(5) + .milliseconds(1))
        XCTAssertEqual(player.stallMessageKey, AppErrorMessage.bufferingKey)
        try assertEnglishCopy(
            player.stallMessage, key: AppErrorMessage.bufferingKey, expected: "Buffering is taking longer than usual")
        player.noteBuffering(elapsed: .zero)
        XCTAssertNil(player.stallMessageKey)
        XCTAssertNil(player.stallMessage)
    }

    @MainActor
    func testServerDownUsesOnlyCurrentViewContent() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        let home = harness.home()
        await home.reload(libraryIDs: [])
        harness.app.handle(.serverUnreachable)
        XCTAssertTrue(harness.app.showsServerDown)  // Loaded empty lists have nothing to display.

        harness.library.resumeItems = [Sample.movie()]
        await harness.app.responses.invalidateAll()
        await home.reload(libraryIDs: [])
        XCTAssertFalse(harness.app.showsServerDown)

        let library = LibraryViewModel(
            library: harness.library, userData: harness.app.userData, responses: harness.app.responses,
            app: harness.app, clock: harness.clock)
        harness.library.error = .network
        await library.reload(libraryID: Sample.library)
        XCTAssertNil(library.state.value)
        XCTAssertEqual(library.state.presentedError, .serverUnreachable)
        XCTAssertTrue(harness.app.showsServerDown)
        XCTAssertEqual(home.resume.value, [Sample.movie()])  // Home is retained, but is no longer visible.

        let items = (0..<50).map { Sample.movie(id: String(format: "%032x", $0)) }
        harness.library.error = nil
        harness.library.pages[0] = Page(items: items, totalCount: 70)
        await library.reload(libraryID: Sample.library)
        XCTAssertFalse(harness.app.showsServerDown)
        harness.library.error = .network
        await library.loadNextPageIfNeeded(visibleIndex: 39)
        XCTAssertEqual(library.state.value, items)
        XCTAssertEqual(library.state.presentedError, .serverUnreachable)
        XCTAssertFalse(harness.app.showsServerDown)

        await harness.app.responses.invalidateAll()
        await library.reload(libraryID: Sample.library)
        XCTAssertEqual(library.state.value, items)
        XCTAssertFalse(harness.app.showsServerDown)
        await library.reload(libraryID: Sample.other)
        XCTAssertNil(library.state.value)
        XCTAssertTrue(harness.app.showsServerDown)
        harness.app.currentView = home  // Returning to a retained screen without a reload.
        XCTAssertFalse(harness.app.showsServerDown)
        harness.app.currentView = nil
        XCTAssertTrue(harness.app.showsServerDown)
        XCTAssertEqual(harness.app.connectivity, .serverUnreachable)
        XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.serverDownKey)
        try assertEnglishCopy(
            harness.app.banner, key: AppErrorMessage.serverDownKey, expected: "Can't reach the server")
    }

    @MainActor
    func testStoredUnparseableVersionIsCleanedAndCappedBeforeFormatting() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        let tail = String(repeating: "e\u{0301}👩‍👩‍👧‍👦", count: 210)
        let raw = "\u{202E}10.\u{0007}x\u{061C}\u{200E}\u{200F}\u{0085}\u{2066}<b>**" + tail
        XCTAssertGreaterThan(raw.count, 200)
        try seed(harness, version: raw, token: Sample.token)
        harness.app.bootstrap()
        guard case .needsLogin = harness.app.phase else { return XCTFail("expected a blocking login screen") }
        let error = try XCTUnwrap(harness.app.blockingError)
        let key = try XCTUnwrap(AppErrorMessage.messageKey(for: error))
        XCTAssertEqual(key, AppErrorMessage.unsupportedServerKey)
        let message = try XCTUnwrap(AppErrorMessage.userFacing(error))
        let expectedVersion = String(("10.x<b>**" + tail).prefix(200))
        XCTAssertEqual(
            message,
            String(
                format: try englishCatalogText(for: key), expectedVersion,
                ServerVersionGate.dotted(.minimumJellyfin)))
        let versionEnd = try XCTUnwrap(message.range(of: " is not supported."))
        let embedded = String(message[..<versionEnd.lowerBound].dropFirst("Server version ".count))
        XCTAssertEqual(embedded, expectedVersion)
        XCTAssertEqual(embedded.count, 200)
        XCTAssertLessThanOrEqual(embedded.count, 200)
        XCTAssertGreaterThan(embedded.unicodeScalars.count, embedded.count)
        XCTAssertTrue(embedded.contains("<b>**"))  // Untrusted markup stays literal.
        XCTAssertFalse(message.unicodeScalars.contains { $0.properties.generalCategory == .control })
        let bidi: Set<UInt32> = [
            0x061C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069,
        ]
        XCTAssertTrue(bidi.isDisjoint(with: message.unicodeScalars.map(\.value)))
        XCTAssertFalse(message.contains("%@"))
        XCTAssertNotNil(try harness.secure.data(for: Sample.account()))
    }

    @MainActor
    func testT02_07_authenticated401LogsOutOnce() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        let task = Task<Void, Never> { try? await Task.sleep(for: .seconds(30)) }
        harness.app.scope.track(task)
        harness.library.resumeError = .unauthorized
        harness.library.nextError = .unauthorized
        let home = harness.home()
        await home.reload(libraryIDs: [])
        guard case .needsLogin(let info) = harness.app.phase else { return XCTFail("expected login") }
        XCTAssertEqual(info.id, Sample.serverID)
        XCTAssertEqual(harness.app.sessionNoticeKey, AppErrorMessage.sessionExpiredKey)
        try assertEnglishCopy(
            harness.app.sessionNotice, key: AppErrorMessage.sessionExpiredKey,
            expected: "Session expired, please sign in again")
        XCTAssertEqual(harness.secure.removed(), [Sample.account()])
        XCTAssertNil(try harness.secure.data(for: Sample.account()))
        XCTAssertFalse(harness.log.contains(Sample.token))
        XCTAssertTrue(harness.log.messages().contains("Ended the session after HTTP 401."))
        if case .failed(.unauthorized, _) = home.resume {} else { XCTFail("resume should fail unauthorized") }
        await task.value
        XCTAssertTrue(task.isCancelled)
        harness.app.handle(.unauthorized)
        XCTAssertEqual(harness.secure.removed().count, 1)
    }

    @MainActor
    func testT02_28_concurrent401StillLogsOutOnce() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        let app = harness.app
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask { @MainActor in
                    app.handle(.unauthorized)
                }
            }
        }
        XCTAssertEqual(harness.secure.removed().count, 1)
        guard case .needsLogin = harness.app.phase else { return XCTFail("expected login") }
        XCTAssertEqual(harness.app.sessionNoticeKey, AppErrorMessage.sessionExpiredKey)
        try assertEnglishCopy(
            harness.app.sessionNotice, key: AppErrorMessage.sessionExpiredKey,
            expected: "Session expired, please sign in again")
    }

    @MainActor
    func testT02_31_network403And5xxDoNotLogOut() async throws {
        let errors: [APIError] = [
            .network, .timeout, .forbidden, .server(status: 500), .server(status: 502), .tls,
            .redirectRejected(.notFollowed),
        ]
        for error in errors {
            let harness = Harness.make()
            defer { harness.cleanup() }
            try harness.signIn()
            harness.library.resumeError = error
            let home = harness.home()
            await home.reload(libraryIDs: [])
            guard case .signedIn = harness.app.phase else {
                XCTFail("\(error) logged out")
                continue
            }
            XCTAssertNotNil(try harness.secure.data(for: Sample.account()))
            XCTAssertNil(harness.app.sessionNotice)
            if harness.app.connectivity == .serverUnreachable {
                XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.serverDownKey)
                try assertEnglishCopy(
                    harness.app.banner, key: AppErrorMessage.serverDownKey, expected: "Can't reach the server")
            }
            XCTAssertTrue(harness.secure.removed().isEmpty)
        }
    }

    @MainActor
    func testT02_32_forbiddenKeepsTheSession() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        harness.library.resumeError = .forbidden
        let home = harness.home()
        await home.reload(libraryIDs: [])
        XCTAssertEqual(home.resume.presentedError, .forbidden)
        XCTAssertEqual(AppErrorMessage.messageKey(for: .forbidden), AppErrorMessage.forbiddenKey)
        guard case .signedIn = harness.app.phase else { return XCTFail("session dropped") }
    }

    @MainActor
    func testT02_22_cancelledIsNotPresented() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        harness.library.resumeError = .cancelled
        let home = harness.home()
        await home.reload(libraryIDs: [])
        XCTAssertNil(home.resume.presentedError)
        if case .failed = home.resume { XCTFail("cancelled became a visible failure") }
        guard case .signedIn = harness.app.phase else { return XCTFail("session dropped") }
        XCTAssertFalse(harness.log.messages().contains("cancelled"))
    }

    @MainActor
    func testT02_23_insecureRedirectSetsSecurityNotice() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        harness.library.resumeError = .redirectRejected(.httpsDowngrade)
        let home = harness.home()
        await home.reload(libraryIDs: [])
        XCTAssertEqual(harness.app.securityNotice, .insecureRedirect)
        guard case .signedIn = harness.app.phase else { return XCTFail("session dropped") }
        if case .failed(.insecureRedirect, _) = home.resume {} else { XCTFail("expected insecure redirect") }
    }

    @MainActor
    func testT02_24_invalidCredentialsDoNotEndASession() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        harness.app.handle(.invalidCredentials)
        guard case .signedIn = harness.app.phase else { return XCTFail("login 401 must not end the session") }
        XCTAssertNil(harness.app.sessionNotice)
        XCTAssertNotNil(try harness.secure.data(for: Sample.account()))
    }

    @MainActor
    func testT02_25_homeShowsSnapshotThenRevalidates() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        let snapshot = HomeSnapshot(resume: [Sample.movie(name: "Cached")], nextUp: [], latest: [])
        XCTAssertTrue(harness.app.snapshots.save(snapshot))
        XCTAssertEqual(harness.app.snapshots.load()?.resume.first?.name, "Cached")
        harness.library.gate = ResumeGate()
        harness.library.resumeItems = [Sample.movie(name: "Live")]
        harness.library.nextItems = [Sample.movie(id: Sample.other, name: "Next")]
        let home = harness.home()
        home.start(libraryIDs: [], coldStart: true)
        await waitUntil { home.resume.isLoading && home.resume.value?.first?.name == "Cached" }
        XCTAssertEqual(ended(harness.signposter.snapshot(), .coldStartHomeFirstRow), 1)
        XCTAssertEqual(began(harness.signposter.snapshot(), .homeSectionsLoaded), 1)
        harness.library.gate?.releaseAll()
        await waitUntil { ended(harness.signposter.snapshot(), .homeSectionsLoaded) == 1 }
        XCTAssertEqual(home.resume.value?.first?.name, "Live")
        XCTAssertEqual(home.nextUp.value?.first?.name, "Next")
        XCTAssertEqual(home.latest.value, [])
        XCTAssertTrue(harness.library.latestIdentifiers().isEmpty)
        XCTAssertEqual(ended(harness.signposter.snapshot(), .coldStartHomeFirstRow), 1)

        harness.app.snapshots.purge()
        XCTAssertNil(harness.app.snapshots.load())
        try Data("not-json".utf8).write(to: harness.app.snapshots.file)
        XCTAssertNil(harness.app.snapshots.load())
    }

    @MainActor
    func testColdStartWithoutSnapshotEndsAfterTheFetch() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        harness.library.gate = ResumeGate()
        harness.library.resumeItems = [Sample.movie()]
        harness.library.latestByID[Sample.library] = .success([Sample.movie(id: Sample.other, name: "Latest")])
        let home = harness.home()
        home.start(libraryIDs: [Sample.library, "not-a-guid"], coldStart: true)
        await waitUntil { home.resume.isLoading }
        XCTAssertEqual(ended(harness.signposter.snapshot(), .coldStartHomeFirstRow), 0)
        harness.library.gate?.releaseAll()
        await waitUntil { ended(harness.signposter.snapshot(), .coldStartHomeFirstRow) == 1 }
        XCTAssertEqual(home.latest.value?.first?.name, "Latest")
        XCTAssertEqual(harness.library.latestIdentifiers(), [Sample.library])
    }

    @MainActor
    func testHomeLatestKeepsSuccessesAndSurfacesATotalFailure() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        harness.library.latestByID[Sample.library] = .failure(.notFound)
        harness.library.latestByID[Sample.other] = .success([Sample.movie()])
        let home = harness.home()
        await home.reload(libraryIDs: [Sample.library, Sample.other])
        XCTAssertEqual(home.latest.value?.map(\.id), [Sample.movie])

        harness.library.latestByID[Sample.other] = .failure(.forbidden)
        harness.manual?.advance(by: NetworkThresholds.homeTTL)
        await home.reload(libraryIDs: [Sample.library, Sample.other])
        if case .failed(.notFound, let previous) = home.latest {
            XCTAssertEqual(previous?.map(\.id), [Sample.movie])
        } else {
            XCTFail("expected notFound with previous items")
        }
    }

    @MainActor
    func testHomeCancellationDoesNotPublish() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        harness.library.gate = ResumeGate()
        harness.library.resumeItems = [Sample.movie(name: "ShouldNotLand")]
        let home = harness.home()
        home.start(libraryIDs: [])
        await waitUntil { harness.library.gate?.waiting() == 1 }
        home.onDisappear()
        harness.library.gate?.releaseAll()
        await waitUntil { ended(harness.signposter.snapshot(), .homeSectionsLoaded) == 1 }
        if case .loaded = home.resume { XCTFail("cancelled load published") }
        XCTAssertNotEqual(home.resume.value?.first?.name, "ShouldNotLand")
    }

    @MainActor
    func testT02_26_serverRestartDoesNotLogOutAndInvalidatesCaches() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        let events = FakeEvents()
        harness.app.watch(events)
        events.emit(.serverRestarting)
        await waitUntil { harness.app.connectivity == .serverUnreachable }
        XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.serverDownKey)
        try assertEnglishCopy(
            harness.app.banner, key: AppErrorMessage.serverDownKey, expected: "Can't reach the server")
        guard case .signedIn = harness.app.phase else { return XCTFail("restart logged out") }
        XCTAssertNotNil(try harness.secure.data(for: Sample.account()))
        events.emit(.serverShuttingDown)
        events.emit(.play)
        events.emit(.playstate)
        events.emit(.generalCommand)
        guard case .signedIn = harness.app.phase else { return XCTFail("session dropped") }

        await harness.app.responses.insert(Data("row".utf8), for: "home.resume", ttl: .seconds(60), now: .zero)
        events.emit(
            .userDataChanged(
                items: [
                    UserDataChange(itemID: "not-a-guid", played: true, positionTicks: 0, isFavorite: false),
                    UserDataChange(itemID: Sample.movie, played: true, positionTicks: -1, isFavorite: true),
                ]))
        await waitUntil { harness.app.userDataGeneration == 1 }
        let state = await harness.app.userData.state(for: Sample.movie)
        XCTAssertEqual(state?.played, true)
        XCTAssertEqual(state?.playbackPosition, .zero)
        let homeCache = await harness.app.responses.data(for: "home.resume", now: .zero)
        XCTAssertNil(homeCache)
        XCTAssertEqual(ended(harness.signposter.snapshot(), .remoteUserData), 1)
        events.emit(
            .userDataChanged(
                items: [UserDataChange(itemID: Sample.movie, played: true, positionTicks: -2, isFavorite: true)]))
        await waitUntil { harness.app.userDataGeneration == 2 }
        XCTAssertEqual(harness.log.messages().filter { $0.contains("Negative position") }.count, 1)

        await harness.app.responses.insert(Data("lib".utf8), for: "library", ttl: .seconds(60), now: .zero)
        events.emit(.libraryChanged)
        await waitUntil { harness.app.libraryGeneration == 1 }
        let libraryCache = await harness.app.responses.data(for: "library", now: .zero)
        XCTAssertNil(libraryCache)
    }

    @MainActor
    func testT02_27_internalInvariantIsLoggedAndDoesNotCrash() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        harness.app.handle(.internalInvariant)
        guard case .signedIn = harness.app.phase else { return XCTFail("invariant ended the session") }
        XCTAssertTrue(harness.log.messages(level: "warning").contains("Non-fatal invariant failure"))
        let library = LibraryViewModel(
            library: harness.library, userData: harness.app.userData, responses: harness.app.responses,
            app: harness.app,
            clock: harness.clock, log: harness.log)
        await library.reload(libraryID: "not-a-guid")
        if case .failed(.internalInvariant, _) = library.state {} else { XCTFail("expected invariant") }
        XCTAssertEqual(harness.library.itemCallCount(), 0)
        let series = SeriesViewModel(
            library: harness.library, userData: harness.app.userData, app: harness.app, log: harness.log)
        await series.load(seriesID: "not-a-guid")
        if case .failed(.internalInvariant, _) = series.seasons {} else { XCTFail("expected invariant") }
        let player = PlayerViewModel(
            playback: harness.playback, reporting: harness.reporting, userData: harness.app.userData, app: harness.app,
            signposter: harness.signposter, log: harness.log)
        await player.load(itemID: "not-a-guid")
        XCTAssertNil(harness.playback.lastBitrate())
        if case .failed(.internalInvariant, _) = player.state {} else { XCTFail("expected invariant") }
    }

    @MainActor
    func testT02_17_searchKeepsTheFullTermAndDropsStaleResults() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        harness.search.gate = ResumeGate()
        let search = SearchViewModel(
            search: harness.search, userData: harness.app.userData, app: harness.app, clock: harness.clock,
            signposter: harness.signposter)
        let term = "abcdefghijklmnopqrst"
        XCTAssertEqual(term.count, 20)
        search.setTerm("ab")
        await waitUntil { harness.search.termsSeen().count == 1 }
        search.setTerm(term)
        XCTAssertEqual(search.term, term)
        await waitUntil { harness.search.termsSeen().count == 2 }
        XCTAssertEqual(harness.manual?.sleeps(), [.milliseconds(300), .milliseconds(300)])
        harness.search.gate?.releaseAll()
        await waitUntil {
            if case .loaded(let items) = search.state { return items.first?.name == term }
            return false
        }
        XCTAssertEqual(ended(harness.signposter.snapshot(), .searchResults), 2)

        harness.search.gate = nil
        harness.search.error = .cancelled
        search.setTerm("cancelled-term")
        await waitUntil { harness.search.termsSeen().contains("cancelled-term") }
        await waitUntil { ended(harness.signposter.snapshot(), .searchResults) == 3 }
        XCTAssertNil(search.state.presentedError)
        search.onDisappear()
    }

    @MainActor
    func testT02_34_libraryPagesAndCacheTTL() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        let first = (0..<50).map { index in
            MediaItem(id: String(format: "%032x", index), kind: .movie, name: "Item \(index)")
        }
        let second = (50..<70).map { index in
            MediaItem(id: "row-\(index)", kind: .movie, name: "Item \(index)")
        }
        harness.library.pages[0] = Page(items: first, totalCount: 70)
        harness.library.pages[50] = Page(items: second, totalCount: 70)
        let library = LibraryViewModel(
            library: harness.library, userData: harness.app.userData, responses: harness.app.responses,
            app: harness.app,
            clock: harness.clock, log: harness.log)
        await library.reload(libraryID: Sample.library)
        XCTAssertEqual(library.state.value?.count, 50)
        XCTAssertEqual(library.totalCount, 70)
        await library.loadNextPageIfNeeded(visibleIndex: 0)
        XCTAssertEqual(harness.library.itemCallCount(), 1)
        await library.loadNextPageIfNeeded(visibleIndex: 39)
        XCTAssertEqual(library.state.value?.count, 70)
        XCTAssertEqual(library.totalCount, 70)
        XCTAssertEqual(harness.library.itemCallCount(), 2)
        await library.loadNextPageIfNeeded(visibleIndex: 69)
        XCTAssertEqual(harness.library.itemCallCount(), 2)

        await library.reload(libraryID: Sample.library)
        XCTAssertEqual(harness.library.itemCallCount(), 2)
        harness.manual?.advance(by: NetworkThresholds.libraryListTTL)
        await library.reload(libraryID: Sample.library)
        XCTAssertEqual(harness.library.itemCallCount(), 3)

        harness.library.error = .cancelled
        await library.reload(libraryID: Sample.other)
        if case .failed = library.state { XCTFail("cancelled page became a failure") }
    }

    @MainActor
    func testSeriesKeepsPreviousSeasonOnFailure() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        harness.library.seasons = [Sample.movie(id: Sample.season, name: "Season")]
        harness.library.episodes = [Sample.movie(id: Sample.other, name: "Pilot")]
        let series = SeriesViewModel(
            library: harness.library, userData: harness.app.userData, app: harness.app, log: harness.log)
        await series.load(seriesID: Sample.movie)
        XCTAssertEqual(series.episodes.value?.first?.name, "Pilot")
        harness.library.seasonError = .network
        await series.load(seriesID: Sample.movie)
        XCTAssertEqual(series.seasons.value?.first?.name, "Season")
        if case .failed(.serverUnreachable, _) = series.seasons {} else { XCTFail("expected unreachable") }
        XCTAssertEqual(harness.app.connectivity, .serverUnreachable)
        guard case .signedIn = harness.app.phase else { return XCTFail("session dropped") }
        XCTAssertFalse(harness.app.showsServerDown)
        XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.serverDownKey)
        try assertEnglishCopy(
            harness.app.banner, key: AppErrorMessage.serverDownKey, expected: "Can't reach the server")
        await series.select(seasonID: "not-a-guid")
        if case .failed(.internalInvariant, _) = series.episodes {} else { XCTFail("expected invariant") }
    }

    @MainActor
    func testT02_29_playbackInstrumentationStallAndStop() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        let player = PlayerViewModel(
            playback: harness.playback, reporting: harness.reporting, userData: harness.app.userData, app: harness.app,
            signposter: harness.signposter, log: harness.log)
        await player.load(itemID: Sample.movie)
        XCTAssertEqual(harness.playback.lastBitrate(), 120_000_000)
        XCTAssertEqual(player.method, .directPlay)
        XCTAssertEqual(harness.log.messages(level: "debug").contains("Playback info loaded."), true)
        player.noteFirstFrame()
        XCTAssertEqual(ended(harness.signposter.snapshot(), .playbackFirstFrame), 1)
        player.noteBuffering(elapsed: .seconds(5))
        XCTAssertNil(player.stallMessage)
        player.noteBuffering(elapsed: .seconds(5) + .milliseconds(1))
        XCTAssertEqual(player.stallMessageKey, AppErrorMessage.bufferingKey)
        try assertEnglishCopy(
            player.stallMessage, key: AppErrorMessage.bufferingKey, expected: "Buffering is taking longer than usual")
        let scrubbed = await player.measureScrub { 1 }
        let trick = await player.measureTrickplay { 2 }
        let switched = await player.measureTrackSwitch { 3 }
        XCTAssertEqual(scrubbed, 1)
        XCTAssertEqual(trick, 2)
        XCTAssertEqual(switched, 3)
        XCTAssertEqual(ended(harness.signposter.snapshot(), .playbackScrub), 1)
        XCTAssertEqual(ended(harness.signposter.snapshot(), .trickplayPreview), 1)
        XCTAssertEqual(ended(harness.signposter.snapshot(), .trackSwitch), 1)

        harness.playback.source.method = .transcode
        await player.load(itemID: Sample.movie)
        XCTAssertEqual(began(harness.signposter.snapshot(), .playbackTranscodeFirstFrame), 1)
        player.noteFirstFrame()
        XCTAssertEqual(ended(harness.signposter.snapshot(), .playbackTranscodeFirstFrame), 1)

        await player.stop(itemID: Sample.movie, position: .seconds(-4), playSessionID: "play", finished: true)
        XCTAssertEqual(harness.reporting.lastStoppedPosition(), .zero)
        XCTAssertTrue(harness.log.messages().contains { $0.contains(Sample.movie) && $0.contains("Negative") })
        XCTAssertFalse(harness.log.contains(Sample.token))
        guard case .signedIn = harness.app.phase else { return XCTFail("stop logged out") }

        harness.reporting.error = .network
        await player.stop(itemID: Sample.movie, position: .seconds(2), playSessionID: "play", finished: false)
        XCTAssertEqual(harness.app.connectivity, .serverUnreachable)
        guard case .signedIn = harness.app.phase else { return XCTFail("network stop logged out") }
        XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.serverDownKey)
        try assertEnglishCopy(
            harness.app.banner, key: AppErrorMessage.serverDownKey, expected: "Can't reach the server")

        harness.playback.error = .cancelled
        await player.load(itemID: Sample.other)
        if case .failed = player.state { XCTFail("cancelled playback became a failure") }

        harness.playback.error = .unauthorized
        await player.load(itemID: Sample.other)
        guard case .needsLogin = harness.app.phase else { return XCTFail("401 should log out") }
        XCTAssertEqual(harness.app.sessionNoticeKey, AppErrorMessage.sessionExpiredKey)
        try assertEnglishCopy(
            harness.app.sessionNotice, key: AppErrorMessage.sessionExpiredKey,
            expected: "Session expired, please sign in again")
    }

    @MainActor
    func testOptimisticEditsCommitRollbackAndRefreshHome() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        harness.library.resumeItems = [Sample.movie(played: false)]
        let home = harness.home()
        await home.reload(libraryIDs: [])
        let editor = UserDataEditor(
            store: harness.app.userData, library: harness.library, app: harness.app, log: harness.log)
        await editor.setPlayed(id: "not-a-guid", played: true)
        XCTAssertEqual(editor.lastError, .internalInvariant)
        XCTAssertTrue(harness.library.played().isEmpty)

        await editor.setPlayed(id: Sample.movie, played: true)
        XCTAssertNil(editor.lastError)
        let played = await harness.app.userData.state(for: Sample.movie)
        let pending = await harness.app.userData.isPending(id: Sample.movie)
        XCTAssertEqual(played?.played, true)
        XCTAssertFalse(pending)
        await home.refreshFromStore()
        XCTAssertEqual(home.resume.value?.first?.userData.played, true)
        XCTAssertEqual(ended(harness.signposter.snapshot(), .watchedStateHome), 1)

        harness.library.error = .forbidden
        await editor.setFavorite(id: Sample.movie, favorite: true)
        XCTAssertEqual(editor.lastError, .forbidden)
        let rolled = await harness.app.userData.state(for: Sample.movie)
        XCTAssertEqual(rolled?.isFavorite, false)
        XCTAssertEqual(rolled?.played, true)
        guard case .signedIn = harness.app.phase else { return XCTFail("403 logged out") }
    }

    @MainActor
    func testSwitchServerKeepsTokensAndRemoveDeletesOnlyThatServer() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        var prefs = harness.app.preferencesSnapshot()
        prefs = try prefs.upserting(
            server: StoredServer(
                id: Sample.otherServerID, name: "Other", url: Sample.url("https://other.example"), version: "10.11.0"))
        prefs = prefs.upserting(
            user: StoredUser(
                serverID: Sample.otherServerID, userID: Sample.otherUserID, userName: "Bea", isAdministrator: false))
        try PreferencesRepository(store: harness.settings).save(prefs)
        let otherAccount = Sample.account(serverID: Sample.otherServerID, userID: Sample.otherUserID)
        try harness.secure.set(Data("other-token".utf8), account: otherAccount, attributes: .production)
        harness.app.handle(.serverUnreachable)
        harness.app.beginServerSwitch()
        XCTAssertEqual(harness.app.phase, .needsServer)
        XCTAssertNil(harness.app.activeServer)
        XCTAssertEqual(harness.app.connectivity, .online)
        XCTAssertNotNil(try harness.secure.data(for: Sample.account()))
        XCTAssertNotNil(try harness.secure.data(for: otherAccount))

        try harness.signIn()
        harness.app.removeServer(id: Sample.otherServerID)
        guard case .signedIn = harness.app.phase else { return XCTFail("removed the wrong server") }
        XCTAssertNil(try harness.secure.data(for: otherAccount))
        XCTAssertNotNil(try harness.secure.data(for: Sample.account()))
        harness.app.removeServer(id: Sample.serverID)
        XCTAssertEqual(harness.app.phase, .needsServer)
        XCTAssertNil(try harness.secure.data(for: Sample.account()))
    }

    @MainActor
    func testProbeTLSAndOfflinePathDoNotLogOut() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try harness.signIn()
        harness.pinger.outcome = .failed(.tlsUntrusted(.unavailable))
        await harness.app.probeServer()
        XCTAssertEqual(harness.app.securityNotice, .tlsUntrusted(.unavailable))
        guard case .signedIn = harness.app.phase else { return XCTFail("tls logged out") }

        harness.pinger.outcome = .failed(.insecureRedirect)
        await harness.app.probeServer()
        XCTAssertEqual(harness.app.securityNotice, .insecureRedirect)

        harness.app.startPathUpdates()
        harness.path.setOnline(false)
        await waitUntil { harness.app.connectivity == .offline }
        await harness.app.probeServer()
        XCTAssertEqual(harness.app.connectivity, .offline)
        guard case .signedIn = harness.app.phase else { return XCTFail("offline probe logged out") }

        let anonymous = await SystemServicePinger(service: StubSystem(pingError: .unauthorized)).ping()
        XCTAssertEqual(anonymous, .failed(.serverError(status: 401)))
        let ok = await SystemServicePinger(service: StubSystem()).ping()
        XCTAssertEqual(ok, .ok)
        let down = await SystemServicePinger(service: StubSystem(pingError: .network), deviceOffline: { true }).ping()
        XCTAssertEqual(down, .failed(.offline))
    }

    @MainActor
    func testT02_30_signedInColdStartDoesNotProbeUntilAsked() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        try seed(harness, version: "12.2.0", token: Sample.token)
        harness.pinger.outcome = .failed(.serverUnreachable)
        harness.app.bootstrap()
        guard case .signedIn = harness.app.phase else { return XCTFail("token should restore the session") }
        XCTAssertEqual(harness.pinger.calls(), 0)
        XCTAssertEqual(harness.app.connectivity, .online)
        await harness.app.probeServer()
        XCTAssertEqual(harness.app.connectivity, .serverUnreachable)
        guard case .signedIn = harness.app.phase else { return XCTFail("probe logged out") }
        XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.serverDownKey)
        try assertEnglishCopy(
            harness.app.banner, key: AppErrorMessage.serverDownKey, expected: "Can't reach the server")
        XCTAssertNotNil(try harness.secure.data(for: Sample.account()))
    }
}

@MainActor
private func seed(_ harness: Harness, version: String, token: String?) throws {
    var preferences = AppPreferences.empty
    preferences = try preferences.upserting(
        server: StoredServer(
            id: Sample.serverID, name: "Home", url: Sample.url("https://media.example:8096"), version: version))
    preferences = preferences.upserting(
        user: StoredUser(serverID: Sample.serverID, userID: Sample.userID, userName: "Ada", isAdministrator: false))
    preferences.activeServerID = Sample.serverID
    preferences.activeUserID = Sample.userID
    try PreferencesRepository(store: harness.settings).save(preferences)
    if let token {
        try harness.secure.set(Data(token.utf8), account: Sample.account(), attributes: .production)
    } else {
        try harness.secure.remove(account: Sample.account())
    }
}

extension AppState {
    fileprivate func preferencesSnapshotJSON() -> Data? {
        try? JSONEncoder().encode(preferencesSnapshot())
    }
}

private final class Counter: @unchecked Sendable {
    var value = 0
}
