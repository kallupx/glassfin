import CoreModels
import CoreNetworking
import CoreState
import Foundation
import XCTest

final class T02FoundationTests: XCTestCase {
    func testT02_02_loadStateKeepsPreviousAndHidesNonUserErrors() {
        var state = LoadState<[MediaItem]>.idle
        XCTAssertNil(state.value)
        XCTAssertFalse(state.isLoading)
        XCTAssertFalse(state.showsSkeleton)
        XCTAssertNil(state.presentedError)

        let previous = [Sample.movie()]
        state = .loading(previous: previous)
        XCTAssertEqual(state.value, previous)
        XCTAssertTrue(state.isLoading)
        XCTAssertFalse(state.showsSkeleton)

        state = .loading(previous: nil)
        XCTAssertTrue(state.showsSkeleton)
        XCTAssertNil(state.value)

        state = .failed(.cancelled, previous: previous)
        XCTAssertEqual(state.value, previous)
        XCTAssertNil(state.presentedError)
        state = .failed(.decoding, previous: previous)
        XCTAssertNil(state.presentedError)
        state = .failed(.internalInvariant, previous: previous)
        XCTAssertNil(state.presentedError)
        state = .failed(.forbidden, previous: previous)
        XCTAssertEqual(state.presentedError, .forbidden)
        XCTAssertEqual(state, .failed(.forbidden, previous: previous))
        XCTAssertEqual(CoreStateModule.name, "CoreState")
    }

    func testT02_08_mappingNeverTurnsNon401IntoLogout() {
        let cases: [(APIError, RequestAuthentication, Bool, AppError)] = [
            (.unauthorized, .authenticated, false, .unauthorized),
            (.unauthorized, .login, false, .invalidCredentials),
            (.unauthorized, .anonymous, false, .serverError(status: 401)),
            (.forbidden, .authenticated, false, .forbidden),
            (.notFound, .authenticated, false, .notFound),
            (.server(status: 500), .authenticated, false, .serverError(status: 500)),
            (.server(status: 500), .authenticated, true, .serverError(status: 500)),
            (.server(status: 502), .authenticated, false, .serverUnreachable),
            (.server(status: 503), .authenticated, false, .serverUnreachable),
            (.server(status: 504), .authenticated, true, .offline),
            (.timeout, .authenticated, false, .serverUnreachable),
            (.timeout, .authenticated, true, .offline),
            (.network, .authenticated, false, .serverUnreachable),
            (.network, .authenticated, true, .offline),
            (.tls, .authenticated, false, .tlsUntrusted(.unavailable)),
            (.decoding, .authenticated, false, .decoding),
            (.cancelled, .authenticated, false, .cancelled),
            (.redirectRejected(.httpsDowngrade), .authenticated, false, .insecureRedirect),
            (.redirectRejected(.credentialQueryCrossHost), .authenticated, false, .insecureRedirect),
            (.redirectRejected(.credentialQueryDowngrade), .authenticated, false, .insecureRedirect),
            (.redirectRejected(.notFollowed), .authenticated, false, .serverUnreachable),
            (.redirectRejected(.notFollowed), .authenticated, true, .offline),
            (.invalidURL, .authenticated, false, .internalInvariant),
            (.headerRejected, .authenticated, false, .internalInvariant),
            (.invalidItemID, .authenticated, false, .internalInvariant),
        ]
        for (error, context, offline, expected) in cases {
            let mapped = AppErrorMapping.map(error, context: context, deviceOffline: offline)
            XCTAssertEqual(mapped, expected)
            XCTAssertEqual(CoreModels.SessionTermination.shouldEndSession(mapped), mapped == .unauthorized)
        }
        XCTAssertTrue(AppErrorMapping.isConnectivity(.offline))
        XCTAssertTrue(AppErrorMapping.isConnectivity(.serverUnreachable))
        XCTAssertFalse(AppErrorMapping.isConnectivity(.forbidden))
        XCTAssertFalse(CoreModels.SessionTermination.shouldEndSession(.serverError(status: 500)))
        XCTAssertFalse(CoreModels.SessionTermination.shouldEndSession(.serverUnreachable))
    }

    func testT02_09_userFacingCopyAndDiagnosticsOmitTokens() {
        let log = CapturingLog()
        XCTAssertEqual(AppErrorMessage.messageKey(for: .offline), AppErrorMessage.offlineKey)
        XCTAssertEqual(AppErrorMessage.messageKey(for: .serverUnreachable), AppErrorMessage.serverDownKey)
        XCTAssertEqual(AppErrorMessage.messageKey(for: .forbidden), AppErrorMessage.forbiddenKey)
        XCTAssertEqual(AppErrorMessage.messageKey(for: .unauthorized), AppErrorMessage.sessionExpiredKey)
        XCTAssertEqual(AppErrorMessage.messageKey(for: .invalidCredentials), AppErrorMessage.invalidCredentialsKey)
        XCTAssertEqual(AppErrorMessage.messageKey(for: .insecureRedirect), AppErrorMessage.insecureRedirectKey)
        XCTAssertEqual(AppErrorMessage.messageKey(for: .notFound), AppErrorMessage.notFoundKey)
        XCTAssertEqual(AppErrorMessage.messageKey(for: .serverError(status: 500)), AppErrorMessage.serverErrorKey)
        XCTAssertEqual(
            AppErrorMessage.messageKey(for: .playback(.itemFailed(code: "NoCompatibleStream"))),
            AppErrorMessage.playbackFailedKey)
        XCTAssertEqual(
            AppErrorMessage.messageKey(for: .unsupportedServer(version: "10.9.11")),
            AppErrorMessage.unsupportedServerKey
        )
        XCTAssertNil(AppErrorMessage.userFacing(.cancelled))
        XCTAssertNil(AppErrorMessage.userFacing(.decoding))
        XCTAssertNil(AppErrorMessage.userFacing(.internalInvariant))
        let certificate = CertificateInfo(
            fingerprintSHA256: "abc", subject: "cn", validFrom: Date(timeIntervalSince1970: 1),
            validUntil: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(
            AppErrorMessage.diagnostic(.tlsUntrusted(certificate)), "tlsUntrusted fingerprint=abc subject=cn")
        XCTAssertEqual(CertificateInfo.unavailable.fingerprintSHA256, "")
        XCTAssertEqual(AppErrorMessage.diagnostic(.playback(.stalled)), "playback stalled")
        XCTAssertEqual(AppErrorMessage.diagnostic(.playback(.fallbackExhausted)), "playback fallbackExhausted")
        XCTAssertFalse(AppErrorMessage.diagnostic(.unauthorized).contains(Sample.token))
        AppErrorMessage.report(.internalInvariant, log: log)
        AppErrorMessage.report(.decoding, log: log)
        AppErrorMessage.report(.cancelled, log: log)
        AppErrorMessage.report(.forbidden, log: log)
        XCTAssertEqual(log.messages(level: "warning"), ["Non-fatal invariant failure", "Skipped undecodable content"])
        XCTAssertEqual(log.messages(level: "error"), ["forbidden"])
        XCTAssertFalse(log.contains(Sample.token))
        XCTAssertNil(ServerVersionGate.failure(for: .minimumJellyfin))
        XCTAssertNil(ServerVersionGate.failure(for: SemVer(major: 10, minor: 10, patch: 6)))
        XCTAssertEqual(
            ServerVersionGate.failure(for: SemVer(major: 10, minor: 9, patch: 11)),
            .unsupportedServer(version: "10.9.11")
        )
    }

    func testAppErrorMessageKeysCoverEveryCase() {
        let cases: [(AppError, String?)] = [
            (.offline, AppErrorMessage.offlineKey),
            (.serverUnreachable, AppErrorMessage.serverDownKey),
            (.tlsUntrusted(.unavailable), AppErrorMessage.tlsUntrustedKey),
            (.unauthorized, AppErrorMessage.sessionExpiredKey),
            (.invalidCredentials, AppErrorMessage.invalidCredentialsKey),
            (.insecureRedirect, AppErrorMessage.insecureRedirectKey),
            (.forbidden, AppErrorMessage.forbiddenKey),
            (.notFound, AppErrorMessage.notFoundKey),
            (.serverError(status: 500), AppErrorMessage.serverErrorKey),
            (.unsupportedServer(version: "10.9.11"), AppErrorMessage.unsupportedServerKey),
            (.publicHTTPRejected, AuthCopy.Key.publicAddressRequiresHTTPS.rawValue),
            (.playback(.itemFailed(code: "NoCompatibleStream")), AppErrorMessage.playbackFailedKey),
            (.playback(.itemFailed(code: nil)), AppErrorMessage.playbackFailedKey),
            (.playback(.stalled), AppErrorMessage.playbackFailedKey),
            (.playback(.fallbackExhausted), AppErrorMessage.playbackFailedKey),
            (.decoding, nil),
            (.cancelled, nil),
            (.internalInvariant, nil),
        ]
        for (error, expectedKey) in cases {
            let key = AppErrorMessage.messageKey(for: error)
            XCTAssertEqual(key, expectedKey, "\(error)")
            XCTAssertEqual(AppErrorMessage.userFacing(error) != nil, key != nil, "\(error)")
        }
    }

    func testT02_11_oneBrokenItemIsSkippedWithoutLoggingThePayload() throws {
        let log = CapturingLog()
        let payload = """
            {"Items":[
              {"Id":"\(Sample.movie)","Name":"North","Type":"Movie"},
              {"Name":"Broken","Overview":"\(Sample.token)"},
              "not-an-object",
              {"Id":"\(Sample.other)","Name":"South","Type":"Movie","UserData":{"Played":true}}
            ],"TotalRecordCount":4}
            """
        let decoded = try ResilientItemDecoder.mediaItems(from: Data(payload.utf8), log: log)
        XCTAssertEqual(decoded.items.map(\.name), ["North", "South"])
        XCTAssertEqual(decoded.totalCount, 4)
        XCTAssertEqual(decoded.skipped, 2)
        XCTAssertEqual(decoded.items[1].userData.played, true)
        XCTAssertEqual(log.messages().count, 2)
        XCTAssertTrue(log.messages().allSatisfy { $0.contains("Skipped list item at index") })
        XCTAssertFalse(log.contains(Sample.token))

        let bare = Data("[{\"Id\":\"\(Sample.movie)\",\"Name\":\"North\",\"Type\":\"Movie\"}]".utf8)
        let array = try ResilientItemDecoder.mediaItems(from: bare, log: log)
        XCTAssertEqual(array.items.count, 1)
        XCTAssertNil(array.totalCount)

        XCTAssertThrowsError(try ResilientItemDecoder.mediaItems(from: Data("not-json".utf8), log: log)) { error in
            XCTAssertEqual(error as? APIError, .decoding)
        }
        XCTAssertThrowsError(
            try ResilientItemDecoder.mediaItems(from: Data("{\"Items\":{\"Id\":\"x\"}}".utf8), log: log)
        ) { error in
            XCTAssertEqual(error as? APIError, .decoding)
        }
        let empty = try ResilientItemDecoder.mediaItems(from: Data("{\"Items\":null}".utf8), log: log)
        XCTAssertEqual(empty.items, [])

        let hints = """
            {"SearchHints":[
              {"ItemId":"\(Sample.movie)","Name":"North","Type":"Movie"},
              {"Name":"Missing"},
              {"Id":"\(Sample.other)","Name":"South","Type":"Series"},
              "bad"
            ]}
            """
        let found = try ResilientItemDecoder.searchHints(from: Data(hints.utf8), log: log)
        XCTAssertEqual(found.map(\.name), ["North", "South"])
        XCTAssertEqual(found.map(\.kind), [.movie, .series])
        XCTAssertFalse(log.contains(Sample.token))
        XCTAssertThrowsError(try ResilientItemDecoder.searchHints(from: Data("[]".utf8), log: log))
    }

    func testT02_12_preferencesStayUnderBudgetAndRejectUserinfo() throws {
        var preferences = AppPreferences.empty
        for index in 0..<10 {
            let server = StoredServer(
                id: String(format: "%032x", index + 1),
                name: "Server \(index)",
                url: Sample.url("https://s\(index).example:8096/jellyfin"),
                version: "10.11.11",
                certificatePinSHA256: String(repeating: "ab", count: 32)
            )
            preferences = try preferences.upserting(server: server)
            preferences = preferences.upserting(
                user: StoredUser(
                    serverID: String(format: "%032x", index + 1), userID: String(format: "%032x", index + 101),
                    userName: "User \(index)", isAdministrator: index == 0,
                    audioLanguage: "fi", subtitleLanguage: "sv"))
        }
        preferences.activeServerID = String(format: "%032x", 1)
        preferences.activeUserID = String(format: "%032x", 101)
        let bytes = try XCTUnwrap(PreferencesRepository.encodedByteCount(preferences))
        XCTAssertLessThan(bytes, CacheBudget.userDefaultsBytes)
        XCTAssertLessThan(bytes, 50 * 1_024)
        let store = InMemorySettingsStore()
        let repository = PreferencesRepository(store: store)
        try repository.save(preferences)
        let saved = repository.load()
        XCTAssertEqual(saved.servers.count, 10)
        XCTAssertEqual(saved.users.count, 10)
        XCTAssertEqual(saved.activeServer()?.id, String(format: "%032x", 1))
        XCTAssertEqual(saved.activeUser()?.userName, "User 0")
        let json = store.string(forKey: PreferencesRepository.storageKey) ?? ""
        XCTAssertFalse(json.contains(Sample.token))

        var huge = AppPreferences.empty
        huge = try huge.upserting(
            server: StoredServer(
                id: "s", name: "n", url: Sample.url("https://example.com"), version: "10.11.0"))
        huge = huge.upserting(
            user: StoredUser(
                serverID: "s", userID: "u", userName: String(repeating: "n", count: 60_000), isAdministrator: false))
        XCTAssertThrowsError(try repository.save(huge)) { error in
            guard let prefs = error as? PreferencesError, case .overBudget = prefs else {
                return XCTFail("expected overBudget")
            }
        }
        XCTAssertEqual(repository.load().servers.count, 10)

        store.set("{", forKey: PreferencesRepository.storageKey)
        XCTAssertEqual(repository.load(), .empty)

        let dirty = StoredServer(
            id: "s",
            name: "Home",
            url: Sample.url("https://alice:secret@media.example/jellyfin"),
            version: "10.11.0"
        )
        XCTAssertThrowsError(try AppPreferences.empty.upserting(server: dirty)) { error in
            XCTAssertEqual(error as? PreferencesError, .invalidServerURL)
        }
        let clean = StoredServer(
            id: "s", name: "Home", url: Sample.url("https://example.com/jellyfin?x=1#fragment"),
            version: "10.11.0")
        let normalized = try AppPreferences.empty.upserting(server: clean).servers[0].url
        XCTAssertEqual(normalized.absoluteString, "https://example.com/jellyfin")
        XCTAssertThrowsError(
            try AppPreferences.empty.upserting(
                server: StoredServer(id: "s", name: "n", url: Sample.url("ftp://example.com"), version: "1.0.0"))
        ) { error in
            XCTAssertEqual(error as? PreferencesError, .invalidServerURL)
        }

        let replaced = try preferences.upserting(
            server: StoredServer(
                id: String(format: "%032x", 1), name: "Renamed", url: Sample.url("https://s0.example:8096/jellyfin"),
                version: "12.0.0"))
        XCTAssertEqual(replaced.servers.first { $0.id == String(format: "%032x", 1) }?.name, "Renamed")
        let (removed, accounts) = replaced.removing(serverID: String(format: "%032x", 1))
        XCTAssertEqual(
            accounts,
            [
                try CredentialVault.tokenAccount(
                    serverID: String(format: "%032x", 1), userID: String(format: "%032x", 101))
            ])
        XCTAssertNil(removed.activeServerID)
        XCTAssertFalse(removed.servers.contains { $0.id == String(format: "%032x", 1) })
        XCTAssertFalse(
            try CredentialVault.tokenAccount(serverID: String(format: "%032x", 1), userID: String(format: "%032x", 101))
                .contains(Sample.token))

        let defaults = UserDefaults(suiteName: "org.glassfin.tests.\(UUID().uuidString)")
        let userDefaults = UserDefaultsSettingsStore(defaults: defaults ?? .standard)
        userDefaults.set("value", forKey: "org.glassfin.preferences")
        XCTAssertEqual(userDefaults.string(forKey: "org.glassfin.preferences"), "value")
        userDefaults.set(nil, forKey: "org.glassfin.preferences")
        XCTAssertNil(userDefaults.string(forKey: "org.glassfin.preferences"))
        userDefaults.set("again", forKey: "org.glassfin.preferences")
        userDefaults.removeAll()
        XCTAssertNil(userDefaults.string(forKey: "org.glassfin.preferences"))
    }

    func testT02_13_diskLRUEvictsAndDoesNotStoreTheToken() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("glassfin-disk-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = DiskImageCache(directory: root, byteLimit: 50)
        let first = Data(repeating: 1, count: 20)
        let second = Data(repeating: 2, count: 20)
        let third = Data(repeating: 3, count: 20)
        expectTrue(await cache.store(key: "a", data: first))
        expectTrue(await cache.store(key: "b", data: second))
        _ = await cache.data(for: "a")
        expectTrue(await cache.store(key: "c", data: third))
        expectEqual(await cache.data(for: "a"), first)
        expectNil(await cache.data(for: "b"))
        expectEqual(await cache.data(for: "c"), third)
        expectLessThanOrEqual(await cache.storedByteCount(), 50)

        let secretKey = "poster?token=\(Sample.token)"
        let otherSecret = "poster?token=another-secret-value"
        expectTrue(await cache.store(key: secretKey, data: first))
        expectTrue(await cache.store(key: otherSecret, data: second))
        expectFalse(await cache.containsToken(Sample.token))
        expectEqual(await cache.data(for: secretKey), await cache.data(for: otherSecret))
        expectFalse(await cache.store(key: "too-big", data: Data(repeating: 9, count: 51)))

        let reloaded = DiskImageCache(directory: root, byteLimit: 50)
        expectEqual(await reloaded.data(for: secretKey), second)
        let names = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        for name in names where name.lastPathComponent != "index.json" {
            try FileManager.default.removeItem(at: name)
        }
        expectNil(await reloaded.data(for: secretKey))
        await cache.purge()
        expectEqual(await cache.storedByteCount(), 0)
        let blocked = DiskImageCache(directory: root, byteLimit: 0)
        expectFalse(await blocked.store(key: "a", data: first))
    }

    func testT02_14_memoryCacheDropsOnCapAndWarningAndImageStoreFallsBackToDisk() async {
        let memory = MemoryImageCache(byteLimit: 30)
        XCTAssertTrue(memory.store(key: "a", data: Data(repeating: 1, count: 20)))
        XCTAssertTrue(memory.store(key: "b", data: Data(repeating: 2, count: 20)))
        XCTAssertNil(memory.data(for: "a"))
        XCTAssertEqual(memory.data(for: "b")?.count, 20)
        XCTAssertLessThanOrEqual(memory.byteCount(), 30)
        XCTAssertFalse(memory.store(key: "big", data: Data(repeating: 3, count: 31)))
        memory.purgeForMemoryWarning()
        XCTAssertEqual(memory.byteCount(), 0)
        XCTAssertNil(memory.data(for: "b"))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("glassfin-mem-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = DiskImageCache(directory: root, byteLimit: 1_024)
        let store = ImageStore(memory: MemoryImageCache(byteLimit: 1_024), disk: disk)
        let blob = Data("poster".utf8)
        await store.store(key: "poster", data: blob)
        expectEqual(await store.data(for: "poster"), blob)
        store.memory.purgeForMemoryWarning()
        expectEqual(await store.data(for: "poster"), blob)
        XCTAssertEqual(store.memory.data(for: "poster"), blob)
        expectNil(await store.data(for: "missing"))
    }

    func testT02_15_responseCacheTTLExpiresAtTheBoundary() async {
        let cache = ResponseCache()
        let now = Duration.zero
        await cache.insert(Data("home".utf8), for: "home.resume", ttl: NetworkThresholds.homeTTL, now: now)
        await cache.insert(Data("library".utf8), for: "library", ttl: NetworkThresholds.libraryListTTL, now: now)
        XCTAssertEqual(NetworkThresholds.homeTTL, .seconds(60))
        XCTAssertEqual(NetworkThresholds.libraryListTTL, .seconds(300))
        expectNotNil(await cache.data(for: "home.resume", now: .seconds(59)))
        expectNil(await cache.data(for: "home.resume", now: .seconds(60)))
        expectNotNil(await cache.data(for: "library", now: .seconds(299)))
        expectNil(await cache.data(for: "missing", now: now))
        await cache.insert(Data("library".utf8), for: "library", ttl: .seconds(300), now: now)
        await cache.invalidateAll()
        expectNil(await cache.data(for: "library", now: now))
    }

    func testT02_16_idempotentGETRetriesBackoffAndSkipsTerminalStatuses() async throws {
        XCTAssertEqual(NetworkThresholds.retryDelays, [.milliseconds(500), .milliseconds(1_500)])
        XCTAssertEqual(NetworkThresholds.requestTimeout, .seconds(15))
        XCTAssertEqual(IdempotentRetry.maximumAttempts(method: "GET"), 3)
        XCTAssertEqual(IdempotentRetry.maximumAttempts(method: "get"), 3)
        XCTAssertEqual(IdempotentRetry.maximumAttempts(method: "POST"), 1)
        XCTAssertTrue(IdempotentRetry.shouldRetry(.timeout))
        XCTAssertTrue(IdempotentRetry.shouldRetry(.network))
        XCTAssertTrue(IdempotentRetry.shouldRetry(.server(status: 502)))
        XCTAssertTrue(IdempotentRetry.shouldRetry(.server(status: 503)))
        XCTAssertTrue(IdempotentRetry.shouldRetry(.server(status: 504)))
        XCTAssertFalse(IdempotentRetry.shouldRetry(.unauthorized))
        XCTAssertFalse(IdempotentRetry.shouldRetry(.forbidden))
        XCTAssertFalse(IdempotentRetry.shouldRetry(.notFound))
        XCTAssertFalse(IdempotentRetry.shouldRetry(.server(status: 500)))
        XCTAssertFalse(IdempotentRetry.shouldRetry(.cancelled))

        let clock = ManualClock()
        let flaky = ScriptedClient(results: [.failure(.network), .failure(.timeout), .success(Data("ok".utf8))])
        let client = RetryingAPIClient(inner: flaky, clock: clock)
        let data = try await client.send(APIRequest(method: "GET", path: "/Items"))
        XCTAssertEqual(data, Data("ok".utf8))
        XCTAssertEqual(flaky.requests().count, 3)
        XCTAssertEqual(clock.sleeps(), [.milliseconds(500), .milliseconds(1_500)])

        let terminal: [APIError] = [.unauthorized, .forbidden, .notFound, .server(status: 500), .cancelled]
        for error in terminal {
            let scripted = ScriptedClient(results: [.failure(error), .success(Data("no".utf8))])
            let retrying = RetryingAPIClient(inner: scripted, clock: ManualClock())
            do {
                _ = try await retrying.send(APIRequest(method: "GET", path: "/Items"))
                XCTFail("expected \(error)")
            } catch let caught {
                XCTAssertEqual(caught, error)
            }
            XCTAssertEqual(scripted.requests().count, 1)
        }

        let post = ScriptedClient(results: [.failure(.network), .success(Data("no".utf8))])
        let postClock = ManualClock()
        let posting = RetryingAPIClient(inner: post, clock: postClock)
        do {
            _ = try await posting.send(APIRequest(method: "POST", path: "/Sessions/Playing"))
            XCTFail("post should not retry")
        } catch let error {
            XCTAssertEqual(error, .network)
        }
        XCTAssertEqual(post.requests().count, 1)
        XCTAssertTrue(postClock.sleeps().isEmpty)

        let gateway = ScriptedClient(results: [.failure(.server(status: 502)), .success(Data("up".utf8))])
        let gatewayClock = ManualClock()
        let gatewayClient = RetryingAPIClient(inner: gateway, clock: gatewayClock)
        let recovered = try await gatewayClient.send(APIRequest(method: "GET", path: "/System/Ping"))
        XCTAssertEqual(recovered, Data("up".utf8))
        XCTAssertEqual(gatewayClock.sleeps(), [.milliseconds(500)])

        let exhausted = ScriptedClient(results: [.failure(.network), .failure(.network), .failure(.network)])
        do {
            _ = try await RetryingAPIClient(inner: exhausted, clock: ManualClock()).send(
                APIRequest(method: "GET", path: "/Items"))
            XCTFail("expected network")
        } catch let error {
            XCTAssertEqual(error, .network)
        }
        XCTAssertEqual(exhausted.requests().count, 3)

        let cancelling = SuspendingClock()
        defer { cancelling.resumeAll() }
        let paused = ScriptedClient(results: [.failure(.network), .success(Data("late".utf8))])
        let retrying = RetryingAPIClient(inner: paused, clock: cancelling)
        let task = Task {
            try await retrying.send(APIRequest(method: "GET", path: "/Items"))
        }
        await cancelling.waitForSleeps(1)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch let error as APIError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("unexpected error")
        }

        let started = ResumeGate()
        let idle = ScriptedClient(results: [.success(Data("no".utf8))])
        let early = Task {
            await started.wait()
            return try await RetryingAPIClient(inner: idle, clock: ManualClock()).send(
                APIRequest(method: "GET", path: "/Items"))
        }
        early.cancel()
        started.releaseAll()
        do {
            _ = try await early.value
            XCTFail("expected cancellation before send")
        } catch let error as APIError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("unexpected error")
        }
        XCTAssertTrue(idle.requests().isEmpty)

        let http = HTTPJellyfinClient(
            server: Sample.url("https://media.example:8096"),
            identity: ClientIdentity(deviceName: "Test", deviceID: "device", version: "0.1.0")
        )
        XCTAssertEqual(http.session.configuration.timeoutIntervalForRequest, 15)
        XCTAssertFalse(http.session.configuration.httpShouldSetCookies)
    }

    func testT02_18_signpostNamesBudgetsAndRecording() {
        XCTAssertEqual(PerformanceCatalog.identifiers, (1...15).map { "P\($0)" })
        let names = Set(PerformanceMark.allCases.map(\.rawValue))
        XCTAssertEqual(
            names,
            [
                "launch.homeFirstRow", "home.sections", "browse.focusScroll", "image.poster.cache",
                "image.poster.network", "playback.firstFrame", "playback.transcodeFirstFrame", "playback.scrub",
                "playback.trickplay", "playback.trackSwitch", "search.results", "memory.browse", "memory.playback",
                "memory.remux", "memory.leakCycle", "home.watchedState", "home.remoteUserData",
            ]
        )
        XCTAssertEqual(PerformanceCatalog.all.filter { $0.id == "P4" }.count, 2)
        XCTAssertEqual(PerformanceCatalog.all.filter { $0.id == "P12" }.count, 2)
        XCTAssertTrue(PerformanceCatalog.meets(elapsed: .milliseconds(100), targetMilliseconds: 100))
        XCTAssertFalse(PerformanceCatalog.meets(elapsed: .milliseconds(101), targetMilliseconds: 100))
        XCTAssertEqual(Signposters.subsystem, "org.glassfin.app")
        XCTAssertEqual(Signposters.category, "Performance")

        let recorder = RecordingSignposter()
        for mark in PerformanceMark.allCases {
            let interval = recorder.begin(mark)
            recorder.end(interval)
            recorder.end(interval)
            recorder.event(mark)
        }
        let samples = recorder.snapshot()
        XCTAssertEqual(began(samples, .playbackFirstFrame), 1)
        XCTAssertEqual(ended(samples, .playbackFirstFrame), 1)
        XCTAssertEqual(samples.filter { $0.phase == "event" }.count, PerformanceMark.allCases.count)

        let noop = NoopSignposter()
        noop.end(noop.begin(.focusScroll))
        noop.event(.memoryBrowse)
        let production = Signposters.production()
        production.end(production.begin(.searchResults))
        production.event(.memoryLeakCycle)

        let browse = BrowseInstrumentation(signposter: recorder)
        XCTAssertEqual(browse.measureFocusScroll { 4 }, 4)
        browse.noteBrowseMemorySample()
        browse.notePlaybackMemorySample()
        browse.noteRemuxMemorySample()
        browse.noteLeakCycleSample()
        XCTAssertEqual(ended(recorder.snapshot(), .focusScroll), 2)
    }

    func testT02_19_pagingPrefetchesWhenTenRemain() {
        XCTAssertEqual(ListPaging.pageSize, 50)
        XCTAssertEqual(ListPaging.prefetchRemaining, 10)
        XCTAssertTrue(ListPaging.shouldPrefetch(index: 39, loaded: 50, total: 80))
        XCTAssertFalse(ListPaging.shouldPrefetch(index: 38, loaded: 50, total: 80))
        XCTAssertFalse(ListPaging.shouldPrefetch(index: 49, loaded: 50, total: 50))
        XCTAssertFalse(ListPaging.shouldPrefetch(index: 0, loaded: 0, total: nil))
        XCTAssertFalse(ListPaging.shouldPrefetch(index: -1, loaded: 10, total: nil))
        XCTAssertFalse(ListPaging.shouldPrefetch(index: 10, loaded: 10, total: nil))
        XCTAssertTrue(ListPaging.shouldPrefetch(index: 39, loaded: 50, total: nil))
    }

    func testT02_20_imageMaxWidthIsPointsTimesScale() {
        XCTAssertEqual(ImageRequestSizing.maxPixelWidth(displayPoints: 200, screenScale: 2), 400)
        XCTAssertEqual(ImageRequestSizing.maxPixelWidth(displayPoints: 0, screenScale: 0), 1)
        XCTAssertEqual(ImageRequestSizing.maxPixelWidth(displayPoints: .max, screenScale: 2), .max)
    }

    func testT02_21_navigationRestoresFocusAndRejectsBadIDs() throws {
        XCTAssertNil(HomeTabRoute.item(id: "not-a-guid"))
        XCTAssertNil(HomeTabRoute.series(id: "not-a-guid"))
        var tabs = TabNavigationState()
        let item = HomeTabRoute.item(id: Sample.movie)
        let series = HomeTabRoute.series(id: Sample.other)
        let movieID = try XCTUnwrap(ItemID(Sample.movie))
        let libraryID = try XCTUnwrap(ItemID(Sample.library))
        XCTAssertEqual(item, .item(movieID))
        tabs.home.push(try XCTUnwrap(item), focusedID: "root-focus", scrollID: "root-scroll")
        tabs.home.push(try XCTUnwrap(series), focusedID: "item-focus", scrollID: "item-scroll")
        tabs.library.push(.folder(libraryID))
        tabs.search.push(.item(movieID))
        tabs.settings.push(.diagnostics)
        tabs.settings.push(.server(Sample.serverID))
        XCTAssertEqual(
            tabs.home.pop(), RouteStack<HomeTabRoute>.RestoredFocus(focusedID: "item-focus", scrollID: "item-scroll"))
        XCTAssertEqual(tabs.home.path, [try XCTUnwrap(item)])
        XCTAssertEqual(
            tabs.home.pop(), RouteStack<HomeTabRoute>.RestoredFocus(focusedID: "root-focus", scrollID: "root-scroll"))
        XCTAssertNil(tabs.home.pop())
        XCTAssertEqual(tabs.settings.path.count, 2)
    }

    func testT02_03_userDataOptimisticRefetchAndWebSocket() async {
        let store = UserDataStore()
        let log = CapturingLog()
        let seeded = await store.project([Sample.movie(played: false)])
        XCTAssertEqual(seeded[0].userData.played, false)
        let previous = await store.applyOptimistic(
            id: Sample.movie, next: UserItemState(played: true, isFavorite: true))
        XCTAssertEqual(previous.played, false)
        expectTrue(await store.isPending(id: Sample.movie))
        let refetched = await store.project([Sample.movie(played: false)])
        XCTAssertEqual(refetched[0].userData.played, true)
        await store.replaceFromServer(id: Sample.movie, UserItemState(played: false))
        expectEqual(await store.state(for: Sample.movie)?.played, true)

        await store.applyRemote(
            UserDataChange(itemID: Sample.movie, played: true, positionTicks: -5, isFavorite: false), log: log)
        let remote = await store.state(for: Sample.movie)
        XCTAssertEqual(remote?.played, true)
        XCTAssertEqual(remote?.isFavorite, false)
        XCTAssertEqual(remote?.playbackPosition, .zero)
        expectFalse(await store.isPending(id: Sample.movie))
        await store.applyRemote(
            UserDataChange(itemID: Sample.movie, played: true, positionTicks: -9, isFavorite: false), log: log)
        XCTAssertEqual(log.messages().count, 1)
        XCTAssertTrue(log.messages()[0].contains(Sample.movie))
        XCTAssertFalse(log.contains(Sample.token))

        await store.applyRemote(
            UserDataChange(itemID: "not-a-guid", played: true, positionTicks: 0, isFavorite: false), log: log)
        expectNil(await store.state(for: "not-a-guid"))
        await store.replaceFromServer(id: "not-a-guid", UserItemState(played: true))
        await store.recordPlayback(id: "not-a-guid", position: .zero, played: true, log: log)
        await store.commit(id: "missing")

        await store.recordPlayback(id: Sample.other, position: .seconds(-3), played: true, log: log)
        await store.recordPlayback(id: Sample.other, position: .seconds(-1), played: true, log: log)
        expectEqual(await store.state(for: Sample.other)?.playbackPosition, .zero)
        XCTAssertEqual(log.messages().count, 2)
        await store.rollback(id: Sample.other, to: UserItemState(played: false))
        expectEqual(await store.state(for: Sample.other)?.played, false)
        expectFalse(await store.isPending(id: Sample.other))

        let fresh = UserDataStore()
        await fresh.replaceFromServer(id: Sample.movie, UserItemState(played: true, isFavorite: true))
        let projected = await fresh.project([Sample.movie(played: false)])
        XCTAssertEqual(projected[0].userData.played, true)
        await fresh.commit(id: Sample.movie)
        expectEqual(await fresh.state(for: Sample.movie)?.played, true)

        let payload = """
            {"MessageType":"UserDataChanged","Data":{"UserDataList":[
              {"ItemId":"not-a-guid","UserData":{"Played":true}},
              {"ItemId":"\(Sample.movie)","UserData":{"Played":true,"PlaybackPositionTicks":10000000,"IsFavorite":true}}
            ]}}
            """
        let changes = ServerEventParser.userDataChanges(in: Data(payload.utf8))
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].itemID, Sample.movie)
        XCTAssertEqual(changes[0].played, true)
        if case .userDataChanged(let items) = ServerEventParser.parse(Data(payload.utf8)) {
            XCTAssertEqual(items.count, 1)
        } else {
            XCTFail("expected user data")
        }
    }

    func testRequestScopeCancelsTrackedWork() async {
        let scope = RequestScope()
        let task = Task<Void, Never> {
            try? await Task.sleep(for: .seconds(30))
        }
        scope.track(task)
        scope.cancelAll()
        await task.value
        XCTAssertTrue(task.isCancelled)
        scope.cancelAll()
    }
}

#if os(macOS) || os(iOS) || os(tvOS)
    import os

    final class T02_33_AppleSignpostMetricTests: XCTestCase {
        func testT02_33_xctMetricRecordsPlaybackFirstFrame() {
            let poster = OSSignposter(subsystem: Signposters.subsystem, category: Signposters.category)
            let metric = XCTOSSignpostMetric(
                subsystem: Signposters.subsystem, category: Signposters.category, name: "playback.firstFrame")
            let options = XCTMeasureOptions()
            options.iterationCount = 1
            measure(metrics: [metric, XCTClockMetric(), XCTMemoryMetric()], options: options) {
                let state = poster.beginInterval("playback.firstFrame")
                var buffer = [UInt8](repeating: 0, count: 256)
                buffer[0] = 1
                poster.endInterval("playback.firstFrame", state)
                _ = buffer
            }
        }
    }
#endif
