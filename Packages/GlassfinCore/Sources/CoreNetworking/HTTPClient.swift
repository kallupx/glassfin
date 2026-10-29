import CoreModels
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public struct APIRequest: Sendable, Equatable {
    public var method: String
    public var path: String
    public var query: [URLQueryItem]
    public var body: Data?
    public var maximumResponseBytes: Int?

    public init(
        method: String, path: String, query: [URLQueryItem] = [], body: Data? = nil,
        maximumResponseBytes: Int? = nil
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.maximumResponseBytes = maximumResponseBytes
    }
}

public protocol JellyfinAPIClient: Sendable {
    func send(_ request: APIRequest) async throws(APIError) -> Data
}

extension JellyfinAPIClient {
    public func send<T: Decodable & Sendable>(_ request: APIRequest, as type: T.Type) async throws(APIError) -> T {
        let data = try await send(request)
        return try ResponseDecoder.decode(type, from: data)
    }
}

public struct ClientIdentity: Sendable, Equatable {
    public var clientName: String
    public var deviceName: String
    public var deviceID: String
    public var version: String
    public var token: String?

    public init(
        clientName: String = "Glassfin", deviceName: String, deviceID: String, version: String, token: String? = nil
    ) {
        self.clientName = clientName
        self.deviceName = deviceName
        self.deviceID = deviceID
        self.version = version
        self.token = token
    }

    public func authorizationHeader() throws -> String {
        do {
            return try AuthorizationHeader.value(
                client: clientName,
                device: deviceName,
                deviceID: deviceID,
                version: version,
                token: token
            )
        } catch {
            throw APIError.headerRejected
        }
    }
}

protocol RequestTransport: Sendable {
    func data(for request: URLRequest, maximumBytes: Int?) async throws -> (Data, URLResponse, Int?)
}

struct URLSessionRequestTransport: RequestTransport {
    var session: URLSession
    var redirects: RedirectSessionDelegate
    var certificatePin: OriginCertificatePin? = nil

    func data(for request: URLRequest, maximumBytes: Int?) async throws -> (Data, URLResponse, Int?) {
        if let maximumBytes {
            // Each bounded transfer owns a session; task identifiers are local to that session.
            let owner = RedirectSessionDelegate()
            let proxy = RedirectTaskProxy(owner: owner, certificatePin: certificatePin)
            let result = try await BoundedRequestDownload(maximumBytes: maximumBytes, redirects: proxy)
                .data(for: request, configuration: session.configuration)
            if let identifier = result.2, let reason = owner.consumeRejection(for: identifier) {
                throw APIError.redirectRejected(reason)
            }
            return result
        }
        let proxy = RedirectTaskProxy(owner: redirects, certificatePin: certificatePin)
        let (data, response) = try await session.data(for: request, delegate: proxy)
        return (data, response, proxy.capturedTaskIdentifier())
    }
}

public struct HTTPJellyfinClient: JellyfinAPIClient {
    public var server: URL
    public var identity: ClientIdentity
    public var session: URLSession
    public var certificatePin: OriginCertificatePin? {
        (transport as? URLSessionRequestTransport)?.certificatePin
    }
    public var redirectDelegate: RedirectSessionDelegate
    public var log: any GlassfinLog
    var transport: any RequestTransport

    public init(
        server: URL, identity: ClientIdentity, log: any GlassfinLog = SilentLog(),
        certificatePin: OriginCertificatePin? = nil
    ) {
        let delegate = RedirectSessionDelegate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        self.init(
            server: server,
            identity: identity,
            session: session,
            redirectDelegate: delegate,
            log: log,
            transport: URLSessionRequestTransport(session: session, redirects: delegate, certificatePin: certificatePin)
        )
    }

    init(
        server: URL,
        identity: ClientIdentity,
        transport: any RequestTransport,
        log: any GlassfinLog = SilentLog()
    ) {
        let delegate = RedirectSessionDelegate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        self.init(
            server: server,
            identity: identity,
            session: URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil),
            redirectDelegate: delegate,
            log: log,
            transport: transport
        )
    }

    init(
        server: URL,
        identity: ClientIdentity,
        session: URLSession,
        redirectDelegate: RedirectSessionDelegate,
        log: any GlassfinLog,
        transport: any RequestTransport
    ) {
        self.server = server
        self.identity = identity
        self.session = session
        self.redirectDelegate = redirectDelegate
        self.log = log
        self.transport = transport
    }

    public func send(_ request: APIRequest) async throws(APIError) -> Data {
        if Task.isCancelled { throw APIError.cancelled }
        // S4.3. Public cleartext is refused before a request is built or handed to the transport.
        if ServerTransportPolicy.evaluate(server) == .publicHTTPRejected {
            throw APIError.invalidURL
        }
        let urlRequest: URLRequest
        do {
            urlRequest = try makeURLRequest(request)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.invalidURL
        }
        do {
            let (data, response, taskIdentifier) = try await transport.data(
                for: urlRequest, maximumBytes: request.maximumResponseBytes)
            guard let http = response as? HTTPURLResponse else { throw APIError.network }
            if let failure = HTTPStatusMapper.apiFailure(for: http.statusCode) {
                if case .redirectRejected = failure {
                    let reason =
                        taskIdentifier.flatMap { redirectDelegate.consumeRejection(for: $0) }
                        ?? redirectDelegate.consumeRejection()
                    if let reason {
                        throw APIError.redirectRejected(reason)
                    }
                }
                throw failure
            }
            if let limit = request.maximumResponseBytes, data.count > limit { throw APIError.decoding }
            return data
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            throw URLErrorMapper.map(error)
        } catch is CancellationError {
            throw APIError.cancelled
        } catch {
            if Task.isCancelled { throw APIError.cancelled }
            log.error("Request failed.")
            throw APIError.network
        }
    }

    func makeURLRequest(_ request: APIRequest) throws -> URLRequest {
        let url = try Self.url(server: server, path: request.path, query: request.query)
        let hasTokenQuery = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .contains { $0.name.lowercased() == "token" }
        if RedirectPolicy.containsCredentialQuery(url) || hasTokenQuery {
            throw APIError.invalidURL
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        if request.body != nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let header: String
        do {
            header = try SafeAuthorizationHeader.value(
                client: identity.clientName,
                device: identity.deviceName,
                deviceID: identity.deviceID,
                version: identity.version,
                token: identity.token
            )
        } catch is SecurityInvariantError {
            throw APIError.headerRejected
        } catch is AuthorizationHeaderError {
            throw APIError.headerRejected
        }
        AuthorizationHeaderWriter.replace(header, on: &urlRequest)
        return urlRequest
    }

    static func url(server: URL, path: String, query: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: server, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        let base = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        let relative = path.hasPrefix("/") ? path : "/" + path
        components.path = base + relative
        if !query.isEmpty {
            var items = components.queryItems ?? []
            items.append(contentsOf: query)
            components.queryItems = items
            // Query parsers treat a literal plus as a space; keep search/image tag text literal.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = components.url else { throw APIError.invalidURL }
        return url
    }
}

/// Per-request delegate so a redirect rejection stays tied to that task.
final class RedirectTaskProxy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let owner: RedirectSessionDelegate
    private let lock = NSLock()
    private var identifier: Int?

    private let trust: TrustCapture

    init(owner: RedirectSessionDelegate, certificatePin: OriginCertificatePin?) {
        self.owner = owner
        self.trust = TrustCapture(certificatePin: certificatePin)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        await trust.urlSession(session, task: task, didReceive: challenge)
    }

    func capturedTaskIdentifier() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return identifier
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        lock.lock()
        identifier = task.taskIdentifier
        lock.unlock()
        owner.urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: request,
            completionHandler: completionHandler
        )
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.lock()
        identifier = task.taskIdentifier
        lock.unlock()
        owner.urlSession(session, task: task, didCompleteWithError: error)
    }
}
