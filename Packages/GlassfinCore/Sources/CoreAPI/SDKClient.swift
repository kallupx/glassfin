import CoreModels
import CoreNetworking
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

#if canImport(JellyfinAPI)
    import Get
    import JellyfinAPI

    /// Replaces jellyfin-sdk-swift 3.3.0's unquoted Authorization header with Glassfin's header.
    final class GlassfinHeaderDelegate: APIClientDelegate, @unchecked Sendable {
        var header: String?

        func client(_ client: APIClient, willSendRequest request: inout URLRequest) async throws {
            if let header {
                request.setValue(header, forHTTPHeaderField: "Authorization")
            }
        }
    }

    public struct SDKJellyfinAPIClient: JellyfinAPIClient {
        private let jellyfin: JellyfinClient
        private let headerDelegate: GlassfinHeaderDelegate
        public var identity: ClientIdentity

        public init(server: URL, identity: ClientIdentity) {
            self.identity = identity
            let headerDelegate = GlassfinHeaderDelegate()
            self.headerDelegate = headerDelegate
            let redirectDelegate = RedirectSessionDelegate()
            let configuration = JellyfinClient.Configuration(
                url: server,
                accessToken: identity.token,
                client: identity.clientName,
                deviceName: identity.deviceName,
                deviceID: identity.deviceID,
                version: identity.version
            )
            jellyfin = JellyfinClient(
                configuration: configuration,
                delegate: headerDelegate,
                sessionDelegate: redirectDelegate
            )
        }

        public func send(_ request: APIRequest) async throws(APIError) -> Data {
            do {
                headerDelegate.header = try identity.authorizationHeader()
            } catch let error as APIError {
                throw error
            } catch {
                throw APIError.headerRejected
            }
            let query = request.query.map { ($0.name, $0.value) }
            let method = HTTPMethod(rawValue: request.method)
            let sdkRequest = Request<Void>(path: request.path, method: method, query: query)
            do {
                let response = try await jellyfin.data(for: sdkRequest) { urlRequest in
                    if let body = request.body {
                        urlRequest.httpBody = body
                        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    }
                }
                if let status = response.statusCode, let failure = HTTPStatusMapper.failure(for: status) {
                    throw failure
                }
                return response.data
            } catch let error as APIError {
                throw error
            } catch let error as Get.APIError {
                if case .unacceptableStatusCode(let status) = error {
                    throw HTTPStatusMapper.failure(for: status) ?? APIError.server(status: status)
                }
                throw APIError.network
            } catch let error as URLError {
                throw URLErrorMapper.map(error)
            } catch is CancellationError {
                throw APIError.cancelled
            } catch {
                throw APIError.network
            }
        }
    }
#endif

public enum JellyfinClientFactory {
    public static func make(server: URL, identity: ClientIdentity) -> any JellyfinAPIClient {
        #if canImport(JellyfinAPI)
            SDKJellyfinAPIClient(server: server, identity: identity)
        #else
            HTTPJellyfinClient(server: server, identity: identity)
        #endif
    }
}
