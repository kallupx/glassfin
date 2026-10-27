import Foundation

/// List decoding that skips a single bad element instead of failing the screen.
public struct ItemListDecode: Sendable, Equatable {
    public var items: [MediaItem]
    public var totalCount: Int?
    public var skipped: Int

    public init(items: [MediaItem], totalCount: Int?, skipped: Int) {
        self.items = items
        self.totalCount = totalCount
        self.skipped = skipped
    }
}

public enum ResilientItemDecoder {
    /// Query results (`Items`) and bare arrays (`/Items/Latest`).
    /// The log line is a fixed sentence plus an index. The payload is not interpolated.
    public static func mediaItems(from data: Data, log: any GlassfinLog) throws(APIError) -> ItemListDecode {
        let json = try jsonObject(data)
        let rawItems: [Any]
        let total: Int?
        if let dict = dictionary(json) {
            rawItems = try itemArray(dict["Items"])
            total = integer(dict["TotalRecordCount"])
        } else if let array = array(json) {
            rawItems = array
            total = nil
        } else {
            throw APIError.decoding
        }
        var items: [MediaItem] = []
        var skipped = 0
        for (index, raw) in rawItems.enumerated() {
            if let item = mediaItem(raw, log: log) {
                items.append(item)
            } else {
                skipped += 1
                log.warning("Skipped list item at index \(index); the JSON did not match a media item.")
            }
        }
        return ItemListDecode(items: items, totalCount: total, skipped: skipped)
    }

    public static func searchHints(from data: Data, log: any GlassfinLog) throws(APIError) -> [MediaItem] {
        let json = try jsonObject(data)
        guard let dict = dictionary(json) else { throw APIError.decoding }
        let rawItems = try itemArray(dict["SearchHints"])
        var items: [MediaItem] = []
        for (index, raw) in rawItems.enumerated() {
            guard let object = dictionary(raw),
                let encoded = try? JSONSerialization.data(withJSONObject: object),
                let hint = try? JSONDecoder().decode(SearchHintDTO.self, from: encoded)
            else {
                log.warning("Skipped search hint at index \(index); the JSON did not match a hint.")
                continue
            }
            guard let id = hint.ItemId ?? hint.Id else { continue }
            items.append(
                MediaItem(
                    id: id, kind: MediaKind.from(serverType: hint.`Type` ?? ""),
                    name: MetadataSanitizer.plainText(hint.Name ?? "")))
        }
        return items
    }

    private static func jsonObject(_ data: Data) throws(APIError) -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw APIError.decoding
        }
    }

    private static func itemArray(_ raw: Any?) throws(APIError) -> [Any] {
        guard let raw, !(raw is NSNull) else { return [] }
        guard let array = array(raw) else { throw APIError.decoding }
        return array
    }

    private static func mediaItem(_ raw: Any, log: any GlassfinLog) -> MediaItem? {
        guard let object = dictionary(raw), JSONSerialization.isValidJSONObject(object),
            let encoded = try? JSONSerialization.data(withJSONObject: object),
            let dto = try? JSONDecoder().decode(BaseItemDTO.self, from: encoded)
        else { return nil }
        return DTOMapper.mediaItem(dto, log: log)
    }

    private static func dictionary(_ raw: Any?) -> [String: Any]? {
        if let dict = raw as? [String: Any] { return dict }
        guard let dict = raw as? NSDictionary else { return nil }
        var result: [String: Any] = [:]
        for (key, value) in dict {
            guard let key = key as? String else { continue }
            result[key] = value
        }
        return result
    }

    private static func array(_ raw: Any?) -> [Any]? {
        if let array = raw as? [Any] { return array }
        if let array = raw as? NSArray { return array.map { $0 } }
        return nil
    }

    private static func integer(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        return nil
    }
}
