#if (os(tvOS) || os(iOS)) && canImport(UIKit)
    import AVKit
    import GlassfinCore
    import SwiftUI
    import UIKit

    struct PlaybackView: View {
        let coordinator: PlaybackCoordinator
        let startTicks: Int64
        let onClose: @MainActor () -> Void

        var body: some View {
            ZStack {
                ContentPaint.scrim
                if let key = failureKey {
                    PlaybackErrorView(messageKey: key, onClose: onClose)
                } else {
                    NativePlaybackView(
                        player: (coordinator.engine as? AVPlayerEngine)?.player,
                        trackMenuItems: PlaybackTrackMenus.items(playback: coordinator), onClose: onClose
                    )
                    // Keep Home's media-surface identifier on its own accessibility container.
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("home.playback")
                    .accessibilityValue(String(startTicks))
                    PlaybackSubtitleOverlay(playback: coordinator)
                    if coordinator.state == .loading || coordinator.state == .buffering { ProgressView() }
                    #if DEBUG
                        if coordinator.engine is MockPlaybackEngine {
                            Button(PlaybackCopy.message(for: PlaybackCopy.okKey), action: onClose)
                                .accessibilityIdentifier("home.playback.close")
                        }
                    #endif
                    #if os(iOS)
                        VStack {
                            HStack {
                                Button(PlaybackCopy.message(for: PlaybackCopy.okKey), action: onClose)
                                    .accessibilityIdentifier("playback.close")
                                Spacer()
                            }
                            Spacer()
                        }.padding()
                    #endif
                }
            }
            .ignoresSafeArea()
            .onChange(of: coordinator.state) { _, state in
                if state == .ended || state == .sessionExpired { onClose() }
            }
            #if os(tvOS)
                .onExitCommand(perform: onClose)
            #endif
        }

        private var failureKey: String? {
            if case .failed(let key) = coordinator.state { return key }
            return nil
        }
    }

    struct PlaybackErrorView: View {
        let messageKey: String
        let onClose: @MainActor () -> Void

        var body: some View {
            VStack(spacing: SpacingToken.l) {
                Text(verbatim: PlaybackCopy.message(for: messageKey))
                    .accessibilityIdentifier("playback.error")
                Button(PlaybackCopy.message(for: PlaybackCopy.okKey), action: onClose)
                    .buttonStyle(.glassProminent)
                    .accessibilityIdentifier("playback.close")
            }
        }
    }

    private struct NativePlaybackView: UIViewControllerRepresentable {
        let player: AVPlayer?
        let trackMenuItems: [UIMenuElement]
        let onClose: @MainActor () -> Void

        func makeCoordinator() -> DismissalHandler { DismissalHandler(onClose: onClose) }

        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let controller = AVPlayerViewController()
            controller.player = player
            controller.delegate = context.coordinator
            #if os(tvOS)
                controller.transportBarCustomMenuItems = trackMenuItems
                controller.appliesPreferredDisplayCriteriaAutomatically = true
            #endif
            return controller
        }

        func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
            controller.player = player
            #if os(tvOS)
                controller.transportBarCustomMenuItems = trackMenuItems
            #endif
        }

        static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: DismissalHandler) {
            controller.player = nil
        }

        @MainActor
        final class DismissalHandler: NSObject, @MainActor AVPlayerViewControllerDelegate {
            let onClose: @MainActor () -> Void
            init(onClose: @escaping @MainActor () -> Void) { self.onClose = onClose }

            #if os(tvOS)
                func playerViewControllerShouldDismiss(_ playerViewController: AVPlayerViewController) -> Bool {
                    onClose()
                    return false
                }
            #endif
        }
    }
#endif
