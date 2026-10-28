import Foundation

public enum PlaybackPreferenceKeys {
    public static let convertASS = "playback.convertASS"
    public static let remoteBitrate = "playback.remoteBitrate"
}

/// Only non-sensitive playback choices enter UserDefaults. No media metadata or URLs persist.
@MainActor
public enum PlaybackPreferences {
    public static func configuration(defaults: UserDefaults = .standard) -> PlaybackConfiguration {
        PlaybackConfiguration(
            convertASS: defaults.object(forKey: PlaybackPreferenceKeys.convertASS) as? Bool ?? true,
            remoteBitrate: defaults.object(forKey: PlaybackPreferenceKeys.remoteBitrate) as? Int ?? 20_000_000)
    }
    public static func setASSConversion(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: PlaybackPreferenceKeys.convertASS)
    }
}
