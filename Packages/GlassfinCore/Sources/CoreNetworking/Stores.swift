import Foundation

public struct KeychainAttributes: Sendable, Equatable {
    /// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (S1.1, confirmed in spec v1.1).
    public var accessibility: String
    public var synchronizable: Bool
    /// Logical group. The entitlement expands `$(AppIdentifierPrefix)` at build time.
    public var accessGroup: String

    public init(accessibility: String, synchronizable: Bool, accessGroup: String) {
        self.accessibility = accessibility
        self.synchronizable = synchronizable
        self.accessGroup = accessGroup
    }

    public static let production = KeychainAttributes(
        accessibility: "AfterFirstUnlockThisDeviceOnly",
        synchronizable: false,
        accessGroup: "org.glassfin.app"
    )
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
            var query = baseQuery(account: account)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess else { throw KeychainError.status(status) }
            return item as? Data
        }

        public func set(_ data: Data, account: String, attributes: KeychainAttributes) throws {
            try? remove(account: account)
            var query = baseQuery(account: account)
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = Self.accessible(attributes.accessibility)
            query[kSecAttrSynchronizable as String] = kCFBooleanFalse
            if !attributes.accessGroup.isEmpty {
                query[kSecAttrAccessGroup as String] = attributes.accessGroup
            }
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError.status(status) }
        }

        public func remove(account: String) throws {
            let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
            if status == errSecItemNotFound || status == errSecSuccess { return }
            throw KeychainError.status(status)
        }

        private func baseQuery(account: String) -> [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "org.glassfin.app",
                kSecAttrAccount as String: account,
            ]
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
        values[key] = value
    }

    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        values.removeAll()
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
