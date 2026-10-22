import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// S1.6 wrapper around `AuthorizationHeader`.
///
/// A device name that contains a control character falls back to "Apple TV".
/// A control character in the client, device id, version, or token is an invariant failure.
public enum SafeAuthorizationHeader {
    public static let deviceNameFallback = "Apple TV"

    public static func value(
        client: String,
        device: String,
        deviceID: String,
        version: String,
        token: String?
    ) throws -> String {
        try rejectIdentity(client)
        try rejectIdentity(deviceID)
        try rejectIdentity(version)
        if let token {
            try rejectIdentity(token)
        }
        let safeDevice = AuthorizationHeader.containsRejectedControl(device) ? deviceNameFallback : device
        return try AuthorizationHeader.value(
            client: client,
            device: safeDevice,
            deviceID: deviceID,
            version: version,
            token: token
        )
    }

    private static func rejectIdentity(_ raw: String) throws {
        if AuthorizationHeader.containsRejectedControl(raw) {
            throw SecurityInvariantError.internalInvariant
        }
    }
}

public enum AuthorizationHeaderWriter {
    /// `setValue` replaces a header the SDK added with `addValue`, so one Authorization line leaves.
    public static func replace(_ value: String, on request: inout URLRequest) {
        request.setValue(value, forHTTPHeaderField: "Authorization")
    }
}
