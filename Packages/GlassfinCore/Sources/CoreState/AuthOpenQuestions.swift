import CoreModels
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
    case quickConnectCode
}

public enum AuthFocusPolicy {
    public static func address(fieldIsEmpty: Bool) -> AuthFocus {
        fieldIsEmpty ? .addressField : .continueButton
    }

    public static let cleartextAndCertificate = AuthFocus.cancel
}

/// TODO markers for authentication behavior the spec leaves open.
/// Tests assert that these values are what the flow consults.
public enum AuthOpenQuestions {
    public enum QuickConnectDisabledPresentation: Sendable {
        case passwordOnly
        case methodScreen
    }

    public enum PostLogoutScreen: Sendable {
        case welcome
        case address
        case login
    }

    /// TODO(Q4-06): Quick Connect disabled. The spec does not say whether to skip the method screen.
    public static let quickConnectDisabledPresentation = QuickConnectDisabledPresentation.methodScreen

    /// TODO(Q4-07): `POST /QuickConnect/Initiate` when entering the method screen, or when opening the code screen.
    public static let initiateQuickConnectOnMethodEntry = false

    /// TODO(Q4-08): The screen text says to renew the code. S3.3 says to cancel polling at five minutes.
    public static let renewQuickConnectCodeAtTimeout = false

    /// TODO(Q4-08): Background and foreground while the code is on screen.
    public static let continueQuickConnectInBackground = true

    /// TODO(Q4-10): Copy for `/Users/Me` 403/500 and for an offline launch with an empty cache.
    public static let sessionRestoreFailureKey: AuthCopy.Key? = nil

    /// TODO(Q4-11): M04's shorter session-ended sentence versus M02's longer one.
    public static let sessionEndedNoticeKey = AuthCopy.Key.sessionEnded

    /// TODO(Q4-12): Where logout lands, and which button is the default on the confirm dialog.
    public static let postLogoutScreen: PostLogoutScreen? = nil
    public static let logoutConfirmDefaultFocus: AuthFocus? = nil

    /// TODO(Q4-13): DeviceProfile arrives with M08. A failed capabilities call does not block sign-in.
    public static let includeDeviceProfile = false
    public static let capabilitiesFailureBlocksSignIn = false

    /// TODO(Q4-15): Wording for a Quick Connect 401. Password 401 uses ``AuthCopy/Key/invalidCredentials``.
    public static let quickConnectUnauthorizedKey = AuthCopy.Key.quickConnectUnauthorized

    /// TODO(Q4-15): Wording for a login network failure or HTTP 5xx.
    public static let loginTransportFailureKey = AuthCopy.Key.loginTransportFailure

    /// TODO(Q4-16): Extra ServerName cap on the address screen. Nil keeps the full sanitized name.
    /// Discovery still caps at 64.
    public static let addressServerNameLimit: Int? = nil

    /// TODO(Q4-17): SPEC.md title says v1.3.3 and the meta line says v1.3. No code branches on it.
}

public enum AuthServerName {
    /// Plain text for a server name. HTML and control characters are removed.
    /// An extra length cap applies only when ``AuthOpenQuestions/addressServerNameLimit`` is set.
    public static func display(_ raw: String) -> String {
        let plain = MetadataSanitizer.plainText(raw)
        let cleaned = plain.unicodeScalars.filter { !isControl($0) }
        let text = String(String.UnicodeScalarView(cleaned))
        guard let limit = AuthOpenQuestions.addressServerNameLimit else { return text }
        return String(text.prefix(limit))
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.value <= 0x1F || scalar.value == 0x7F { return true }
        switch scalar.value {
        case 0x202A...0x202E, 0x2066...0x2069:
            return true
        default:
            return false
        }
    }
}

public enum AuthSessionTiming {
    /// `/Users/Me` at launch. One attempt, no retry.
    public static let currentUserTimeout: Duration = .seconds(5)
}
