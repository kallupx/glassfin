import Foundation

/// Userinfo is forbidden for playback independently of RFC 6454 origin identity.
public enum MediaURLValidation {
    public static func hasNoUserInfo(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return false }
        // Empty user/password fields still carry userinfo (https://@host, https://:@host).
        return components.user == nil && components.password == nil
    }
}
