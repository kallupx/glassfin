import CoreModels
import Foundation

public enum ItemImageType: String, Codable, Sendable {
    case primary = "Primary"
    case backdrop = "Backdrop"
    case thumb = "Thumb"
    case logo = "Logo"
}

/// Image identity contains no URL or credentials. Size is in displayed pixels.
public struct ImageResource: Hashable, Sendable {
    public let serverID: String
    public let itemID: String
    public let type: ItemImageType
    public let tag: String
    public let width: Int
    public let height: Int

    public init(serverID: String, itemID: String, type: ItemImageType, tag: String, width: Int, height: Int) {
        self.serverID = serverID
        self.itemID = itemID
        self.type = type
        self.tag = tag
        self.width = max(1, width)
        self.height = max(1, height)
    }

    /// Length-prefixed components avoid ambiguous tuple encodings.
    public var cacheKey: String {
        let parts = [serverID, itemID, type.rawValue, tag, String(width), String(height)]
        let encoded = parts.map { "\($0.utf8.count):\($0)" }.joined()
        return CertificateFingerprint.sha256Hex(Data(encoded.utf8))
    }

    public func request() throws(APIError) -> APIRequest {
        guard let id = ItemID(itemID) else { throw .invalidItemID }
        return APIRequest(
            method: "GET", path: "/Items/\(id.value)/Images/\(type.rawValue)",
            query: [
                URLQueryItem(name: "tag", value: tag),
                URLQueryItem(name: "maxWidth", value: String(width)),
                URLQueryItem(name: "maxHeight", value: String(height)),
            ])
    }
}

public enum ImageDataError: Error, Equatable, Sendable {
    case oversized
    case invalidImage
}

public enum ImageDataPolicy {
    public static func validate(_ data: Data) throws(ImageDataError) {
        guard data.count <= MetadataPolicy.imageMaxBytes else { throw .oversized }
    }
}
