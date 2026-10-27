import Foundation

/// S4.7/S6.1: remove control and bidi scalars; preserve tags and entities literally.
public enum MetadataSanitizer {
    public static func plainText(_ raw: String) -> String {
        String(
            String.UnicodeScalarView(
                raw.unicodeScalars.filter { scalar in
                    scalar.properties.generalCategory != .control && !scalar.properties.isBidiControl
                }))
    }

    /// S4.7/Q4-16: literal display text, at most 64 extended grapheme clusters.
    public static func displayName(_ raw: String, fallbackHost: String) -> String {
        let plain = plainText(raw)
        let value =
            plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? plainText(fallbackHost) : plain
        return MetadataPolicy.clean(value, limit: MetadataPolicy.displayNameMax)
    }
}
