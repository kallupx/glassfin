import Foundation

#if os(Linux)
    extension String {
        /// swift-corelibs-foundation has no `String(localized:bundle:)`.
        /// The catalog key is the English development-language value, so return that.
        /// Apple builds use Foundation's initializer and `Localizable.xcstrings`.
        init(localized keyAndValue: String, bundle _: Bundle?) {
            self = keyAndValue
        }
    }
#endif
