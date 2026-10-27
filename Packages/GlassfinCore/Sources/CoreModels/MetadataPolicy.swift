import Foundation

/// S6.1, S6.6 and S6.7 limits, shared by all content features.
public enum MetadataPolicy {
    public static let overviewMaxCharacters = 2_000
    public static let taglinesMax = 3
    public static let taglineMaxCharacters = 200
    public static let genresMax = 10
    public static let genreMaxCharacters = 64
    public static let nameMaxCharacters = 200
    public static let displayNameMaxCharacters = 64
    public static let imageMaxBytes = 20 * 1024 * 1024
    public static let recentSearchesMax = 20

    /// Clean before truncating extended grapheme clusters. Markup remains literal.
    public static func clean(_ raw: String, limit: Int = nameMaxCharacters) -> String {
        String(MetadataSanitizer.strippingControlsAndBidi(raw).prefix(max(0, limit)))
    }
}
