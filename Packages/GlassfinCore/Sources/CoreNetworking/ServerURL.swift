import CoreModels
import Foundation

public enum ServerURLNormalizer {
    /// Accepts only http(s), rejects userinfo, and keeps a reverse-proxy subpath.
    public static func normalize(_ raw: URL) throws -> URL {
        guard let scheme = raw.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw APIError.invalidURL
        }
        guard var components = URLComponents(url: raw, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        guard components.user == nil, components.password == nil else { throw APIError.invalidURL }
        components.query = nil
        components.fragment = nil
        components.scheme = scheme
        guard let url = components.url, url.host != nil else { throw APIError.invalidURL }
        return url
    }
}
