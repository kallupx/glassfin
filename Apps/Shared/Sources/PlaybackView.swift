#if (os(tvOS) || os(iOS)) && canImport(UIKit)
    import AVKit
    import GlassfinCore
    import SwiftUI
    import UIKit

    struct PlaybackView: View {
        let coordinator: PlaybackCoordinator
        let onClose: @MainActor () -> Void
        @State private var companion: PlaybackCompanion
        @State private var clockStart = ContinuousClock.now

        init(coordinator: PlaybackCoordinator, onClose: @escaping @MainActor () -> Void) {
            self.coordinator = coordinator
            self.onClose = onClose
            _companion = State(
                initialValue: coordinator.makeCompanion(
                    settings: .load(from: UserDefaultsSettingsStore(defaults: .standard))))
        }

        var body: some View {
            ZStack {
                ContentPaint.scrim
                if let key = failureKey {
                    PlaybackErrorView(messageKey: key, onClose: onClose)
                } else {
                    NativePlaybackView(
                        player: (coordinator.engine as? AVPlayerEngine)?.player,
                        coordinator: coordinator, companion: companion,
                        trackMenuItems: PlaybackTrackMenus.items(playback: coordinator), onClose: onClose)
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
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("playback.root")
            .task(id: coordinator.currentItemID) {
                if let id = coordinator.currentItemID, let source = coordinator.currentMediaSourceID {
                    await companion.load(itemID: id, mediaSourceID: source)
                }
                let clock = ContinuousClock()
                while !Task.isCancelled {
                    let endedWithPrompt = coordinator.state == .ended && companion.countdownSeconds != nil
                    await companion.update(
                        position: endedWithPrompt
                            ? (companion.runtime ?? coordinator.engine.position) : coordinator.engine.position,
                        isPlaying: coordinator.state == .playing || endedWithPrompt,
                        now: clockStart.duration(to: clock.now))
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                }
            }
            .onChange(of: coordinator.state) { _, state in
                if (state == .ended && companion.countdownSeconds == nil) || state == .sessionExpired { onClose() }
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
            .onDisappear { Task { await companion.shutdown() } }
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
            context.coordinator.update(controller)
        }

        static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: DismissalHandler) {
            controller.player = nil
        }

        @MainActor
        final class DismissalHandler: NSObject, AVPlayerViewControllerDelegate {
            let playback: PlaybackCoordinator
            let companion: PlaybackCompanion
            let gestures: PlaybackScrubGestures
            let onClose: @MainActor () -> Void
            private var skipEnd: Int64?
            private var skipKind: SegmentKind?

            init(
                playback: PlaybackCoordinator, companion: PlaybackCompanion,
                onClose: @escaping @MainActor () -> Void
            ) {
                self.playback = playback
                self.companion = companion
                self.onClose = onClose
                gestures = PlaybackScrubGestures(playback: playback, companion: companion)
            }

            func update(_ controller: AVPlayerViewController) {
                let customScrub = companion.layout != nil && companion.runtime != nil
                gestures.update()
                #if os(tvOS)
                    controller.playbackControlsIncludeTransportBar = !customScrub
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

                nonisolated func playerViewControllerShouldDismiss(_ playerViewController: AVPlayerViewController)
                    -> Bool
                {
                    Task { @MainActor [weak self] in self?.onClose() }
                    return false
                }
            #endif
        }
    }

#endif
