import Foundation

/// Jellyfin item id. Only a 32-digit hex GUID, with or without dashes, may be placed in a URL path.
public struct ItemID: Sendable, Hashable, Equatable {
    public let value: String

    public init?(_ raw: String) {
        guard Self.isGUID(raw) else { return nil }
        self.value = raw
    }

    public static func require(_ raw: String) throws(APIError) -> ItemID {
        guard let id = ItemID(raw) else { throw APIError.invalidItemID }
        return id
    }

    private static func isGUID(_ raw: String) -> Bool {
        let bytes = Array(raw.utf8)
        if bytes.count == 32 {
            return bytes.allSatisfy(isHex)
        }
        guard bytes.count == 36 else { return false }
        let dashIndexes: Set<Int> = [8, 13, 18, 23]
        for (index, byte) in bytes.enumerated() {
            if dashIndexes.contains(index) {
                if byte != 45 { return false }
            } else if !isHex(byte) {
                return false
            }
        }
        return true
    }

    private static func isHex(_ byte: UInt8) -> Bool {
        (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 70) || (byte >= 97 && byte <= 102)
    }
}
