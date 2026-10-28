#if DEBUG
    import Foundation
    import GlassfinCore
    import Security

    /// Resets only this app's state before constructing its real or mock services.
    enum UITestStateReset {
        static func reset(
            defaults: UserDefaults = .standard,
            cacheRoot: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0],
            keychainService: String = KeychainItemQuery.service
        ) throws {
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            ]
            let group = KeychainAttributes.production.accessGroup
            if !group.isEmpty { query[kSecAttrAccessGroup as String] = group }
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.status(status)
            }
            UserDefaultsSettingsStore(defaults: defaults).removeAll()
            URLCache.shared.removeAllCachedResponses()
            let glassfinCache = cacheRoot.appendingPathComponent("Glassfin", isDirectory: true)
            if FileManager.default.fileExists(atPath: glassfinCache.path) {
                try FileManager.default.removeItem(at: glassfinCache)
            }
        }
    }
#endif
