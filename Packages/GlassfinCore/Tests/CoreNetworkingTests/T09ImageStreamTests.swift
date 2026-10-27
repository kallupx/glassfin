import CoreModels
import Foundation
import XCTest

@testable import CoreNetworking

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

final class T09ImageStreamTests: XCTestCase, @unchecked Sendable {
    /// T09-69: missing and lying Content-Length cannot bypass the counted streaming cap.
    func testT09_69_oversizedStreamsAreCancelledWithoutReadingTheTail() async throws {
        for declaredLength: Int? in [nil, 1] {
            let scenario = ImageStreamScenario(length: MetadataPolicy.imageMaxBytes * 2, declaredLength: declaredLength)
            let (client, request) = try fixture(scenario)
            do {
                _ = try await client.send(request)
                XCTFail("Expected the streaming byte limit")
            } catch { XCTAssertEqual(error, .responseTooLarge) }
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while !scenario.stopped && ContinuousClock.now < deadline { await Task.yield() }
            XCTAssertTrue(scenario.stopped)
            XCTAssertEqual(scenario.sent, MetadataPolicy.imageMaxBytes + 64 * 1024)
            XCTAssertLessThan(scenario.sent, scenario.length, "The body must be cancelled before reading the tail")
        }
    }

    /// T09-65: exactly the image budget is allowed, regardless of a missing length header.
    func testT09_65_exactStreamBoundaryIsAccepted() async throws {
        let scenario = ImageStreamScenario(length: MetadataPolicy.imageMaxBytes, declaredLength: nil)
        let (client, request) = try fixture(scenario)
        let data = try await client.send(request)
        XCTAssertEqual(data.count, MetadataPolicy.imageMaxBytes)
        XCTAssertEqual(request.maximumResponseBytes, MetadataPolicy.imageMaxBytes)
        XCTAssertEqual(scenario.sent, scenario.length)
        XCTAssertFalse(scenario.stopped)
    }

    /// T09-59: a 401 takes precedence over an oversized image error body.
    func testT09_59_streamingImage401IsNotHiddenByItsBody() async throws {
        let scenario = ImageStreamScenario(length: MetadataPolicy.imageMaxBytes * 2, declaredLength: nil, status: 401)
        let (client, request) = try fixture(scenario)
        do {
            _ = try await client.send(request)
            XCTFail("Expected session expiry")
        } catch { XCTAssertEqual(error, .unauthorized) }
        XCTAssertLessThan(scenario.sent, scenario.length)
    }

    /// T09-18: cancellation propagates into the delegate's active transfer.
    func testT09_18_cancelledImageStreamStopsTheTransfer() async throws {
        let scenario = ImageStreamScenario(length: MetadataPolicy.imageMaxBytes * 2, declaredLength: nil)
        let (client, request) = try fixture(scenario)
        let work = Task { try await client.send(request) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while scenario.sent == 0 && ContinuousClock.now < deadline { await Task.yield() }
        work.cancel()
        do {
            _ = try await work.value
            XCTFail("Expected cancellation")
        } catch { XCTAssertEqual(error as? APIError, .cancelled) }
        while !scenario.stopped && ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertTrue(scenario.stopped)
        XCTAssertLessThan(scenario.sent, MetadataPolicy.imageMaxBytes)
    }

    private func fixture(_ scenario: ImageStreamScenario) throws -> (HTTPJellyfinClient, APIRequest) {
        let server = try XCTUnwrap(URL(string: "https://image.example/" + UUID().uuidString))
        ImageStreamProtocol.scenarios.insert(scenario, for: server.path)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ImageStreamProtocol.self]
        let redirects = RedirectSessionDelegate()
        let session = URLSession(configuration: configuration)
        let client = HTTPJellyfinClient(
            server: server, identity: ClientIdentity(deviceName: "TV", deviceID: "test", version: "1", token: "test"),
            session: session, redirectDelegate: redirects, log: SilentLog(),
            transport: URLSessionRequestTransport(session: session, redirects: redirects))
        let image = ItemImageRequest(
            serverID: "server", itemID: try XCTUnwrap(ItemID("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")),
            type: .primary, tag: nil, width: 300, height: 450)
        return (client, image.request)
    }
}

private final class ImageStreamScenario: @unchecked Sendable {
    let length: Int
    let declaredLength: Int?
    let status: Int
    private let lock = NSLock()
    private var count = 0
    private var cancelled = false
    var sent: Int { lock.withLock { count } }
    var stopped: Bool { lock.withLock { cancelled } }

    init(length: Int, declaredLength: Int?, status: Int = 200) {
        self.length = length
        self.declaredLength = declaredLength
        self.status = status
    }

    func stop() { lock.withLock { cancelled = true } }
    func nextChunk() -> Data? {
        lock.withLock {
            guard !cancelled, count < length else { return nil }
            let size = min(64 * 1024, length - count)
            count += size
            return Data(repeating: 1, count: size)
        }
    }
}

private final class ImageStreamScenarios: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: ImageStreamScenario] = [:]
    func insert(_ value: ImageStreamScenario, for path: String) { lock.withLock { values[path] = value } }
    func take(for path: String) -> ImageStreamScenario? {
        lock.withLock { values.removeValue(forKey: "/" + path.split(separator: "/")[0]) }
    }
}

private final class ImageStreamProtocol: URLProtocol {
    static let scenarios = ImageStreamScenarios()
    private var scenario: ImageStreamScenario?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let scenario = Self.scenarios.take(for: url.path),
            let response = HTTPURLResponse(
                url: url, statusCode: scenario.status, httpVersion: "HTTP/1.1",
                headerFields: scenario.declaredLength.map { ["Content-Length": String($0)] })
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        self.scenario = scenario
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        emit(scenario)
    }

    private func emit(_ scenario: ImageStreamScenario) {
        let emitter = ImageStreamEmitter(source: self)
        // Delay the tail after the first excess chunk so queued producer bytes cannot hide a late abort.
        let delay: DispatchTimeInterval =
            scenario.sent > MetadataPolicy.imageMaxBytes ? .milliseconds(100) : .milliseconds(1)
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            let source = emitter.source
            guard !scenario.stopped else { return }
            if let data = scenario.nextChunk() {
                source.client?.urlProtocol(source, didLoad: data)
                source.emit(scenario)
            } else {
                source.client?.urlProtocolDidFinishLoading(source)
            }
        }
    }

    override func stopLoading() { scenario?.stop() }
}

/// URLProtocol is confined to the protocol callbacks; the scheduled emitter only forwards chunks.
private struct ImageStreamEmitter: @unchecked Sendable {
    let source: ImageStreamProtocol
}
