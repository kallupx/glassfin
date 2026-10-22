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

    public init(method: String, path: String, query: [URLQueryItem] = [], body: Data? = nil) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
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

public struct HTTPJellyfinClient: JellyfinAPIClient {
    public var server: URL
    public var identity: ClientIdentity
    public var session: URLSession
    public var redirectDelegate: RedirectSessionDelegate
    public var log: any GlassfinLog

    public init(server: URL, identity: ClientIdentity, log: any GlassfinLog = SilentLog()) {
        let delegate = RedirectSessionDelegate()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpShouldSetCookies = false
        self.server = server
        self.identity = identity
        self.redirectDelegate = delegate
        self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        self.log = log
    }

    public func send(_ request: APIRequest) async throws(APIError) -> Data {
        if Task.isCancelled { throw APIError.cancelled }
        let urlRequest: URLRequest
        do {
            urlRequest = try makeURLRequest(request)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.invalidURL
        }
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw APIError.network }
            if let failure = HTTPStatusMapper.failure(for: http.statusCode) {
                if case .redirectRejected = failure, let reason = redirectDelegate.consumeRejection() {
                    throw APIError.redirectRejected(reason)
                }
                throw failure
            }
            return data
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            throw URLErrorMapper.map(error)
        } catch is CancellationError {
            throw APIError.cancelled
        } catch {
            if Task.isCancelled { throw APIError.cancelled }
            log.error("Request failed for \(SensitiveRedactor.redact(urlRequest.url?.absoluteString ?? request.path))")
            throw APIError.network
        }
    }

    func makeURLRequest(_ request: APIRequest) throws -> URLRequest {
        let url = try Self.url(server: server, path: request.path, query: request.query)
        if RedirectPolicy.containsCredentialQuery(url) {
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
        }
        guard let url = components.url else { throw APIError.invalidURL }
        return url
    }
}
