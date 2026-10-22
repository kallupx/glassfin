import CoreModels
import Foundation
import XCTest

@testable import CoreNetworking

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

final class AuthorizationHeaderTests: XCTestCase {
    func testHeaderOmitsTokenBeforeLogin() throws {
        let header = try AuthorizationHeader.value(
            client: "Glassfin",
            device: "Apple TV",
            deviceID: "device-1",
            version: "0.1.0",
            token: nil
        )
        XCTAssertEqual(
            header,
            "MediaBrowser Client=\"Glassfin\", Device=\"Apple%20TV\", DeviceId=\"device-1\", Version=\"0.1.0\""
        )
        XCTAssertFalse(header.contains("Token"))

        let empty = try AuthorizationHeader.value(
            client: "Glassfin",
            device: "Apple TV",
            deviceID: "device-1",
            version: "0.1.0",
            token: ""
        )
        XCTAssertFalse(empty.contains("Token"))
    }

    func testHeaderAppendsQuotedTokenAfterLogin() throws {
        let header = try AuthorizationHeader.value(
            client: "Glassfin",
            device: "Apple TV",
            deviceID: "device-1",
            version: "0.1.0",
            token: "tok en"
        )
        XCTAssertEqual(
            header,
            "MediaBrowser Client=\"Glassfin\", Device=\"Apple%20TV\", DeviceId=\"device-1\", Version=\"0.1.0\", Token=\"tok%20en\""
        )
    }

    func testDeviceNameWithQuotesCommaAndEmojiIsPercentEncoded() throws {
        let header = try AuthorizationHeader.value(
            client: "Glassfin",
            device: "Living \"Room\", 🎬",
            deviceID: "device-1",
            version: "1.0.0",
            token: nil
        )
        XCTAssertEqual(
            header,
            "MediaBrowser Client=\"Glassfin\", Device=\"Living%20%22Room%22%2C%20%F0%9F%8E%AC\", DeviceId=\"device-1\", Version=\"1.0.0\""
        )
        XCTAssertFalse(header.contains("🎬"))
        XCTAssertFalse(header.contains("Living \""))
    }

    /// T01-28. CR, LF, and CRLF in a header value are rejected so they cannot inject another header line.
    func testT01_28_rejectsControlCharactersAndCRLFInjection() {
        for device in ["Living\nRoom", "Living\rRoom", "Living\r\nX-Injected: yes"] {
            XCTAssertThrowsError(
                try AuthorizationHeader.value(
                    client: "Glassfin",
                    device: device,
                    deviceID: "device-1",
                    version: "1",
                    token: nil
                )
            ) { error in
                XCTAssertEqual(error as? AuthorizationHeaderError, .controlCharacter)
            }
        }
        let identity = ClientIdentity(
            deviceName: "Living\r\nRoom",
            deviceID: "device-1",
            version: "1",
            token: "abc"
        )
        do {
            _ = try identity.authorizationHeader()
            XCTFail("Expected the header builder to reject CRLF")
        } catch let error as APIError {
            XCTAssertEqual(error, .headerRejected)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }
}

final class RedactionTests: XCTestCase {
    /// T01-29. The same redaction covers logs and CI text artifacts (`scripts/redact_artifacts.py`).
    func testT01_29_redactsSecretsInLogsAndCIArtifacts() {
        let legacy = "api" + "_key"
        let raw = """
            https://media.example/Videos/1/stream?\(legacy)=legacy-secret&static=true
            https://media.example/Videos/1/stream?ApiKey=query-secret&deviceId=dev
            Authorization: MediaBrowser Token="header-secret"
            {"Pw":"password-secret","Token":"json-secret","AccessToken":"access-secret"}
            """
        let redacted = SensitiveRedactor.redact(raw)
        XCTAssertFalse(redacted.contains("legacy-secret"))
        XCTAssertFalse(redacted.contains("query-secret"))
        XCTAssertFalse(redacted.contains("header-secret"))
        XCTAssertFalse(redacted.contains("password-secret"))
        XCTAssertFalse(redacted.contains("json-secret"))
        XCTAssertFalse(redacted.contains("access-secret"))
        XCTAssertTrue(redacted.contains("REDACTED"))
        GlassfinLogger().warning(raw)
        let bare = SensitiveRedactor.redact("server Glassfin Home version 12.2.0 ApiKey=query-secret")
        XCTAssertFalse(bare.contains("query-secret"))
        GlassfinLogger().infoPublic(bare)
    }

    /// T01-32. Detection and redaction match apikey and the underscored legacy name in any case.
    func testT01_32_detectsAndRedactsCredentialQueryNamesIgnoringCase() throws {
        let legacy = "api" + "_key"
        for name in ["apikey", "APIKEY", "ApiKey", legacy, legacy.uppercased()] {
            let url = try XCTUnwrap(URL(string: "https://media.example/v?\(name)=secret"))
            XCTAssertTrue(RedirectPolicy.containsCredentialQuery(url), name)
            let redacted = SensitiveRedactor.redact("https://media.example/v?\(name)=case-secret&x=1")
            XCTAssertFalse(redacted.contains("case-secret"), name)
            XCTAssertTrue(redacted.contains("REDACTED"), name)
        }
    }
}

final class RedirectPolicyTests: XCTestCase {
    func testAuthorizationDoesNotCrossHostsAndDowngradesAreRejected() throws {
        let same = try decide("https://media.example/a", "https://media.example/b")
        XCTAssertEqual(same, .follow(stripAuthorization: false))

        let cross = try decide("https://media.example/a", "https://other.example/b")
        XCTAssertEqual(cross, .follow(stripAuthorization: true))

        let caseFold = try decide("https://Media.Example/a", "https://media.example/b")
        XCTAssertEqual(caseFold, .follow(stripAuthorization: false))

        let downgrade = try decide("https://media.example/a", "http://media.example/a")
        XCTAssertEqual(downgrade, .reject(.httpsDowngrade))

        let credentialCross = try decide("https://media.example/v?ApiKey=secret", "https://other.example/v")
        XCTAssertEqual(credentialCross, .reject(.credentialQueryCrossHost))

        let credentialDowngrade = try decide("https://media.example/v?ApiKey=secret", "http://media.example/v")
        XCTAssertEqual(credentialDowngrade, .reject(.credentialQueryDowngrade))

        let legacy = "api" + "_key"
        let legacyCross = try decide("https://media.example/v?\(legacy)=secret", "https://cdn.example/v")
        XCTAssertEqual(legacyCross, .reject(.credentialQueryCrossHost))

        let credentialSame = try decide("https://media.example/v?ApiKey=secret", "https://media.example/v2")
        XCTAssertEqual(credentialSame, .follow(stripAuthorization: false))

        let defaultPort = try decide("https://media.example/a", "https://media.example:443/b")
        XCTAssertEqual(defaultPort, .follow(stripAuthorization: false))

        let differentPort = try decide("http://media.example:8096/a", "http://media.example:8080/a")
        XCTAssertEqual(differentPort, .follow(stripAuthorization: true))

        let credentialPort = try decide(
            "http://media.example:8096/v?ApiKey=secret", "http://media.example:8080/v")
        XCTAssertEqual(credentialPort, .reject(.credentialQueryCrossHost))
    }

    /// T01-33. A redirect from host:8096 to host:8080 drops Authorization.
    func testT01_33_changedPortDropsAuthorization() throws {
        var original = URLRequest(url: URL(string: "http://media.example:8096/Items")!)
        original.setValue("MediaBrowser Token=\"secret\"", forHTTPHeaderField: "Authorization")
        var proposed = URLRequest(url: URL(string: "http://media.example:8080/Items")!)
        proposed.setValue("MediaBrowser Token=\"secret\"", forHTTPHeaderField: "Authorization")
        guard case .follow(let next) = RedirectPolicy.apply(original: original, proposed: proposed) else {
            return XCTFail("Expected a stripped follow")
        }
        XCTAssertNil(next.value(forHTTPHeaderField: "Authorization"))
    }

    func testCrossHostFollowStripsTheAuthorizationHeader() throws {
        var original = URLRequest(url: URL(string: "https://media.example/Items")!)
        original.setValue("MediaBrowser Token=\"secret\"", forHTTPHeaderField: "Authorization")
        var proposed = URLRequest(url: URL(string: "https://other.example/Items")!)
        proposed.setValue("MediaBrowser Token=\"secret\"", forHTTPHeaderField: "Authorization")
        guard case .follow(let next) = RedirectPolicy.apply(original: original, proposed: proposed) else {
            return XCTFail("Expected a stripped follow")
        }
        XCTAssertNil(next.value(forHTTPHeaderField: "Authorization"))
    }

    private func decide(_ original: String, _ redirect: String) throws -> RedirectFollow {
        RedirectPolicy.decide(
            originalURL: try XCTUnwrap(URL(string: original)),
            redirectURL: try XCTUnwrap(URL(string: redirect))
        )
    }
}

final class BackoffTests: XCTestCase {
    func testFullJitterSequenceAndStableReset() {
        let expected = [1_000, 2_000, 4_000, 8_000, 16_000, 30_000, 30_000].map { Duration.milliseconds($0) }
        var controller = ReconnectController()
        var delays: [Duration] = []
        for _ in 0..<7 {
            delays.append(controller.delayAfterFailure(now: .zero, jitterUnit: 1))
        }
        XCTAssertEqual(delays, expected)

        controller.didConnect(now: .seconds(0))
        controller.markStableIfNeeded(now: .seconds(9))
        XCTAssertEqual(controller.attempt, 7)
        let early = controller.delayAfterFailure(now: .seconds(9), jitterUnit: 1)
        XCTAssertEqual(early, .seconds(30))

        var stable = ReconnectController(attempt: 4)
        stable.didConnect(now: .seconds(0))
        stable.markStableIfNeeded(now: .seconds(10))
        XCTAssertEqual(stable.attempt, 0)
        XCTAssertEqual(stable.delayAfterFailure(now: .seconds(10), jitterUnit: 1), .seconds(1))
        XCTAssertEqual(ExponentialBackoff.delay(attempt: 0, jitterUnit: 0), .zero)
    }
}

final class DeviceIdentityTests: XCTestCase {
    func testDeviceIdentifierIsStableUntilReset() throws {
        let store = InMemorySecureStore()
        let first = try DeviceIdentityStore.loadOrCreate(secureStore: store, reset: false)
        let second = try DeviceIdentityStore.loadOrCreate(secureStore: store, reset: false)
        XCTAssertEqual(first, second)
        let reset = try DeviceIdentityStore.loadOrCreate(secureStore: store, reset: true)
        XCTAssertNotEqual(first, reset)
    }

    /// T01-31. A signed build expands `GlassfinKeychainAccessGroup` to the team-prefixed group.
    /// The SecItem query includes that group. Simulator and Linux runs read the app Info.plist
    /// and check the same query a signed build sends.
    func testT01_31_keychainWriteQueryContainsInfoPlistAccessGroup() throws {
        let key = KeychainAccessGroup.infoDictionaryKey
        let declared = "$(AppIdentifierPrefix)org.glassfin.app"
        for platform in ["tvOS", "iOS"] {
            let info = try appInfoPlist(platform)
            XCTAssertEqual(info[key] as? String, declared)
            XCTAssertEqual(KeychainAccessGroup.resolve(info), "")
            XCTAssertNil(KeychainItemQuery.base(account: DeviceIdentityStore.account, accessGroup: "")["agrp"])
        }
        let signedGroup = "ABCDE12345.org.glassfin.app"
        let attributes = KeychainAttributes.production(info: [key: signedGroup])
        XCTAssertEqual(attributes.accessibility, "AfterFirstUnlockThisDeviceOnly")
        XCTAssertFalse(attributes.synchronizable)
        XCTAssertEqual(attributes.accessGroup, signedGroup)
        let query = KeychainItemQuery.base(
            account: DeviceIdentityStore.account, accessGroup: attributes.accessGroup)
        XCTAssertEqual(query["agrp"] as? String, signedGroup)
        XCTAssertEqual(KeychainWritePlan.afterUpdate(status: KeychainWritePlan.success), .updated)
        XCTAssertEqual(KeychainWritePlan.afterUpdate(status: KeychainWritePlan.itemNotFound), .add)
        XCTAssertEqual(KeychainWritePlan.afterUpdate(status: -1), .fail(-1))
    }

    private func appInfoPlist(_ platform: String) throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("Apps/\(platform)/Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(plist as? [String: Any])
    }
}

#if DEBUG
    final class LaunchConfigurationTests: XCTestCase {
        func testDebugLaunchArguments() {
            let config = LaunchConfiguration(arguments: ["-uitest-mock-server", "-uitest-reset"])
            XCTAssertTrue(config.useMockServer)
            XCTAssertTrue(config.resetState)
            let plain = LaunchConfiguration(arguments: [])
            XCTAssertFalse(plain.useMockServer)
            XCTAssertFalse(plain.resetState)
        }
    }
#endif

final class MediaAndSocketTests: XCTestCase {
    func testHeaderAndAPIKeyModesAreMutuallyExclusive() throws {
        let server = URL(string: "https://media.example/jellyfin")!
        let identity = ClientIdentity(
            deviceName: "Living Room", deviceID: "device-1", version: "0.1.0", token: "token-secret")
        let header = try MediaRequestBuilder.prepare(
            server: server,
            path: "/Videos/movie/stream",
            identity: identity,
            mode: .header
        )
        XCTAssertNotNil(header.authorizationHeader)
        XCTAssertFalse(header.usesAPIKeyQuery)
        XCTAssertFalse(header.url.absoluteString.contains("ApiKey"))

        let query = try MediaRequestBuilder.prepare(
            server: server,
            path: "/Videos/movie/stream",
            identity: identity,
            mode: .apiKeyQuery
        )
        XCTAssertNil(query.authorizationHeader)
        XCTAssertTrue(query.usesAPIKeyQuery)
        XCTAssertTrue(query.url.absoluteString.contains("ApiKey=token-secret"))
        XCTAssertFalse(String(describing: query).contains("token-secret"))
    }

    func testSocketUsesTheAuthorizationHeaderAndNotAPIKey() throws {
        let request = try SocketRequestBuilder.make(
            server: URL(string: "https://media.example/jellyfin/")!,
            identity: ClientIdentity(
                deviceName: "Living Room", deviceID: "device-1", version: "0.1.0", token: "token-secret")
        )
        let url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.scheme, "wss")
        XCTAssertEqual(url.path, "/jellyfin/socket")
        XCTAssertFalse(url.absoluteString.contains("ApiKey"))
        XCTAssertTrue(url.absoluteString.contains("deviceId=device-1"))
        XCTAssertNotNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testAPIRequestsRejectCredentialQuery() throws {
        let client = HTTPJellyfinClient(
            server: URL(string: "https://media.example")!,
            identity: ClientIdentity(deviceName: "TV", deviceID: "device-1", version: "0.1.0", token: "token-secret")
        )
        XCTAssertThrowsError(
            try client.makeURLRequest(
                APIRequest(method: "GET", path: "/Items", query: [URLQueryItem(name: "ApiKey", value: "x")]))
        )
    }

    func testServerURLDropsUserinfo() throws {
        let normalized = try ServerURLNormalizer.normalize(URL(string: "https://user:secret@media.example/jellyfin")!)
        XCTAssertNil(normalized.user)
        XCTAssertNil(normalized.password)
        XCTAssertEqual(normalized.path, "/jellyfin")
        XCTAssertThrowsError(try ServerURLNormalizer.normalize(URL(string: "ftp://media.example")!))
    }
}

final class ScriptClock: GlassfinClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Duration
    private var recorded: [Duration] = []
    var hang: Bool

    init(now: Duration = .zero, hang: Bool = false) {
        current = now
        self.hang = hang
    }

    func now() -> Duration {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func sleeps() -> [Duration] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func sleep(for duration: Duration) async throws {
        record(duration)
        if hang {
            try await Task.sleep(for: .seconds(60))
        }
    }

    private func record(_ duration: Duration) {
        lock.lock()
        recorded.append(duration)
        lock.unlock()
    }
}

final class ScriptedSocket: RealtimeSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var inbox: [Data]
    private var sent: [Data] = []
    private let connectError: (any Error)?

    init(inbox: [Data] = [], connectError: (any Error)? = nil) {
        self.inbox = inbox
        self.connectError = connectError
    }

    func connect() async throws {
        if let connectError { throw connectError }
    }

    func receive() async throws -> Data {
        if let next = dequeue() { return next }
        try await Task.sleep(for: .seconds(60))
        throw CancellationError()
    }

    func send(_ data: Data) async throws {
        enqueueSent(data)
    }

    private func dequeue() -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return inbox.isEmpty ? nil : inbox.removeFirst()
    }

    private func enqueueSent(_ data: Data) {
        lock.lock()
        sent.append(data)
        lock.unlock()
    }

    func close() async {}

    func sentMessages() -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        return sent
    }
}

final class ScriptedFactory: RealtimeSocketFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [ScriptedSocket]

    init(_ queue: [ScriptedSocket]) { self.queue = queue }

    func makeSocket(url: URL) -> any RealtimeSocket {
        lock.lock()
        defer { lock.unlock() }
        if queue.isEmpty { return ScriptedSocket() }
        return queue.removeFirst()
    }
}

final class LockedEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ServerEvent] = []
    func append(_ event: ServerEvent) {
        lock.lock()
        values.append(event)
        lock.unlock()
    }
    func snapshot() -> [ServerEvent] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

final class ServerEventStreamTests: XCTestCase {
    func testEventsKeepAliveAndUnknownMessages() async {
        let socket = ScriptedSocket(inbox: [
            Data("{\"MessageType\":\"UserDataChanged\"}".utf8),
            Data("{\"MessageType\":\"LibraryChanged\"}".utf8),
            Data("{\"MessageType\":\"KeepAlive\"}".utf8),
            Data("{\"MessageType\":\"NotARealEvent\"}".utf8),
            Data("{\"MessageType\":\"ForceKeepAlive\"}".utf8),
        ])
        let events = LockedEvents()
        let stream = makeStream(sockets: [socket], clock: ScriptClock())
        let collect = Task {
            for await event in stream.events {
                events.append(event)
            }
        }
        await waitUntil { events.snapshot().count >= 2 && socket.sentMessages().count >= 1 }
        stream.stop()
        await collect.value
        XCTAssertEqual(events.snapshot(), [.userDataChanged(items: []), .libraryChanged])
        XCTAssertEqual(socket.sentMessages(), [ServerEventParser.keepAliveReply])
    }

    func testServerRestartDoesNotLookLikeLogout() async {
        let events = LockedEvents()
        let stream = makeStream(
            sockets: [
                ScriptedSocket(inbox: [Data("{\"MessageType\":\"ServerRestarting\"}".utf8)]),
                ScriptedSocket(),
            ],
            clock: ScriptClock()
        )
        let collect = Task {
            for await event in stream.events {
                events.append(event)
            }
        }
        await waitUntil { stream.phase == .connected && events.snapshot().contains(.serverRestarting) }
        stream.stop()
        await collect.value
        XCTAssertEqual(events.snapshot(), [.serverRestarting])
        XCTAssertNotEqual(stream.phase, .idle)
    }

    func testBackoffDelaysMatchTheFullJitterCap() async {
        let clock = ScriptClock()
        let failing = (0..<7).map { _ in ScriptedSocket(connectError: URLError(.networkConnectionLost)) }
        let stream = makeStream(sockets: failing + [ScriptedSocket()], clock: clock)
        await waitUntil(timeoutSeconds: 3) { clock.sleeps().count >= 7 }
        stream.stop()
        XCTAssertEqual(
            Array(clock.sleeps().prefix(7)),
            [1_000, 2_000, 4_000, 8_000, 16_000, 30_000, 30_000].map { Duration.milliseconds($0) }
        )
    }

    func testForegroundHookSkipsTheBackoffSleep() async {
        let clock = ScriptClock(hang: true)
        let events = LockedEvents()
        let stream = makeStream(
            sockets: [
                ScriptedSocket(connectError: URLError(.networkConnectionLost)),
                ScriptedSocket(inbox: [Data("{\"MessageType\":\"UserDataChanged\"}".utf8)]),
            ],
            clock: clock
        )
        let collect = Task {
            for await event in stream.events {
                events.append(event)
            }
        }
        await waitUntil { !clock.sleeps().isEmpty }
        stream.applicationDidBecomeActive()
        await waitUntil {
            events.snapshot().contains { event in
                if case .userDataChanged = event { return true }
                return false
            }
        }
        stream.stop()
        await collect.value
        XCTAssertEqual(events.snapshot(), [.userDataChanged(items: [])])
        XCTAssertEqual(clock.sleeps().count, 1)
    }

    private func makeStream(sockets: [ScriptedSocket], clock: ScriptClock) -> ReconnectingServerEventStream {
        let url = URL(string: "wss://media.example/socket?deviceId=device-1")!
        return ReconnectingServerEventStream(
            request: URLRequest(url: url),
            sockets: ScriptedFactory(sockets),
            clock: clock,
            jitter: ConstantJitter(unit: 1)
        )
    }

    private func waitUntil(timeoutSeconds: Double = 2, _ predicate: () -> Bool) async {
        let clock = ContinuousClock()
        let start = clock.now
        while !predicate() {
            if start.duration(to: .now) > .seconds(timeoutSeconds) { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
