import Foundation

/// Custom scheme AVFoundation does not fetch itself, so the resource loader is invoked.
///
/// `https` never reaches `AVAssetResourceLoaderDelegate`. The wrapped URL is the origin
/// without a credential query. Unwrapping fails closed if a credential is present.
public enum MediaAssetScheme {
    public static let name = "glassfin-media"
    public static let host = "origin"

    public static func wrap(_ origin: URL) -> URL? {
        let clean = MediaCredentialQuery.stripping(origin)
        guard !MediaCredentialQuery.contains(clean) else { return nil }
        guard clean.scheme?.lowercased() == "https" || clean.scheme?.lowercased() == "http" else { return nil }
        var components = URLComponents()
        components.scheme = name
        components.host = host
        let allowed = CharacterSet.alphanumerics
        guard let encoded = clean.absoluteString.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return nil
        }
        components.percentEncodedPath = "/" + encoded
        return components.url
    }

    public static func unwrap(_ asset: URL) -> URL? {
        guard asset.scheme?.lowercased() == name, asset.host == host else { return nil }
        guard let components = URLComponents(url: asset, resolvingAgainstBaseURL: false) else { return nil }
        var encoded = components.percentEncodedPath
        if encoded.hasPrefix("/") { encoded.removeFirst() }
        guard let decoded = encoded.removingPercentEncoding, let origin = URL(string: decoded) else { return nil }
        guard !MediaCredentialQuery.contains(origin) else { return nil }
        return origin
    }
}
