import GlassfinCore
import SwiftUI

struct SettingsView: View {
    @State private var model: SettingsViewModel
    @Binding private var restoreSignOutFocus: Bool
    @FocusState private var signOutFocused: Bool
    @Namespace private var focusScope

    init(flow: AuthFlow, restoreSignOutFocus: Binding<Bool>) {
        _model = State(initialValue: SettingsViewModel(auth: flow))
        _restoreSignOutFocus = restoreSignOutFocus
    }

    var body: some View {
        VStack(spacing: SpacingToken.l) {
            PlaybackSettingsView()
            Button {
                model.requestSignOut()
            } label: {
                Text(verbatim: AuthCopy.localized(.signOut))
            }
            .buttonStyle(.glass)
            .focused($signOutFocused)
            #if os(tvOS)
                .prefersDefaultFocus(in: focusScope)
            #endif
            .accessibilityIdentifier("settings.signOut")

            Text(verbatim: versionText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .focusable(false)
                .accessibilityIdentifier("settings.version")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .defaultFocus($signOutFocused, true, priority: restoreSignOutFocus ? .userInitiated : .automatic)
        #if os(tvOS)
            .focusScope(focusScope)
            .task(id: restoreSignOutFocus) {
                // Tab navigation keeps focus on the tab bar until the user enters its content.
                // Only returning from confirmation should reclaim the originating row.
                guard restoreSignOutFocus else { return }
                await Task.yield()
                guard !Task.isCancelled, restoreSignOutFocus else { return }
                signOutFocused = true
                restoreSignOutFocus = false
            }
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.root")
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
    }

    private var versionText: String {
        if let version = model.appVersion {
            Copy.format(.settingsVersion, text: version)
        } else {
            Copy.string(.settingsVersionUnavailable)
        }
    }
}
