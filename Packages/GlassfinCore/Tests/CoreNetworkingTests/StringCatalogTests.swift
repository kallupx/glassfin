import CoreModels
import CoreNetworking
import Foundation
import XCTest

final class StringCatalogTests: XCTestCase {
    private let playbackKeys: Set<String> = [
        PlaybackCopy.unsupportedVideoKey, PlaybackCopy.couldNotPlayKey, PlaybackCopy.insecureRedirectKey,
        PlaybackCopy.pinnedHLSKey, PlaybackCopy.okKey,
    ]

    /// Every `*.xcstrings` in the checkout is checked, not only CoreModels.
    /// That includes `Apps/Shared/Resources/Localizable.xcstrings`.
    func testEveryStringCatalogHasTranslatedEnglishAndFinnish() throws {
        let root = try XCTUnwrap(repositoryRoot(), "Repository root not found from \(#filePath)")
        let catalogs = StringCatalogLint.catalogs(at: root)
        XCTAssertFalse(catalogs.isEmpty, "Expected at least one .xcstrings catalog")
        XCTAssertTrue(
            catalogs.contains { $0.path.hasSuffix("Sources/CoreModels/Localizable.xcstrings") },
            "CoreModels string catalog was not discovered"
        )
        let sharedSuffix = "Apps/Shared/Resources/Localizable.xcstrings"
        XCTAssertTrue(
            catalogs.contains { $0.path.hasSuffix(sharedSuffix) },
            "Apps/Shared string catalog was not discovered"
        )
        let issues = catalogs.flatMap { StringCatalogLint.issues(in: $0, root: root) }
        XCTAssertEqual(issues, [], issues.joined(separator: "\n"))
    }

    func testNetworkingCatalogKeysAndLocalizedAccessors() throws {
        let englishValues = try catalogEnglishValues(module: "CoreModels")
        try assertLocalized(
            ServerTransportPolicy.unencryptedWarning,
            key: ServerTransportPolicy.unencryptedWarningKey,
            englishValues: englishValues
        )
        try assertLocalized(
            ServerTransportPolicy.publicAddressRequiresHTTPS,
            key: ServerTransportPolicy.publicAddressRequiresHTTPSKey,
            englishValues: englishValues
        )
        try assertLocalized(
            SessionEndCopy.serverSessionMayRemain,
            key: SessionEndCopy.serverSessionMayRemainKey,
            englishValues: englishValues
        )
        for key in playbackKeys.sorted() {
            try assertLocalized(PlaybackCopy.message(for: key), key: key, englishValues: englishValues)
        }
    }

    func testModelsCatalogKeysAndLocalizedAccessor() throws {
        let englishValues = try catalogEnglishValues(module: "CoreModels")
        XCTAssertEqual(Set(englishValues.keys), Set(AuthCopy.Key.allCases.map(\.rawValue)).union(playbackKeys))
        for key in englishValues.keys.sorted() {
            try assertLocalized(AppErrorMessage.localized(key), key: key, englishValues: englishValues)
        }
    }

    private func catalogEnglishValues(module: String, excluding nonlocalizedConstants: Set<String> = []) throws
        -> [String: String]
    {
        let root = try XCTUnwrap(repositoryRoot(), "Repository root not found from \(#filePath)")
        let sources = root.appendingPathComponent("Packages/GlassfinCore/Sources/\(module)")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
        let pattern = #"\bstatic\s+let\s+(\w+Key)\s*=\s*"([^"\r\n]+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        var keys: Set<String> = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                let nameRange = try XCTUnwrap(Range(match.range(at: 1), in: source))
                if nonlocalizedConstants.contains(String(source[nameRange])) { continue }
                let range = try XCTUnwrap(Range(match.range(at: 2), in: source))
                keys.insert(String(source[range]))
            }
        }
        XCTAssertFalse(keys.isEmpty, "\(module): expected source key constants")
        if module == "CoreModels" {
            keys.formUnion(AuthCopy.Key.allCases.map(\.rawValue))
            keys.formUnion(playbackKeys)
        }
        let data = try Data(contentsOf: sources.appendingPathComponent("Localizable.xcstrings"))
        let catalog = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        XCTAssertEqual(Set(strings.keys).subtracting(keys), [], "\(module): orphan catalog keys")
        var englishValues: [String: String] = [:]
        for key in keys.sorted() {
            let entry = try XCTUnwrap(strings[key] as? [String: Any], "Missing catalog key: \(key)")
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], "\(key): missing localizations")
            for locale in ["en", "fi"] {
                let translation = try XCTUnwrap(
                    localizations[locale] as? [String: Any],
                    "\(key): missing \(locale)"
                )
                let unit = try XCTUnwrap(
                    translation["stringUnit"] as? [String: Any],
                    "\(key): missing \(locale) string unit"
                )
                XCTAssertEqual(unit["state"] as? String, "translated", "\(key): \(locale) must be translated")
                let value = try XCTUnwrap(unit["value"] as? String, "\(key): missing \(locale) value")
                XCTAssertFalse(
                    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(key): \(locale) value must not be empty"
                )
                if locale == "en" {
                    englishValues[key] = value
                }
            }
        }
        return englishValues
    }

    private func assertLocalized(_ localized: String, key: String, englishValues: [String: String]) throws {
        #if os(Linux)
            XCTAssertEqual(localized, key)
        #else
            XCTAssertEqual(localized, try XCTUnwrap(englishValues[key]), key)
        #endif
    }

    func testScannerChecksCatalogsOutsideCoreNetworking() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "glassfin-catalogs-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let packageCatalog = root.appendingPathComponent(
            "Packages/GlassfinCore/Sources/CoreNetworking/Localizable.xcstrings"
        )
        let appCatalog = root.appendingPathComponent("Apps/Shared/Resources/Localizable.xcstrings")
        try writeCatalog(packageCatalog, fi: ("translated", "fi-translation"))
        try writeCatalog(appCatalog, fi: nil)

        let catalogs = StringCatalogLint.catalogs(at: root)
        XCTAssertEqual(
            catalogs.map { StringCatalogLint.relative($0, root: root) },
            [
                "Apps/Shared/Resources/Localizable.xcstrings",
                "Packages/GlassfinCore/Sources/CoreNetworking/Localizable.xcstrings",
            ]
        )
        let issues = catalogs.flatMap { StringCatalogLint.issues(in: $0, root: root) }
        let appIssues = issues.filter { $0.hasPrefix("Apps/Shared/Resources/Localizable.xcstrings") }
        XCTAssertTrue(appIssues.contains { $0.contains("missing fi") })
        XCTAssertFalse(issues.contains { $0.contains("Sources/CoreNetworking/Localizable.xcstrings") })
    }

    func testCatalogLintRejectsMissingOrUntranslatedLocales() throws {
        let missingFinnish = try catalog(en: ("translated", "Hello"), fi: nil)
        XCTAssertFalse(StringCatalogLint.issues(data: missingFinnish, file: "Missing.xcstrings").isEmpty)

        let needsReview = try catalog(en: ("translated", "Hello"), fi: ("needs_review", "fi-translation"))
        let reviewIssues = StringCatalogLint.issues(data: needsReview, file: "Review.xcstrings")
        XCTAssertTrue(reviewIssues.contains { $0.contains("fi") && $0.contains("needs_review") })

        let newEnglish = try catalog(en: ("new", "Hello"), fi: ("translated", "fi-translation"))
        let newIssues = StringCatalogLint.issues(data: newEnglish, file: "New.xcstrings")
        XCTAssertTrue(newIssues.contains { $0.contains("en") && $0.contains("new") })

        let emptyValue = try catalog(en: ("translated", "Hello"), fi: ("translated", ""))
        let emptyIssues = StringCatalogLint.issues(data: emptyValue, file: "Empty.xcstrings")
        XCTAssertTrue(emptyIssues.contains { $0.contains("empty") })

        let wrongSource = try catalog(
            sourceLanguage: "fi",
            en: ("translated", "Hello"),
            fi: ("translated", "fi-translation")
        )
        let sourceIssues = StringCatalogLint.issues(data: wrongSource, file: "Source.xcstrings")
        XCTAssertTrue(sourceIssues.contains { $0.contains("sourceLanguage") })

        let ok = try catalog(en: ("translated", "Hello"), fi: ("translated", "fi-translation"))
        XCTAssertEqual(StringCatalogLint.issues(data: ok, file: "Ok.xcstrings"), [])
    }

    func testCatalogLintRejectsEmptyStringsTable() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "sourceLanguage": "en",
            "strings": [:],
            "version": "1.0",
        ])
        XCTAssertEqual(
            StringCatalogLint.issues(data: data, file: "Empty.xcstrings"),
            ["Empty.xcstrings: strings table has no keys"]
        )
    }

    func testCatalogLintRejectsWhitespaceOnlyValues() throws {
        for locale in ["en", "fi"] {
            let whitespace = " \t\r\n\u{00A0}"
            let data = try catalog(
                en: ("translated", locale == "en" ? whitespace : "Hello"),
                fi: ("translated", locale == "fi" ? whitespace : "fi-translation")
            )
            XCTAssertEqual(
                StringCatalogLint.issues(data: data, file: "Whitespace.xcstrings"),
                ["Whitespace.xcstrings: key \"Hello\" locale \(locale) value is empty"]
            )
        }
    }

    func testCatalogLintChecksEveryPluralVariation() throws {
        let json = """
            {
              "sourceLanguage": "en",
              "strings": {
                "items": {
                  "localizations": {
                    "en": {
                      "variations": {
                        "plural": {
                          "one": { "stringUnit": { "state": "translated", "value": "One" } },
                          "other": { "stringUnit": { "state": "new", "value": "Other" } }
                        }
                      }
                    },
                    "fi": {
                      "variations": {
                        "plural": {
                          "one": { "stringUnit": { "state": "translated", "value": "One fi" } },
                          "other": { "stringUnit": { "state": "translated", "value": "Other fi" } }
                        }
                      }
                    }
                  }
                }
              },
              "version": "1.0"
            }
            """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let issues = StringCatalogLint.issues(data: data, file: "Plural.xcstrings")
        XCTAssertTrue(issues.contains { $0.contains("en") && $0.contains("new") })
    }

    private func catalog(
        sourceLanguage: String = "en",
        en: (String, String)?,
        fi: (String, String)?
    ) throws -> Data {
        var localizations: [String: Any] = [:]
        if let en {
            localizations["en"] = ["stringUnit": ["state": en.0, "value": en.1]]
        }
        if let fi {
            localizations["fi"] = ["stringUnit": ["state": fi.0, "value": fi.1]]
        }
        let root: [String: Any] = [
            "sourceLanguage": sourceLanguage,
            "strings": [
                "Hello": [
                    "localizations": localizations
                ]
            ],
            "version": "1.0",
        ]
        return try JSONSerialization.data(withJSONObject: root)
    }

    private func writeCatalog(_ url: URL, fi: (String, String)?) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try catalog(en: ("translated", "Hello"), fi: fi).write(to: url)
    }
}

private enum StringCatalogLint {
    /// Every `*.xcstrings` under `root` (Packages, Apps, and the rest of the repo).
    static func catalogs(at root: URL) -> [URL] {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }
        let skip: Set<String> = [".build", "checkouts", "DerivedData"]
        var found: [URL] = []
        for case let url as URL in enumerator {
            if skip.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            if url.pathExtension == "xcstrings" {
                found.append(url)
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    static func issues(in url: URL, root: URL) -> [String] {
        let file = relative(url, root: root)
        guard let data = try? Data(contentsOf: url) else {
            return ["\(file): unreadable"]
        }
        return issues(data: data, file: file)
    }

    static func issues(data: Data, file: String) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["\(file): invalid JSON"]
        }
        var issues: [String] = []
        if (object["sourceLanguage"] as? String) != "en" {
            issues.append("\(file): sourceLanguage must be en")
        }
        guard let strings = object["strings"] as? [String: Any] else {
            issues.append("\(file): missing strings table")
            return issues
        }
        if strings.isEmpty {
            issues.append("\(file): strings table has no keys")
        }
        for key in strings.keys.sorted() {
            guard let entry = strings[key] as? [String: Any] else {
                issues.append("\(file): key \"\(key)\" is not an object")
                continue
            }
            guard let localizations = entry["localizations"] as? [String: Any] else {
                issues.append("\(file): key \"\(key)\" is missing en")
                issues.append("\(file): key \"\(key)\" is missing fi")
                continue
            }
            for locale in ["en", "fi"] {
                guard let localeObject = localizations[locale] else {
                    issues.append("\(file): key \"\(key)\" is missing \(locale)")
                    continue
                }
                let units = stringUnits(in: localeObject)
                if units.isEmpty {
                    issues.append("\(file): key \"\(key)\" locale \(locale) has no translation")
                    continue
                }
                for unit in units {
                    if unit.state != "translated" {
                        issues.append(
                            "\(file): key \"\(key)\" locale \(locale) state is \"\(unit.state)\", expected translated"
                        )
                    }
                    if unit.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        issues.append("\(file): key \"\(key)\" locale \(locale) value is empty")
                    }
                }
            }
        }
        return issues
    }

    private static func stringUnits(in object: Any) -> [(state: String, value: String)] {
        var found: [(state: String, value: String)] = []
        func walk(_ value: Any) {
            if let dict = value as? [String: Any] {
                if let state = dict["state"] as? String, let text = dict["value"] as? String {
                    found.append((state, text))
                }
                for (key, child) in dict where key != "state" && key != "value" {
                    walk(child)
                }
                return
            }
            if let array = value as? [Any] {
                for child in array {
                    walk(child)
                }
            }
        }
        walk(object)
        return found
    }

    static func relative(_ url: URL, root: URL) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        return path
    }
}

private func repositoryRoot(file: String = #filePath) -> URL? {
    var url = URL(fileURLWithPath: file).deletingLastPathComponent()
    let fileManager = FileManager.default
    while url.path != "/" {
        let license = url.appendingPathComponent("LICENSE")
        let package = url.appendingPathComponent("Packages/GlassfinCore")
        if fileManager.fileExists(atPath: license.path) && fileManager.fileExists(atPath: package.path) {
            return url
        }
        url.deleteLastPathComponent()
    }
    return nil
}
