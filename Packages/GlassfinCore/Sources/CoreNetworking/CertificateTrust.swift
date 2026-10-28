import CoreModels
import Foundation

public struct CertificatePresentation: Sendable, Equatable {
    public var sha256: String
    public var subject: String
    public var notBefore: Date
    public var notAfter: Date

    public init(sha256: String, subject: String, notBefore: Date, notAfter: Date) {
        self.sha256 = sha256
        self.subject = subject
        self.notBefore = notBefore
        self.notAfter = notAfter
    }
}

/// A pin authorizes only the HTTPS origin where its certificate was presented.
public struct OriginCertificatePin: Sendable, Equatable {
    public let url: URL
    public let sha256: String

    public init(url: URL, sha256: String) {
        self.url = url
        self.sha256 = sha256
    }

    public func fingerprint(for target: URL) -> String? {
        guard target.scheme?.lowercased() == "https", RedirectPolicy.originsMatch(url, target),
            CertificateFingerprint.isValid(sha256)
        else { return nil }
        return sha256
    }
}

public enum ServerTrustDecision: Sendable, Equatable {
    /// CA-validated certificates are not pinned, so a renewed public certificate still connects.
    case performDefaultHandling
    case usePinnedCredential
    case cancelUntrusted
    case cancelPinMismatch(previous: String, presented: CertificatePresentation)
}

public enum CertificateFingerprint {
    public static func sha256Hex(_ data: Data) -> String {
        SHA256Digest.hex(Array(data))
    }

    public static func normalize(_ raw: String) -> String {
        String(raw.lowercased().filter(\.isHexDigit))
    }

    public static func isValid(_ raw: String) -> Bool {
        raw.count == 64 && raw.allSatisfy(\.isHexDigit)
    }
}

public protocol CertificatePinStore: Sendable {
    /// Nil means no pin is configured. Unreadable or invalid stored pins must throw.
    func fingerprint(for serverID: String) throws -> String?
    func save(fingerprint: String, serverID: String) throws
    func remove(serverID: String) throws
}

extension CertificatePinStore {
    /// Resolve trust before constructing a client; a failed lookup must never become an unpinned session.
    public func certificatePin(for serverID: String, url: URL) throws(APIError) -> OriginCertificatePin? {
        do {
            guard let fingerprint = try fingerprint(for: serverID) else { return nil }
            guard CertificateFingerprint.isValid(fingerprint) else { throw APIError.tls }
            return OriginCertificatePin(url: url, sha256: fingerprint)
        } catch {
            throw .tls
        }
    }
}

/// Fingerprint only. M02's server list can read `certificate-pin.<serverID>`.
public struct SettingsCertificatePinStore: CertificatePinStore {
    public var settings: any SettingsStore

    public init(settings: any SettingsStore) {
        self.settings = settings
    }

    public func fingerprint(for serverID: String) throws -> String? {
        let key = Self.key(serverID)
        guard let fingerprint = settings.string(forKey: key) else {
            guard !settings.containsValue(forKey: key) else { throw SecurityInvariantError.internalInvariant }
            return nil
        }
        guard CertificateFingerprint.isValid(fingerprint) else { throw SecurityInvariantError.internalInvariant }
        return fingerprint
    }

    public func save(fingerprint: String, serverID: String) throws {
        let normalized = CertificateFingerprint.normalize(fingerprint)
        guard CertificateFingerprint.isValid(normalized) else { throw SecurityInvariantError.internalInvariant }
        settings.set(normalized, forKey: Self.key(serverID))
    }

    public func remove(serverID: String) throws {
        settings.set(nil, forKey: Self.key(serverID))
    }

    public static func key(_ serverID: String) -> String {
        "certificate-pin.\(serverID)"
    }
}

public enum SelfSignedTrustFlow {
    public struct Outcome: Sendable, Equatable {
        public var decision: ServerTrustDecision
        public var pinToStore: String?

        public init(decision: ServerTrustDecision, pinToStore: String?) {
            self.decision = decision
            self.pinToStore = pinToStore
        }
    }

    /// Mockable trust decision. A system-trusted leaf is never pinned.
    ///
    /// `userAcceptedFingerprint` is the fingerprint the user confirmed in the dialog.
    /// The pin is stored only when that value normalizes to the presented leaf.
    /// A boolean acceptance is not enough: confirming B while the connection presents C cancels.
    public static func handle(
        isSystemTrusted: Bool,
        leaf: CertificatePresentation,
        pinnedSHA256: String?,
        userAcceptedFingerprint: String?
    ) -> Outcome {
        if isSystemTrusted {
            return Outcome(decision: .performDefaultHandling, pinToStore: nil)
        }
        let leafHex = CertificateFingerprint.normalize(leaf.sha256)
        let pinned = pinnedSHA256.map(CertificateFingerprint.normalize)
        let hasPin = pinned.map { !$0.isEmpty } ?? false
        if hasPin, let pinned, pinned == leafHex, CertificateFingerprint.isValid(leafHex) {
            return Outcome(decision: .usePinnedCredential, pinToStore: nil)
        }
        if accepted(userAcceptedFingerprint, matches: leafHex) {
            return Outcome(decision: .usePinnedCredential, pinToStore: leafHex)
        }
        if hasPin, let pinned {
            return Outcome(
                decision: .cancelPinMismatch(previous: pinned, presented: leaf),
                pinToStore: nil
            )
        }
        return Outcome(decision: .cancelUntrusted, pinToStore: nil)
    }

    /// Case and separators (`:` and spaces) are ignored. The stored pin is lowercase hex.
    private static func accepted(_ userAcceptedFingerprint: String?, matches leafHex: String) -> Bool {
        guard CertificateFingerprint.isValid(leafHex) else { return false }
        guard let raw = userAcceptedFingerprint else { return false }
        return CertificateFingerprint.normalize(raw) == leafHex
    }
}

/// Local SHA-256 so certificate tests run on Linux. TODO: replace with swift-crypto.
enum SHA256Digest {
    static func hex(_ message: [UInt8]) -> String {
        hash(message).map { String(format: "%02x", $0) }.joined()
    }

    static func hash(_ message: [UInt8]) -> [UInt8] {
        var hash: [UInt32] = [
            0x6a09_e667, 0xbb67_ae85, 0x3c6e_f372, 0xa54f_f53a,
            0x510e_527f, 0x9b05_688c, 0x1f83_d9ab, 0x5be0_cd19,
        ]
        var bytes = message
        let bitLength = UInt64(message.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 {
            bytes.append(0)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }
        for chunkStart in stride(from: 0, to: bytes.count, by: 64) {
            var words = [UInt32](repeating: 0, count: 64)
            for index in 0..<16 {
                let offset = chunkStart + index * 4
                words[index] =
                    (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16)
                    | (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
            }
            for index in 16..<64 {
                let s0 = rotr(words[index - 15], 7) ^ rotr(words[index - 15], 18) ^ (words[index - 15] >> 3)
                let s1 = rotr(words[index - 2], 17) ^ rotr(words[index - 2], 19) ^ (words[index - 2] >> 10)
                words[index] = words[index - 16] &+ s0 &+ words[index - 7] &+ s1
            }
            var a = hash[0]
            var b = hash[1]
            var c = hash[2]
            var d = hash[3]
            var e = hash[4]
            var f = hash[5]
            var g = hash[6]
            var h = hash[7]
            for index in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let choice = (e & f) ^ (~e & g)
                let temp1 = h &+ s1 &+ choice &+ constants[index] &+ words[index]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temp2 = s0 &+ majority
                h = g
                g = f
                f = e
                e = d &+ temp1
                d = c
                c = b
                b = a
                a = temp1 &+ temp2
            }
            hash[0] = hash[0] &+ a
            hash[1] = hash[1] &+ b
            hash[2] = hash[2] &+ c
            hash[3] = hash[3] &+ d
            hash[4] = hash[4] &+ e
            hash[5] = hash[5] &+ f
            hash[6] = hash[6] &+ g
            hash[7] = hash[7] &+ h
        }
        var out: [UInt8] = []
        out.reserveCapacity(32)
        for value in hash {
            out.append(UInt8((value >> 24) & 0xff))
            out.append(UInt8((value >> 16) & 0xff))
            out.append(UInt8((value >> 8) & 0xff))
            out.append(UInt8(value & 0xff))
        }
        return out
    }

    private static func rotr(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value >> count) | (value << (32 - count))
    }

    private static let constants: [UInt32] = [
        0x428a_2f98, 0x7137_4491, 0xb5c0_fbcf, 0xe9b5_dba5,
        0x3956_c25b, 0x59f1_11f1, 0x923f_82a4, 0xab1c_5ed5,
        0xd807_aa98, 0x1283_5b01, 0x2431_85be, 0x550c_7dc3,
        0x72be_5d74, 0x80de_b1fe, 0x9bdc_06a7, 0xc19b_f174,
        0xe49b_69c1, 0xefbe_4786, 0x0fc1_9dc6, 0x240c_a1cc,
        0x2de9_2c6f, 0x4a74_84aa, 0x5cb0_a9dc, 0x76f9_88da,
        0x983e_5152, 0xa831_c66d, 0xb003_27c8, 0xbf59_7fc7,
        0xc6e0_0bf3, 0xd5a7_9147, 0x06ca_6351, 0x1429_2967,
        0x27b7_0a85, 0x2e1b_2138, 0x4d2c_6dfc, 0x5338_0d13,
        0x650a_7354, 0x766a_0abb, 0x81c2_c92e, 0x9272_2c85,
        0xa2bf_e8a1, 0xa81a_664b, 0xc24b_8b70, 0xc76c_51a3,
        0xd192_e819, 0xd699_0624, 0xf40e_3585, 0x106a_a070,
        0x19a4_c116, 0x1e37_6c08, 0x2748_774c, 0x34b0_bcb5,
        0x391c_0cb3, 0x4ed8_aa4a, 0x5b9c_ca4f, 0x682e_6ff3,
        0x748f_82ee, 0x78a5_636f, 0x84c8_7814, 0x8cc7_0208,
        0x90be_fffa, 0xa450_6ceb, 0xbef9_a3f7, 0xc671_78f2,
    ]
}
