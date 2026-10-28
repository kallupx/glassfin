import GlassfinCore
import SwiftUI

struct PlaybackSettingsView: View {
    @State private var settings = PlaybackFeatureSettings.load(from: UserDefaultsSettingsStore(defaults: .standard))

    var body: some View {
        VStack(spacing: SpacingToken.s) {
            Toggle(isOn: $settings.autoplay) { Copy.text(.playbackAutoplay) }
                .accessibilityIdentifier("settings.playback.autoplay")
            ForEach(SegmentKind.allCases, id: \.self) { kind in
                VStack(alignment: .leading, spacing: SpacingToken.xs) {
                    Text(verbatim: Copy.playbackFeature(kind.copyKey)).font(.caption)
                    Picker(
                        selection: Binding(
                            get: { settings.behavior(for: kind) },
                            set: { settings.segments[kind] = $0 }
                        )
                    ) {
                        ForEach(SegmentBehavior.allCases, id: \.self) { behavior in
                            Text(verbatim: Copy.playbackFeature(behavior.copyKey)).tag(behavior)
                        }
                    } label: {
                        Text(verbatim: Copy.playbackFeature(kind.copyKey))
                    }
                    .labelsHidden()
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("settings.playback.segment." + kind.rawValue.lowercased())
            }
        }
        .frame(maxWidth: 800)
        .onChange(of: settings) { _, value in value.save(to: UserDefaultsSettingsStore(defaults: .standard)) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.playback.preferences")
    }
}
