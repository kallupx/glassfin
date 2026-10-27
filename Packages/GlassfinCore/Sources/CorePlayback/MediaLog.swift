import CoreModels
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Redacts media URIs before they reach `GlassfinLog` or diagnostics.
///
/// Q8-2-07: values read from `AVPlayerItem.errorLog()` and `accessLog()` use this path.
/// The replacement text is `<redacted>`.
public enum MediaLogRedactor {
    private static let credentialNames =
        "(?:accesstoken|" + ("api" + "_key") + "|apikey|token|x-emby-token|x-mediabrowser-token|secret|pw)"

    /// Redact the raw view first, preserving its spelling whenever possible. Inspect up to
    /// two percent-decoded views, carrying prior redactions forward. If decoding reveals
    /// another credential, emit that redacted decoded view instead of the encoded secret.
    public static func redact(_ input: String) -> String {
        var output = redactView(input)
        var view = output
        for _ in 0..<2 {
            guard let decoded = view.removingPercentEncoding, decoded != view else { break }
            view = redactView(decoded)
            if view != decoded { output = view }
        }
        return output
    }

    private static func redactView(_ input: String) -> String {
        var text = input
        text = redactQuery(text)
        text = redactJSON(text)
        text = redactEncodedQuery(text)
        text = redactAuthorization(text)
        text = redactTokenHeaders(text)
        text = redactTokenQuotes(text)
        return text
    }

    public static func redact(urlError: URLError) -> String {
        let failing = urlError.failingURL?.absoluteString ?? ""
        return "URLError(\(urlError.code.rawValue)) \(redact(failing))"
    }

    private static func redactQuery(_ text: String) -> String {
        let pattern = "((?:^|[?&\\s])" + credentialNames + #"=)(?:"[^"]*"|'[^']*'|[^&#\s"']*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        return replace(regex, in: text, template: "$1<redacted>")
    }

    private static func redactJSON(_ text: String) -> String {
        // Capture the quote delimiter (a normal quote or a backslash-escaped quote).
        // Normal JSON values may themselves contain escaped quotes.
        let pattern = #"((\\?")"# + credentialNames + #"\2\s*:\s*\2)(?:(?!\2)\\.|(?!\2)[^\\])*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        return replace(regex, in: text, template: "$1<redacted>")
    }

    private static func redactEncodedQuery(_ text: String) -> String {
        let pattern = "((?:%26|%3f|[?&])" + credentialNames + #"%3d)(?:(?!%26)[^&#\s"'])*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        return replace(regex, in: text, template: "$1<redacted>")
    }

    private static func redactAuthorization(_ text: String) -> String {
        guard
            let regex = try? NSRegularExpression(
                pattern: "Authorization:\\s*[^\\r\\n]+",
                options: [.caseInsensitive]
            )
        else { return text }
        return replace(regex, in: text, template: "Authorization: <redacted>")
    }

    private static func redactTokenHeaders(_ text: String) -> String {
        guard
            let regex = try? NSRegularExpression(
                pattern: #"(^[\t ]*(?:x-emby-token|x-mediabrowser-token):[\t ]*)[^\r\n]+"#,
                options: [.caseInsensitive, .anchorsMatchLines]
            )
        else { return text }
        return replace(regex, in: text, template: "$1<redacted>")
    }

    private static func redactTokenQuotes(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "Token=\"[^\"]*\"") else { return text }
        return replace(regex, in: text, template: "Token=\"<redacted>\"")
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, template: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

/// Forwards player log URIs through ``MediaLogRedactor`` and never writes the raw value.
public struct PlaybackLog: GlassfinLog {
    public var sink: any GlassfinLog

    public init(sink: any GlassfinLog) {
        self.sink = sink
    }

    public func warning(_ message: String) { sink.warning(MediaLogRedactor.redact(message)) }
    public func debug(_ message: String) { sink.debug(MediaLogRedactor.redact(message)) }
    public func error(_ message: String) { sink.error(MediaLogRedactor.redact(message)) }
}

public enum PlayerLogSink {
    public static func record(_ uris: [String?], log: any GlassfinLog) {
        for uri in uris {
            guard let uri else { continue }
            log.debug(MediaLogRedactor.redact(uri))
        }
    }
}
