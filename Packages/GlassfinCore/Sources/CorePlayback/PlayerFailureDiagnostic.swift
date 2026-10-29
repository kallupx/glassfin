import Foundation

/// A public-log-safe error summary. Never formats NSError descriptions or userInfo.
public struct PlayerFailureDiagnostic: Sendable, Equatable, CustomStringConvertible {
    public let description: String

    public init(error: NSError?) {
        guard let error else {
            description = "AVPlayer failure: item error unavailable"
            return
        }
        var entries: [String] = []
        var current: NSError? = error
        var seen: Set<ObjectIdentifier> = []
        while let value = current, entries.count < 5, seen.insert(ObjectIdentifier(value)).inserted {
            // Error domains are strings too: only known framework constants can go public.
            let domain = Self.domains.contains(value.domain) ? value.domain : "<redacted-domain>"
            entries.append("\(domain)(\(value.code))")
            current = value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        description = "AVPlayer failure: " + entries.joined(separator: " <- ")
    }

    private static let domains: Set<String> = [
        "AVFoundationErrorDomain", "CoreMediaErrorDomain", "NSURLErrorDomain",
        "NSPOSIXErrorDomain", "NSOSStatusErrorDomain", "NSCocoaErrorDomain",
        "kCFErrorDomainCFNetwork", "kCFErrorDomainOSStatus",
    ]
}
