import Foundation

public enum AuthorizationHeaderError: Error, Sendable, Equatable {
    case controlCharacter
}

/// MediaBrowser authorization header built by Glassfin, not by jellyfin-sdk-swift.
///
/// jellyfin-sdk-swift 3.3.0 joins raw `key=value` pairs with no quotes and no encoding
/// (S1.6). Official clients (jellyfin-sdk-typescript `encodeURIComponent`, server
/// `GetParts` + `WebUtility.UrlDecode`) require each value to be percent-encoded and
/// wrapped in double quotes. Field order is Client, Device, DeviceId, Version, then
/// Token only after login.
public enum AuthorizationHeader {
    public static func value(
        client: String,
        device: String,
        deviceID: String,
        version: String,
        token: String?
    ) throws -> String {
        var fields: [(String, String)] = [
            ("Client", client),
            ("Device", device),
            ("DeviceId", deviceID),
            ("Version", version),
        ]
        if let token, !token.isEmpty {
            fields.append(("Token", token))
        }
        let encoded = try fields.map { key, raw in
            "\(key)=\"\(try encodeComponent(raw))\""
        }
        return "MediaBrowser " + encoded.joined(separator: ", ")
    }

    /// `encodeURIComponent`: UTF-8 percent-encoding, unreserved plus `!'()*-._~` left intact.
    static func containsRejectedControl(_ raw: String) -> Bool {
        raw.unicodeScalars.contains(where: isRejectedControl)
    }

    static func encodeComponent(_ raw: String) throws -> String {
        if containsRejectedControl(raw) {
            throw AuthorizationHeaderError.controlCharacter
        }
        var allowed = CharacterSet()
        allowed.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        guard let encoded = raw.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw AuthorizationHeaderError.controlCharacter
        }
        return encoded
    }

    private static func isRejectedControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .lineSeparator, .paragraphSeparator:
            return true
        default:
            return scalar.value == 0x7F
        }
    }
}
