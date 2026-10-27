import Foundation

/// S4.7/S6.1: remove control and bidi scalars; preserve tags and entities literally.
public enum MetadataSanitizer {
    /// Strips control and bidi characters, then caps grapheme clusters. Tags remain literal text (S6.1).
    public static func displayText(_ raw: String, limit: Int) -> String {
        let cleaned = raw.unicodeScalars.filter { !isControl($0) }
        return String(String(String.UnicodeScalarView(cleaned)).prefix(limit))
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.properties.generalCategory == .control { return true }
        switch scalar.value {
        case 0x061C, 0x200E...0x200F, 0x202A...0x202E, 0x2066...0x2069:
            return true
        default:
            return false
        }
    }

    public static func plainText(_ raw: String) -> String {
        String(
            String.UnicodeScalarView(
                raw.unicodeScalars.filter { scalar in
                    !isControl(scalar)
                }))
    }

    /// S4.7/Q4-16: literal display text, at most 64 extended grapheme clusters.
    public static func displayName(_ raw: String, fallbackHost: String) -> String {
        let plain = displayText(raw, limit: MetadataPolicy.displayNameMax)
        let value =
            plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? displayText(fallbackHost, limit: MetadataPolicy.displayNameMax) : plain
        return value
    }
}
