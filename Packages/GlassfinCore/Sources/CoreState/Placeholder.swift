import Foundation

/// M02 will add `AppState`, `LoadState`, and `UserDataStore` here.
/// UDP discovery (port 7359) is intentionally absent: those responses are untrusted
/// and must not auto-connect (S4.7).
public enum CoreStateModule {
    public static let name = "CoreState"
}
