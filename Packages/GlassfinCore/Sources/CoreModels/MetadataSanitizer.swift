import Foundation

/// S6.1: metadata stays literal, including tags and entities. Filter only controls/bidi.
public enum MetadataSanitizer {
    public static func plainText(_ raw: String, limit: Int = MetadataPolicy.nameMax) -> String {
        MetadataPolicy.clean(raw, limit: limit)
    }

    public static func strippingControlsAndBidi(_ raw: String) -> String {
        MetadataPolicy.clean(raw, limit: raw.count)
    }

    /// S4.7/Q4-16: literal display text, at most 64 extended grapheme clusters.
    public static func displayName(_ raw: String, fallbackHost: String) -> String {
        let plain = strippingControlsAndBidi(raw)
        let value = plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackHost : plain
        return MetadataPolicy.clean(value, limit: MetadataPolicy.displayNameMax)
    }
}
