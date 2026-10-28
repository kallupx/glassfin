#if canImport(AVFoundation) && canImport(Security)
    import AVFoundation
    import CoreModels
    import CoreNetworking
    import Foundation
    import Observation

    @MainActor
    @Observable
    public final class AVPlayerEngine: PlaybackEngine {
        public private(set) var player: AVPlayer?
        private let origin: any MediaOriginClient
        private let log: PlaybackLog
        private var mediaSession: AVPlayerMediaSession?
        private var continuation: AsyncStream<PlaybackEngineEvent>.Continuation?
        private var observations: [NSKeyValueObservation] = []
        private var notifications: [NSObjectProtocol] = []
        private var run = 0
        private var ready = false
        private var wantsToPlay = false
        private var seeking = false
        private var start: Duration = .zero

        public init(origin: any MediaOriginClient, log: any GlassfinLog = SilentLog()) {
            self.origin = origin
            self.log = PlaybackLog(sink: log)
        }

        public var events: AsyncStream<PlaybackEngineEvent> {
            let pair = AsyncStream<PlaybackEngineEvent>.makeStream()
            continuation = pair.continuation
            return pair.stream
        }

        public var position: Duration {
            guard ready, let time = player?.currentTime().seconds, time.isFinite, time >= 0 else { return start }
            return .seconds(time)
        }

        public var canSeek: Bool { player?.currentItem?.seekableTimeRanges.isEmpty == false }

        public func load(_ carrier: ResourceLoaderCarrier, startAt: Duration) async throws(APIError) {
            clearPlayer()
            run += 1
            let currentRun = run
            start = max(.zero, startAt)
            guard
                let session = AVPlayerMediaSession(
                    carrier: carrier, origin: origin,
                    onFailure: { [weak self] error in
                        Task { @MainActor [weak self] in
                            guard let self, self.run == currentRun, error != .cancelled else { return }
                            self.continuation?.yield(.failed(error))
                        }
                    }
                )
            else { throw .invalidURL }
            mediaSession = session
            let item = AVPlayerItem(asset: session.asset)
            let player = AVPlayer(playerItem: item)
            self.player = player
            observations.append(
                item.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in await self?.itemChanged(run: currentRun) }
                })
            observations.append(
                player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.run == currentRun, self.ready else { return }
                        switch self.player?.timeControlStatus {
                        case .playing: self.continuation?.yield(.playing)
                        case .paused: self.continuation?.yield(.paused)
                        case .waitingToPlayAtSpecifiedRate: self.continuation?.yield(.buffering)
                        default: break
                        }
                    }
                })
            observe(item, name: AVPlayerItem.didPlayToEndTimeNotification, run: currentRun) { engine in
                engine.continuation?.yield(.ended)
            }
            observe(item, name: AVPlayerItem.failedToPlayToEndTimeNotification, run: currentRun) { engine in
                engine.recordFailure()
            }
            observe(item, name: AVPlayerItem.timeJumpedNotification, run: currentRun) { engine in
                if engine.ready && !engine.seeking { engine.continuation?.yield(.seeked) }
            }
            observe(item, name: AVPlayerItem.newErrorLogEntryNotification, run: currentRun) { engine in
                engine.forwardLogs()
                if engine.player?.currentItem?.errorLog()?.events.last?.errorStatusCode == 401 {
                    engine.continuation?.yield(.failed(.unauthorized))
                }
            }
            observe(item, name: AVPlayerItem.newAccessLogEntryNotification, run: currentRun) { engine in
                engine.forwardLogs()
            }
        }

        public func play() {
            wantsToPlay = true
            if ready { player?.play() }
        }

        public func pause() {
            wantsToPlay = false
            player?.pause()
        }

        public func seek(to position: Duration) async {
            guard let player else { return }
            let currentRun = run
            seeking = true
            await player.seek(to: Self.time(position), toleranceBefore: .zero, toleranceAfter: .zero)
            guard run == currentRun else { return }
            seeking = false
            continuation?.yield(.seeked)
        }

        public func stop() {
            run += 1
            clearPlayer()
            continuation?.finish()
            continuation = nil
        }

        private func itemChanged(run currentRun: Int) async {
            guard run == currentRun, let item = player?.currentItem else { return }
            switch item.status {
            case .readyToPlay:
                guard !ready, !seeking else { return }
                seeking = true
                await player?.seek(to: Self.time(start), toleranceBefore: .zero, toleranceAfter: .zero)
                guard run == currentRun else { return }
                // Track selection and subtitle rendering belong to M08a full scope.
                if let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) {
                    item.select(nil, in: group)
                }
                guard run == currentRun else { return }
                seeking = false
                ready = true
                continuation?.yield(.ready)
                if wantsToPlay { player?.play() }
            case .failed: recordFailure()
            default: break
            }
        }

        private func observe(
            _ item: AVPlayerItem, name: Notification.Name, run currentRun: Int,
            action: @escaping @MainActor @Sendable (AVPlayerEngine) -> Void
        ) {
            notifications.append(
                NotificationCenter.default.addObserver(
                    forName: name, object: item, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.run == currentRun else { return }
                        action(self)
                    }
                })
        }

        private func recordFailure() {
            forwardLogs()
            let status401 = player?.currentItem?.errorLog()?.events.contains { $0.errorStatusCode == 401 } == true
            let error = mediaSession?.lastFailure ?? (status401 ? .unauthorized : .network)
            continuation?.yield(.failed(error))
        }

        private func forwardLogs() {
            if let item = player?.currentItem { AVPlayerLogForwarder.forward(item: item, log: log) }
        }

        private func clearPlayer() {
            observations.removeAll()
            for observer in notifications { NotificationCenter.default.removeObserver(observer) }
            notifications.removeAll()
            player?.pause()
            mediaSession?.cancel()
            player?.replaceCurrentItem(with: nil)
            player = nil
            mediaSession = nil
            ready = false
            seeking = false
            wantsToPlay = false
        }

        private static func time(_ duration: Duration) -> CMTime {
            CMTime(value: Ticks.outboundPositionTicks(from: duration), timescale: CMTimeScale(Ticks.perSecond))
        }

        isolated deinit {
            clearPlayer()
            continuation?.finish()
        }
    }
#endif
