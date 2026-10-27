import CoreModels
import CoreNetworking
import CoreState
import Foundation
import XCTest

final class T06ImageStoreTests: XCTestCase {
    // T06-72: canonical spec/TESTPLAN-M06.md.
    func testT06_72_diskFilenameIsTheStableSHA256AndBytesRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let resource = JellyfinImageResource(
            serverID: "s", itemID: Sample.movie, type: .primary, tag: "tag", width: 250, height: 375)
        let cache = DiskImageCache(directory: root, byteLimit: CacheBudget.imageDiskBytes)
        let client = ScriptedClient(results: [.success(Data([1, 2, 3]))])
        let loader = HomeImageLoader(client: client, disk: cache)
        let first = try await loader.data(for: resource)
        let cached = try await loader.data(for: resource)
        XCTAssertEqual(first, cached)
        XCTAssertEqual(client.requests().count, 1)
        let filenames = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertEqual(Set(filenames), Set([resource.cacheKey, "index.json"]))
        XCTAssertTrue(resource.cacheKey.allSatisfy(\.isHexDigit))
    }

    // T06-82: canonical spec/TESTPLAN-M06.md.
    func testT06_82_loaderAndDiskRejectOversizedImageWithoutCaching() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let resource = JellyfinImageResource(
            serverID: "s", itemID: Sample.movie, type: .primary, tag: "tag", width: 1, height: 1)
        let cache = DiskImageCache(directory: root, byteLimit: CacheBudget.imageDiskBytes)
        let huge = Data(count: MetadataPolicy.imageMaxBytes + 1)
        let loader = HomeImageLoader(client: ScriptedClient(results: [.success(huge)]), disk: cache)
        do {
            _ = try await loader.data(for: resource)
            XCTFail("Expected oversized image rejection")
        } catch {
            XCTAssertEqual(error as? ImageDataError, .oversized)
        }
        let stored = await cache.data(for: resource.cacheKey)
        XCTAssertNil(stored)
        let accepted = await cache.store(key: resource.cacheKey, data: huge)
        XCTAssertFalse(accepted)
    }
}
