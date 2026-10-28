import CoreModels
import Foundation

/// What a resource-loader HTTP status means before a session decision.
public enum MediaStatusDecision: Sendable, Equatable {
    case bytes
    case failed
    /// Q8-2-09: a media 401 does not log the user out by itself.
    case checkCurrentUser
}

public enum MediaStatusPolicy {
    public static func decide(status: Int) -> MediaStatusDecision {
        switch status {
        case 200..<300:
            return .bytes
        case 401:
            return .checkCurrentUser
        default:
            return .failed
        }
    }
}

public enum LoaderTerminal: Sendable, Equatable {
    case finished
    case failed
    case awaitingSessionCheck
}

public struct LoaderOutcome: Sendable, Equatable {
    public var terminal: LoaderTerminal
    public var tokenCleared: Bool

    public init(terminal: LoaderTerminal, tokenCleared: Bool) {
        self.terminal = terminal
        self.tokenCleared = tokenCleared
    }
}

public enum ResourceLoaderFailurePolicy {
    /// Timeout and 5xx end playback. They do not clear the token (S2.2).
    public static func outcome(status: Int?, timedOut: Bool) -> LoaderOutcome {
        if timedOut {
            return LoaderOutcome(terminal: .failed, tokenCleared: false)
        }
        guard let status else {
            return LoaderOutcome(terminal: .failed, tokenCleared: false)
        }
        switch MediaStatusPolicy.decide(status: status) {
        case .bytes:
            return LoaderOutcome(terminal: .finished, tokenCleared: false)
        case .checkCurrentUser:
            return LoaderOutcome(terminal: .awaitingSessionCheck, tokenCleared: false)
        case .failed:
            return LoaderOutcome(terminal: .failed, tokenCleared: false)
        }
    }
}

public protocol CurrentUserProbing: Sendable {
    func currentUser() async throws(APIError)
}

public enum MediaAuthenticationFailure: Sendable, Equatable {
    /// `/Users/Me` did not return 401. Show a playback error and keep the session.
    case playbackError
    /// `/Users/Me` returned 503. Keep the session and offer a manual retry.
    case serverStarting
    /// `/Users/Me` also returned 401. The caller applies S2.2.
    case logOut
}

/// Q8-2-09. A media 401 stops playback and probes `/Users/Me`. Only a second 401 logs out.
public enum MediaUnauthorizedPolicy {
    public static func decide(probe: any CurrentUserProbing) async -> MediaAuthenticationFailure {
        do {
            _ = try await probe.currentUser()
            return .playbackError
        } catch {
            if case .unauthorized = error {
                return .logOut
            }
            if error == .serverStarting { return .serverStarting }
            return .playbackError
        }
    }
}

/// Segment `ApiKey` stays only while redaction and S4.6 are both on (T08-2-17).
public enum SegmentCredentialPolicy {
    public static func mayLeaveServerCredential(redactionOn: Bool, redirectRulesOn: Bool) -> Bool {
        redactionOn && redirectRulesOn
    }
}
