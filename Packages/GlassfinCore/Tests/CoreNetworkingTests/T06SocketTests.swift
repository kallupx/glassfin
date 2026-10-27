import CoreModels
import CoreNetworking
import Foundation
import XCTest

final class T06SocketTests: XCTestCase {
    func testT06_16_socket401StopsWithoutReconnect() async throws {
        let sockets = UnauthorizedSocketFactory()
        let request = try SocketRequestBuilder.make(
            server: try XCTUnwrap(URL(string: "https://media.example")),
            identity: ClientIdentity(deviceName: "TV", deviceID: "d", version: "1", token: "secret"))
        let stream = ReconnectingServerEventStream(
            request: request, sockets: sockets, clock: SystemGlassfinClock(), jitter: ConstantJitter(unit: 0))
        defer { stream.stop() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while stream.phase != .stopped && ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertEqual(stream.phase, .stopped)
        XCTAssertEqual(sockets.calls(), 1)
    }
}

private final class UnauthorizedSocketFactory: RealtimeSocketFactory, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func makeSocket(url: URL) -> any RealtimeSocket {
        lock.lock()
        count += 1
        lock.unlock()
        return UnauthorizedSocket()
    }
    func calls() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private struct UnauthorizedSocket: RealtimeSocket {
    func connect() async throws { throw APIError.unauthorized }
    func receive() async throws -> Data { throw APIError.unauthorized }
    func send(_ data: Data) async throws {}
    func close() async {}
}
