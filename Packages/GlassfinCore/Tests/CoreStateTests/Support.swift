import CoreModels
import CoreNetworking
import CoreState
import Foundation
import GlassfinServices
import XCTest

enum Sample {
    static let token = "super-secret-token"
    static let serverID = "11111111111111111111111111111111"
    static let otherServerID = "22222222222222222222222222222222"
    static let userID = "33333333333333333333333333333333"
    static let otherUserID = "44444444444444444444444444444444"
    static let movie = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    static let other = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    static let library = "cccccccccccccccccccccccccccccccc"
    static let season = "dddddddddddddddddddddddddddddddd"

    static func url(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("bad url")
        }
        return url
    }

    static func server(version: SemVer = SemVer(major: 10, minor: 11, patch: 0)) -> ServerInfo {
        ServerInfo(id: serverID, name: "Home", url: url("https://media.example:8096"), version: version)
    }

    static func session(version: SemVer = SemVer(major: 10, minor: 11, patch: 0)) -> UserSession {
        UserSession(server: server(version: version), userID: userID, userName: "Ada", isAdministrator: false)
    }

    static func movie(id: String = movie, name: String = "North", played: Bool = false) -> MediaItem {
        MediaItem(id: id, kind: .movie, name: name, userData: UserItemState(played: played))
    }

    static func account(serverID: String = serverID, userID: String = userID) -> String {
        guard let account = try? CredentialVault.tokenAccount(serverID: serverID, userID: userID) else {
            preconditionFailure("Expected GUID test fixtures")
        }
        return account
    }
}

final class CapturingLog: GlassfinLog, @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [(String, String)] = []

    func warning(_ message: String) { append("warning", message) }
    func debug(_ message: String) { append("debug", message) }
    func error(_ message: String) { append("error", message) }

    func messages(level: String? = nil) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines.compactMap { entry in
            guard level == nil || entry.0 == level else { return nil }
            return entry.1
        }
    }

    func contains(_ token: String) -> Bool {
        messages().contains { $0.contains(token) }
    }

    private func append(_ level: String, _ message: String) {
        lock.lock()
        lines.append((level, message))
        lock.unlock()
    }
}

struct StoreWriteError: Error {}

final class CountingSecureStore: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var removedAccounts: [String] = []
    private var writtenAccounts: [String] = []
    var failSet = false

    func data(for account: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[account]
    }

    func set(_ data: Data, account: String, attributes: KeychainAttributes) throws {
        if failSet { throw StoreWriteError() }
        lock.lock()
        values[account] = data
        writtenAccounts.append(account)
        lock.unlock()
    }

    func remove(account: String) throws {
        lock.lock()
        removedAccounts.append(account)
        values[account] = nil
        lock.unlock()
    }

    func writes() -> [String] { lock.withLock { writtenAccounts } }

    func removed() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return removedAccounts
    }
}

final class ManualClock: GlassfinClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Duration = .zero
    private var recorded: [Duration] = []

    func now() -> Duration {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by delta: Duration) {
        lock.lock()
        current += delta
        lock.unlock()
    }

    func sleeps() -> [Duration] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func sleep(for duration: Duration) async throws {
        remember(duration)
        try Task.checkCancellation()
    }

    private func remember(_ duration: Duration) {
        lock.lock()
        recorded.append(duration)
        lock.unlock()
    }
}

final class SuspendingClock: GlassfinClock, @unchecked Sendable {
    private struct Waiter {
        var id: UUID
        var continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var current: Duration = .zero
    private var recorded: [Duration] = []
    private var waiters: [Waiter] = []
    private var sleepObservers: [CheckedContinuation<Void, Never>] = []

    deinit {
        let pending = takeWaiters()
        for waiter in pending {
            waiter.continuation.resume(throwing: CancellationError())
        }
    }

    func now() -> Duration {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by delta: Duration) {
        lock.lock()
        current += delta
        lock.unlock()
    }

    func sleeps() -> [Duration] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func waitForSleeps(_ count: Int) async {
        while true {
            if sleeps().count >= count { return }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if recorded.count >= count {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                sleepObservers.append(continuation)
                lock.unlock()
            }
        }
    }

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.enqueue(id: id, duration: duration, continuation: continuation)
            }
        } onCancel: {
            self.finish(id, .failure(CancellationError()))
        }
    }

    func resumeAll() {
        for waiter in takeWaiters() {
            waiter.continuation.resume()
        }
    }

    private func enqueue(id: UUID, duration: Duration, continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        recorded.append(duration)
        waiters.append(Waiter(id: id, continuation: continuation))
        let observers = sleepObservers
        sleepObservers.removeAll()
        let cancelled = Task.isCancelled
        lock.unlock()
        for observer in observers {
            observer.resume()
        }
        if cancelled {
            finish(id, .failure(CancellationError()))
        }
    }

    private func finish(_ id: UUID, _ result: Result<Void, Error>) {
        lock.lock()
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            lock.unlock()
            return
        }
        let waiter = waiters.remove(at: index)
        lock.unlock()
        switch result {
        case .success:
            waiter.continuation.resume()
        case .failure(let error):
            waiter.continuation.resume(throwing: error)
        }
    }

    private func takeWaiters() -> [Waiter] {
        lock.lock()
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        return pending
    }
}

final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var pendingReleases = 0

    func wait() async {
        await withCheckedContinuation { continuation in
            self.lock.lock()
            if self.pendingReleases > 0 {
                self.pendingReleases -= 1
                self.lock.unlock()
                continuation.resume()
                return
            }
            self.waiters.append(continuation)
            self.lock.unlock()
        }
    }

    func releaseAll() {
        lock.lock()
        let pending = waiters
        waiters.removeAll()
        if pending.isEmpty {
            pendingReleases += 1
        }
        lock.unlock()
        for waiter in pending {
            waiter.resume()
        }
    }

    func waiting() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return waiters.count
    }
}

final class PipePath: ConnectivityPath, @unchecked Sendable {
    private let lock = NSLock()
    private var online: Bool
    private var continuations: [AsyncStream<Bool>.Continuation] = []

    init(online: Bool) {
        self.online = online
    }

    var isOnline: Bool {
        lock.lock()
        defer { lock.unlock() }
        return online
    }

    func changes() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            self.lock.lock()
            self.continuations.append(continuation)
            let current = self.online
            self.lock.unlock()
            continuation.yield(current)
        }
    }

    func setOnline(_ online: Bool) {
        lock.lock()
        self.online = online
        let current = continuations
        lock.unlock()
        for continuation in current {
            continuation.yield(online)
        }
    }
}

final class StubPinger: ReachabilityPinging, @unchecked Sendable {
    private let lock = NSLock()
    var outcome: PingOutcome = .ok
    private var callCount = 0

    func ping() async -> PingOutcome {
        nextOutcome()
    }

    private func nextOutcome() -> PingOutcome {
        lock.lock()
        defer { lock.unlock() }
        callCount += 1
        return outcome
    }

    func calls() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return callCount
    }
}

final class FakeEvents: ServerEventStream, @unchecked Sendable {
    let events: AsyncStream<ServerEvent>
    private let continuation: AsyncStream<ServerEvent>.Continuation
    var phase: ConnectionPhase = .connected

    init() {
        let pair = AsyncStream<ServerEvent>.makeStream()
        events = pair.stream
        continuation = pair.continuation
    }

    func emit(_ event: ServerEvent) {
        continuation.yield(event)
    }

    func applicationDidBecomeActive() {}

    func stop() {
        continuation.finish()
    }
}

final class StubLibrary: LibraryService, @unchecked Sendable {
    private let lock = NSLock()
    var resumeItems: [MediaItem] = []
    var nextItems: [MediaItem] = []
    var latestByID: [String: Result<[MediaItem], APIError>] = [:]
    var pages: [Int: Page<MediaItem>] = [:]
    var seasons: [MediaItem] = []
    var episodes: [MediaItem] = []
    var error: APIError?
    var resumeError: APIError?
    var nextError: APIError?
    var seasonError: APIError?
    var episodeError: APIError?
    var gate: ResumeGate?
    private var resumeCalls = 0
    private var nextCalls = 0
    private var latestIDs: [String] = []
    private var itemCalls = 0
    private var playedWrites: [(String, Bool)] = []
    private var favoriteWrites: [(String, Bool)] = []
    private var resumeFinished = false

    func userViews() async throws(APIError) -> [Library] { [] }

    func items(in library: Library.ID, query: ItemQuery, page: PageRequest) async throws(APIError) -> Page<MediaItem> {
        let (error, stored) = value { () -> (APIError?, Page<MediaItem>?) in
            itemCalls += 1
            return (self.error, pages[page.startIndex])
        }
        if let error { throw error }
        return stored ?? Page(items: [], totalCount: 0)
    }

    func resume(limit: Int) async throws(APIError) -> [MediaItem] {
        let (error, items, gate) = value { () -> (APIError?, [MediaItem], ResumeGate?) in
            resumeCalls += 1
            return (resumeError ?? self.error, resumeItems, self.gate)
        }
        if let gate { await gate.wait() }
        value { resumeFinished = true }
        if let error { throw error }
        return items
    }

    func nextUp(limit: Int) async throws(APIError) -> [MediaItem] {
        let (error, items) = value { () -> (APIError?, [MediaItem]) in
            nextCalls += 1
            return (nextError, nextItems)
        }
        if let error { throw error }
        return items
    }

    func latest(in library: Library.ID, limit: Int) async throws(APIError) -> [MediaItem] {
        let result = value { () -> Result<[MediaItem], APIError> in
            latestIDs.append(library)
            return latestByID[library] ?? .success([])
        }
        switch result {
        case .success(let items):
            return items
        case .failure(let error):
            throw error
        }
    }

    func seasons(series: MediaItem.ID) async throws(APIError) -> [MediaItem] {
        let (error, items) = value { () -> (APIError?, [MediaItem]) in
            (seasonError, seasons)
        }
        if let error { throw error }
        return items
    }

    func episodes(series: MediaItem.ID, season: MediaItem.ID?) async throws(APIError) -> [MediaItem] {
        let (error, items) = value { () -> (APIError?, [MediaItem]) in
            (episodeError, episodes)
        }
        if let error { throw error }
        return items
    }

    func item(id: MediaItem.ID) async throws(APIError) -> MediaItem { Sample.movie() }

    func similar(id: MediaItem.ID, limit: Int) async throws(APIError) -> [MediaItem] { [] }

    func filters(in library: Library.ID) async throws(APIError) -> ItemFilterSet {
        ItemFilterSet(genres: [], years: [])
    }

    func setPlayed(_ id: MediaItem.ID, _ played: Bool) async throws(APIError) {
        let error = value { () -> APIError? in
            playedWrites.append((id, played))
            return self.error
        }
        if let error { throw error }
    }

    func setFavorite(_ id: MediaItem.ID, _ favorite: Bool) async throws(APIError) {
        let error = value { () -> APIError? in
            favoriteWrites.append((id, favorite))
            return self.error
        }
        if let error { throw error }
    }

    func userData(id: MediaItem.ID) async throws(APIError) -> UserItemState { UserItemState() }

    func updateUserData(id: MediaItem.ID, position: Duration, played: Bool) async throws(APIError) {}

    func resumeCallCount() -> Int { value { resumeCalls } }
    func nextCallCount() -> Int { value { nextCalls } }
    func itemCallCount() -> Int { value { itemCalls } }
    func latestIdentifiers() -> [String] { value { latestIDs } }
    func played() -> [(String, Bool)] { value { playedWrites } }
    func favorites() -> [(String, Bool)] { value { favoriteWrites } }
    func didFinishResume() -> Bool { value { resumeFinished } }

    private func value<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

final class StubSearch: SearchService, @unchecked Sendable {
    private let lock = NSLock()
    var results: [MediaItem] = []
    var error: APIError?
    var gate: ResumeGate?
    private var terms: [String] = []

    func hints(term: String, limit: Int) async throws(APIError) -> [MediaItem] {
        let (error, results, gate) = snapshot(term)
        if let gate { await gate.wait() }
        if let error { throw error }
        return results
    }

    private func snapshot(_ term: String) -> (APIError?, [MediaItem], ResumeGate?) {
        lock.lock()
        defer { lock.unlock() }
        terms.append(term)
        let results = results.isEmpty ? [Sample.movie(name: term)] : results
        return (error, results, gate)
    }

    func termsSeen() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return terms
    }
}

final class StubPlayback: PlaybackInfoService, @unchecked Sendable {
    var source = PlaybackSource(
        mediaSourceID: "source",
        playSessionID: "play",
        method: .directPlay,
        url: Sample.url("https://media.example/video"),
        audioTracks: [],
        subtitleTracks: [],
        transcodeReasons: []
    )
    var error: APIError?
    private let lock = NSLock()
    private var bitrate: Int?
    private var start: Duration?

    func playbackInfo(itemID: String, start: Duration, maxBitrate: Int) async throws(APIError) -> PlaybackSource {
        note(start: start, maxBitrate: maxBitrate)
        if let error { throw error }
        return source
    }

    private func note(start: Duration, maxBitrate: Int) {
        lock.lock()
        bitrate = maxBitrate
        self.start = start
        lock.unlock()
    }

    func mediaSegments(itemID: String) async throws(APIError) -> [MediaSegment] { [] }

    func bitrateTest(size: Int) async throws(APIError) -> Data { Data() }

    func lastBitrate() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return bitrate
    }
}

final class StubReporting: ReportingService, @unchecked Sendable {
    var error: APIError?
    private let lock = NSLock()
    private var stoppedPosition: Duration?

    func started(itemID: String, position: Duration, playSessionID: String) async throws(APIError) {}

    func progress(itemID: String, position: Duration, playSessionID: String, paused: Bool) async throws(APIError) {}

    func stopped(itemID: String, position: Duration, playSessionID: String, failed: Bool) async throws(APIError) {
        noteStopped(position)
        if let error { throw error }
    }

    private func noteStopped(_ position: Duration) {
        lock.lock()
        stoppedPosition = position
        lock.unlock()
    }

    func ping(playSessionID: String) async throws(APIError) {}

    func lastStoppedPosition() -> Duration? {
        lock.lock()
        defer { lock.unlock() }
        return stoppedPosition
    }
}

struct StubSystem: SystemService {
    var pingError: APIError?
    var pingValue = "Jellyfin Server"

    func publicInfo() async throws(APIError) -> ServerInfo { Sample.server() }

    func ping() async throws(APIError) -> String {
        if let pingError { throw pingError }
        return pingValue
    }
}

final class ScriptedClient: JellyfinAPIClient, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<Data, APIError>]
    private var sent: [APIRequest] = []

    init(results: [Result<Data, APIError>]) {
        self.results = results
    }

    func send(_ request: APIRequest) async throws(APIError) -> Data {
        guard let result = dequeue(request) else { throw APIError.network }
        switch result {
        case .success(let data):
            return data
        case .failure(let error):
            throw error
        }
    }

    private func dequeue(_ request: APIRequest) -> Result<Data, APIError>? {
        lock.lock()
        defer { lock.unlock() }
        sent.append(request)
        return results.isEmpty ? nil : results.removeFirst()
    }

    func requests() -> [APIRequest] {
        lock.lock()
        defer { lock.unlock() }
        return sent
    }
}

@MainActor
struct Harness {
    var secure: CountingSecureStore
    var settings: InMemorySettingsStore
    var path: PipePath
    var pinger: StubPinger
    var manual: ManualClock?
    var suspending: SuspendingClock?
    var signposter: RecordingSignposter
    var log: CapturingLog
    var root: URL
    var app: AppState
    var library: StubLibrary
    var search: StubSearch
    var playback: StubPlayback
    var reporting: StubReporting

    var clock: any GlassfinClock {
        if let manual { return manual }
        if let suspending { return suspending }
        preconditionFailure("missing clock")
    }

    static func make(automaticPing: Bool = false, online: Bool = true, suspendingClock: Bool = false) -> Harness {
        let secure = CountingSecureStore()
        let settings = InMemorySettingsStore()
        let path = PipePath(online: online)
        let pinger = StubPinger()
        let manual = suspendingClock ? nil : ManualClock()
        let suspending = suspendingClock ? SuspendingClock() : nil
        let clock: any GlassfinClock
        if let manual {
            clock = manual
        } else if let suspending {
            clock = suspending
        } else {
            clock = ManualClock()
        }
        let signposter = RecordingSignposter()
        let log = CapturingLog()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "glassfin-m02-\(UUID().uuidString)", isDirectory: true)
        let app = AppState(
            secureStore: secure,
            settings: settings,
            path: path,
            pinger: pinger,
            cacheRoot: root,
            clock: clock,
            automaticPing: automaticPing,
            signposter: signposter,
            log: log
        )
        return Harness(
            secure: secure,
            settings: settings,
            path: path,
            pinger: pinger,
            manual: manual,
            suspending: suspending,
            signposter: signposter,
            log: log,
            root: root,
            app: app,
            library: StubLibrary(),
            search: StubSearch(),
            playback: StubPlayback(),
            reporting: StubReporting()
        )
    }

    func signIn(token: String = Sample.token) throws {
        try app.didSignIn(Sample.session(), token: token)
    }

    func cleanup() {
        suspending?.resumeAll()
        try? FileManager.default.removeItem(at: root)
    }

    func home() -> HomeViewModel {
        HomeViewModel(
            library: library,
            userData: app.userData,
            snapshots: app.snapshots,
            responses: app.responses,
            app: app,
            clock: clock,
            signposter: signposter,
            scope: app.scope,
            log: log
        )
    }
}

func waitUntil(
    _ condition: @MainActor () -> Bool,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    let start = ContinuousClock.now
    while !(await condition()) {
        if start.duration(to: .now) > .seconds(3) {
            XCTFail("condition was not met", file: file, line: line)
            return
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

func ended(_ samples: [RecordingSignposter.Sample], _ mark: PerformanceMark) -> Int {
    samples.filter { $0.mark == mark && $0.phase == "end" }.count
}

func began(_ samples: [RecordingSignposter.Sample], _ mark: PerformanceMark) -> Int {
    samples.filter { $0.mark == mark && $0.phase == "begin" }.count
}

func englishCatalogText(for key: String) throws -> String {
    let package = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: package.appendingPathComponent("Sources/CoreModels/Localizable.xcstrings"))
    let catalog = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
    let entry = try XCTUnwrap(strings[key] as? [String: Any])
    let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
    let english = try XCTUnwrap(localizations["en"] as? [String: Any])
    let unit = try XCTUnwrap(english["stringUnit"] as? [String: Any])
    return try XCTUnwrap(unit["value"] as? String)
}

func assertEnglishCopy(
    _ text: String?, key: String, expected: String, file: StaticString = #filePath, line: UInt = #line
) throws {
    XCTAssertEqual(text, AppErrorMessage.localized(key), file: file, line: line)
    XCTAssertEqual(text, try englishCatalogText(for: key), file: file, line: line)
    XCTAssertEqual(text, expected, file: file, line: line)
}

func expectEqual<T: Equatable>(
    _ lhs: T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertEqual(lhs, rhs, file: file, line: line)
}

func expectTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(value, file: file, line: line)
}

func expectFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertFalse(value, file: file, line: line)
}

func expectNil(_ value: Any?, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertNil(value, file: file, line: line)
}

func expectNotNil(_ value: Any?, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertNotNil(value, file: file, line: line)
}

func expectLessThanOrEqual<T: Comparable>(
    _ lhs: T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertLessThanOrEqual(lhs, rhs, file: file, line: line)
}
