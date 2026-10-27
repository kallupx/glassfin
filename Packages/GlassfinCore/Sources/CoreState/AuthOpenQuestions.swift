import CoreModels
import CoreNetworking
import Foundation

/// Focus targets for the authentication screens. Q4-05 is decided: the address field,
/// or Continue when that field is already filled, and Cancel on the cleartext and certificate screens.
public enum AuthFocus: Hashable, Sendable {
    case connect
    case addressField
    case continueButton
    case cancel
    case quickConnect
    case usePassword
    case username
    case password
    case signIn
    case tryAgain
    case back
    case newCode
    case quickConnectCode
}

public enum AuthFocusPolicy {
    public static func address(fieldIsEmpty: Bool) -> AuthFocus {
        fieldIsEmpty ? .addressField : .continueButton
    }

    public static let cleartextAndCertificate = AuthFocus.cancel
}

/// The remaining name-limit decision awaits Security confirmation.
public enum AuthOpenQuestions {
    // TODO(Q4-16): pending Turvallisuus confirmation
    public static let addressServerNameLimit = 64
}

public enum AuthServerName {
    /// Plain text for a server name. HTML and control characters are removed.
    /// Uses the S4.7 display sanitizer and the same 64-character limit everywhere.
    public static func display(_ raw: String) -> String {
        DiscoveryPolicy.displayName(raw)
    }
}

public enum AuthSessionTiming {
    /// `/Users/Me` at launch. One attempt, no retry.
    public static let currentUserTimeout: Duration = .seconds(5)
}
