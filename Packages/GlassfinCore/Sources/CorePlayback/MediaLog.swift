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
    public static func redact(_ input: String) -> String {
        var text = input
        text = redactQuery(text)
        text = redactJSON(text)
        text = redactEncodedQuery(text)
        text = redactAuthorization(text)
        text = redactTokenQuotes(text)
        return text
    }

    public static func redact(urlError: URLError) -> String {
        let failing = urlError.failingURL?.absoluteString ?? ""
        return "URLError(\(urlError.code.rawValue)) \(redact(failing))"
    }

    private static func redactQuery(_ text: String) -> String {
        let names = "(?:accesstoken|" + ("api" + "_key") + "|apikey|token|secret|pw)"
        let pattern = "((?:^|[?&\\s])" + names + "=)[^&#\\s]*"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        return replace(regex, in: text, template: "$1<redacted>")
    }

    private static func redactJSON(_ text: String) -> String {
        let names = "(?:apikey|" + ("api" + "_key") + "|accesstoken|token)"
        let pattern = "(\"" + names + #""\s*:\s*")"# + #"(?:\\.|[^"\\])*"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        return replace(regex, in: text, template: "$1<redacted>")
    }

    private static func redactEncodedQuery(_ text: String) -> String {
        let names = "(?:apikey|" + ("api" + "_key") + "|accesstoken|token)"
        let pattern = "((?:%26|%3f)" + names + #"%3d)(?:(?!%26)[^&#\s"'])*"#
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
