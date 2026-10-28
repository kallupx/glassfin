import Foundation
import Observation

/// PoC settings are local content and stay available when the server is unreachable.
@MainActor
@Observable
public final class SettingsViewModel: ViewContentProviding {
    public let appVersion: String?
    public var hasContent: Bool { true }

    @ObservationIgnored private let auth: AuthFlow

    public init(
        auth: AuthFlow,
        appVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    ) {
        self.auth = auth
        let version = appVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.appVersion = version?.isEmpty == false ? version : nil
    }

    /// Reclaim the visible-screen slot on every tab entry, including returns without a reload.
    public func onAppear() {
        auth.settingsApp.currentView = self
    }

    public func onDisappear() {
        if auth.settingsApp.currentView === self {
            auth.settingsApp.currentView = nil
        }
    }

    public func requestSignOut() {
        auth.requestLogout()
    }
}
