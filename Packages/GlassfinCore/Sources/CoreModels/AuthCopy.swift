import Foundation

/// User-facing authentication copy. The enum raw value is the String Catalog key
/// (English, the development language). Finnish lives only in `Localizable.xcstrings`.
/// Tests compare ``Key``, never the localized sentence.
public enum AuthCopy {
    public enum Key: String, Sendable, Equatable, CaseIterable {
        case glassfin = "Glassfin"
        case connectToServer = "Connect to a server"
        case serverAddress = "Server address"
        case `continue` = "Continue"
        case cancel = "Cancel"
        case accept = "Accept"
        case tryAgain = "Try again"
        case back = "Back"
        case serverNotFound = "Server not found"
        case notJellyfin = "Not a Jellyfin server"
        case publicAddressRequiresHTTPS =
            "Public addresses require HTTPS. Use an IP address, a .local name, or an HTTPS reverse proxy."
        case httpOnlyOnLocalNetwork = "If your server only uses HTTP, it must be on your local network"
        case connectionNotEncrypted = "The connection is not encrypted"
        case setupIncomplete = "Server setup is incomplete. Finish setup in a browser at %@"
        case invalidAddress = "That address cannot be used"
        case unsupportedServer = "This server version is not supported"
        case invalidCredentials = "Incorrect username or password"
        case quickConnectUnauthorized = "Quick Connect sign-in failed. Get a new code and try again."
        case loginTransportFailure = "Can't reach the server. Check your connection and try again."
        case sessionExpired = "Session expired, please sign in again"
        case serverSessionMayRemain =
            "The server session may remain active until an administrator removes this device."
        case quickConnectInstruction =
            "Open Jellyfin on a phone or in a browser → User → Quick Connect → enter the code"
        case usePassword = "Use a password"
        case quickConnect = "Quick Connect"
        case signIn = "Sign in"
        case username = "Username"
        case password = "Password"
        case home = "Home"
        case signOut = "Sign out"
        case signOutConfirm = "Sign out of this server?"
        case removeServer = "Remove server"
        case certificateChanged = "The server certificate changed"
        case offline = "Offline"
        case userinfoRejected = "Addresses containing a username or password are not allowed"
        case loginServerFailure = "The server ran into a problem. Try again later."
        case quickConnectExpired = "The code expired"
        case getNewCode = "Get a new code"
        case serverUnreachable = "Can't reach the server"
        case noNetworkConnection = "No network connection"
        case settings = "Settings"
        case continueUnencrypted = "Continue unencrypted"
        case switchServer = "Switch server"
        case forbidden = "You do not have permission for this action"
        case playbackFailed = "This file could not be played"
        case buffering = "Buffering is taking longer than usual"
        case playbackOffline = "Playback is unavailable without a network connection"
        case playbackUnreachable = "Playback is unavailable because the server cannot be reached"
        case certificateUntrusted = "The server certificate is not trusted"
        case insecureRedirect = "The connection was redirected to an insecure address"
        case itemNotFound = "Item not found"
        case serverError = "The server returned an error"
        case unsupportedServerDetail = "Server version %@ is too old (required ≥ %@)"

    }

    /// Looks up the catalog key. The English development string is the key.
    /// Finnish is selected by the user's locale from `Localizable.xcstrings`.
    public static func localized(_ key: Key) -> String {
        NSLocalizedString(key.rawValue, bundle: .module, comment: "")
    }

    public static func key(for error: AppError) -> Key? {
        if case .publicHTTPRejected = error { return .publicAddressRequiresHTTPS }
        return nil
    }

    /// Formats ``Key/setupIncomplete`` with the server address. Tests still compare the key.
    public static func setupIncomplete(address: String) -> String {
        String(format: localized(.setupIncomplete), locale: Locale(identifier: "en"), address)
    }
}
