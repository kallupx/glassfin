#if os(tvOS) || os(iOS)
    import GlassfinCore
    import SwiftUI

    /// System-font text avoids the native tvOS subtitle path's unverified CJK rendering.
    struct PlaybackSubtitleOverlay: View {
        let playback: PlaybackCoordinator

        var body: some View {
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                let text = WebVTT.text(at: playback.engine.position, cues: playback.subtitleCues)
                VStack {
                    Spacer()
                    if !text.isEmpty {
                        Text(verbatim: text)
                            .font(.title2)
                            .multilineTextAlignment(.center)
                            .padding(SpacingToken.s)
                            .background(.background)
                            .padding(.bottom, SpacingToken.xl)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityIdentifier("playback.subtitle.overlay")
        }
    }
#endif
