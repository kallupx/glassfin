import Foundation

/// Resolves a key in CoreNetworking's string catalog, using English source keys on Linux.
func localizedString(_ key: String) -> String {
    #if os(Linux)
        // swift-corelibs-foundation lacks the localization API, including String.LocalizationValue.
        return key
    #else
        return String(localized: String.LocalizationValue(key), bundle: .module)
    #endif
}
