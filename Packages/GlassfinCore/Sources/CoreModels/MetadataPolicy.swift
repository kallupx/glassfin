import Foundation

/// Shared limits for untrusted server metadata, images, and local search history.
public enum MetadataPolicy {
    public static let overviewMax = 2000
    public static let taglinesMax = 3
    public static let taglineMax = 200
    public static let genresMax = 10
    public static let genreMax = 64
    public static let nameMax = 200
    public static let displayNameMax = 64
    public static let recentSearchesMax = 20
    public static let imageMaxBytes = 20 * 1024 * 1024

    /// Clean before truncating by extended grapheme clusters. Markup stays literal.
    public static func clean(_ value: String, limit: Int) -> String {
        let scalars = value.unicodeScalars.filter {
            $0.properties.generalCategory != .control && !$0.properties.isBidiControl
        }
        return String(String(String.UnicodeScalarView(scalars)).prefix(max(0, limit)))
    }
}
