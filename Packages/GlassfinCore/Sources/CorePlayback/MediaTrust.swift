import Foundation

/// How playback should treat the server certificate.
///
/// M03 (PR #5, not on main) owns the pin store. Callers pass the fingerprint that store
/// would return from `CertificatePinStore.fingerprint(for:)`. AVPlayer never sees that store:
/// only the resource loader's `URLSession` can apply it.
public enum ServerTrustClass: Sendable, Equatable {
    /// CA-validated HTTPS. AVPlayer's own stack can verify it. Do not pin.
    case publiclyTrusted
    /// HTTP. No certificate is presented. ATS local networking still applies.
    case cleartext
    /// User accepted this SHA-256 leaf fingerprint for the server (S4.4).
    case pinnedSelfSigned(fingerprintSHA256: String)
    /// Self-signed, and the user has not pinned it. Playback must not start.
    case unpinnedSelfSigned
}

public enum PinnedTrustVerdict: Sendable, Equatable {
    /// Let the system evaluate a public CA chain.
    case performDefaultHandling
    /// The observed leaf matches the pin. Use that credential.
    case allowPinned
    /// Refuse the challenge. Do not accept an arbitrary self-signed certificate.
    case cancel
}

public enum PinnedTrustGate {
    public static func decide(trust: ServerTrustClass, observedFingerprintSHA256: String?) -> PinnedTrustVerdict {
        switch trust {
        case .publiclyTrusted:
            return .performDefaultHandling
        case .cleartext, .unpinnedSelfSigned:
            return .cancel
        case .pinnedSelfSigned(let expected):
            guard let observed = observedFingerprintSHA256,
                let expectedHex = normalizeFingerprint(expected),
                let observedHex = normalizeFingerprint(observed),
                expectedHex == observedHex
            else {
                return .cancel
            }
            return .allowPinned
        }
    }

    /// Lowercase hex, separators removed. `nil` unless the result is 64 hex digits.
    public static func normalizeFingerprint(_ raw: String) -> String? {
        let hex = raw.lowercased().filter(\.isHexDigit)
        guard hex.count == 64 else { return nil }
        return hex
    }
}
