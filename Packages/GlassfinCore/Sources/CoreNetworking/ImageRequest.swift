import CoreModels
import Foundation

public enum ItemImageType: String, Sendable, Hashable {
    case primary = "Primary"
    case thumb = "Thumb"
    case backdrop = "Backdrop"
}

/// Only this tuple contributes to an image filename. No URL or credential is accepted.
public struct ImageCacheKey: Sendable, Hashable {
    public let sha256: String

    public init(serverID: String, itemID: ItemID, type: ItemImageType, tag: String?, width: Int, height: Int) {
        let parts = [serverID, itemID.value, type.rawValue, tag ?? "", String(width), String(height)]
        // Length prefixes make the tuple unambiguous, even when a tag contains a separator.
        let canonical = parts.map { "\($0.utf8.count):\($0)" }.joined()
        sha256 = CertificateFingerprint.sha256Hex(Data(canonical.utf8))
    }
}

public struct ItemImageRequest: Sendable {
    public let request: APIRequest
    public let cacheKey: ImageCacheKey
    public let maximumPixelSize: Int

    public init(serverID: String, itemID: ItemID, type: ItemImageType, tag: String?, width: Int, height: Int) {
        let width = max(1, width)
        let height = max(1, height)
        self.maximumPixelSize = max(width, height)
        self.cacheKey = ImageCacheKey(
            serverID: serverID, itemID: itemID, type: type, tag: tag, width: width, height: height)
        var query = [
            URLQueryItem(name: "maxWidth", value: String(width)),
            URLQueryItem(name: "maxHeight", value: String(height)),
        ]
        if let tag { query.append(URLQueryItem(name: "tag", value: tag)) }
        request = APIRequest(method: "GET", path: "/Items/\(itemID.value)/Images/\(type.rawValue)", query: query)
    }
}
