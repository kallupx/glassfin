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
        var trackSelectionPeers: [PlaybackTrack] = []
        var expectedNativeAudio: AVMediaSelectionOption?
        var expectedNativeSubtitle: AVMediaSelectionOption?
        @ObservationIgnored private var seekInterval: DevicePerformance.Interval?

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
                        case .playing:
                            if !self.seeking { self.endSeekMeasurement() }
                            self.continuation?.yield(.playing)
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
            observe(item, name: AVPlayerItem.mediaSelectionDidChangeNotification, run: currentRun) { engine in
                Task { await engine.nativeSelectionChanged() }
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
            beginSeekMeasurement()
            seeking = true
            await player.seek(to: Self.time(position), toleranceBefore: .zero, toleranceAfter: .zero)
            guard run == currentRun else { return }
            seeking = false
            if player.timeControlStatus == .playing { endSeekMeasurement() }
            continuation?.yield(.seeked)
        }

        /// AVKit calls this at scrub confirmation, before it performs its own seek.
        public func beginSeekMeasurement(_ interval: DevicePerformance.Interval? = nil) {
            seekInterval?.end(completed: false)
            seekInterval = interval ?? DevicePerformance.begin(.playbackSeek)
        }

        private func endSeekMeasurement() {
            seekInterval?.end()
            seekInterval = nil
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
                // The coordinator applies the full profile's selected tracks after ready.
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

        func emitNativeSelection(kind: PlaybackTrack.Kind, id: Int?) {
            continuation?.yield(.trackChanged(kind: kind, id: id))
        }

        private func recordFailure() {
            let diagnostic = PlayerFailureDiagnostic(error: player?.currentItem?.error as NSError?)
            log.error(diagnostic.description)
            // This summary contains only allowlisted domains and numeric codes. Public
            // visibility lets simulator e2e logs retain it without enabling private logs.
            GlassfinLogger(category: "playback").infoPublic(diagnostic.description)
            forwardLogs()
            let status401 = player?.currentItem?.errorLog()?.events.contains { $0.errorStatusCode == 401 } == true
            let error = mediaSession?.lastFailure ?? (status401 ? .unauthorized : .network)
            continuation?.yield(.failed(error))
        }

        private func forwardLogs() {
            if let item = player?.currentItem { AVPlayerLogForwarder.forward(item: item, log: log) }
        }

        private func clearPlayer() {
            trackSelectionPeers = []
            expectedNativeAudio = nil
            expectedNativeSubtitle = nil
            seekInterval?.end(completed: false)
            seekInterval = nil
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
