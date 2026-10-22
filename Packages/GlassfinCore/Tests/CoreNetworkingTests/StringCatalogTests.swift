import Foundation
import XCTest

final class StringCatalogTests: XCTestCase {
    func testEveryStringCatalogHasTranslatedEnglishAndFinnish() throws {
        let root = try XCTUnwrap(repositoryRoot(), "Repository root not found from \(#filePath)")
        let catalogs = StringCatalogLint.catalogs(at: root)
        XCTAssertFalse(catalogs.isEmpty, "Expected at least one .xcstrings catalog")
        XCTAssertTrue(
            catalogs.contains { $0.path.hasSuffix("Sources/CoreNetworking/Localizable.xcstrings") },
            "CoreNetworking string catalog was not discovered"
        )
        let issues = catalogs.flatMap { StringCatalogLint.issues(in: $0, root: root) }
        XCTAssertEqual(issues, [], issues.joined(separator: "\n"))
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
}

private enum StringCatalogLint {
    static func catalogs(at root: URL) -> [URL] {
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
                    if unit.value.isEmpty {
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

    private static func relative(_ url: URL, root: URL) -> String {
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        if url.path.hasPrefix(prefix) {
            return String(url.path.dropFirst(prefix.count))
        }
        return url.path
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
