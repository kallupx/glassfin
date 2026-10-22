import CoreModels
import Foundation

/// Q8-2-03, recorded for M08b. This prototype does not open a loopback server (Q8-2-01).
public enum LoopbackRemuxContract {
    public static let owner = "M08b"
    public static let listensOnEphemeralPort = true
    public static let stopsWhenPlaybackEnds = true
    public static let stopsWhenAppBackgrounds = true
    public static let allowedMethods = ["GET", "HEAD"]

    public static func allowsBindHost(_ host: String) -> Bool {
        host == "127.0.0.1" || host == "::1"
    }

    public static func allows(method: String, mediaID: String, knownMediaIDs: Set<String>) -> Bool {
        guard allowedMethods.contains(method) else { return false }
        guard ItemID(mediaID) != nil else { return false }
        return knownMediaIDs.contains(mediaID)
    }

    /// `http://127.0.0.1:<port>/<token>/<mediaID>/index.m3u8` with no Jellyfin credential.
    public static func playerURL(port: Int, pathToken: String, mediaID: String) -> URL? {
        guard allowsBindHost("127.0.0.1") else { return nil }
        guard LoopbackPathToken.isValid(pathToken) else { return nil }
        guard ItemID(mediaID) != nil else { return nil }
        guard (1...65_535).contains(port) else { return nil }
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = port
        components.path = "/\(pathToken)/\(mediaID)/index.m3u8"
        guard let url = components.url, !MediaCredentialQuery.contains(url) else { return nil }
        return url
    }
}

public enum LoopbackPathToken {
    public static func make(bytes: [UInt8]) -> String? {
        guard bytes.count == 16 else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    public static func isValid(_ token: String) -> Bool {
        token.count == 32 && token.allSatisfy(\.isHexDigit)
    }

    /// Compares 32 hex characters in a fixed number of steps.
    public static func equals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        var diff: UInt8 = 0
        for index in 0..<32 {
            let l: UInt8 = index < left.count ? left[index] : 0
            let r: UInt8 = index < right.count ? right[index] : 0
            diff |= l ^ r
        }
        if left.count != 32 || right.count != 32 {
            diff |= 1
        }
        return diff == 0
    }
}
