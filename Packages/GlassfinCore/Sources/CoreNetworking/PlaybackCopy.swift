import CoreModels

/// Keys are shared with the UI; translations live only in CoreModels' catalog.
public enum PlaybackCopy {
    public static let unsupportedVideoKey = "playback.unsupportedVideoFormat"
    public static let couldNotPlayKey = "playback.error.couldNotPlay"
    public static let insecureRedirectKey = "playback.error.insecureRedirect"
    public static let pinnedHLSKey = "playback.selfSignedRemuxBlocked"
    public static let okKey = "playback.ok"

    public static func message(for key: String) -> String { AppErrorMessage.localized(key) }
}
