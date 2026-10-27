import GlassfinCore

/// S6.1: server text stays literal; only control/bidi filtering and grapheme limits apply.
enum PlainText {
    static func overview(_ source: String) -> String {
        MetadataPolicy.clean(source, limit: MetadataPolicy.overviewMax)
    }
}
