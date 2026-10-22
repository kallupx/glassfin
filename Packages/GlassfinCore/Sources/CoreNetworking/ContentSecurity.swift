import Foundation

public enum ClientPlatform: Sendable, Equatable {
    case tvOS
    case iOS
}

/// S6.2. tvOS never opens external links. iOS opens only http(s).
public enum ExternalLinkPolicy {
    public static func canOpen(_ url: URL, on platform: ClientPlatform) -> Bool {
        switch platform {
        case .tvOS:
            return false
        case .iOS:
            let scheme = url.scheme?.lowercased()
            return scheme == "http" || scheme == "https"
        }
    }
}

/// S6.4. Subtitle files are untrusted and capped at 10 MB, with a caller-enforced deadline.
public enum SubtitleFilePolicy {
    public static let maxBytes = 10 * 1_024 * 1_024

    public static func accept(byteCount: Int, exceededDeadline: Bool) -> Bool {
        byteCount >= 0 && byteCount <= maxBytes && !exceededDeadline
    }
}

/// S6.5. Search text is a query item. It is never concatenated into the path.
public enum QueryTransport {
    public static func searchHints(term: String, limit: Int) -> APIRequest {
        APIRequest(
            method: "GET",
            path: "/Search/Hints",
            query: [
                URLQueryItem(name: "searchTerm", value: term),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
    }
}

/// S7. `IsAdministrator` is only a UI hint. The server still authorizes the call.
public enum AdminGate {
    public static func showAdmin(isAdministrator: Bool) -> Bool {
        isAdministrator
    }
}

public enum DestructiveAdminAction: Sendable, Equatable {
    case restartServer
    case deleteUser
    case deleteDevice
}

public struct DestructiveConfirmation: Sendable, Equatable {
    public var action: DestructiveAdminAction
    public var defaultFocusIsCancel: Bool

    public init(action: DestructiveAdminAction, defaultFocusIsCancel: Bool) {
        self.action = action
        self.defaultFocusIsCancel = defaultFocusIsCancel
    }

    public static func dialog(for action: DestructiveAdminAction) -> DestructiveConfirmation {
        DestructiveConfirmation(action: action, defaultFocusIsCancel: true)
    }
}

/// S8.1 floor until M18 picks the exact class. Downloads stay out of iCloud backups.
public enum DownloadProtection {
    public static let minimumFileProtection = "NSFileProtectionCompleteUntilFirstUserAuthentication"
    public static let excludeFromBackup = true
}

/// S6.3. Native demuxers, when they exist, stay on the LGPL build and get security updates within 14 days.
public enum NativeMediaLibraryPolicy {
    public static let securityUpdateWindowDays = 14
    public static let gplBuildAllowed = false
}
