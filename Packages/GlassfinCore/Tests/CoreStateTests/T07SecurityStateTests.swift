import CoreModels
import CoreNetworking
import CoreState
import CoreTestSupport
import Foundation
import GlassfinServices
import XCTest

@MainActor
final class T07SecurityStateTests: XCTestCase {
    func testT07_16_401CancelsAllRequestsEndsSessionOnceAndNeverRetries() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let inner = T07CancellationClient()
        let client = SessionFeatureClient(inner: inner, app: rig.app)
        let slow = Task { () -> APIError? in
            do {
                _ = try await client.send(APIRequest(method: "GET", path: "/slow"))
                return nil
            } catch let error as APIError { return error } catch { return .network }
        }
        await inner.waitUntilStarted()
        do {
            _ = try await client.send(APIRequest(method: "GET", path: "/unauthorized"))
            XCTFail("401 accepted")
        } catch { XCTAssertEqual(error, .unauthorized) }
        let failure = await slow.value
        XCTAssertEqual(failure, .cancelled)
        XCTAssertEqual(rig.app.sessionNoticeKey, .sessionExpired)
        guard case .needsLogin = rig.app.phase else { return XCTFail("Expected sign-in") }
        do { _ = try await client.send(APIRequest(method: "GET", path: "/unauthorized")) } catch {
            XCTAssertEqual(error, .cancelled)
        }
        let unauthorizedCalls = await inner.unauthorizedCalls
        XCTAssertEqual(unauthorizedCalls, 1)
        XCTAssertEqual(rig.secure.removed().filter { $0 == Sample.account() }.count, 1)
    }

    func testT07_35_disappearCancelsTheActivePageAndIgnoresItsResult() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let inner = T07CancellationClient()
        let model = LibraryViewModel(
            library: JellyfinLibraryService(client: inner), userData: rig.app.userData,
            responses: rig.app.responses, app: rig.app, clock: rig.clock)
        let load = Task { await model.reload(libraryID: Sample.library) }
        await inner.waitUntilStarted()
        model.onDisappear()
        await load.value
        XCTAssertNil(model.state.value)
        XCTAssertNil(model.state.presentedError)
    }

    func testT07_29_non401ErrorsKeepSessionAndCancellationIsNotPresented() async throws {
        for error in [
            APIError.forbidden, .notFound, .server(status: 500), .timeout, .network, .tls, .cancelled, .decoding,
        ] {
            let rig = Harness.make()
            defer { rig.cleanup() }
            try rig.signIn()
            let inner = MockAPIClient { _ async throws(APIError) -> Data in throw error }
            let client = SessionFeatureClient(inner: inner, app: rig.app)
            do {
                _ = try await client.send(APIRequest(method: "GET", path: "/Items"))
                XCTFail("Expected failure")
            } catch {}
            guard case .signedIn = rig.app.phase else { return XCTFail("Non-401 signed out") }
            XCTAssertNil(rig.app.sessionNoticeKey)
            if error == .cancelled { XCTAssertNil(AppErrorMessage.key(for: .cancelled)) }
        }
    }

    func testT07_24_imageLoaderAndDiskRejectOversizeAndUseTheExactHashFilename() async throws {
        let rig = Harness.make()
        defer { rig.cleanup() }
        try rig.signIn()
        let request = LibraryImageRequest(
            serverID: Sample.serverID, itemID: try XCTUnwrap(ItemID(Sample.movie)), type: .primary, tag: "tag",
            width: 250, height: 375)
        let client = MockAPIClient { _ in Data(repeating: 0, count: MetadataPolicy.imageMaxBytes + 1) }
        let loader = LibraryImageLoader(client: client, cache: rig.app.images.disk)
        do {
            _ = try await loader.data(for: request)
            XCTFail("Oversize accepted")
        } catch { XCTAssertEqual(error, .decoding) }
        let missing = await rig.app.images.disk.data(for: request.cacheKey)
        XCTAssertNil(missing)
        let rejected = await rig.app.images.disk.store(
            key: request.cacheKey, data: Data(repeating: 0, count: MetadataPolicy.imageMaxBytes + 1))
        XCTAssertFalse(rejected)
        await client.setHandler { _ in Data([1, 2, 3]) }
        let loaded = try await loader.data(for: request)
        let cached = try await loader.data(for: request)
        XCTAssertEqual(loaded, cached)
        let calls = await client.calls
        XCTAssertEqual(calls.count, 2)
        let enumerator = FileManager.default.enumerator(at: rig.root, includingPropertiesForKeys: nil)
        let paths = (enumerator?.allObjects as? [URL] ?? []).map(\.lastPathComponent)
        XCTAssertTrue(paths.contains(request.cacheKey))
        XCTAssertFalse(
            paths.contains { $0.contains("https") || $0.contains(Sample.token) || $0.contains(Sample.movie) })
    }
}

private actor T07CancellationClient: JellyfinAPIClient {
    private var started = false
    private var observers: [CheckedContinuation<Void, Never>] = []
    var unauthorizedCalls = 0

    func send(_ request: APIRequest) async throws(APIError) -> Data {
        if request.path == "/unauthorized" {
            unauthorizedCalls += 1
            throw .unauthorized
        }
        started = true
        for observer in observers { observer.resume() }
        observers.removeAll()
        do { try await Task.sleep(for: .seconds(60)) } catch { throw .cancelled }
        return Data()
    }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { observers.append($0) }
    }
}
