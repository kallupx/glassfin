import Foundation

/// Writes a certificate pin only from ``SelfSignedTrustFlow/Outcome/pinToStore``.
/// The fingerprint the user typed is never stored on its own.
public struct CertificateAcceptanceCoordinator: Sendable {
    public var pins: any CertificatePinStore

    public init(pins: any CertificatePinStore) {
        self.pins = pins
    }

    public func apply(
        isSystemTrusted: Bool,
        leaf: CertificatePresentation,
        pinnedSHA256: String?,
        userAcceptedFingerprint: String?,
        serverID: String
    ) throws -> SelfSignedTrustFlow.Outcome {
        let outcome = SelfSignedTrustFlow.handle(
            isSystemTrusted: isSystemTrusted,
            leaf: leaf,
            pinnedSHA256: pinnedSHA256,
            userAcceptedFingerprint: userAcceptedFingerprint
        )
        if let pin = outcome.pinToStore {
            try pins.save(fingerprint: pin, serverID: serverID)
        }
        return outcome
    }
}
