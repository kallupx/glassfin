import CoreModels
import CoreNetworking
import Foundation

#if canImport(JellyfinAPI)
    import JellyfinAPI
#endif

/// S6.5. Apple builds pass search parameters through the generated SDK query builders.
/// The transport remains CoreNetworking so image auth, redirects and accepted TLS pins
/// use the same audited path as M04. Linux uses the equivalent URLQueryItem adapter.
public struct SearchQueryClient: JellyfinAPIClient {
    private let inner: any JellyfinAPIClient
    public init(inner: any JellyfinAPIClient) { self.inner = inner }

    public func send(_ request: APIRequest) async throws(CoreModels.APIError) -> Data {
        var prepared = request
        #if canImport(JellyfinAPI)
            if let term = value("searchTerm", in: request) {
                let kinds = value("includeItemTypes", in: request)?.split(separator: ",")
                    .compactMap { BaseItemKind(rawValue: String($0)) }
                if request.path == "/Items" {
                    var parameters = Paths.GetItemsParameters()
                    parameters.searchTerm = term
                    parameters.includeItemTypes = kinds
                    parameters.isRecursive = value("recursive", in: request).map { $0 == "true" }
                    parameters.limit = value("limit", in: request).flatMap(Int.init)
                    parameters.startIndex = value("startIndex", in: request).flatMap(Int.init)
                    parameters.enableUserData = value("enableUserData", in: request).map { $0 == "true" }
                    parameters.enableTotalRecordCount = value("enableTotalRecordCount", in: request).map {
                        $0 == "true"
                    }
                    parameters.fields = [.primaryImageAspectRatio]
                    prepared.query = parameters.asQuery.map { URLQueryItem(name: $0.0, value: $0.1) }
                } else if request.path == "/Search/Hints" {
                    var parameters = Paths.GetSearchHintsParameters(searchTerm: term)
                    parameters.includeItemTypes = kinds
                    parameters.startIndex = value("startIndex", in: request).flatMap(Int.init)
                    parameters.limit = value("limit", in: request).flatMap(Int.init)
                    parameters.isIncludeMedia = true
                    prepared.query = parameters.asQuery.map { URLQueryItem(name: $0.0, value: $0.1) }
                }
            }
        #endif
        return try await inner.send(prepared)
    }

    private func value(_ name: String, in request: APIRequest) -> String? {
        request.query.first { $0.name == name }?.value
    }
}
