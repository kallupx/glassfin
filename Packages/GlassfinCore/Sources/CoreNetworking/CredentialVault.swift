import CoreModels
import Foundation

/// Session fields that may live in UserDefaults. The access token is not one of them.
public struct StoredSessionProfile: Codable, Equatable, Sendable {
    public var serverID: String
    public var serverName: String
    public var serverURL: String
    public var userID: String
    public var userName: String
    public var isAdministrator: Bool

    public init(
        serverID: String,
        serverName: String,
        serverURL: String,
        userID: String,
        userName: String,
        isAdministrator: Bool
    ) {
        self.serverID = serverID
        self.serverName = serverName
        self.serverURL = serverURL
        self.userID = userID
        self.userName = userName
        self.isAdministrator = isAdministrator
    }
}

/// Access tokens live only in `SecureStore`, keyed by server id and user id (S1.1, S1.3, S1.4).
public struct CredentialVault: Sendable {
    public var secureStore: any SecureStore
    public var settings: any SettingsStore
    public var accessGroup: String
    private static let indexAccount = "token-index"

    public init(
        secureStore: any SecureStore, settings: any SettingsStore,
        accessGroup: String = KeychainAttributes.production.accessGroup
    ) {
        self.secureStore = secureStore
        self.settings = settings
        self.accessGroup = accessGroup
    }

    /// Always `AfterFirstUnlockThisDeviceOnly` and never synchronizable, whatever the caller passed in.
    public var attributes: KeychainAttributes {
        KeychainAttributes(
            accessibility: "AfterFirstUnlockThisDeviceOnly",
            synchronizable: false,
            accessGroup: accessGroup
        )
    }

    public static func tokenAccount(serverID: String, userID: String) throws -> String {
        let server = try ItemID.require(serverID).value
        let user = try ItemID.require(userID).value
        return "token:\(server):\(user)"
    }

    public static func profileKey(serverID: String, userID: String) throws -> String {
        let server = try ItemID.require(serverID).value
        let user = try ItemID.require(userID).value
        return "session.profile.\(server).\(user)"
    }

    public func save(token: String, serverID: String, userID: String, profile: StoredSessionProfile) throws {
        guard !token.isEmpty else { throw SecurityInvariantError.internalInvariant }
        let account = try Self.tokenAccount(serverID: serverID, userID: userID)
        try secureStore.set(Data(token.utf8), account: account, attributes: attributes)
        var accounts = try readIndex()
        if !accounts.contains(account) {
            accounts.append(account)
            try writeIndex(accounts)
        }
        let payload = try JSONEncoder().encode(profile)
        let text = String(decoding: payload, as: UTF8.self)
        if text.contains(token) {
            throw SecurityInvariantError.internalInvariant
        }
        settings.set(text, forKey: try Self.profileKey(serverID: serverID, userID: userID))
    }

    public func loadToken(serverID: String, userID: String) throws -> String? {
        let account = try Self.tokenAccount(serverID: serverID, userID: userID)
        guard let data = try secureStore.data(for: account), !data.isEmpty else { return nil }
        let token = String(decoding: data, as: UTF8.self)
        return token.isEmpty ? nil : token
    }

    public func deleteToken(serverID: String, userID: String) throws {
        let account = try Self.tokenAccount(serverID: serverID, userID: userID)
        try secureStore.remove(account: account)
        let remaining = try readIndex().filter { $0 != account }
        try writeIndex(remaining)
    }

    public func deleteTokens(serverID: String) throws {
        let server = try ItemID.require(serverID).value
        let prefix = "token:\(server):"
        let accounts = try readIndex()
        for account in accounts where account.hasPrefix(prefix) {
            try secureStore.remove(account: account)
        }
        try writeIndex(accounts.filter { !$0.hasPrefix(prefix) })
    }

    private func readIndex() throws -> [String] {
        guard let data = try secureStore.data(for: Self.indexAccount), !data.isEmpty else { return [] }
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    private func writeIndex(_ accounts: [String]) throws {
        let text = accounts.joined(separator: "\n")
        try secureStore.set(Data(text.utf8), account: Self.indexAccount, attributes: attributes)
    }
}

/// Password bytes exist only for the `AuthenticateByName` call, then the field is cleared (S1.2).
public struct PasswordField: Sendable {
    private var value: String

    public init(_ value: String) {
        self.value = value
    }

    public var isEmpty: Bool { value.isEmpty }

    public mutating func clear() {
        value.removeAll(keepingCapacity: false)
    }

    public mutating func authenticate<T: Sendable>(_ body: (String) async throws -> T) async rethrows -> T {
        let snapshot = value
        defer { clear() }
        return try await body(snapshot)
    }
}

/// UserDefaults must not receive passwords, tokens, Quick Connect secrets, or API keys.
public struct GuardedSettings: Sendable {
    public var store: any SettingsStore

    public init(store: any SettingsStore) {
        self.store = store
    }

    public func set(_ value: String?, forKey key: String) throws {
        if Self.isForbidden(key) {
            throw SecurityInvariantError.internalInvariant
        }
        store.set(value, forKey: key)
    }

    public static func isForbidden(_ key: String) -> Bool {
        let folded = key.lowercased()
        if folded == "pw" { return true }
        let markers = ["password", "passwd", "secret", "token", "apikey", "api" + "_key", "api-key"]
        return markers.contains { folded.contains($0) }
    }
}
