import GlassfinCore
import SwiftUI

struct SettingsView: View {
    @AppStorage(PlaybackPreferenceKeys.convertASS) private var convertASS = true
    @AppStorage(PlaybackPreferenceKeys.remoteBitrate) private var remoteBitrate = 20_000_000
    @State private var model: SettingsViewModel
    @Binding private var restoreSignOutFocus: Bool
    @FocusState private var signOutFocused: Bool
    @Namespace private var focusScope
    private let playbackConfiguration: PlaybackConfiguration

    init(
        flow: AuthFlow, restoreSignOutFocus: Binding<Bool>,
        playbackConfiguration: PlaybackConfiguration = .poc
    ) {
        _model = State(initialValue: SettingsViewModel(auth: flow))
        _restoreSignOutFocus = restoreSignOutFocus
        self.playbackConfiguration = playbackConfiguration
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

            // The PoC shell keeps M10's Sign out and version screen (SPEC section 3a).
            if !playbackConfiguration.isPoC {
                Toggle(isOn: $convertASS) {
                    Text(verbatim: Copy.string(.playbackConvertASS))
                }
                .accessibilityIdentifier("settings.playback.convertASS")

                Picker(selection: $remoteBitrate) {
                    ForEach([5, 10, 20, 40, 80, 120], id: \.self) { value in
                        Text(verbatim: "\(value) Mbps").tag(value * 1_000_000)
                    }
                } label: {
                    Text(verbatim: Copy.string(.playbackRemoteBitrate))
                }
                .accessibilityIdentifier("settings.playback.remoteBitrate")
            }

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
