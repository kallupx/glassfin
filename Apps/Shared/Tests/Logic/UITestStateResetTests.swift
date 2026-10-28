import Foundation
import GlassfinCore
import Security
import XCTest

@testable import Glassfin

@MainActor
final class UITestStateResetTests: XCTestCase {
    func testResetWithoutMockFlagKeepsLiveServicesSelected() {
        let configuration = LaunchConfiguration(arguments: ["-uitest-reset"])
        XCTAssertTrue(configuration.resetState)
        XCTAssertFalse(configuration.useMockServer)
        XCTAssertFalse(configuration.startOnHome)
    }

    func testResetClearsAppStateAndPreservesOtherKeychainServicesAndCaches() throws {
        let suite = "org.glassfin.uitest-reset.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("old-session", forKey: "session")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = root.appendingPathComponent("Glassfin", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let sibling = root.appendingPathComponent("unrelated-cache")
        try Data([1]).write(to: sibling)
        let otherService = suite + ".other"
        for service in [suite, otherService] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "test-item",
                kSecValueData as String: Data([1]),
            ]
            XCTAssertEqual(SecItemAdd(query as CFDictionary, nil), errSecSuccess)
        }
        defer {
            for service in [suite, otherService] {
                SecItemDelete(
                    [
                        kSecClass as String: kSecClassGenericPassword,
                        kSecAttrService as String: service,
                    ] as CFDictionary)
            }
        }

        try UITestStateReset.reset(defaults: defaults, cacheRoot: root, keychainService: suite)

        XCTAssertNil(defaults.string(forKey: "session"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path))
        for (service, expected) in [(suite, errSecItemNotFound), (otherService, errSecSuccess)] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
            ]
            XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, nil), expected)
        }
        // Repeating a reset on an already clean installation must succeed.
        XCTAssertNoThrow(try UITestStateReset.reset(defaults: defaults, cacheRoot: root, keychainService: suite))
    }
}
