import Foundation
import GlassfinCore
import XCTest

@testable import Glassfin

final class T10SettingsLogicTests: XCTestCase {
    @MainActor
    func testTPOC_42_versionMatchesTheAppBundleAndCatalogFormatsBothLanguages() async throws {
        let flow = AuthAssembly.make(arguments: ["-uitest-mock-server", "-uitest-reset"])
        let version = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        XCTAssertFalse(version.isEmpty)
        XCTAssertEqual(SettingsViewModel(auth: flow).appVersion, version)
        for language in ["en", "fi"] {
            let resource = LocalizedStringResource(
                "settings.version", locale: Locale(identifier: language), bundle: .main)
            let pattern = String(localized: resource)
            XCTAssertNotEqual(pattern, CopyKey.settingsVersion.rawValue)
            XCTAssertTrue(pattern.contains("%@"))
            XCTAssertTrue(String(format: pattern, version).contains(version))
            let fallback = String(
                localized: LocalizedStringResource(
                    "settings.versionUnavailable", locale: Locale(identifier: language), bundle: .main))
            XCTAssertNotEqual(fallback, CopyKey.settingsVersionUnavailable.rawValue)
            XCTAssertFalse(fallback.isEmpty)
        }
    }
}
