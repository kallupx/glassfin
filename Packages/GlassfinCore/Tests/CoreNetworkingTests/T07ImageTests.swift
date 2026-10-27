import CoreModels
import Foundation
import XCTest

@testable import CoreNetworking

#if canImport(ImageIO)
    import ImageIO
#endif

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

final class T07ImageTests: XCTestCase {
    /// T07-80: the exact options used by the decoder are testable on every platform.
    func testT07_80_thumbnailOptionsUseDisplayedPixelsAndImmediateTransformedThumbnailOnly() {
        for pixels in [250, 375, 2160, 3840] {
            let options = LibraryThumbnailOptions.make(maxPixelSize: pixels)
            XCTAssertEqual(options.count, 4)
            XCTAssertEqual(options["kCGImageSourceThumbnailMaxPixelSize"] as? Int, pixels)
            XCTAssertEqual(options["kCGImageSourceCreateThumbnailFromImageAlways"] as? Bool, true)
            XCTAssertEqual(options["kCGImageSourceCreateThumbnailWithTransform"] as? Bool, true)
            XCTAssertEqual(options["kCGImageSourceShouldCacheImmediately"] as? Bool, true)
            #if canImport(ImageIO)
                // Verify the portable keys match the SDK constants consumed by ImageIO.
                XCTAssertEqual(options[kCGImageSourceThumbnailMaxPixelSize as String] as? Int, pixels)
                XCTAssertEqual(options[kCGImageSourceCreateThumbnailFromImageAlways as String] as? Bool, true)
                XCTAssertEqual(options[kCGImageSourceCreateThumbnailWithTransform as String] as? Bool, true)
                XCTAssertEqual(options[kCGImageSourceShouldCacheImmediately as String] as? Bool, true)
            #endif
        }
        XCTAssertEqual(LibraryThumbnailOptions.make(maxPixelSize: 0)["kCGImageSourceThumbnailMaxPixelSize"] as? Int, 1)
    }

    /// T07-81: no length header; count actual delegate chunks and cancel before EOF.
    func testT07_81_missingContentLengthStreamIsCancelledAtTheCap() async throws {
        try await assertStreamIsCancelled(path: "missing")
    }

    /// T07-81: a false 1 MB header must not bypass the 20 MB byte count.
    func testT07_81_lyingContentLengthStreamIsCancelledAtTheCap() async throws {
        try await assertStreamIsCancelled(path: "lying")
    }

    private func assertStreamIsCancelled(path: String) async throws {
        let url = try XCTUnwrap(URL(string: "https://image.test/\(path)"))
        let probe = ImageStreamProtocol.probes.register(url)
        defer { ImageStreamProtocol.probes.remove(url) }
        let download = BoundedResponseDownload(
            limit: MetadataPolicy.imageMaxBytes, redirects: RedirectSessionDelegate(), certificatePin: nil)
        do {
            _ = try await download.run(URLRequest(url: url), protocolClasses: [ImageStreamProtocol.self])
            XCTFail("Oversize stream reached EOF instead of being aborted")
        } catch {
            XCTAssertEqual(error as? APIError, .decoding)
        }
        await fulfillment(of: [probe.cancelled], timeout: 5)
        let count = probe.bytesSent
        XCTAssertGreaterThan(count, MetadataPolicy.imageMaxBytes)
        // Allow a few queued URLSession callbacks, but require cancellation at the cap,
        // well before the fixture's extra 8 MB can be transmitted.
        XCTAssertLessThanOrEqual(count, MetadataPolicy.imageMaxBytes + 4 * ImageStreamProtocol.chunkSize)
        XCTAssertFalse(probe.finished)
    }

    /// T07-78: canonical spec/TESTPLAN-M07.md.
    func testT07_78_imageURLHasNoCredentialQueryAndRequestUsesAuthorization() throws {
        let descriptor = LibraryImageRequest(
            serverID: "server", itemID: try XCTUnwrap(ItemID("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")),
            type: .primary, tag: "image tag", width: 250, height: 375)
        let client = HTTPJellyfinClient(
            server: try XCTUnwrap(URL(string: "https://media.example/jellyfin")),
            identity: ClientIdentity(deviceName: "TV", deviceID: "device", version: "1", token: "secret"))
        let request = try client.makeURLRequest(descriptor.apiRequest)
        let url = try XCTUnwrap(request.url)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertFalse(query.contains { ["apikey", "api" + "_key", "token"].contains($0.name.lowercased()) })
        XCTAssertFalse(url.absoluteString.contains("secret"))
        XCTAssertTrue(try XCTUnwrap(request.value(forHTTPHeaderField: "Authorization")).contains("Token=\"secret\""))
        XCTAssertEqual(descriptor.apiRequest.maximumResponseBytes, MetadataPolicy.imageMaxBytes)
        XCTAssertEqual(url.path, "/jellyfin/Items/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/Images/Primary")
    }

    /// T07-78: canonical spec/TESTPLAN-M07.md.
    func testT07_78_imageRequestsRejectCredentialParametersIncludingBaseURLAndRedirects() throws {
        for name in ["ApiKey", "api" + "_key", "token", "TOKEN"] {
            let url = try XCTUnwrap(URL(string: "https://media.example?\(name)=secret"))
            let client = HTTPJellyfinClient(
                server: url, identity: ClientIdentity(deviceName: "TV", deviceID: "d", version: "1"))
            XCTAssertThrowsError(
                try client.makeURLRequest(
                    APIRequest(method: "GET", path: "/image", maximumResponseBytes: MetadataPolicy.imageMaxBytes)))
            XCTAssertTrue(BoundedResponseDownload.hasCredentialQuery(url))
        }
    }

    /// T07-78: canonical spec/TESTPLAN-M07.md.
    func testT07_78_cacheKeyIsStableSHA256OfTheWholeTuple() throws {
        let item = try XCTUnwrap(ItemID("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
        let request = LibraryImageRequest(
            serverID: "s", itemID: item, type: .primary, tag: "t", width: 250, height: 375)
        let framed = "1:s32:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa7:Primary1:t3:2503:375"
        XCTAssertEqual(request.cacheKey, CertificateFingerprint.sha256Hex(Data(framed.utf8)))
        XCTAssertEqual(request.cacheKey.count, 64)
        XCTAssertEqual(request.cacheKey, request.cacheKey)
        for other in [
            LibraryImageRequest(serverID: "other", itemID: item, type: .primary, tag: "t", width: 250, height: 375),
            LibraryImageRequest(serverID: "s", itemID: item, type: .logo, tag: "t", width: 250, height: 375),
            LibraryImageRequest(serverID: "s", itemID: item, type: .primary, tag: "new", width: 250, height: 375),
            LibraryImageRequest(serverID: "s", itemID: item, type: .primary, tag: "t", width: 500, height: 750),
        ] { XCTAssertNotEqual(other.cacheKey, request.cacheKey) }
    }

    /// T07-78: canonical spec/TESTPLAN-M07.md.
    func testT07_78_HTTPClientRejectsOversizeImage() async throws {
        let url = try XCTUnwrap(URL(string: "https://media.example"))
        let client = HTTPJellyfinClient(
            server: url, identity: ClientIdentity(deviceName: "TV", deviceID: "d", version: "1"),
            transport: OversizeImageTransport(url: url))
        do {
            _ = try await client.send(
                APIRequest(method: "GET", path: "/image", maximumResponseBytes: MetadataPolicy.imageMaxBytes))
            XCTFail("Oversize image accepted")
        } catch { XCTAssertEqual(error, .decoding) }
    }
}

/// A paced URLProtocol exercises the real URLSession delegate without a live server.
/// The body deliberately contradicts its header and never completes before cancellation.
private final class ImageStreamProtocol: URLProtocol {
    static let chunkSize = 64 * 1024
    static let probes = ImageStreamProbes()
    private var probe: ImageStreamProbe?

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "image.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let probe = Self.probes.probe(url) else { return }
        self.probe = probe
        let headers = url.lastPathComponent == "lying" ? ["Content-Length": "1048576"] : [:]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        emitChunk()
    }

    private func emitChunk() {
        let handle = ImageStreamHandle(value: self)
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(2)) {
            let stream = handle.value
            guard let probe = stream.probe, probe.send(bytes: Self.chunkSize) else { return }
            stream.client?.urlProtocol(stream, didLoad: Data(repeating: 0, count: Self.chunkSize))
            if probe.bytesSent < MetadataPolicy.imageMaxBytes + 8 * 1024 * 1024 {
                stream.emitChunk()
            } else {
                probe.complete()
                stream.client?.urlProtocolDidFinishLoading(stream)
            }
        }
    }

    override func stopLoading() { probe?.stop() }
}

/// A single paced producer owns callbacks; cancellation and counters use the locked probe.
private struct ImageStreamHandle: @unchecked Sendable {
    let value: ImageStreamProtocol
}

private final class ImageStreamProbe: @unchecked Sendable {
    let cancelled = XCTestExpectation(description: "URLSession cancels the oversized stream")
    private let lock = NSLock()
    private var stopped = false
    private var sent = 0
    private var reachedEOF = false
    var bytesSent: Int { lock.withLock { sent } }
    var finished: Bool { lock.withLock { reachedEOF } }

    func send(bytes: Int) -> Bool {
        lock.withLock {
            guard !stopped else { return false }
            sent += bytes
            return true
        }
    }

    func complete() { lock.withLock { reachedEOF = true } }
    func stop() {
        let first = lock.withLock {
            let first = !stopped
            stopped = true
            return first
        }
        if first { cancelled.fulfill() }
    }
}

private final class ImageStreamProbes: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [URL: ImageStreamProbe] = [:]
    func register(_ url: URL) -> ImageStreamProbe {
        lock.withLock {
            let probe = ImageStreamProbe()
            values[url] = probe
            return probe
        }
    }
    func probe(_ url: URL) -> ImageStreamProbe? { lock.withLock { values[url] } }
    func remove(_ url: URL) { _ = lock.withLock { values.removeValue(forKey: url) } }
}

private struct OversizeImageTransport: RequestTransport {
    let url: URL
    func data(for request: URLRequest) async throws -> (Data, URLResponse, Int?) {
        (
            Data(repeating: 0, count: MetadataPolicy.imageMaxBytes + 1),
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil
        )
    }
}
