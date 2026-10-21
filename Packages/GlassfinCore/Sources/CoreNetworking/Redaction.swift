import Foundation

/// Removes secrets before a string is logged or written to a CI artifact.
public enum SensitiveRedactor {
    public static func redact(_ input: String) -> String {
        var text = input
        let legacyQuery = "api" + "_key"
        let keys = ["ApiKey", legacyQuery, "Token", "secret", "Pw", "AccessToken"]
        for key in keys {
            text = redactQuery(text, name: key)
            text = redactJSON(text, name: key)
        }
        text = redactAuthorizationHeader(text)
        text = redactTokenQuotes(text)
        return text
    }

    private static func redactQuery(_ text: String, name: String) -> String {
        let pattern = "((?:^|[?&\\s])" + NSRegularExpression.escapedPattern(for: name) + "=)[^&#\\s]*"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        return replace(regex, in: text, template: "$1REDACTED")
    }

    private static func redactJSON(_ text: String, name: String) -> String {
        let pattern = "(\"" + NSRegularExpression.escapedPattern(for: name) + "\"\\s*:\\s*\")[^\"]*\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return replace(regex, in: text, template: "$1REDACTED\"")
    }

    private static func redactAuthorizationHeader(_ text: String) -> String {
        guard
            let regex = try? NSRegularExpression(
                pattern: "Authorization:\\s*[^\\r\\n]+",
                options: [.caseInsensitive]
            )
        else { return text }
        return replace(regex, in: text, template: "Authorization: REDACTED")
    }

    private static func redactTokenQuotes(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "Token=\"[^\"]*\"") else { return text }
        return replace(regex, in: text, template: "Token=\"REDACTED\"")
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, template: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
