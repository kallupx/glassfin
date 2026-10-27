import CoreModels
import CoreNetworking
import CoreState
import Foundation
import GlassfinServices
import XCTest

#if canImport(ImageIO)
    import CoreGraphics
    import ImageIO
#endif

@MainActor
final class T09PrivacyAndImageTests: XCTestCase {
    /// T09-47: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.
    func testT09_47_historyIsScopedByBothServerAndUserAndSurvivesRestart() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecentSearchStore(directory: root)
        try store.record("first", serverID: Sample.serverID, userID: Sample.userID)
        try store.record("second", serverID: Sample.serverID, userID: Sample.otherUserID)
        try store.record("third", serverID: Sample.otherServerID, userID: Sample.userID)
        let restored = RecentSearchStore(directory: root)
        XCTAssertEqual(try restored.queries(serverID: Sample.serverID, userID: Sample.userID), ["first"])
        XCTAssertEqual(try restored.queries(serverID: Sample.serverID, userID: Sample.otherUserID), ["second"])
        XCTAssertEqual(try restored.queries(serverID: Sample.otherServerID, userID: Sample.userID), ["third"])
    }

    /// T09-44: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    func testT09_44_historyCapRecencyAndDeduplication() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecentSearchStore(directory: root)
        for index in 0..<(MetadataPolicy.recentSearchesMax + 5) {
            try store.record("query \(index)", serverID: Sample.serverID, userID: Sample.userID)
        }
        try store.record("query 7", serverID: Sample.serverID, userID: Sample.userID)
        let values = try store.queries(serverID: Sample.serverID, userID: Sample.userID)
        XCTAssertEqual(values.count, MetadataPolicy.recentSearchesMax)
        XCTAssertEqual(values.first, "query 7")
        XCTAssertEqual(Set(values).count, values.count)
        XCTAssertEqual(values[1], "query \(MetadataPolicy.recentSearchesMax + 4)")
        XCTAssertFalse(values.contains("query 0"))
    }

    /// T09-49: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    func testT09_49_onlyQueryTextInApplicationSupportNoPreferencesOrKeychainWrites() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecentSearchStore(directory: root)
        let query = "& # ä 日本"
        try store.record(query, serverID: Sample.serverID, userID: Sample.userID)
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }
        XCTAssertEqual(files.count, 1)
        let file = try XCTUnwrap(files.first)
        XCTAssertEqual(try JSONDecoder().decode([String].self, from: Data(contentsOf: file)), [query])
        XCTAssertEqual(file.deletingPathExtension().lastPathComponent.count, 64)
        XCTAssertFalse(file.path.contains(Sample.userID))
        let support = try XCTUnwrap(
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        XCTAssertTrue(RecentSearchStore.applicationSupportDirectory.path.hasPrefix(support.path))
        // The store accepts only a directory; it has no SecureStore, SettingsStore or logger dependency.
    }

    /// T09-51: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    func testT09_51_signOutDeletesOnlyThatUsersHistory() throws {
        try checkCleanup(removeServer: false, unauthorized: false)
        try checkCleanup(removeServer: false, unauthorized: true)
    }

    /// T09-52: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    func testT09_52_serverRemovalDeletesAllItsUsersOnly() throws {
        try checkCleanup(removeServer: true, unauthorized: false)
    }

    /// T09-65: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    func testT09_65_imageCacheUsesStableSHA256TupleAsActualFilename() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try XCTUnwrap(ItemID(Sample.movie))
        let key = ImageCacheKey(
            serverID: Sample.serverID, itemID: id, type: .primary, tag: "abc", width: 200, height: 300)
        let repeated = ImageCacheKey(
            serverID: Sample.serverID, itemID: id, type: .primary, tag: "abc", width: 200, height: 300)
        XCTAssertEqual(key, repeated)
        XCTAssertEqual(key.sha256.count, 64)
        XCTAssertEqual(
            key.sha256,
            CertificateFingerprint.sha256Hex(
                Data("32:\(Sample.serverID)32:\(Sample.movie)7:Primary3:abc3:2003:300".utf8)))
        for changed in [
            ImageCacheKey(
                serverID: Sample.otherServerID, itemID: id, type: .primary, tag: "abc", width: 200, height: 300),
            ImageCacheKey(
                serverID: Sample.serverID, itemID: try XCTUnwrap(ItemID(Sample.other)), type: .primary, tag: "abc",
                width: 200, height: 300),
            ImageCacheKey(serverID: Sample.serverID, itemID: id, type: .thumb, tag: "abc", width: 200, height: 300),
            ImageCacheKey(serverID: Sample.serverID, itemID: id, type: .primary, tag: "other", width: 200, height: 300),
            ImageCacheKey(serverID: Sample.serverID, itemID: id, type: .primary, tag: "abc", width: 201, height: 300),
        ] { XCTAssertNotEqual(key, changed) }
        let disk = DiskImageCache(directory: root, byteLimit: CacheBudget.imageDiskBytes)
        let stored = await disk.store(imageKey: key, data: Data([1, 2, 3]))
        XCTAssertTrue(stored)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(key.sha256).path))
        let recovered = await DiskImageCache(directory: root, byteLimit: CacheBudget.imageDiskBytes).data(for: key)
        XCTAssertEqual(recovered, Data([1, 2, 3]))
    }

    /// T09-69: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    func testT09_69_oversizedImagesRejectedBeforeCachingOrDecode() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let disk = DiskImageCache(directory: root, byteLimit: CacheBudget.imageDiskBytes)
        let request = ItemImageRequest(
            serverID: Sample.serverID, itemID: try XCTUnwrap(ItemID(Sample.movie)), type: .primary, tag: nil,
            width: 100, height: 150)
        let tooLarge = Data(repeating: 0, count: MetadataPolicy.imageMaxBytes + 1)
        let loader = SearchImageLoader(client: ImageBytesClient(bytes: tooLarge), disk: disk)
        do {
            _ = try await loader.bytes(for: request)
            XCTFail("Expected oversized image rejection")
        } catch { XCTAssertEqual(error as? SearchImageError, .oversized) }
        let rejected = await disk.store(imageKey: request.cacheKey, data: tooLarge)
        XCTAssertFalse(rejected)
        let count = await disk.storedByteCount()
        XCTAssertEqual(count, 0)
        let boundary = Data(repeating: 0, count: MetadataPolicy.imageMaxBytes)
        let accepted = await disk.store(imageKey: request.cacheKey, data: boundary)
        XCTAssertTrue(accepted)
    }

    /// T09-59: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.

    func testT09_59_sessionClientCancelsAllRequestsAndNeverRetries401() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecentSearchStore(directory: root.appendingPathComponent("history"))
        let app = AppState(
            secureStore: CountingSecureStore(), settings: InMemorySettingsStore(),
            path: StaticConnectivityPath(online: true),
            pinger: StubPinger(), cacheRoot: root, automaticPing: false, recentSearches: store)
        try app.didSignIn(Sample.session(), token: Sample.token)
        let gate = SessionGateClient()
        let client = SessionAPIClient(inner: gate, app: app)
        let image = Task { try? await client.send(APIRequest(method: "GET", path: "/image")) }
        await waitUntil { gate.started == 1 }
        do {
            _ = try await client.send(APIRequest(method: "GET", path: "/unauthorized"))
            XCTFail("Expected 401")
        } catch { XCTAssertEqual(error, .unauthorized) }
        _ = await image.value
        XCTAssertTrue(gate.imageCancelled)
        XCTAssertEqual(gate.started, 2)
        XCTAssertEqual(app.requestGeneration, 1)
        XCTAssertEqual(app.sessionNoticeKey, .sessionExpired)
        do { _ = try await client.send(APIRequest(method: "GET", path: "/blocked")) } catch {}
        XCTAssertEqual(gate.started, 2)
    }

    #if canImport(ImageIO)
        /// T09-68: canonical scenario; see docs/M09-TEST-MAPPING.md for scope.
        func testT09_68_decodeDownsamplesOffMainThread() async throws {
            let bitmap = try XCTUnwrap(
                CGContext(
                    data: nil, width: 128, height: 96, bitsPerComponent: 8, bytesPerRow: 128 * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let original = try XCTUnwrap(bitmap.makeImage())
            let data = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, original, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            let decoded = try await SearchImageDecoder.downsample(data as Data, maximumPixelSize: 32)
            XCTAssertTrue(decoded.decodedOffMainThread)
            XCTAssertEqual(decoded.image.width, 32)
            XCTAssertEqual(decoded.image.height, 24)
            do {
                _ = try await SearchImageDecoder.downsample(
                    Data(repeating: 0, count: MetadataPolicy.imageMaxBytes + 1), maximumPixelSize: 1)
                XCTFail("Expected image byte cap before ImageIO")
            } catch { XCTAssertEqual(error as? SearchImageError, .oversized) }
        }
    #endif

    private func checkCleanup(removeServer: Bool, unauthorized: Bool) throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecentSearchStore(directory: root.appendingPathComponent("history"))
        let app = AppState(
            secureStore: CountingSecureStore(), settings: InMemorySettingsStore(),
            path: StaticConnectivityPath(online: true),
            pinger: StubPinger(), cacheRoot: root, automaticPing: false, recentSearches: store)
        try app.didSignIn(Sample.session(), token: Sample.token)
        try store.record("current", serverID: Sample.serverID, userID: Sample.userID)
        try store.record("other user", serverID: Sample.serverID, userID: Sample.otherUserID)
        try store.record("other server", serverID: Sample.otherServerID, userID: Sample.userID)
        if removeServer {
            app.removeServer(id: Sample.serverID)
        } else if unauthorized {
            app.handle(.unauthorized)
        } else {
            app.signOutLocally(notice: nil)
        }
        let restored = RecentSearchStore(directory: root.appendingPathComponent("history"))
        XCTAssertEqual(try restored.queries(serverID: Sample.serverID, userID: Sample.userID), [])
        XCTAssertEqual(
            try restored.queries(serverID: Sample.serverID, userID: Sample.otherUserID),
            removeServer ? [] : ["other user"])
        XCTAssertEqual(try restored.queries(serverID: Sample.otherServerID, userID: Sample.userID), ["other server"])
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
}

private struct ImageBytesClient: JellyfinAPIClient {
    let bytes: Data
    func send(_ request: APIRequest) async throws(APIError) -> Data { bytes }
}

private final class SessionGateClient: JellyfinAPIClient, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var cancelled = false
    var started: Int { lock.withLock { calls } }
    var imageCancelled: Bool { lock.withLock { cancelled } }

    func send(_ request: APIRequest) async throws(APIError) -> Data {
        lock.withLock { calls += 1 }
        if request.path == "/unauthorized" { throw .unauthorized }
        do { try await Task.sleep(for: .seconds(30)) } catch {
            lock.withLock { cancelled = true }
            throw .cancelled
        }
        return Data()
    }
}
