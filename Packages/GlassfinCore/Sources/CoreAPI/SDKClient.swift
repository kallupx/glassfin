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
        private let server: URL
        private let headerDelegate: GlassfinHeaderDelegate
        private let certificatePin: OriginCertificatePin?
        public var identity: ClientIdentity

        public init(server: URL, identity: ClientIdentity, certificatePin: OriginCertificatePin? = nil) {
            self.server = server
            self.identity = identity
            self.certificatePin = certificatePin
            let headerDelegate = GlassfinHeaderDelegate()
            self.headerDelegate = headerDelegate
            let redirectDelegate = RedirectSessionDelegate(certificatePin: certificatePin)
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

        var boundedClient: HTTPJellyfinClient {
            HTTPJellyfinClient(server: server, identity: identity, certificatePin: certificatePin)
        }

        public func send(_ request: APIRequest) async throws(CoreModels.APIError) -> Data {
            // SDK data(for:) buffers whole bodies. Bounded image requests must use CoreNetworking's delegate.
            if request.maximumResponseBytes != nil {
                return try await boundedClient.send(request)
            }
            do {
                headerDelegate.header = try identity.authorizationHeader()
            } catch let error as CoreModels.APIError {
                throw error
            } catch {
                throw CoreModels.APIError.headerRejected
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
                if let status = response.statusCode, let failure = HTTPStatusMapper.apiFailure(for: status) {
                    throw failure
                }
                return response.data
            } catch let error as CoreModels.APIError {
                throw error
            } catch let error as Get.APIError {
                if case .unacceptableStatusCode(let status) = error {
                    throw HTTPStatusMapper.apiFailure(for: status) ?? CoreModels.APIError.server(status: status)
                }
                throw CoreModels.APIError.network
            } catch let error as URLError {
                throw URLErrorMapper.map(error)
            } catch is CancellationError {
                throw CoreModels.APIError.cancelled
            } catch {
                throw CoreModels.APIError.network
            }
        }
    }
#endif

public enum JellyfinClientFactory {
    public static func make(
        server: URL, identity: ClientIdentity, certificatePin: OriginCertificatePin? = nil
    ) -> any JellyfinAPIClient {
        #if canImport(JellyfinAPI)
            SDKJellyfinAPIClient(server: server, identity: identity, certificatePin: certificatePin)
        #else
            HTTPJellyfinClient(server: server, identity: identity, certificatePin: certificatePin)
        #endif
    }
}
