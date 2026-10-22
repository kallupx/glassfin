import Foundation

/// Server metadata is shown as plain text. Tags are removed and markup is not rendered.
enum PlainText {
    static func overview(_ source: String) -> String {
        var text = decodeEntities(source)
        text = removeBlocks(text, named: "script")
        text = removeBlocks(text, named: "style")
        text = stripTags(text)
        text = decodeEntities(text)
        if text.contains("<") {
            text = stripTags(text)
        }
        return text
    }

    private static func removeBlocks(_ source: String, named tag: String) -> String {
        var text = source
        let pattern = "(?is)<\(tag)\\b[^>]*>.*?</\(tag)>"
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        text = expression.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        let open = "(?is)<\(tag)\\b[^>]*>.*"
        if let trailing = try? NSRegularExpression(pattern: open) {
            let tailRange = NSRange(text.startIndex..<text.endIndex, in: text)
            text = trailing.stringByReplacingMatches(in: text, range: tailRange, withTemplate: "")
        }
        return text
    }

    private static func stripTags(_ source: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: "<[^>]+>") else {
            return source
        }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        return expression.stringByReplacingMatches(in: source, range: range, withTemplate: "")
    }

    private static func decodeEntities(_ source: String) -> String {
        var text = source
        let named = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&#39;": "'",
        ]
        for (entity, value) in named {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        text = decodeNumeric(text, pattern: "&#x([0-9a-fA-F]+);", radix: 16)
        text = decodeNumeric(text, pattern: "&#([0-9]+);", radix: 10)
        return text
    }

    private static func decodeNumeric(_ source: String, pattern: String, radix: Int) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return source
        }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let matches = expression.matches(in: source, range: range)
        var text = source
        for match in matches.reversed() {
            guard let scalarRange = Range(match.range(at: 1), in: text),
                let whole = Range(match.range, in: text),
                let code = UInt32(text[scalarRange], radix: radix),
                let scalar = Unicode.Scalar(code)
            else {
                continue
            }
            text.replaceSubrange(whole, with: String(Character(scalar)))
        }
        return text
    }
}
