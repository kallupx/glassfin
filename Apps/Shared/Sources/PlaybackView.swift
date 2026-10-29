#if (os(tvOS) || os(iOS)) && canImport(UIKit)
    import AVKit
    import GlassfinCore
    import SwiftUI
    import UIKit

    struct PlaybackView: View {
        let coordinator: PlaybackCoordinator
        let companion: PlaybackCompanion
        let startTicks: Int64
        let onClose: @MainActor () -> Void
        @State private var clockStart = ContinuousClock.now

        var body: some View {
            ZStack {
                ContentPaint.scrim
                if failureKey == AppErrorMessage.serverStartingKey {
                    VStack(spacing: SpacingToken.m) {
                        ErrorStateView(
                            messageOverride: AppErrorMessage.userFacing(.serverStarting),
                            failure: .server(status: 503), attempts: 0,
                            onRetry: { Task { await coordinator.retryServerStarting() } }, onSwitchServer: {})
                        Button(AuthCopy.localized(.back), action: onClose)
                            .accessibilityIdentifier("playback.close")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let key = failureKey {
                    PlaybackErrorView(messageKey: key, onClose: onClose)
                } else {
                    NativePlaybackView(
                        player: (coordinator.engine as? AVPlayerEngine)?.player,
                        coordinator: coordinator, companion: companion,
                        trackMenuItems: PlaybackTrackMenus.items(playback: coordinator), onClose: onClose
                    )
                    // Keep Home's media-surface identifier on its own accessibility container.
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("home.playback")
                    .accessibilityValue(String(startTicks))
                    PlaybackSubtitleOverlay(playback: coordinator)
                    PlaybackFeatureOverlay(
                        companion: companion, itemID: coordinator.currentItemID,
                        mediaSourceID: coordinator.currentMediaSourceID)
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
            .task(id: coordinator.currentItemID ?? coordinator.lastStop?.itemID) {
                guard let id = coordinator.currentItemID, let source = coordinator.currentMediaSourceID else { return }
                await companion.load(itemID: id, mediaSourceID: source)
                let clock = ContinuousClock()
                while !Task.isCancelled {
                    let engine = coordinator.engine
                    let endedWithPrompt = coordinator.state == .ended && companion.countdownSeconds != nil
                    await companion.update(
                        position: endedWithPrompt ? (companion.runtime ?? engine.position) : engine.position,
                        isPlaying: coordinator.state == .playing || endedWithPrompt,
                        now: clockStart.duration(to: clock.now))
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                }
            }
            .onChange(of: coordinator.state) { _, state in
                if (state == .ended && companion.countdownSeconds == nil && !companion.advancing)
                    || state == .sessionExpired
                {
                    onClose()
                }
            }
            #if os(tvOS)
                .onExitCommand {
                    if companion.scrubPosition != nil {
                        Task { await companion.endScrubbing(commit: false) }
                    } else {
                        onClose()
                    }
                }
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
        let coordinator: PlaybackCoordinator
        let companion: PlaybackCompanion
        let trackMenuItems: [UIMenuElement]
        let onClose: @MainActor () -> Void

        func makeCoordinator() -> DismissalHandler {
            DismissalHandler(playback: coordinator, companion: companion, onClose: onClose)
        }

        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let controller = AVPlayerViewController()
            controller.player = player
            controller.delegate = context.coordinator
            context.coordinator.gestures.install(on: controller.view)
            context.coordinator.observeFirstFrame(controller)
            #if os(tvOS)
                controller.transportBarCustomMenuItems = trackMenuItems
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
        }

        @MainActor
        final class DismissalHandler: NSObject, @MainActor AVPlayerViewControllerDelegate {
            let playback: PlaybackCoordinator
            let onClose: @MainActor () -> Void
            let companion: PlaybackCompanion
            let gestures: PlaybackScrubGestures
            private var skipEnd: Int64?
            private var skipKind: SegmentKind?
            private var firstFrame: NSKeyValueObservation?

            init(playback: PlaybackCoordinator, companion: PlaybackCompanion, onClose: @escaping @MainActor () -> Void)
            {
                self.playback = playback
                self.onClose = onClose
                self.companion = companion
                gestures = PlaybackScrubGestures(playback: playback, companion: companion)
            }

            func observeFirstFrame(_ controller: AVPlayerViewController) {
                firstFrame = controller.observe(\.isReadyForDisplay, options: [.initial, .new]) {
                    [weak self] _, change in
                    guard change.newValue == true else { return }
                    Task { @MainActor [weak self] in self?.playback.noteFirstFrameReady() }
                }
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

                func playerViewControllerShouldDismiss(_ playerViewController: AVPlayerViewController) -> Bool {
                    if companion.scrubPosition != nil {
                        Task { await companion.endScrubbing(commit: false) }
                    } else {
                        onClose()
                    }
                    return false
                }
            #endif
        }
    }

#endif
