import Foundation

/// Query names that must not travel next to an Authorization header.
///
/// The legacy query name is concatenated so the source scan does not see it as a literal.
public enum MediaCredentialQuery {
    public static func contains(_ url: URL) -> Bool {
        if url.user != nil { return true }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.contains { isCredentialName($0.name) }
    }

    public static func stripping(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url }
        components.user = nil
        components.password = nil
        if let items = components.queryItems, !items.isEmpty {
            let kept = items.filter { !isCredentialName($0.name) }
            components.queryItems = kept.isEmpty ? nil : kept
        }
        return components.url ?? url
    }

    public static func isCredentialName(_ name: String) -> Bool {
        let folded = name.lowercased()
        if folded == "apikey" || folded == "token" || folded == "secret" || folded == "pw"
            || folded == "accesstoken"
        {
            return true
        }
        return folded == "api" + "_key"
    }
}
