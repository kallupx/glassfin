import CoreModels
import CoreState
import Foundation
import XCTest

@testable import CoreNetworking

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

final class ServerStartingTests: XCTestCase {
    func test503HasDedicatedCopyInEveryAuthenticationContextEvenIfPathIsOffline() throws {
        let failure = try XCTUnwrap(HTTPStatusMapper.apiFailure(for: 503))
        XCTAssertEqual(failure, .serverStarting)
        for context in [RequestAuthentication.anonymous, .login, .authenticated] {
            for offline in [false, true] {
                let error = AppErrorMapping.map(failure, context: context, deviceOffline: offline)
                XCTAssertEqual(error, .serverStarting)
                XCTAssertEqual(AppErrorMessage.messageKey(for: error), AppErrorMessage.serverStartingKey)
                XCTAssertEqual(AuthCopy.Key.serverStarting.rawValue, AppErrorMessage.serverStartingKey)
                XCTAssertFalse(CoreModels.SessionTermination.shouldEndSession(error))
                XCTAssertTrue(AppErrorMapping.isConnectivity(error))
            }
        }
    }

    @MainActor
    func test503HTMLWithRetryAfterKeepsTokenAndPublishesStartupAcrossSessionClients() async throws {
        for kind in 0..<3 {
            let harness = Harness.make(automaticPing: true)
            defer { harness.cleanup() }
            try harness.signIn()
            let wire = StartupTransport()
            let http = HTTPJellyfinClient(
                server: Sample.server().url,
                identity: ClientIdentity(
                    deviceName: "Test", deviceID: "test-device", version: "test", token: Sample.token),
                transport: wire, log: harness.log)
            defer { http.session.invalidateAndCancel() }
            let retrying = RetryingAPIClient(inner: http, clock: harness.clock)
            let client: any JellyfinAPIClient
            switch kind {
            case 0: client = HomeSessionClient(inner: retrying, app: harness.app, scope: harness.app.scope)
            case 1: client = SessionAPIClient(inner: retrying, app: harness.app)
            default: client = SessionFeatureClient(inner: retrying, app: harness.app)
            }
            let generation = harness.app.requestGeneration
            let request = APIRequest(
                method: kind == 2 ? "POST" : "GET", path: "/Users/Me",
                maximumResponseBytes: kind == 1 ? 1 : nil)
            do {
                _ = try await client.send(request, as: PublicSystemInfoDTO.self)
                XCTFail("Expected startup before JSON decoding")
            } catch {
                XCTAssertEqual(error, .serverStarting)
            }
            XCTAssertTrue(harness.app.isServerStarting)
            XCTAssertEqual(harness.app.bannerKey, AppErrorMessage.serverStartingKey)
            XCTAssertEqual(harness.app.serverDownTitleKey, AppErrorMessage.serverStartingKey)
            XCTAssertEqual(harness.app.playbackBlockedMessageKey, AppErrorMessage.serverStartingKey)
            XCTAssertEqual(harness.app.retryTitleKey, AppErrorMessage.retryKey)
            XCTAssertEqual(harness.app.requestGeneration, generation)
            XCTAssertEqual(harness.app.phase, .signedIn(Sample.session()))
            XCTAssertEqual(try harness.secure.data(for: Sample.account()), Data(Sample.token.utf8))
            XCTAssertTrue(harness.secure.removed().isEmpty)
            XCTAssertEqual(wire.calls, 1)
            XCTAssertTrue(harness.manual?.sleeps().isEmpty == true)
            XCTAssertFalse(harness.log.contains(StartupTransport.bodyMarker))
            XCTAssertFalse(harness.log.contains(StartupTransport.headerMarker))
            XCTAssertFalse(AppErrorMessage.userFacing(.serverStarting)?.contains(StartupTransport.headerMarker) == true)

            harness.pinger.outcome = .failed(.serverStarting)
            await harness.app.retryNow()
            XCTAssertTrue(harness.app.isServerStarting)
            harness.pinger.outcome = .ok
            await harness.app.retryNow()
            XCTAssertFalse(harness.app.isServerStarting)
            XCTAssertEqual(harness.app.connectivity, .online)
            XCTAssertEqual(try harness.secure.data(for: Sample.account()), Data(Sample.token.utf8))
        }
    }

    func testConnectProbe503StopsCandidateWalkWithoutInterpretingHTML() async {
        let wire = StartupTransport()
        let client = URLSessionPublicInfoClient(transport: wire)
        let outcome = await ServerProbe(client: client).run(address: "media.local")
        XCTAssertEqual(outcome, .serverStarting)
        XCTAssertEqual(ProbeErrorCopy.key(for: outcome), .serverStarting)
        XCTAssertFalse(ProbeErrorCopy.httpSkippedByPolicy(outcome))
        XCTAssertEqual(wire.calls, 1)
    }

    @MainActor
    func testSessionRestore503RetainsTokenAndStartupCopy() async throws {
        let harness = Harness.make(suspendingClock: true)
        defer { harness.cleanup() }
        try harness.signIn()
        let wire = StartupTransport()
        let http = HTTPJellyfinClient(
            server: Sample.server().url,
            identity: ClientIdentity(deviceName: "Test", deviceID: "test-device", version: "test"),
            transport: wire)
        defer { http.session.invalidateAndCancel() }
        let flow = AuthFlow(
            app: harness.app, backend: LiveAuthBackend(secureStore: harness.secure, client: http),
            pins: SettingsCertificatePinStore(settings: harness.settings),
            vault: CredentialVault(secureStore: harness.secure, settings: harness.settings, accessGroup: ""),
            clock: harness.clock)
        await flow.restoreSession()
        XCTAssertEqual(flow.screen, .home)
        XCTAssertEqual(flow.homeErrorKey, .serverStarting)
        XCTAssertEqual(flow.bannerKey, .serverStarting)
        XCTAssertEqual(harness.app.phase, .signedIn(Sample.session()))
        XCTAssertEqual(try harness.secure.data(for: Sample.account()), Data(Sample.token.utf8))
        XCTAssertTrue(harness.secure.removed().isEmpty)
        XCTAssertEqual(wire.calls, 1)
    }

    @MainActor
    func testConnectProbe503DoesNotStoreAcceptedTOFUPinUntilNormalResponse() async throws {
        let harness = Harness.make()
        defer { harness.cleanup() }
        let wire = StartupTransport()
        let candidate = CertificateThenPublicInfo(transport: wire)
        let pins = SettingsCertificatePinStore(settings: harness.settings)
        let backend = LiveAuthBackend(
            secureStore: harness.secure, probeClient: candidate, clock: harness.clock,
            client: DisabledQuickConnectClient(), pins: pins)
        let flow = AuthFlow(
            app: harness.app, backend: backend, pins: pins,
            vault: CredentialVault(secureStore: harness.secure, settings: harness.settings, accessGroup: ""),
            clock: harness.clock)
        defer { flow.cancelProbe() }
        flow.addressText = Sample.server().url.absoluteString
        flow.submitAddress()
        await waitUntil { flow.screen == .certificate && !flow.isProbing }
        try flow.acceptCertificate(userAcceptedFingerprint: CertificateThenPublicInfo.fingerprint)
        await waitUntil { flow.inlineError == .serverStarting && !flow.isProbing }
        XCTAssertEqual(flow.screen, .address)
        XCTAssertEqual(flow.focus, .tryAgain)
        XCTAssertNil(try pins.fingerprint(for: Sample.serverID))
        XCTAssertTrue(harness.settings.allValues().keys.allSatisfy { !$0.hasPrefix("certificate-pin.") })
        XCTAssertTrue(harness.app.preferencesSnapshot().servers.isEmpty)
        XCTAssertEqual(candidate.lastPin?.sha256, CertificateThenPublicInfo.fingerprint)
        XCTAssertEqual(wire.calls, 1)

        wire.answerNormally()
        await flow.retryServerStarting()
        await waitUntil { flow.screen == .credentials && !flow.isProbing }
        XCTAssertEqual(try pins.fingerprint(for: Sample.serverID), CertificateThenPublicInfo.fingerprint)
        XCTAssertNil(flow.inlineError)
        XCTAssertEqual(wire.calls, 2)
    }

    func testQuickConnectStartupStopsPollingWithoutSleepingOrAuthenticating() async {
        let clock = ManualClock()
        let outcome = await QuickConnectMonitor(clock: clock).run(
            secret: QuickConnectSecret("mock-secret"), code: "123456", log: SilentLog()
        ) { _ in .serverStarting }
        XCTAssertEqual(outcome, .serverStarting)
        XCTAssertTrue(clock.sleeps().isEmpty)
    }
}

private final class StartupTransport: RequestTransport, @unchecked Sendable {
    static let bodyMarker = "private-html-body"
    static let headerMarker = "private-message-header"
    private let lock = NSLock()
    private var count = 0
    private var normal = false
    var calls: Int { lock.withLock { count } }
    func answerNormally() { lock.withLock { normal = true } }

    func data(for request: URLRequest, maximumBytes: Int?) async throws -> (Data, URLResponse, Int?) {
        let normal = lock.withLock {
            count += 1
            return self.normal
        }
        let response = HTTPURLResponse(
            url: try XCTUnwrap(request.url), statusCode: normal ? 200 : 503, httpVersion: "HTTP/1.1",
            headerFields: ["Retry-After": "60", "Content-Type": "text/html", "Message": Self.headerMarker])!
        let data =
            normal
            ? Data(
                """
                {"Id":"\(Sample.serverID)","ServerName":"Test","Version":"10.11.0",
                 "ProductName":"Jellyfin Server","StartupWizardCompleted":true}
                """.utf8)
            : Data("<html><body>\(Self.bodyMarker)</body></html>".utf8)
        return (data, response, nil)
    }
}

private final class CertificateThenPublicInfo: ServerCandidateClient, @unchecked Sendable {
    static let fingerprint = String(repeating: "ab", count: 32)
    private let lock = NSLock()
    private var first = true
    private var storedPin: OriginCertificatePin?
    private let client: URLSessionPublicInfoClient
    var lastPin: OriginCertificatePin? { lock.withLock { storedPin } }
    init(transport: any RequestTransport) { client = URLSessionPublicInfoClient(transport: transport) }

    func fetchPublicInfo(url: URL, timeout: Duration, certificatePin: OriginCertificatePin?) async
        -> ServerCandidateResult
    {
        let needsCertificate = lock.withLock {
            storedPin = certificatePin
            let value = first
            first = false
            return value
        }
        if needsCertificate {
            return .tls(
                CertificatePresentation(
                    sha256: Self.fingerprint, subject: "Test", notBefore: .distantPast, notAfter: .distantFuture))
        }
        return await client.fetchPublicInfo(url: url, timeout: timeout, certificatePin: certificatePin)
    }
}

private struct DisabledQuickConnectClient: JellyfinAPIClient {
    func send(_ request: APIRequest) async throws(APIError) -> Data { Data("false".utf8) }
}
