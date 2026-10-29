import Foundation

/// User-facing authentication copy. The enum raw value is the String Catalog key
/// (English, the development language). Finnish lives only in `Localizable.xcstrings`.
/// Tests compare ``Key``, never the localized sentence.
public enum AuthCopy {
    public enum Key: Sendable, Equatable, CaseIterable {
        case glassfin
        case connectToServer
        case serverAddress
        case `continue`
        case cancel
        case accept
        case tryAgain
        case back
        case serverNotFound
        case notJellyfin
        case publicAddressRequiresHTTPS
        case httpOnlyOnLocalNetwork
        case connectionNotEncrypted
        case setupIncomplete
        case invalidAddress
        case unsupportedServer
        case invalidCredentials
        case quickConnectUnauthorized
        case loginTransportFailure
        case sessionExpired
        case serverSessionMayRemain
        case quickConnectInstruction
        case usePassword
        case quickConnect
        case signIn
        case username
        case password
        case home
        case signOut
        case signOutConfirm
        case removeServer
        case certificateChanged
        case offline
        case userinfoRejected
        case loginServerFailure
        case quickConnectExpired
        case getNewCode
        case serverUnreachable
        case serverStarting
        case noNetworkConnection
        case settings
        case continueUnencrypted
        case switchServer
        case forbidden
        case playbackFailed
        case buffering
        case playbackOffline
        case playbackUnreachable
        case certificateUntrusted
        case insecureRedirect
        case itemNotFound
        case serverError
        case unsupportedServerDetail

        /// Shared errors reuse the PR #7 catalog constants.
        public var rawValue: String {
            switch self {
            case .glassfin: "Glassfin"
            case .connectToServer: "Connect to a server"
            case .serverAddress: "Server address"
            case .`continue`: "Continue"
            case .cancel: "Cancel"
            case .accept: "Accept"
            case .tryAgain: AppErrorMessage.retryKey
            case .back: "Back"
            case .serverNotFound: "Server not found"
            case .notJellyfin: "Not a Jellyfin server"
            case .publicAddressRequiresHTTPS:
                "Public addresses require HTTPS. Use an IP address, a .local name, or an HTTPS reverse proxy."
            case .httpOnlyOnLocalNetwork: "If your server only uses HTTP, it must be on your local network"
            case .connectionNotEncrypted: "The connection is not encrypted"
            case .setupIncomplete: "Server setup is incomplete. Finish setup in a browser at %@"
            case .invalidAddress: "That address cannot be used"
            case .unsupportedServer: "This server version is not supported"
            case .invalidCredentials: AppErrorMessage.invalidCredentialsKey
            case .quickConnectUnauthorized: "Quick Connect sign-in failed. Get a new code and try again."
            case .loginTransportFailure: "Can't reach the server. Check your connection and try again."
            case .sessionExpired: AppErrorMessage.sessionExpiredKey
            case .serverSessionMayRemain:
                "The server session may remain active until an administrator removes this device."
            case .quickConnectInstruction:
                "Open Jellyfin on a phone or in a browser → User → Quick Connect → enter the code"
            case .usePassword: "Use a password"
            case .quickConnect: "Quick Connect"
            case .signIn: "Sign in"
            case .username: "Username"
            case .password: "Password"
            case .home: "Home"
            case .signOut: "Sign out"
            case .signOutConfirm: "Sign out of this server?"
            case .removeServer: "Remove server"
            case .certificateChanged: "The server certificate changed"
            case .offline: "Offline"
            case .userinfoRejected: "Addresses containing a username or password are not allowed"
            case .loginServerFailure: "The server ran into a problem. Try again later."
            case .quickConnectExpired: "The code expired"
            case .getNewCode: "Get a new code"
            case .serverUnreachable: AppErrorMessage.serverDownKey
            case .serverStarting: AppErrorMessage.serverStartingKey
            case .noNetworkConnection: AppErrorMessage.offlineKey
            case .settings: "Settings"
            case .continueUnencrypted: "Continue unencrypted"
            case .switchServer: AppErrorMessage.changeServerKey
            case .forbidden: AppErrorMessage.forbiddenKey
            case .playbackFailed: AppErrorMessage.playbackFailedKey
            case .buffering: AppErrorMessage.bufferingKey
            case .playbackOffline: AppErrorMessage.playbackOfflineKey
            case .playbackUnreachable: AppErrorMessage.playbackUnreachableKey
            case .certificateUntrusted: AppErrorMessage.tlsUntrustedKey
            case .insecureRedirect: AppErrorMessage.insecureRedirectKey
            case .itemNotFound: AppErrorMessage.notFoundKey
            case .serverError: AppErrorMessage.serverErrorKey
            case .unsupportedServerDetail: AppErrorMessage.unsupportedServerKey
            }
        }
    }

    /// Looks up the catalog key. The English development string is the key.
    /// Finnish is selected by the user's locale from `Localizable.xcstrings`.
    public static func localized(_ key: Key) -> String {
        localizedString(key.rawValue)
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
