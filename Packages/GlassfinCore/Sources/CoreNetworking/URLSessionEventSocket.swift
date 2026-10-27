import CoreModels
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Header-authenticated sockets use the same certificate decision as HTTP requests.
public struct URLSessionEventSocketFactory: RealtimeSocketFactory {
    private let request: URLRequest
    private let pin: OriginCertificatePin?
    private let server: URL
    private let onUnauthorized: @Sendable () async -> Void

    public init(
        server: URL, identity: ClientIdentity, pin: OriginCertificatePin?,
        onUnauthorized: @escaping @Sendable () async -> Void
    ) throws {
        guard ServerTransportPolicy.evaluate(server) != .publicHTTPRejected else { throw APIError.invalidURL }
        self.request = try SocketRequestBuilder.make(server: server, identity: identity)
        self.pin = pin
        self.server = server
        self.onUnauthorized = onUnauthorized
    }

    public func makeSocket(url: URL) -> any RealtimeSocket {
        HeaderEventSocket(request: request, server: server, pin: pin, onUnauthorized: onUnauthorized)
    }
}

private final class HeaderEventSocket: RealtimeSocket, @unchecked Sendable {
    private let session: URLSession
    private let socket: URLSessionWebSocketTask
    private let onUnauthorized: @Sendable () async -> Void

    init(
        request: URLRequest, server: URL, pin: OriginCertificatePin?,
        onUnauthorized: @escaping @Sendable () async -> Void
    ) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(
            configuration: configuration, delegate: TrustCapture(certificatePin: pin, connectionURL: server),
            delegateQueue: nil)
        self.session = session
        self.socket = session.webSocketTask(with: request)
        self.onUnauthorized = onUnauthorized
    }

    deinit {
        socket.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }

    func connect() async throws {
        try Task.checkCancellation()
        socket.resume()
    }

    func receive() async throws -> Data {
        do {
            let message = try await withTaskCancellationHandler {
                try await socket.receive()
            } onCancel: {
                socket.cancel(with: .goingAway, reason: nil)
                session.invalidateAndCancel()
            }
            switch message {
            case .data(let data): return data
            case .string(let text): return Data(text.utf8)
            @unknown default: throw APIError.decoding
            }
        } catch {
            if (socket.response as? HTTPURLResponse)?.statusCode == 401 {
                await onUnauthorized()
                throw APIError.unauthorized
            }
            throw error
        }
    }

    func send(_ data: Data) async throws { try await socket.send(.data(data)) }

    func close() async {
        socket.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }
}
