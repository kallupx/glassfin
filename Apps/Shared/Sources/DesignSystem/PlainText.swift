import GlassfinCore

/// Server metadata stays literal, with controls removed and a grapheme limit.
enum PlainText {
    static func overview(_ source: String) -> String {
        MetadataSanitizer.displayText(source, limit: MetadataPolicy.overviewMax)
    }
}
