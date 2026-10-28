import CoreNetworking
import Foundation

public enum SessionCredential {
    /// Keychain account for one server and user. S1.4. The token bytes are not part of the account name.
    public static func account(serverID: String, userID: String) -> String {
        "session-token/\(serverID)/\(userID)"
    }
}

public struct StoredServer: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var url: URL
    public var version: String
    public var certificatePinSHA256: String?

    public init(id: String, name: String, url: URL, version: String, certificatePinSHA256: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.version = version
        self.certificatePinSHA256 = certificatePinSHA256
    }
}

public struct StoredUser: Codable, Sendable, Equatable {
    public var serverID: String
    public var userID: String
    public var userName: String
    public var isAdministrator: Bool
    public var audioLanguage: String?
    public var subtitleLanguage: String?

    public init(
        serverID: String,
        userID: String,
        userName: String,
        isAdministrator: Bool,
        audioLanguage: String? = nil,
        subtitleLanguage: String? = nil
    ) {
        self.serverID = serverID
        self.userID = userID
        self.userName = userName
        self.isAdministrator = isAdministrator
        self.audioLanguage = audioLanguage
        self.subtitleLanguage = subtitleLanguage
    }
}

public enum PreferencesError: Error, Sendable, Equatable {
    case overBudget(bytes: Int)
    case invalidServerURL
    case encodingFailed
    case keychainFailed
}

public struct AppPreferences: Codable, Sendable, Equatable {
    public var servers: [StoredServer]
    public var users: [StoredUser]
    public var activeServerID: String?
    public var activeUserID: String?

    public init(servers: [StoredServer], users: [StoredUser], activeServerID: String?, activeUserID: String?) {
        self.servers = servers
        self.users = users
        self.activeServerID = activeServerID
        self.activeUserID = activeUserID
    }

    public static let empty = AppPreferences(servers: [], users: [], activeServerID: nil, activeUserID: nil)
    public static let maximumBytes = CacheBudget.userDefaultsBytes

    public func activeServer() -> StoredServer? {
        guard let activeServerID else { return nil }
        return servers.first { $0.id == activeServerID }
    }

    public func activeUser() -> StoredUser? {
        guard let activeServerID, let activeUserID else { return nil }
        return users.first { $0.serverID == activeServerID && $0.userID == activeUserID }
    }

    public func upserting(server: StoredServer) throws(PreferencesError) -> AppPreferences {
        let url: URL
        do {
            url = try ServerURLNormalizer.normalize(server.url)
        } catch {
            throw .invalidServerURL
        }
        var copy = self
        var stored = server
        stored.url = url
        if let index = copy.servers.firstIndex(where: { $0.id == stored.id }) {
            copy.servers[index] = stored
        } else {
            copy.servers.append(stored)
        }
        return copy
    }

    public func upserting(user: StoredUser) -> AppPreferences {
        var copy = self
        if let index = copy.users.firstIndex(where: { $0.serverID == user.serverID && $0.userID == user.userID }) {
            copy.users[index] = user
        } else {
            copy.users.append(user)
        }
        return copy
    }

    /// Drops the server and its users. Returned strings are keychain accounts to delete.
    public func removing(serverID: String) -> (AppPreferences, [String]) {
        var copy = self
        let accounts = users.filter { $0.serverID == serverID }.map {
            SessionCredential.account(serverID: $0.serverID, userID: $0.userID)
        }
        copy.servers.removeAll { $0.id == serverID }
        copy.users.removeAll { $0.serverID == serverID }
        if copy.activeServerID == serverID {
            copy.activeServerID = nil
            copy.activeUserID = nil
        }
        return (copy, accounts)
    }
}

public struct PreferencesRepository: Sendable {
    public static let storageKey = "org.glassfin.preferences"
    public var store: any SettingsStore

    public init(store: any SettingsStore) {
        self.store = store
    }

    public func load() -> AppPreferences {
        guard let raw = store.string(forKey: Self.storageKey), let data = raw.data(using: .utf8) else {
            return .empty
        }
        guard let prefs = try? JSONDecoder().decode(AppPreferences.self, from: data) else { return .empty }
        return prefs
    }

    public func save(_ preferences: AppPreferences) throws(PreferencesError) {
        let data: Data
        do {
            data = try JSONEncoder().encode(preferences)
        } catch {
            throw .encodingFailed
        }
        if data.count > AppPreferences.maximumBytes {
            throw .overBudget(bytes: data.count)
        }
        store.set(String(decoding: data, as: UTF8.self), forKey: Self.storageKey)
    }

    public static func encodedByteCount(_ preferences: AppPreferences) -> Int? {
        guard let data = try? JSONEncoder().encode(preferences) else { return nil }
        return data.count
    }
}

public final class UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    public func set(_ value: String?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    public func removeAll() {
        for key in defaults.dictionaryRepresentation().keys {
            defaults.removeObject(forKey: key)
        }
    }
}
