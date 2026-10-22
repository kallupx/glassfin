import CoreModels
import Foundation

public enum AuthenticatedRequestKind: Sendable, Equatable {
    /// `AuthenticateByName` / Quick Connect. A 401 is a wrong credential, not a dead session.
    case login
    case authenticated
}

public enum SessionFailurePolicy {
    public enum Effect: Sendable, Equatable {
        case endSession
        case invalidCredentials
        case keepToken
    }

    /// Only an authenticated HTTP 401 ends the session (S2.2).
    public static func effect(of error: APIError, kind: AuthenticatedRequestKind) -> Effect {
        guard LogoutPolicy.shouldLogOut(error) else { return .keepToken }
        switch kind {
        case .login:
            return .invalidCredentials
        case .authenticated:
            return .endSession
        }
    }
}

public struct SessionEndResult: Sendable, Equatable {
    public var tokenRemoved: Bool
    public var serverCallAttempted: Bool
    public var serverCallSucceeded: Bool
    public var serverSessionMayRemain: Bool

    public init(
        tokenRemoved: Bool,
        serverCallAttempted: Bool,
        serverCallSucceeded: Bool,
        serverSessionMayRemain: Bool
    ) {
        self.tokenRemoved = tokenRemoved
        self.serverCallAttempted = serverCallAttempted
        self.serverCallSucceeded = serverCallSucceeded
        self.serverSessionMayRemain = serverSessionMayRemain
    }

    /// Catalog key for ``userMessage``, or nil when no message should be shown.
    public var userMessageKey: String? {
        serverSessionMayRemain ? SessionEndCopy.serverSessionMayRemainKey : nil
    }

    public var userMessage: String? {
        guard userMessageKey != nil else { return nil }
        return SessionEndCopy.serverSessionMayRemain
    }
}

public enum SessionEndCopy {
    /// Key in CoreNetworking `Localizable.xcstrings` (development language `en`, plus `fi`).
    /// Follow `String(localized: "English source", bundle: .module)` for other user-facing copy.
    public static let serverSessionMayRemainKey =
        "The server session may remain active until an administrator removes this device."

    public static var serverSessionMayRemain: String {
        String(
            localized: "The server session may remain active until an administrator removes this device.",
            bundle: .module
        )
    }
}

public enum SessionTermination {
    /// Always calls `POST /Sessions/Logout`, then deletes the local token even when the call fails (S2.1).
    public static func logOut(
        serverID: String,
        userID: String,
        vault: CredentialVault,
        client: any JellyfinAPIClient
    ) async -> SessionEndResult {
        var succeeded = false
        do {
            _ = try await client.send(APIRequest(method: "POST", path: "/Sessions/Logout"))
            succeeded = true
        } catch {
            succeeded = false
        }
        var removed = false
        do {
            try vault.deleteToken(serverID: serverID, userID: userID)
            removed = try vault.loadToken(serverID: serverID, userID: userID) == nil
        } catch {
            removed = false
        }
        return SessionEndResult(
            tokenRemoved: removed,
            serverCallAttempted: true,
            serverCallSucceeded: succeeded,
            serverSessionMayRemain: !succeeded
        )
    }

    /// Deletes the token only when `effect` is `endSession`.
    public static func apply(
        error: APIError,
        kind: AuthenticatedRequestKind,
        serverID: String,
        userID: String,
        vault: CredentialVault
    ) throws -> SessionFailurePolicy.Effect {
        let effect = SessionFailurePolicy.effect(of: error, kind: kind)
        if effect == .endSession {
            try vault.deleteToken(serverID: serverID, userID: userID)
        }
        return effect
    }
}

public enum ServerDataRemoval {
    /// Removing a server drops every token for it and its certificate pin (S2.3).
    public static func remove(serverID: String, vault: CredentialVault, pins: any CertificatePinStore) throws {
        try vault.deleteTokens(serverID: serverID)
        try pins.remove(serverID: serverID)
    }
}
