#if (os(tvOS) || os(iOS)) && canImport(UIKit)
    import AVKit
    import GlassfinCore
    import SwiftUI
    import UIKit

    /// M07 can present this view after calling `coordinator.play(itemID:choice:)`.
    struct PlaybackView: View {
        let coordinator: PlaybackCoordinator
        let engine: AVPlayerEngine
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            ZStack {
                NativePlaybackView(player: engine.player, coordinator: coordinator)
                if coordinator.state == .loading || coordinator.state == .buffering {
                    ProgressView()
                }
            }
            .ignoresSafeArea()
            .alert(
                PlaybackCopy.message(for: failureKey ?? PlaybackCopy.couldNotPlayKey),
                isPresented: Binding(
                    get: { failureKey != nil },
                    set: { if !$0 { dismiss() } }
                )
            ) {
                Button(PlaybackCopy.message(for: PlaybackCopy.okKey)) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .onChange(of: coordinator.state) { _, state in
                if state == .ended || state == .sessionExpired { dismiss() }
            }
            #if os(tvOS)
                .onExitCommand { dismiss() }
            #endif
            .onDisappear {
                Task { await coordinator.stop() }
            }
        }

        private var failureKey: String? {
            if case .failed(let key) = coordinator.state { return key }
            return nil
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
