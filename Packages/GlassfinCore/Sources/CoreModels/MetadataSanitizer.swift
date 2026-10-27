import Foundation

/// S4.7/Q4-16 and S6.1: remove controls and bidi overrides; preserve literal markup.
public enum MetadataSanitizer {
    public static func plainText(_ raw: String) -> String {
        MetadataPolicy.clean(raw, limit: raw.count)
    }

    public static func displayName(_ raw: String, fallbackHost: String) -> String {
        let plain = plainText(raw)
        let value = plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackHost : plain
        return MetadataPolicy.clean(value, limit: MetadataPolicy.displayNameMax)
    }
}
