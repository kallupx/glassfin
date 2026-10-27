import CoreModels
import Foundation

/// S4.3. Public HTTP is rejected. HTTP is allowed for private addresses and local hostnames, and stays marked unencrypted.
public enum ServerTransportPolicy {
    public enum Verdict: Sendable, Equatable {
        case secure
        case unencryptedLocal
        case publicHTTPRejected
        case invalid
    }

    public static var unencryptedWarning: String { AuthCopy.localized(.connectionNotEncrypted) }
    public static var publicAddressRequiresHTTPS: String { AuthCopy.localized(.publicAddressRequiresHTTPS) }

    public static func messageKey(for verdict: Verdict) -> AuthCopy.Key? {
        switch verdict {
        case .unencryptedLocal: .connectionNotEncrypted
        case .publicHTTPRejected: .publicAddressRequiresHTTPS
        case .secure, .invalid: nil
        }
    }

    public static func evaluate(_ url: URL) -> Verdict {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .invalid
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else { return .invalid }
        if scheme == "https" { return .secure }
        if isLocal(host) { return .unencryptedLocal }
        return .publicHTTPRejected
    }

    public static func showsUnencryptedMark(_ url: URL) -> Bool {
        evaluate(url) == .unencryptedLocal
    }

    public static func message(for verdict: Verdict) -> String? {
        switch verdict {
        case .unencryptedLocal:
            return unencryptedWarning
        case .publicHTTPRejected:
            return publicAddressRequiresHTTPS
        case .secure, .invalid:
            return nil
        }
    }

    public static func badge(for url: URL) -> ServerSecurityBadge {
        let verdict = evaluate(url)
        return ServerSecurityBadge(
            showsUnencryptedMark: verdict == .unencryptedLocal, messageKey: messageKey(for: verdict))
    }

    enum HostClass: Sendable, Equatable {
        case privateAddress
        case publicAddress
        case localHostname
        case publicHostname
    }

    static func isLocal(_ host: String) -> Bool {
        switch hostClass(host) {
        case .privateAddress, .localHostname:
            return true
        case .publicAddress, .publicHostname:
            return false
        }
    }

    /// Classifies the literal host string. DNS is never consulted, so a name that would
    /// resolve to a private address stays a hostname.
    ///
    /// An IPv4 literal is accepted only as four decimal octets with no leading zeros.
    /// A single-label name is not local when it is all digits (decimal or leading-zero octal)
    /// or `0x` plus hex. Hex without that prefix, such as `7f000001`, is an ordinary hostname
    /// and may stay local. `.local` and other single-label names are accepted by name (S4.3, known risk).
    static func hostClass(_ host: String) -> HostClass {
        var trimmed = host.lowercased()
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
            trimmed.removeFirst()
            trimmed.removeLast()
        }
        if trimmed.isEmpty { return .publicHostname }
        if trimmed.contains(":") {
            guard let groups = canonicalIPv6(trimmed) else { return .publicAddress }
            return isPrivateIPv6(groups) ? .privateAddress : .publicAddress
        }
        let hadTrailingDot = trimmed.hasSuffix(".")
        var bare = trimmed
        while bare.hasSuffix(".") { bare.removeLast() }
        if bare.isEmpty { return .publicHostname }
        if isNumericIPv4Attempt(bare) {
            if hadTrailingDot { return .publicAddress }
            guard let octets = canonicalIPv4(bare) else { return .publicAddress }
            return isPrivateIPv4(octets) ? .privateAddress : .publicAddress
        }
        if bare == "localhost" || bare.hasSuffix(".local") || (!bare.contains(".") && !bare.contains(":")) {
            return .localHostname
        }
        return .publicHostname
    }

    /// Decimal digits, a leading-zero octal component, or a `0x` hex component.
    private static func isNumericIPv4Attempt(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.contains(where: { !$0.isEmpty }) else { return false }
        return parts.allSatisfy { part in
            if part.isEmpty { return false }
            if part.hasPrefix("0x") {
                let digits = part.dropFirst(2)
                return !digits.isEmpty && digits.allSatisfy(\.isHexDigit)
            }
            return part.allSatisfy { $0.isASCII && $0.isNumber }
        }
    }

    /// Four decimal octets, no leading zeros. Hex, short forms, and integer forms are not addresses.
    private static func canonicalIPv4(_ host: String) -> [UInt8]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var octets: [UInt8] = []
        for part in parts {
            if part.isEmpty || part.count > 3 { return nil }
            if part.count > 1 && part.hasPrefix("0") { return nil }
            guard part.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(part), (0...255).contains(value)
            else { return nil }
            octets.append(UInt8(value))
        }
        return octets
    }

    private static func isPrivateIPv4(_ octets: [UInt8]) -> Bool {
        switch octets[0] {
        case 127, 10:
            return true
        case 172:
            return (16...31).contains(Int(octets[1]))
        case 192:
            return octets[1] == 168
        case 169:
            return octets[1] == 254
        case 100:
            return (64...127).contains(Int(octets[1]))
        default:
            return false
        }
    }

    /// Eight hextets. Only an IPv4-mapped address (`::ffff:0:0/96`) is classified with the IPv4 rules.
    private static func canonicalIPv6(_ host: String) -> [UInt16]? {
        var text = host
        if text.hasPrefix("["), text.hasSuffix("]") {
            text.removeFirst()
            text.removeLast()
        }
        if let zone = text.firstIndex(of: "%") {
            text = String(text[..<zone])
        }
        var ipv4: [UInt8]?
        if text.contains(".") {
            guard let colon = text.lastIndex(of: ":") else { return nil }
            let tail = String(text[text.index(after: colon)...])
            guard let octets = canonicalIPv4(tail) else { return nil }
            ipv4 = octets
            let head = text[..<colon]
            // `::192.168.1.1` loses one colon of the compression marker when the tail is removed.
            text = head.hasSuffix(":") ? head + ":" : String(head)
        }
        let groups: [UInt16]
        if text.contains("::") {
            let sides = text.components(separatedBy: "::")
            guard sides.count == 2, let left = hextets(sides[0]), let right = hextets(sides[1]) else { return nil }
            let tailCount = right.count + (ipv4 == nil ? 0 : 2)
            guard left.count + tailCount < 8 else { return nil }
            let zeros = 8 - left.count - right.count - (ipv4 == nil ? 0 : 2)
            groups = left + Array(repeating: 0, count: zeros) + right
        } else {
            guard let all = hextets(text) else { return nil }
            let expected = 8 - (ipv4 == nil ? 0 : 2)
            guard all.count == expected else { return nil }
            groups = all
        }
        var full = groups
        if let ipv4 {
            full.append(UInt16(ipv4[0]) << 8 | UInt16(ipv4[1]))
            full.append(UInt16(ipv4[2]) << 8 | UInt16(ipv4[3]))
        }
        guard full.count == 8 else { return nil }
        return full
    }

    private static func hextets(_ text: String) -> [UInt16]? {
        if text.isEmpty { return [] }
        var out: [UInt16] = []
        for part in text.split(separator: ":", omittingEmptySubsequences: false) {
            if part.isEmpty || part.count > 4 { return nil }
            guard part.allSatisfy(\.isHexDigit), let value = UInt16(part, radix: 16) else { return nil }
            out.append(value)
        }
        return out
    }

    private static func isPrivateIPv6(_ groups: [UInt16]) -> Bool {
        if isIPv4Mapped(groups) {
            return isPrivateIPv4(embeddedIPv4(groups))
        }
        if groups == [0, 0, 0, 0, 0, 0, 0, 1] { return true }
        // S4.3: IPv4-compatible ::/96 and NAT64 64:ff9b::/96 stay public, whatever address they embed.
        if isIPv4Compatible(groups) || isNAT64(groups) { return false }
        if groups[0] & 0xffc0 == 0xfe80 { return true }
        if groups[0] & 0xfe00 == 0xfc00 { return true }
        return false
    }

    /// `::ffff:0:0/96`, including the hex form `::ffff:808:808`.
    private static func isIPv4Mapped(_ groups: [UInt16]) -> Bool {
        groups[0] == 0 && groups[1] == 0 && groups[2] == 0 && groups[3] == 0 && groups[4] == 0 && groups[5] == 0xffff
    }

    /// Deprecated `::/96` IPv4-compatible addresses, such as `::192.168.1.1`.
    private static func isIPv4Compatible(_ groups: [UInt16]) -> Bool {
        groups[0] == 0 && groups[1] == 0 && groups[2] == 0 && groups[3] == 0 && groups[4] == 0 && groups[5] == 0
    }

    /// Well-known NAT64 prefix `64:ff9b::/96`.
    private static func isNAT64(_ groups: [UInt16]) -> Bool {
        groups[0] == 0x0064 && groups[1] == 0xff9b && groups[2] == 0 && groups[3] == 0 && groups[4] == 0
            && groups[5] == 0
    }

    private static func embeddedIPv4(_ groups: [UInt16]) -> [UInt8] {
        [
            UInt8(groups[6] >> 8), UInt8(groups[6] & 0xff), UInt8(groups[7] >> 8), UInt8(groups[7] & 0xff),
        ]
    }
}

public struct ServerSecurityBadge: Sendable, Equatable {
    public var showsUnencryptedMark: Bool
    public var messageKey: AuthCopy.Key?

    public var message: String? { messageKey.map(AuthCopy.localized) }

    public init(showsUnencryptedMark: Bool, messageKey: AuthCopy.Key?) {
        self.showsUnencryptedMark = showsUnencryptedMark
        self.messageKey = messageKey
    }
}

/// S4.5. http(s) only, userinfo rejected, dot segments collapsed, query and fragment removed.
public enum ServerAddress {
    public static func canonical(_ raw: URL) throws -> URL {
        let normalized = try ServerURLNormalizer.normalize(raw)
        guard var components = URLComponents(url: normalized, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.fragment = nil
        components.query = nil
        components.path = normalizePath(components.path)
        guard let url = components.url, url.host != nil else { throw APIError.invalidURL }
        return url
    }

    static func normalizePath(_ path: String) -> String {
        let trailing = path.count > 1 && path.hasSuffix("/")
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        var stack: [Substring] = []
        for part in parts {
            if part == "." { continue }
            if part == ".." {
                if !stack.isEmpty { stack.removeLast() }
                continue
            }
            stack.append(part)
        }
        if stack.isEmpty { return path.isEmpty ? "" : "/" }
        var result = "/" + stack.joined(separator: "/")
        if trailing { result.append("/") }
        return result
    }
}
