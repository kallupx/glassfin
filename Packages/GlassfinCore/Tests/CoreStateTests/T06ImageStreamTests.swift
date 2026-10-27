import CoreModels
import CoreState
import Foundation
import XCTest

@testable import CoreNetworking

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

final class T06ImageStreamTests: XCTestCase {
    // T06-76: URLSession receives 25 MB without Content-Length; cancel at the counted cap, no disk write.
    func testT06_76_missingContentLengthAbortsDuringDownload() async throws {
        try await assertOversizedStream(contentLength: nil)
    }

    // T06-77: a 1 MB header cannot authorize a 25 MB body; the body counter is authoritative.
    func testT06_77_lyingContentLengthAbortsDuringDownload() async throws {
        try await assertOversizedStream(contentLength: 1024 * 1024)
    }

    // T06-78: an advertised 30 MB image may be rejected before reading its body.
    func testT06_78_advertisedOversizeRejectsBeforeBody() async throws {
        try await assertOversizedStream(contentLength: 30 * 1024 * 1024, early: true)
    }

    // T06-76: the boundary itself is accepted, so the cap does not reject a valid 20 MB stream.
    func testT06_76_exactByteLimitIsAcceptedAndCached() async throws {
        let fixture = try Fixture(contentLength: nil, bodyBytes: MetadataPolicy.imageMaxBytes)
        defer { fixture.cleanup() }
        let bytes = try await fixture.loader.data(for: fixture.resource)
        XCTAssertEqual(bytes.count, MetadataPolicy.imageMaxBytes)
        let stored = await fixture.disk.data(for: fixture.resource.cacheKey)
        XCTAssertEqual(stored?.count, MetadataPolicy.imageMaxBytes)
    }

    // T06-51: an image 401 wins over an oversized header and is never disguised as a size error.
    func testT06_51_image401TakesPrecedenceOverSizeHeader() async throws {
        let fixture = try Fixture(contentLength: 30 * 1024 * 1024, status: 401)
        defer { fixture.cleanup() }
        do {
            _ = try await fixture.loader.data(for: fixture.resource)
            XCTFail("Expected unauthorized")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthorized)
        }
        let stored = await fixture.disk.data(for: fixture.resource.cacheKey)
        XCTAssertNil(stored)
    }

    // T06-82: cancelling a streamed image stops its transport and cannot write a partial cache entry.
    func testT06_82_cancelledStreamCannotCachePartialImage() async throws {
        let fixture = try Fixture(contentLength: nil)
        defer { fixture.cleanup() }
        let task = Task { try await fixture.loader.data(for: fixture.resource) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while fixture.probe.sentBytes == 0 && ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertGreaterThan(fixture.probe.sentBytes, 0)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? APIError, .cancelled)
        }
        let stored = await fixture.disk.data(for: fixture.resource.cacheKey)
        XCTAssertNil(stored)
    }

    private func assertOversizedStream(contentLength: Int?, early: Bool = false) async throws {
        let fixture = try Fixture(contentLength: contentLength)
        defer { fixture.cleanup() }
        do {
            _ = try await fixture.loader.data(for: fixture.resource)
            XCTFail("Expected oversized stream rejection")
        } catch {
            XCTAssertEqual(error as? ImageDataError, .oversized)
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !fixture.probe.stopped && ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertTrue(fixture.probe.stopped)
        if early {
            XCTAssertLessThanOrEqual(fixture.probe.sentBytes, StreamProbe.chunkBytes)
        } else {
            XCTAssertGreaterThan(fixture.probe.sentBytes, MetadataPolicy.imageMaxBytes)
            // URLSession can have an additional chunk in flight when cancellation is delivered.
            XCTAssertLessThanOrEqual(fixture.probe.sentBytes, MetadataPolicy.imageMaxBytes + 2 * StreamProbe.chunkBytes)
        }
        XCTAssertLessThan(fixture.probe.sentBytes, fixture.probe.bodyBytes)
        let stored = await fixture.disk.data(for: fixture.resource.cacheKey)
        XCTAssertNil(stored)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent(fixture.resource.cacheKey).path))
    }
}

private struct Fixture {
    let root: URL
    let disk: DiskImageCache
    let loader: HomeImageLoader
    let resource: ImageResource
    let probe: StreamProbe
    let session: URLSession

    init(contentLength: Int?, bodyBytes: Int = 25 * 1024 * 1024, status: Int = 200) throws {
        let tag = UUID().uuidString
        probe = StreamProbe(contentLength: contentLength, bodyBytes: bodyBytes, status: status)
        ImageStreamProtocol.probes.insert(probe, key: tag)
        root = FileManager.default.temporaryDirectory.appendingPathComponent(tag)
        disk = DiskImageCache(directory: root, byteLimit: CacheBudget.imageDiskBytes)
        resource = ImageResource(
            serverID: "s", itemID: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", type: .primary, tag: tag, width: 250, height: 375
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageStreamProtocol.self]
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        let redirects = RedirectSessionDelegate()
        session = URLSession(configuration: configuration, delegate: redirects, delegateQueue: nil)
        let client = HTTPJellyfinClient(
            server: try XCTUnwrap(URL(string: "https://image.invalid")),
            identity: ClientIdentity(deviceName: "TV", deviceID: "d", version: "1", token: "mock-token"),
            session: session, redirectDelegate: redirects, log: SilentLog(),
            transport: URLSessionRequestTransport(session: session, redirects: redirects))
        loader = HomeImageLoader(client: client, disk: disk)
    }

    func cleanup() {
        session.invalidateAndCancel()
        ImageStreamProtocol.probes.remove(key: resource.tag)
        try? FileManager.default.removeItem(at: root)
    }
}

private final class StreamProbe: @unchecked Sendable {
    static let chunkBytes = 64 * 1024
    let contentLength: Int?
    let bodyBytes: Int
    let status: Int
    private let lock = NSLock()
    private var sent = 0
    private var cancelled = false
    var sentBytes: Int { lock.withLock { sent } }
    var stopped: Bool { lock.withLock { cancelled } }

    init(contentLength: Int?, bodyBytes: Int, status: Int) {
        self.contentLength = contentLength
        self.bodyBytes = bodyBytes
        self.status = status
    }

    func next() -> Data? {
        lock.withLock {
            guard !cancelled, sent < bodyBytes else { return nil }
            let count = min(Self.chunkBytes, bodyBytes - sent)
            sent += count
            return Data(count: count)
        }
    }

    func stop() { lock.withLock { cancelled = true } }
}

private final class ProbeRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: StreamProbe] = [:]
    func insert(_ probe: StreamProbe, key: String) { lock.withLock { values[key] = probe } }
    func remove(key: String) { _ = lock.withLock { values.removeValue(forKey: key) } }
    func value(key: String) -> StreamProbe? { lock.withLock { values[key] } }
}

/// Sends incremental chunks through the real URLSessionDataDelegate used in production.
private final class ImageStreamProtocol: URLProtocol {
    static let probes = ProbeRegistry()
    private let queue = DispatchQueue(label: "glassfin.test.image-stream")
    private var probe: StreamProbe? {
        let tag =
            request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == "tag" }?.value ?? ""
        return Self.probes.value(key: tag)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let probe, let url = request.url,
            let response = HTTPURLResponse(
                url: url, statusCode: probe.status, httpVersion: "HTTP/1.1",
                headerFields: probe.contentLength.map { ["Content-Length": String($0)] })
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        schedule(probe)
    }

    override func stopLoading() { probe?.stop() }

    private func schedule(_ probe: StreamProbe) {
        let delivery = StreamDelivery(source: self)
        queue.asyncAfter(deadline: .now() + .milliseconds(2)) { delivery.source.pump(probe) }
    }

    private struct StreamDelivery: @unchecked Sendable {
        // URLProtocol is confined to this serial delivery queue; cancellation only touches locked probes.
        let source: ImageStreamProtocol
    }

    private func pump(_ probe: StreamProbe) {
        guard !probe.stopped else { return }
        guard let chunk = probe.next() else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        client?.urlProtocol(self, didLoad: chunk)
        schedule(probe)
    }
}
