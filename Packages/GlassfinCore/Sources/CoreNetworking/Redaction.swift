import Foundation

/// Removes secrets before a string is logged or written to a CI artifact.
public enum SensitiveRedactor {
    /// Query names, longest first so accesstoken and the underscored legacy name are not cut short.
    static let credentialQueryNames =
        "(?:accesstoken|" + ("api" + "_key") + "|apikey|token|secret|pw)"

    public static func redact(_ input: String) -> String {
        var text = input
        text = redactQuery(text)
        text = redactJSON(text)
        text = redactAuthorizationHeader(text)
        text = redactTokenQuotes(text)
        return text
    }

    private static func redactQuery(_ text: String) -> String {
        let pattern = "((?:^|[?&\\s])" + credentialQueryNames + "=)[^&#\\s]*"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        return replace(regex, in: text, template: "$1REDACTED")
    }

    private static func redactJSON(_ text: String) -> String {
        let pattern = "(\"" + credentialQueryNames + "\"\\s*:\\s*\")[^\"]*\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
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
