import CoreModels
import CoreNetworking
import Foundation

/// Small interchangeable boundary. A nil kind means the initial three grouped rows.
public protocol SearchBackend: Sendable {
    func results(term: String, kind: SearchKind?, page: PageRequest) async throws(APIError) -> SearchResponse
}

/// ADR-M09-1: the default is three concurrent /Items requests, one limit per row.
/// Keep this default until all three versions have accepted benchmark evidence (Q9-01).
public struct ItemsSearchBackend: SearchBackend {
    private let client: any JellyfinAPIClient

    public init(client: any JellyfinAPIClient) { self.client = client }

    public func results(term: String, kind: SearchKind?, page: PageRequest) async throws(APIError) -> SearchResponse {
        do {
            let kinds = kind.map { [$0] } ?? SearchKind.allCases
            let response = try await withThrowingTaskGroup(of: (SearchKind, Result<SearchGroup, APIError>).self) {
                tasks in
                for kind in kinds {
                    tasks.addTask {
                        do { return (kind, .success(try await fetch(term: term, kind: kind, page: page))) } catch let
                            error as APIError
                        {
                            if error == .unauthorized || error == .cancelled { throw error }
                            return (kind, .failure(error))
                        } catch {
                            throw APIError.cancelled
                        }
                    }
                }
                var collected: [SearchKind: SearchGroup] = [:]
                var failures: [SearchKind: APIError] = [:]
                for try await (kind, result) in tasks {
                    switch result {
                    case .success(let group): collected[kind] = group
                    case .failure(let error): failures[kind] = error
                    }
                }
                // Q9-05: hide a failed sibling row; a failure of every row remains retryable.
                if collected.isEmpty, let error = kinds.compactMap({ failures[$0] }).first { throw error }
                return SearchResponse(term: term, groups: kinds.compactMap { collected[$0] }, failedRows: failures)
            }
            return response
        } catch let error as APIError {
            throw error
        } catch {
            throw .cancelled
        }
    }

    private func fetch(term: String, kind: SearchKind, page: PageRequest) async throws(APIError) -> SearchGroup {
        let data = try await client.send(
            APIRequest(
                method: "GET", path: "/Items",
                query: [
                    URLQueryItem(name: "searchTerm", value: term),
                    URLQueryItem(name: "includeItemTypes", value: kind.rawValue),
                    URLQueryItem(name: "recursive", value: "true"),
                    URLQueryItem(name: "limit", value: String(page.limit)),
                    URLQueryItem(name: "startIndex", value: String(page.startIndex)),
                    URLQueryItem(name: "fields", value: "PrimaryImageAspectRatio"),
                    URLQueryItem(name: "enableUserData", value: "true"),
                    URLQueryItem(name: "enableTotalRecordCount", value: "true"),
                ]))
        if Task.isCancelled { throw .cancelled }
        let decoded = try ResilientItemDecoder.mediaItems(from: data, log: SilentLog())
        // Use raw page consumption, including skipped/unsupported elements, for the cursor.
        let consumed = decoded.items.count + decoded.skipped
        let next = page.startIndex + consumed
        let hasMore = consumed >= page.limit && (decoded.totalCount.map { next < $0 } ?? true)
        return SearchGroup(
            id: kind, items: decoded.items.filter { $0.kind == kind.mediaKind }, nextIndex: hasMore ? next : nil)
    }
}

public struct SearchHintsBackend: SearchBackend {
    private let client: any JellyfinAPIClient

    public init(client: any JellyfinAPIClient) { self.client = client }

    public func results(term: String, kind: SearchKind?, page: PageRequest) async throws(APIError) -> SearchResponse {
        let kinds = kind.map { [$0] } ?? SearchKind.allCases
        // A single hints request gets the same total initial result budget as /Items x3.
        let limit = page.limit * (kind == nil ? SearchKind.allCases.count : 1)
        var request = QueryTransport.searchHints(term: term, limit: limit)
        request.query += [
            URLQueryItem(name: "includeItemTypes", value: kinds.map(\.rawValue).joined(separator: ",")),
            URLQueryItem(name: "startIndex", value: String(page.startIndex)),
            URLQueryItem(name: "isIncludeMedia", value: "true"),
        ]
        let data = try await client.send(request)
        let items = try ResilientItemDecoder.searchHints(from: data, log: SilentLog())
        let groups = kinds.map { kind in
            let matched = items.filter { $0.kind == kind.mediaKind }
            // Initial hints share one server limit. Subsequent pages query just this type.
            return SearchGroup(
                id: kind, items: Array(matched.prefix(page.limit)),
                nextIndex: matched.count >= page.limit || items.count >= limit
                    ? page.startIndex + min(matched.count, page.limit) : nil)
        }
        return SearchResponse(term: term, groups: groups)
    }
}

/// Compatibility for M02's injected SearchService tests. Production uses ItemsSearchBackend.
public struct SearchServiceBackend: SearchBackend {
    private let service: any SearchService
    public init(service: any SearchService) { self.service = service }

    public func results(term: String, kind: SearchKind?, page: PageRequest) async throws(APIError) -> SearchResponse {
        let items = try await service.hints(term: term, limit: page.limit)
        return SearchResponse(
            term: term,
            groups: (kind.map { [$0] } ?? SearchKind.allCases).map { kind in
                SearchGroup(id: kind, items: items.filter { $0.kind == kind.mediaKind })
            })
    }
}
