import Foundation

/// S4.7/Q4-16 and S6.1: remove controls and bidi overrides; preserve literal markup.
public enum MetadataSanitizer {
    /// Strip controls and bidi scalars before capping extended grapheme clusters; preserve markup literally.
    public static func displayText(_ raw: String, limit: Int) -> String {
        let scalars = raw.unicodeScalars.filter { scalar in
            guard scalar.properties.generalCategory != .control else { return false }
            switch scalar.value {
            case 0x061C, 0x200E...0x200F, 0x202A...0x202E, 0x2066...0x2069: return false
            default: return true
            }
        }
        return String(String(String.UnicodeScalarView(scalars)).prefix(max(0, limit)))
    }

    public static func plainText(_ raw: String) -> String {
        displayText(raw, limit: raw.count)
    }

    public static func displayName(_ raw: String, fallbackHost: String) -> String {
        let plain = displayText(raw, limit: raw.count)
        let value = plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackHost : plain
        return displayText(value, limit: MetadataPolicy.displayNameMax)
    }
}
