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
                NativePlaybackView(
                    player: engine.player, coordinator: coordinator,
                    trackMenuItems: PlaybackTrackMenus.items(playback: coordinator))
                PlaybackSubtitleOverlay(playback: coordinator)
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
                // keyboardShortcut is unavailable on tvOS; the Siri Remote select
                // button already activates the focused alert action there.
                #if os(tvOS)
                    Button(PlaybackCopy.message(for: PlaybackCopy.okKey)) { dismiss() }
                #else
                    Button(PlaybackCopy.message(for: PlaybackCopy.okKey)) { dismiss() }
                        .keyboardShortcut(.defaultAction)
                #endif
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
        let trackMenuItems: [UIMenuElement]

        func makeCoordinator() -> DismissalHandler { DismissalHandler(playback: coordinator) }

        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let controller = AVPlayerViewController()
            controller.player = player
            controller.delegate = context.coordinator
            context.coordinator.observeFirstFrame(controller)
            #if os(tvOS)
                controller.transportBarCustomMenuItems = trackMenuItems
            #endif
            #if os(tvOS)
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
            Task { await coordinator.playback.stop() }
        }

        @MainActor
        final class DismissalHandler: NSObject, AVPlayerViewControllerDelegate {
            let playback: PlaybackCoordinator
            private var firstFrame: NSKeyValueObservation?
            init(playback: PlaybackCoordinator) { self.playback = playback }

            func observeFirstFrame(_ controller: AVPlayerViewController) {
                firstFrame = controller.observe(\.isReadyForDisplay, options: [.initial, .new]) {
                    [weak self] _, change in
                    guard change.newValue == true else { return }
                    Task { @MainActor [weak self] in self?.playback.noteFirstFrameReady() }
                }
            }

            #if os(tvOS)
                nonisolated func playerViewController(
                    _ playerViewController: AVPlayerViewController,
                    timeToSeekAfterUserNavigatedFrom oldTime: CMTime, to targetTime: CMTime
                ) -> CMTime {
                    let interval = DevicePerformance.begin(.playbackSeek)
                    Task { @MainActor [weak self] in
                        (self?.playback.engine as? AVPlayerEngine)?.beginSeekMeasurement(interval)
                    }
                    return targetTime
                }

                func playerViewControllerWillDismiss(_ playerViewController: AVPlayerViewController) {
                    Task { await playback.stop() }
                }
            #endif
        }
    }
#endif
