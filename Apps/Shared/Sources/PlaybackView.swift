#if (os(tvOS) || os(iOS)) && canImport(UIKit)
    import AVKit
    import GlassfinCore
    import SwiftUI
    import UIKit

    /// M07 can present this view after calling `coordinator.play(itemID:choice:)`.
    struct PlaybackView: View {
        let coordinator: PlaybackCoordinator
        let engine: AVPlayerEngine
        let onReturnFocus: (String) -> Void
        @State private var companion: PlaybackCompanion
        @State private var clockStart = ContinuousClock.now
        @Environment(\.dismiss) private var dismiss

        init(
            coordinator: PlaybackCoordinator, engine: AVPlayerEngine, userDataStore: UserDataStore,
            playNext: (@MainActor (String) async -> Void)? = nil,
            onReturnFocus: @escaping (String) -> Void
        ) {
            self.coordinator = coordinator
            self.engine = engine
            self.onReturnFocus = onReturnFocus
            _companion = State(
                initialValue: coordinator.makeCompanion(
                    settings: .load(from: UserDefaultsSettingsStore(defaults: .standard)),
                    playNext: playNext,
                    completed: { id, position in
                        await userDataStore.recordPlayback(id: id, position: position, played: true, log: SilentLog())
                    }))
        }

        var body: some View {
            ZStack {
                NativePlaybackView(
                    player: engine.player, coordinator: coordinator, companion: companion,
                    trackMenuItems: PlaybackTrackMenus.items(playback: coordinator))
                PlaybackSubtitleOverlay(playback: coordinator)
                PlaybackFeatureOverlay(
                    companion: companion, itemID: coordinator.currentItemID,
                    mediaSourceID: coordinator.currentMediaSourceID)
                if coordinator.state == .loading || coordinator.state == .buffering {
                    ProgressView()
                }
            }
            .ignoresSafeArea()
            .task(id: coordinator.currentItemID) {
                if let id = coordinator.currentItemID, let source = coordinator.currentMediaSourceID {
                    await companion.load(itemID: id, mediaSourceID: source)
                }
                let clock = ContinuousClock()
                while !Task.isCancelled {
                    let endedWithPrompt = coordinator.state == .ended && companion.countdownSeconds != nil
                    await companion.update(
                        position: endedWithPrompt ? (companion.runtime ?? engine.position) : engine.position,
                        isPlaying: coordinator.state == .playing || endedWithPrompt,
                        now: clockStart.duration(to: clock.now))
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                }
            }
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
                if (state == .ended && companion.countdownSeconds == nil) || state == .sessionExpired { dismiss() }
            }
            #if os(tvOS)
                .onExitCommand {
                    if companion.scrubPosition != nil {
                        Task { await companion.endScrubbing(commit: false) }
                    } else {
                        dismiss()
                    }
                }
            #endif
            .onDisappear {
                if let id = companion.returnFocusItemID { onReturnFocus(id) }
                Task {
                    await companion.shutdown()
                    await coordinator.stop()
                }
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
        let companion: PlaybackCompanion
        let trackMenuItems: [UIMenuElement]

        func makeCoordinator() -> DismissalHandler { DismissalHandler(playback: coordinator, companion: companion) }

        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let controller = AVPlayerViewController()
            controller.player = player
            controller.delegate = context.coordinator
            context.coordinator.gestures.install(on: controller.view)
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
            context.coordinator.update(controller)
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
            let companion: PlaybackCompanion
            let gestures: PlaybackScrubGestures
            private var skipEnd: Int64?
            private var skipKind: SegmentKind?

            init(playback: PlaybackCoordinator, companion: PlaybackCompanion) {
                self.playback = playback
                self.companion = companion
                gestures = PlaybackScrubGestures(playback: playback, companion: companion)
            }

            func update(_ controller: AVPlayerViewController) {
                gestures.update()
                #if os(tvOS)
                    // Keep native track menus reachable outside the custom scrub surface.
                    controller.playbackControlsIncludeTransportBar = companion.scrubPosition == nil
                    let skip =
                        companion.scrubPosition == nil && companion.countdownSeconds == nil ? companion.segment : nil
                    if skipEnd != skip?.end || skipKind != skip?.kind {
                        skipEnd = skip?.end
                        skipKind = skip?.kind
                        if let skip {
                            controller.contextualActions = [
                                UIAction(
                                    title: Copy.playbackFeature("playback.skip." + skip.kind.rawValue.lowercased()),
                                    identifier: UIAction.Identifier("playback.segment.skip")
                                ) { [weak self] _ in
                                    Task { @MainActor in await self?.companion.skipSegment() }
                                }
                            ]
                        } else {
                            controller.contextualActions = []
                        }
                    }
                #endif
            }

            #if os(tvOS)
                nonisolated func playerViewController(
                    _ playerViewController: AVPlayerViewController,
                    willTransitionToVisibilityOfTransportBar visible: Bool,
                    with coordinator: any AVPlayerViewControllerAnimationCoordinator
                ) {
                    // AVKit's delegate requirement is nonisolated. Only the visibility
                    // value crosses to the main actor that owns playback UI state.
                    Task { @MainActor [weak self] in
                        self?.companion.transportVisible = visible
                    }
                }

                func playerViewControllerWillDismiss(_ playerViewController: AVPlayerViewController) {
                    Task { await playback.stop() }
                }
            #endif
        }
    }

#endif
