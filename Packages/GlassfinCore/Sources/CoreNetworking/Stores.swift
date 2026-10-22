import Foundation

public struct KeychainAttributes: Sendable, Equatable {
    /// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (S1.1, confirmed in spec v1.1).
    public var accessibility: String
    public var synchronizable: Bool
    /// Team-prefixed group from the app Info.plist (`GlassfinKeychainAccessGroup`).
    public var accessGroup: String

    public init(accessibility: String, synchronizable: Bool, accessGroup: String) {
        self.accessibility = accessibility
        self.synchronizable = synchronizable
        self.accessGroup = accessGroup
    }

    /// Reads the access group Xcode wrote into the app Info.plist.
    /// An unexpanded `$(...)` build setting is not a usable group.
    public static func production(info: [String: Any]?) -> KeychainAttributes {
        KeychainAttributes(
            accessibility: "AfterFirstUnlockThisDeviceOnly",
            synchronizable: false,
            accessGroup: KeychainAccessGroup.resolve(info)
        )
    }

    public static var production: KeychainAttributes {
        production(info: Bundle.main.infoDictionary)
    }
}

public enum KeychainAccessGroup {
    public static let infoDictionaryKey = "GlassfinKeychainAccessGroup"

    public static func resolve(_ info: [String: Any]?) -> String {
        guard let value = info?[infoDictionaryKey] as? String else { return "" }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("$(") { return "" }
        return trimmed
    }
}

/// Shared keychain lookup. `agrp` is the access group, included on every read and write.
public enum KeychainItemQuery {
    public static let service = "org.glassfin.app"

    public static func base(account: String, accessGroup: String) -> [String: Any] {
        var query: [String: Any] = [
            "class": "genp",
            "svce": service,
            "acct": account,
        ]
        if !accessGroup.isEmpty {
            query["agrp"] = accessGroup
        }
        return query
    }
}

/// `SecItemUpdate` keeps the existing item. Add only when the item is missing.
public enum KeychainWritePlan: Equatable, Sendable {
    public static let success: Int32 = 0
    /// `errSecItemNotFound`.
    public static let itemNotFound: Int32 = -25300

    public enum Action: Equatable, Sendable {
        case updated
        case add
        case fail(Int32)
    }

    public static func afterUpdate(status: Int32) -> Action {
        if status == success { return .updated }
        if status == itemNotFound { return .add }
        return .fail(status)
    }
}

public protocol SecureStore: Sendable {
    func data(for account: String) throws -> Data?
    func set(_ data: Data, account: String, attributes: KeychainAttributes) throws
    func remove(account: String) throws
}

public final class InMemorySecureStore: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    public init() {}

    public func data(for account: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[account]
    }

    public func set(_ data: Data, account: String, attributes: KeychainAttributes) throws {
        lock.lock()
        defer { lock.unlock() }
        values[account] = data
    }

    public func remove(account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values[account] = nil
    }
}

#if canImport(Security)
    import Security

    public final class KeychainSecureStore: SecureStore, @unchecked Sendable {
        public var attributes: KeychainAttributes
        public init(attributes: KeychainAttributes = .production) {
            self.attributes = attributes
        }

        public func data(for account: String) throws -> Data? {
            var query = KeychainItemQuery.base(account: account, accessGroup: attributes.accessGroup)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess else { throw KeychainError.status(status) }
            return item as? Data
        }

        public func set(_ data: Data, account: String, attributes: KeychainAttributes) throws {
            let query = KeychainItemQuery.base(account: account, accessGroup: attributes.accessGroup)
            let changes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: Self.accessible(attributes.accessibility),
                kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            ]
            let status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
            switch KeychainWritePlan.afterUpdate(status: status) {
            case .updated:
                return
            case .fail(let code):
                throw KeychainError.status(code)
            case .add:
                var add = query
                for (key, value) in changes {
                    add[key] = value
                }
                let addStatus = SecItemAdd(add as CFDictionary, nil)
                guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
            }
        }

        public func remove(account: String) throws {
            let query = KeychainItemQuery.base(account: account, accessGroup: attributes.accessGroup)
            let status = SecItemDelete(query as CFDictionary)
            if status == errSecItemNotFound || status == errSecSuccess { return }
            throw KeychainError.status(status)
        }

        private static func accessible(_ name: String) -> CFString {
            switch name {
            case "AfterFirstUnlockThisDeviceOnly":
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            default:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            }
        }
    }

    public enum KeychainError: Error, Sendable {
        case status(OSStatus)
    }
#endif

public protocol SettingsStore: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
    func removeAll()
}

public final class InMemorySettingsStore: SettingsStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    public init() {}
    public func string(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    public func set(_ value: String?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        if let value {
            values[key] = value
        } else {
            values.removeValue(forKey: key)
        }
    }

    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        values.removeAll()
    }

    /// Every value currently stored. Used to prove a token never landed in settings.
    public func allValues() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

public protocol NetworkMonitor: Sendable {
    var isOnline: Bool { get }
}

public struct StaticNetworkMonitor: NetworkMonitor {
    public var isOnline: Bool
    public init(isOnline: Bool) { self.isOnline = isOnline }
}

public enum DeviceIdentityStore {
    public static let account = "device-id"

    public static func loadOrCreate(secureStore: any SecureStore, reset: Bool) throws -> String {
        if reset {
            try secureStore.remove(account: account)
        }
        if let existing = try secureStore.data(for: account), let string = String(data: existing, encoding: .utf8),
            !string.isEmpty
        {
            return string
        }
        let created = UUID().uuidString
        try secureStore.set(Data(created.utf8), account: account, attributes: .production)
        return created
    }
}
