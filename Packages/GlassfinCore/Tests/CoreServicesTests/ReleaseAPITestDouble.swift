// Test-only replacement for the Debug app mock, allowing the service suite to run in Release.
import CoreModels
import CoreNetworking
import Foundation

#if !DEBUG
    public actor MockAPIClient: JellyfinAPIClient {
        public struct Call: Sendable, Equatable {
            public var method: String
            public var path: String
            public var query: [URLQueryItem]
            public var body: Data?

            public init(method: String, path: String, query: [URLQueryItem], body: Data?) {
                self.method = method
                self.path = path
                self.query = query
                self.body = body
            }
        }

        public private(set) var calls: [Call] = []
        private var handler: @Sendable (APIRequest) async throws(APIError) -> Data

        public init(handler: @escaping @Sendable (APIRequest) async throws(APIError) -> Data = { _ in Data() }) {
            self.handler = handler
        }

        public func setHandler(_ handler: @escaping @Sendable (APIRequest) async throws(APIError) -> Data) {
            self.handler = handler
        }

        public func send(_ request: APIRequest) async throws(APIError) -> Data {
            calls.append(Call(method: request.method, path: request.path, query: request.query, body: request.body))
            if Task.isCancelled { throw APIError.cancelled }
            return try await handler(request)
        }
    }
#endif
