import Foundation

/// Keys are shared with the UI; translations live only in CoreNetworking's catalog.
public enum PlaybackCopy {
    public static let unsupportedVideoKey = "playback.error.unsupportedVideo"
    public static let couldNotPlayKey = "playback.error.couldNotPlay"
    public static let insecureRedirectKey = "playback.error.insecureRedirect"
    public static let pinnedHLSKey = "playback.error.pinnedHLS"
    public static let okKey = "playback.ok"

    public static func message(for key: String) -> String { localizedString(key) }
}
