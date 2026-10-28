import CoreModels
import CoreNetworking
import Foundation

public enum AuthScreen: Sendable, Equatable {
    case welcome
    case address
    case cleartext
    case certificate
    case certificateMismatch
    case unsupported
    case setupIncomplete
    case loginMethod
    case quickConnect
    case userPicker
    case credentials
    case home
    case signedOut
    case logoutConfirm
}

public protocol AuthBackend: Sendable {
    func probe(_ address: String, certificatePin: OriginCertificatePin?) async -> ServerProbeOutcome
    func quickConnectEnabled(on server: ServerInfo) async throws(APIError) -> Bool
    func beginQuickConnect(on server: ServerInfo) async throws(APIError) -> QuickConnectChallenge
    func pollQuickConnect(on server: ServerInfo, secret: QuickConnectSecret) async throws(APIError) -> Bool
    func signIn(on server: ServerInfo, username: String, password: String) async throws(APIError)
        -> AuthenticatedSession
    func finishQuickConnect(on server: ServerInfo, secret: QuickConnectSecret) async throws(APIError)
        -> AuthenticatedSession
    func currentUser(on server: ServerInfo, token: String) async throws(APIError) -> UserSession
    func publicUsers(on server: ServerInfo) async throws(APIError) -> [PublicUser]
    func postCapabilities(on server: ServerInfo, token: String) async throws(APIError)
    func logout(on server: ServerInfo, token: String) async throws(APIError)
}
