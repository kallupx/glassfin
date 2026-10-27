#if (os(tvOS) || os(iOS)) && canImport(UIKit)
    import AVKit
    import GlassfinCore
    import SwiftUI
    import UIKit

    /// M07 can present this view after calling `coordinator.play(itemID:choice:)`.
    struct PlaybackView: View {
        let coordinator: PlaybackCoordinator
        let engine: AVPlayerEngine

        var body: some View {
            ZStack {
                NativePlaybackView(player: engine.player, coordinator: coordinator)
                if case .failed(let key) = coordinator.state {
                    Text(verbatim: PlaybackCopy.message(for: key))
                        .padding()
                        .background(.regularMaterial)
                }
                if coordinator.state == .loading || coordinator.state == .buffering {
                    ProgressView()
                }
            }
            .ignoresSafeArea()
            .onDisappear {
                Task { await coordinator.stop() }
            }
        }
    }

    private struct NativePlaybackView: UIViewControllerRepresentable {
        let player: AVPlayer?
        let coordinator: PlaybackCoordinator

        func makeCoordinator() -> DismissalHandler { DismissalHandler(playback: coordinator) }

        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let controller = AVPlayerViewController()
            controller.player = player
            controller.delegate = context.coordinator
            #if os(tvOS)
                controller.appliesPreferredDisplayCriteriaAutomatically = true
            #endif
            return controller
        }

        func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
            controller.player = player
        }

        static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: DismissalHandler) {
            controller.player = nil
            Task { await coordinator.playback.stop() }
        }

        @MainActor
        final class DismissalHandler: NSObject, AVPlayerViewControllerDelegate {
            let playback: PlaybackCoordinator
            init(playback: PlaybackCoordinator) { self.playback = playback }

            #if os(tvOS)
                func playerViewControllerWillDismiss(_ playerViewController: AVPlayerViewController) {
                    Task { await playback.stop() }
                }
            #endif
        }
    }
#endif
