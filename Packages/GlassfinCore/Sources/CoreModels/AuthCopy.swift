import Foundation

/// User-facing authentication copy. The enum raw value is the String Catalog key
/// (English, the development language). Finnish lives only in `Localizable.xcstrings`.
/// Tests compare ``Key``, never the localized sentence.
public enum AuthCopy {
    public enum Key: String, Sendable, Equatable, CaseIterable {
        case glassfin = "Glassfin"
        case connectToServer = "Connect to server"
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
        case invalidCredentials = "Wrong username or password"
        case quickConnectUnauthorized = "Quick Connect was rejected"
        case loginTransportFailure = "Could not sign in"
        case sessionEnded = "Session ended"
        case serverSessionMayRemain =
            "The server session may remain active until an administrator removes this device."
        case quickConnectInstruction = "Enter this code on the server under Quick Connect."
        case usePassword = "Use password"
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
