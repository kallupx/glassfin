import Foundation

/// Server names and overviews are plain text. Tags are not rendered.
public enum MetadataSanitizer {
    public static func plainText(_ raw: String) -> String {
        var text = raw
        text = removeElement(text, named: "script")
        text = removeElement(text, named: "style")
        text = removeTags(text)
        let decoded = decodeEntities(text)
        return strippingControlsAndBidi(decoded)
    }

    /// Shared scalar filter for literal metadata and the existing auth sanitizer.
    public static func strippingControlsAndBidi(_ raw: String) -> String {
        MetadataPolicy.clean(raw, limit: raw.count)
    }

    /// S4.7/Q4-16: literal display text, at most 64 extended grapheme clusters.
    public static func displayName(_ raw: String, fallbackHost: String) -> String {
        let plain = plainText(raw)
        let value =
            plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? plainText(fallbackHost) : plain
        return String(value.prefix(MetadataPolicy.displayNameMax))
    }

    private static func removeElement(_ text: String, named tag: String) -> String {
        var result = ""
        var rest = Substring(text)
        let open = "<" + tag
        let close = "</" + tag
        while let start = rest.range(of: open, options: [.caseInsensitive]) {
            let afterName = rest[start.upperBound...]
            guard isTagBoundary(afterName) else {
                result.append(contentsOf: rest[..<start.upperBound])
                rest = afterName
                continue
            }
            result.append(contentsOf: rest[..<start.lowerBound])
            guard let gt = afterName.firstIndex(of: ">") else { return result }
            let afterOpen = rest[rest.index(after: gt)...]
            guard let end = afterOpen.range(of: close, options: [.caseInsensitive]) else { return result }
            let afterCloseName = afterOpen[end.upperBound...]
            guard let closeGt = afterCloseName.firstIndex(of: ">") else { return result }
            rest = afterCloseName[afterCloseName.index(after: closeGt)...]
        }
        result.append(contentsOf: rest)
        return result
    }

    private static func isTagBoundary(_ text: Substring) -> Bool {
        guard let first = text.first else { return false }
        return first == ">" || first == "/" || first.isWhitespace
    }

    private static func removeTags(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "<", looksLikeTag(text, at: index), let end = text[index...].firstIndex(of: ">") {
                index = text.index(after: end)
                continue
            }
            result.append(text[index])
            index = text.index(after: index)
        }
        return result
    }

    private static func looksLikeTag(_ text: String, at index: String.Index) -> Bool {
        let next = text.index(after: index)
        guard next < text.endIndex else { return false }
        let character = text[next]
        return character == "/" || character == "!" || character.isLetter
    }

    private static func decodeEntities(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "&" {
                var cursor = text.index(after: index)
                var steps = 0
                var end: String.Index?
                while cursor < text.endIndex && steps < 32 {
                    if text[cursor] == ";" {
                        end = cursor
                        break
                    }
                    cursor = text.index(after: cursor)
                    steps += 1
                }
                if let end {
                    let body = String(text[text.index(after: index)..<end])
                    if let decoded = entity(body) {
                        result.append(decoded)
                        index = text.index(after: end)
                        continue
                    }
                }
            }
            result.append(text[index])
            index = text.index(after: index)
        }
        return result
    }

    private static func entity(_ body: String) -> String? {
        switch body {
        case "amp":
            return "&"
        case "lt":
            return "<"
        case "gt":
            return ">"
        case "quot":
            return "\""
        case "apos":
            return "'"
        case "nbsp":
            return "\u{00A0}"
        default:
            break
        }
        let value: UInt32?
        if body.hasPrefix("#x") || body.hasPrefix("#X") {
            value = UInt32(body.dropFirst(2), radix: 16)
        } else if body.hasPrefix("#") {
            value = UInt32(body.dropFirst(), radix: 10)
        } else {
            value = nil
        }
        guard let value, let scalar = Unicode.Scalar(value) else { return nil }
        return String(Character(scalar))
    }
}
