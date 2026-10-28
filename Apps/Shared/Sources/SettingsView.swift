import GlassfinCore
import SwiftUI

struct SettingsView: View {
    @State private var model: SettingsViewModel
    @FocusState private var signOutFocused: Bool
    @Namespace private var focusScope

    init(flow: AuthFlow) {
        _model = State(initialValue: SettingsViewModel(auth: flow))
    }

    var body: some View {
        VStack(spacing: SpacingToken.l) {
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
        .defaultFocus($signOutFocused, true, priority: .userInitiated)
        #if os(tvOS)
            .focusScope(focusScope)
            .task {
                // The tab content must join the focus hierarchy before reclaiming the originating row.
                await Task.yield()
                guard !Task.isCancelled else { return }
                signOutFocused = true
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
