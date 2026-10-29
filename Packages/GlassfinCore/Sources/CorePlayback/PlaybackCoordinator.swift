import CoreModels
import CoreNetworking
import Foundation
import Observation

public enum PlaybackStartChoice: Sendable, Equatable {
    /// Fetch UserData.PlaybackPositionTicks with the active user before PlaybackInfo.
    case resume
    /// Use the caller's saved position while still checking current stream metadata.
    case resumeAt(ticks: Int64)
    case startOver
}

@MainActor
@Observable
public final class PlaybackCoordinator {
    public private(set) var state: PlaybackState = .idle
    public private(set) var failure: PlaybackFailure?
    /// App-level error for the generic playback failure, sharing the UI's catalog key.
    public var appError: AppError? {
        failure == .couldNotPlay ? .playback(.couldNotPlay) : nil
    }
    public let engine: any PlaybackEngine
    public private(set) var returnFocusID: String?
    public private(set) var lastStop: PlaybackStop?
    public private(set) var tracks: [PlaybackTrack] = []
    public private(set) var selection = PlaybackTrackSelection()
    public private(set) var subtitleCues: [SubtitleCue] = []
    public private(set) var diagnostics: PlaybackDiagnostics?
    public var bufferedDuration: Duration { (engine as? any PlaybackBufferReporting)?.bufferedDuration ?? .zero }
    public private(set) var playMethod: PlayMethod?
    public private(set) var transcodeReasons: [String] = []
    public var convertsASS: Bool { configuration.convertASS }
    private var requiresBurnIn: Bool {
        guard let track = tracks.first(where: { $0.kind == .subtitle && $0.id == selection.subtitle }) else {
            return false
        }
        if ["ass", "ssa"].contains(track.codec) { return !configuration.convertASS }
        return track.delivery == .burnIn
    }

    private var configuration: PlaybackConfiguration
    private var capabilities = PlaybackCapabilities()
    private var attempt: PlaybackAttempt = .automatic
    private var sourceSnapshot: MediaSourceDTO?
    private var sourceStreams: [MediaStreamDTO] = []
    private var selectedSourceID: String?
    private var selectingTrack = false
    private var trackChangePending = false
    private var firstFrameTask: Task<Void, Never>?
    private let clock: any GlassfinClock

    private let onStopped: (@MainActor (PlaybackStop) async -> Void)?
    private var request: PlaybackRequest?
    private let session: any PlaybackSessionProviding
    private let origin: any MediaOriginClient
    private let api: PlaybackAPI
    private let reporter: PlaybackReporter
    private let timer: any PlaybackProgressScheduling
    private let log: PlaybackLog
    private let maxBitrate: Int
    private var context: PlaybackReportContext?
    private var eventsTask: Task<Void, Never>?
    private var generation = 0
    private var started = false
    private var paused = false
    private var engineLoaded = false
    private var startPosition: Duration = .zero
    private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var firstFrameInterval: DevicePerformance.Interval?
    @ObservationIgnored private var lifetimeInterval: DevicePerformance.Interval?
    private var stoppingTask: Task<APIError?, Never>?

    public init(
        session: any PlaybackSessionProviding, engine: any PlaybackEngine, origin: any MediaOriginClient,
        timer: any PlaybackProgressScheduling = PlaybackProgressTimer(),
        maxBitrate: Int? = nil, log: any GlassfinLog = SilentLog(),
        configuration: PlaybackConfiguration? = nil,
        clock: any GlassfinClock = SystemGlassfinClock(),
        onStopped: (@MainActor (PlaybackStop) async -> Void)? = nil
    ) {
        self.session = session
        self.engine = engine
        self.origin = origin
        self.timer = timer
        let configuration = configuration ?? PlaybackPreferences.configuration()
        self.configuration = configuration
        self.clock = clock
        // Reuse the audited LAN host classifier without DNS or a second address policy.
        var transportURL = URLComponents(url: session.serverURL, resolvingAgainstBaseURL: false)
        transportURL?.scheme = "http"
        let lan = transportURL?.url.map { ServerTransportPolicy.evaluate($0) == .unencryptedLocal } ?? false
        self.maxBitrate = maxBitrate ?? (lan || configuration.isPoC ? 120_000_000 : configuration.remoteBitrate)
        self.log = PlaybackLog(sink: log)
        self.api = PlaybackAPI(client: session.apiClient)
        self.reporter = PlaybackReporter(client: session.apiClient, log: log)
        self.onStopped = onStopped
    }

    public func play(_ request: PlaybackRequest, returnFocusID: String) async {
        let firstFrame = DevicePerformance.begin(.playbackFirstFrame)
        await stop()
        firstFrameInterval = firstFrame
        self.request = request
        self.returnFocusID = returnFocusID
        lastStop = nil
        await start(itemID: request.itemID.value, choice: .resumeAt(ticks: request.startTicks))
    }

    /// Stopped and the local user-data update complete before presentation can close.
    @discardableResult
    public func dismiss() async -> String? {
        await stop()
        _ = await stoppingTask?.value
        return returnFocusID
    }

    public func play(itemID: String, choice: PlaybackStartChoice = .resume) async {
        let firstFrame = DevicePerformance.begin(.playbackFirstFrame)
        await stop()
        firstFrameInterval = firstFrame
        request = nil
        returnFocusID = nil
        lastStop = nil
        await start(itemID: itemID, choice: choice)
    }

    private func start(itemID: String, choice: PlaybackStartChoice) async {
        generation += 1
        let run = generation
        failure = nil
        paused = false
        state = .loading
        attempt = .automatic
        selectedSourceID = nil
        selection = PlaybackTrackSelection()
        tracks = []
        sourceStreams = []
        sourceSnapshot = nil
        diagnostics = nil
        playMethod = nil
        transcodeReasons = []
        trackChangePending = false
        subtitleCues = []
        capabilities = configuration.capabilities ?? PlaybackCapabilities.current()
        do {
            var item = try await api.item(itemID: itemID, userID: session.userID)
            guard await continueStartup(run) else { return }
            if item.MediaStreams == nil && item.MediaSources?.first?.MediaStreams == nil {
                item = try await api.item(itemID: itemID, userID: session.userID)
                guard await continueStartup(run) else { return }
            }
            if configuration.isPoC,
                let reason = PlaybackDecision.videoFailure(
                    streams: item.MediaStreams ?? item.MediaSources?.first?.MediaStreams)
            {
                throw reason
            }
            if configuration.isPoC {
                selection.audio =
                    PlaybackDecision.defaultAudio(
                        streams: item.MediaStreams ?? item.MediaSources?.first?.MediaStreams)?.Index
            } else {
                let user = try await api.userConfiguration()
                guard await continueStartup(run) else { return }
                sourceStreams = item.MediaStreams ?? item.MediaSources?.first?.MediaStreams ?? []
                tracks = PlaybackTrack.map(
                    sourceStreams,
                    convertASS: configuration.convertASS)
                selection = PlaybackTrackSelection.defaults(tracks: tracks, user: user)
            }
            if let audio = request?.audioStreamIndex { selection.audio = audio }
            if let subtitle = request?.subtitleStreamIndex { selection.subtitle = subtitle }
            let ticks: Int64
            switch choice {
            case .resume: ticks = item.UserData?.PlaybackPositionTicks ?? 0
            case .resumeAt(let value): ticks = value
            case .startOver: ticks = 0
            }
            guard await continueStartup(run) else { return }
            if ticks < 0 {
                log.warning("Negative UserData.PlaybackPositionTicks for item \(try ItemID.require(itemID).value)")
            }
            let start = Ticks.positionDuration(from: max(0, ticks), log: log)
            startPosition = start
            await startAttempt(itemID: itemID, start: start, run: run)
        } catch {
            await startupFailed(error, run: run)
        }
    }

    private func startAttempt(
        itemID: String, start: Duration, run: Int, directStreamOnly: Bool = false,
        previousSessionID: String? = nil
    ) async {
        startPosition = start
        do {
            let info: PlaybackInfoResponseDTO
            if configuration.isPoC {
                info = try await api.playbackInfo(
                    itemID: itemID, userID: session.userID, start: start, maxBitrate: maxBitrate,
                    enableDirectPlay: !directStreamOnly, audioStreamIndex: selection.audio)
            } else {
                info = try await api.negotiate(
                    itemID: itemID, userID: session.userID, start: start,
                    profile: RuntimeDeviceProfile(
                        capabilities: capabilities, maxBitrate: maxBitrate,
                        convertASS: configuration.convertASS),
                    maxBitrate: maxBitrate, attempt: requiresBurnIn ? .transcode : attempt,
                    selection: selection, mediaSourceID: selectedSourceID)
            }
            guard await continueStartup(run) else { return }
            guard info.ErrorCode == nil,
                let source = selectedSourceID == nil
                    ? info.MediaSources?.first
                    : info.MediaSources?.first(where: { $0.Id == selectedSourceID }),
                let sourceID = source.Id, let playSessionID = info.PlaySessionId, !playSessionID.isEmpty,
                playSessionID != previousSessionID
            else { throw PlaybackFailure.couldNotPlay }
            let delivery: MediaDelivery
            let url: URL
            let method: PlayMethod
            if configuration.isPoC {
                let decision = PlaybackDecision.decide(mediaSource: source, allowDirectPlay: !directStreamOnly)
                switch decision {
                case .unsupported(let reason): throw reason
                case .directPlay:
                    method = .directPlay
                    delivery = source.Container?.lowercased() == "hls" ? .serverHLS : .directFile
                    url = try MediaURLBuilder.directPlay(
                        server: session.serverURL, identity: session.identity,
                        itemID: itemID, mediaSourceID: sourceID, playSessionID: playSessionID
                    ).url
                case .directStream(let conversion):
                    method = .directStream
                    delivery = .serverHLS
                    url = try MediaURLBuilder.videoCopyHLS(
                        server: session.serverURL, transcodingURL: source.TranscodingUrl ?? "", conversion: conversion)
                }
            } else {
                sourceStreams = source.MediaStreams ?? sourceStreams
                tracks = PlaybackTrack.map(sourceStreams, convertASS: configuration.convertASS)
                selectedSourceID = sourceID
                if selection.audio == nil { selection.audio = source.DefaultAudioStreamIndex }
                if selection.subtitle == nil { selection.subtitle = source.DefaultSubtitleStreamIndex ?? -1 }
                let chosenSubtitle = tracks.first { $0.kind == .subtitle && $0.id == selection.subtitle }
                let decision = try PlaybackStreamSelection.decide(
                    source: source, attempt: attempt, subtitle: chosenSubtitle)
                method = decision.method
                delivery = decision.usesHLS ? .serverHLS : .directFile
                if method == .directPlay {
                    url = try MediaURLBuilder.directPlay(
                        server: session.serverURL, identity: session.identity,
                        itemID: itemID, mediaSourceID: sourceID, playSessionID: playSessionID
                    ).url
                } else {
                    url = try MediaURLBuilder.negotiatedHLS(
                        server: session.serverURL,
                        transcodingURL: source.TranscodingUrl ?? "")
                }
                sourceSnapshot = source
                diagnostics = PlaybackDiagnostics(source: source, method: method, selection: selection)
                playMethod = method
                transcodeReasons = VideoTranscodeReasons.parse(transcodingURL: source.TranscodingUrl).map {
                    MetadataSanitizer.displayText(MediaLogRedactor.redact($0), limit: 200)
                }
            }
            if method != .directPlay {
                firstFrameInterval?.end(completed: false)
                firstFrameInterval = DevicePerformance.begin(
                    method == .transcode ? .playbackTranscodeFirstFrame : .playbackDirectStreamFirstFrame)
            }
            context = PlaybackReportContext(
                itemID: try ItemID.require(itemID).value, mediaSourceID: try ItemID.require(sourceID).value,
                playSessionID: playSessionID, method: method,
                audioStreamIndex: configuration.isPoC ? nil : selection.audio,
                subtitleStreamIndex: configuration.isPoC ? nil : selection.subtitle)
            // Q8P-13: a pinned self-signed server never attempts remux; keep its own message first.
            if delivery == .serverHLS, case .pinnedSelfSigned = session.trust {
                throw PlaybackFailure.hlsSegmentsBypassPinnedTrust
            }
            // Preserve the server's raw query before the video-copy builder strips credentials.
            let playlistCredentials: ServerHLSCredentialQuery?
            if delivery == .serverHLS, let transcodingURL = source.TranscodingUrl,
                let original = MediaURLBuilder.resolveTranscodingURL(
                    server: session.serverURL, transcodingURL: transcodingURL),
                MediaOrigin.matches(session.serverURL, original),
                !MediaOrigin.isHTTPSDowngrade(session.serverURL, original)
            {
                playlistCredentials = ServerHLSCredentialQuery(transcodingURL: original)
            } else {
                playlistCredentials = nil
            }
            // Q8P-24: header-only playlists cannot authenticate AVPlayer's segment requests.
            // Reject remux before preparation sends its first playlist GET.
            if method != .directPlay, playlistCredentials == nil {
                log.warning("Remux rejected: server playlist credential query is missing")
                throw AppError.playback(.couldNotPlay)
            }
            let header = try session.identity.authorizationHeader()
            let result = try await PlaybackPreparation(client: origin, log: log).prepare(
                delivery: delivery, initialURL: url, authorizationHeader: header,
                options: MediaOpenOptions(trust: session.trust, headerFieldsKeyAvailable: false),
                playlistCredentials: playlistCredentials
            )
            guard await continueStartup(run) else { return }
            let carrier: ResourceLoaderCarrier
            switch result {
            case .open(let plan):
                // Media credentials always stay on the resource-loader path.
                if plan.primary.block == .hlsSegmentsBypassPinnedTrust {
                    throw PlaybackFailure.hlsSegmentsBypassPinnedTrust
                }
                guard case .resourceLoader(let value) = plan.primary else { throw PlaybackFailure.couldNotPlay }
                carrier = value
            case .rejected(.transport(status: 401)): throw APIError.unauthorized
            case .rejected(.insecureRedirect): throw PlaybackFailure.insecureRedirect
            case .rejected: throw PlaybackFailure.couldNotPlay
            }
            if !configuration.isPoC {
                subtitleCues = []
                if let track = tracks.first(where: { $0.kind == .subtitle && $0.id == selection.subtitle }),
                    track.delivery == .externalVTT
                {
                    subtitleCues = try await api.subtitles(itemID: itemID, mediaSourceID: sourceID, index: track.id)
                    guard await continueStartup(run) else { return }
                }
            }
            let events = engine.events
            eventsTask = Task { [weak self] in
                for await event in events {
                    guard let self, !Task.isCancelled, self.isCurrent(run) else { return }
                    await self.handle(event, run: run)
                }
            }
            lifetimeInterval = DevicePerformance.begin(.playbackLifetime)
            try await engine.load(carrier, startAt: start)
            guard await continueStartup(run) else { return }
            engineLoaded = true
            if !configuration.isPoC && !paused && method == .directPlay {
                firstFrameTask = Task { [weak self, clock] in
                    do { try await clock.sleep(for: .seconds(10)) } catch { return }
                    guard let self, self.isCurrent(run) else { return }
                    await self.attemptFailed(run: run, fromEngineEvent: true)
                }
            }
            if paused { engine.pause() } else { engine.play() }
        } catch {
            await startupFailed(error, run: run)
        }
    }

    private func startupFailed(_ error: any Error, run: Int) async {
        guard generation == run else { return }
        if Task.isCancelled || error as? APIError == .cancelled {
            await finish(state: .idle, failed: false)
        } else if error as? APIError == .unauthorized {
            if context != nil {
                await mediaUnauthorized()
            } else {
                await expireSession(run: run)
            }
        } else {
            let reason = (error as? PlaybackFailure) ?? .couldNotPlay
            if reason == .couldNotPlay || (reason == .insecureRedirect && context?.method == .directPlay) {
                await attemptFailed(run: run)
            } else {
                await fail(reason)
            }
        }
    }

    private func attemptFailed(run: Int, fromEngineEvent: Bool = false) async {
        guard isCurrent(run) else { return }
        guard let failedAttempt = context,
            configuration.isPoC
                ? failedAttempt.method == .directPlay : (attempt.next != nil && failedAttempt.method != .transcode)
        else {
            await fail(.couldNotPlay)
            return
        }
        if case .pinnedSelfSigned = session.trust {
            await fail(.hlsSegmentsBypassPinnedTrust)
            return
        }
        if !configuration.isPoC { attempt = failedAttempt.method == .directPlay ? .directStream : .transcode }
        // A startup failure can arrive inside the retry task itself. Do not cancel its
        // own execution while closing the previous session and scheduling the next stage.
        retryTask = nil
        let position = engineLoaded ? max(.zero, engine.position) : startPosition
        let retryRun = generation + 1
        let error = await finish(state: .loading, failed: true)
        guard generation == retryRun else { return }
        if error == .unauthorized {
            state = .failed(localizedKey: PlaybackCopy.couldNotPlayKey)
            await checkCurrentUser(run: retryRun)
            return
        }
        if !fromEngineEvent && Task.isCancelled {
            await finish(state: .idle, failed: false)
            return
        }
        paused = false
        // finish cancels the failed engine's event task. The remux owns a fresh task and generation.
        let task = Task<Void, Never> { [weak self] in
            await self?.startAttempt(
                itemID: failedAttempt.itemID, start: position, run: retryRun,
                directStreamOnly: true, previousSessionID: failedAttempt.playSessionID)
        }
        retryTask = task
        if fromEngineEvent {
            await task.value
        } else {
            await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }
        }
        if generation == retryRun { retryTask = nil }
    }

    public func selectTrack(id: Int?, kind: PlaybackTrack.Kind) async {
        guard !configuration.isPoC, !selectingTrack, let oldContext = context, engineLoaded, state != .loading else {
            return
        }
        selectingTrack = true
        defer { selectingTrack = false }
        let track = tracks.first { $0.kind == kind && $0.id == id }
        guard id == nil || track != nil else { return }
        if kind == .audio && track == nil { return }
        if (kind == .audio ? selection.audio : selection.subtitle ?? -1) == (id ?? -1) { return }
        let trackInterval = DevicePerformance.begin(.playbackTrackApply)
        defer { trackInterval?.end(completed: false) }
        let run = generation
        let oldSubtitle = tracks.first { $0.kind == .subtitle && $0.id == selection.subtitle }
        let mustReload =
            oldSubtitle?.delivery == .burnIn || track?.delivery == .burnIn
        var native = false
        if !mustReload, track == nil || track?.delivery == .embedded {
            native =
                await (engine as? any PlaybackTrackSelecting)?.selectNativeTrack(track, kind: kind, peers: tracks)
                == true
            guard isCurrent(run) else { return }
        }
        if !mustReload, kind == .subtitle, track?.delivery == .externalVTT {
            do {
                let cues = try await api.subtitles(
                    itemID: oldContext.itemID, mediaSourceID: oldContext.mediaSourceID,
                    index: track?.id ?? -1)
                guard isCurrent(run) else { return }
                _ = await (engine as? any PlaybackTrackSelecting)?.selectNativeTrack(
                    nil, kind: .subtitle, peers: tracks)
                subtitleCues = cues
                native = true
            } catch {
                guard isCurrent(run) else { return }
                await startupFailed(error, run: run)
                return
            }
        }
        if kind == .audio { selection.audio = id } else { selection.subtitle = id ?? -1 }
        if native {
            refreshDiagnostics()
            context?.audioStreamIndex = selection.audio
            context?.subtitleStreamIndex = selection.subtitle
            if kind == .subtitle && track?.delivery != .externalVTT { subtitleCues = [] }
            trackInterval?.end()
            await progress()
            return
        }
        let position = engine.position
        let wasPaused = paused
        let nextRun = generation + 1
        let stopError = await finish(state: .loading, failed: false)
        guard generation == nextRun else { return }
        if stopError == .unauthorized {
            await checkCurrentUser(run: nextRun)
            return
        }
        trackChangePending = true
        paused = wasPaused
        // Renegotiation may return DirectPlay, remux, audio conversion or subtitle burn-in.
        attempt = .automatic
        await startAttempt(
            itemID: oldContext.itemID, start: position, run: nextRun,
            previousSessionID: oldContext.playSessionID)
        if isCurrent(nextRun), engineLoaded, context != nil { trackInterval?.end() }
    }

    public func setASSConversion(_ enabled: Bool) async {
        guard !selectingTrack, configuration.convertASS != enabled else { return }
        selectingTrack = true
        defer { selectingTrack = false }
        configuration.convertASS = enabled
        tracks = PlaybackTrack.map(sourceStreams, convertASS: enabled)
        PlaybackPreferences.setASSConversion(enabled)
        // Re-map from the next PlaybackInfo response; the selected ASS track must be renegotiated.
        guard let current = context, let track = tracks.first(where: { $0.id == selection.subtitle }),
            ["ass", "ssa"].contains(track.codec)
        else { return }
        let position = engine.position
        let wasPaused = paused
        let nextRun = generation + 1
        let stopError = await finish(state: .loading, failed: false)
        guard generation == nextRun else { return }
        if stopError == .unauthorized {
            await checkCurrentUser(run: nextRun)
            return
        }
        trackChangePending = true
        paused = wasPaused
        attempt = .automatic
        await startAttempt(
            itemID: current.itemID, start: position, run: nextRun,
            previousSessionID: current.playSessionID)
    }

    private func applyInitialNativeTracks(run: Int) async -> Bool {
        guard let selector = engine as? any PlaybackTrackSelecting else { return true }
        var matched = true
        if let track = tracks.first(where: { $0.kind == .audio && $0.id == selection.audio }),
            playMethod == .directPlay
        {
            matched = await selector.selectNativeTrack(track, kind: .audio, peers: tracks)
        }
        guard isCurrent(run) else { return false }
        let subtitle = tracks.first { $0.kind == .subtitle && $0.id == selection.subtitle }
        let subtitleMatched = await selector.selectNativeTrack(
            subtitle?.delivery == .embedded ? subtitle : nil,
            kind: .subtitle, peers: tracks)
        return matched && (subtitle?.delivery != .embedded || subtitleMatched)
    }

    public func stop() async {
        // SwiftUI disappearance and AVKit dismissal can both stop the same presentation.
        guard context != nil || state == .loading else { return }
        let terminalRun = generation + 1
        let error = await finish(state: .idle, failed: false)
        if error == .unauthorized, generation == terminalRun { await checkCurrentUser(run: terminalRun) }
    }

    /// Called only by the presentation surface when its first video frame is ready for display.
    /// AVPlayerItem.readyToPlay and timeControlStatus.playing are not first-frame signals.
    public func noteFirstFrameReady() {
        guard context != nil else { return }
        firstFrameInterval?.end()
        firstFrameInterval = nil
    }

    public func pause() { engine.pause() }
    public func resume() { engine.play() }

    public func seek(to position: Duration) async {
        guard context != nil else { return }
        await engine.seek(to: max(.zero, position))
    }

    private func isCurrent(_ run: Int) -> Bool { generation == run && !Task.isCancelled }

    private func continueStartup(_ run: Int) async -> Bool {
        guard generation == run else { return false }
        if Task.isCancelled {
            await finish(state: .idle, failed: false)
            return false
        }
        return true
    }

    private func handle(_ event: PlaybackEngineEvent, run: Int) async {
        switch event {
        case .ready:
            guard !started, context != nil else { return }
            if !configuration.isPoC {
                let matched = await applyInitialNativeTracks(run: run)
                guard isCurrent(run) else { return }
                if !matched {
                    await attemptFailed(run: run, fromEngineEvent: true)
                    return
                }
            }
            if paused { state = .paused }
            started = true
            let error = await report("")
            guard isCurrent(run) else { return }
            if error == .unauthorized {
                await mediaUnauthorized()
                return
            }
            guard isCurrent(run), context != nil else { return }
            timer.start { [weak self] in await self?.progress() }
            if trackChangePending {
                trackChangePending = false
                await progress()
            }
        case .playing:
            firstFrameTask?.cancel()
            firstFrameTask = nil
            state = .playing
            if paused {
                paused = false
                await progress()
            }
        case .paused:
            guard started, !paused else { return }
            firstFrameTask?.cancel()
            paused = true
            state = .paused
            await progress()
        case .buffering: state = .buffering
        case .seeked: await progress()
        case .trackChanged(let kind, let id):
            guard !configuration.isPoC else { return }
            if kind == .audio {
                selection.audio = id
            } else {
                selection.subtitle = id ?? -1
                subtitleCues = []
            }
            context?.audioStreamIndex = selection.audio
            context?.subtitleStreamIndex = selection.subtitle
            refreshDiagnostics()
            await progress()
        case .ended:
            let terminalRun = generation + 1
            let error = await finish(state: .ended, failed: false)
            if error == .unauthorized, generation == terminalRun { await checkCurrentUser(run: terminalRun) }
        case .failed(.unauthorized): await mediaUnauthorized()
        case .failed(.cancelled): break
        case .failed: await attemptFailed(run: run, fromEngineEvent: true)
        }
    }

    private func refreshDiagnostics() {
        guard let sourceSnapshot, let playMethod else { return }
        diagnostics = PlaybackDiagnostics(source: sourceSnapshot, method: playMethod, selection: selection)
    }

    private func progress() async {
        guard started, context != nil else { return }
        let run = generation
        if await report("/Progress") == .unauthorized, isCurrent(run) { await mediaUnauthorized() }
    }

    private func report(_ event: String) async -> APIError? {
        guard let context else { return nil }
        return await reporter.send(
            event, context: context, position: engine.position, paused: paused, canSeek: engine.canSeek
        )
    }

    @discardableResult
    private func finish(state terminal: PlaybackState, failed: Bool) async -> APIError? {
        firstFrameInterval?.end(completed: false)
        firstFrameInterval = nil
        lifetimeInterval?.end(completed: !failed)
        lifetimeInterval = nil
        generation += 1
        firstFrameTask?.cancel()
        firstFrameTask = nil
        retryTask?.cancel()
        retryTask = nil
        timer.cancel()
        eventsTask?.cancel()
        eventsTask = nil
        let stopped = context
        context = nil
        subtitleCues = []
        let position = engineLoaded ? engine.position : startPosition
        let canSeek = engineLoaded && engine.canSeek
        engineLoaded = false
        engine.stop()
        started = false
        guard let stopped else {
            state = terminal
            return nil
        }
        let result = PlaybackStop(itemID: stopped.itemID, position: position, finished: terminal == .ended)
        lastStop = result
        let terminalRun = generation
        let task = Task { [onStopped, reporter, paused] in
            await onStopped?(result)
            return await reporter.send(
                "/Stopped", context: stopped, position: position, paused: paused, canSeek: canSeek, failed: failed)
        }
        stoppingTask = task
        state = terminal
        let error = await task.value
        if generation == terminalRun { stoppingTask = nil }
        return error
    }

    private func fail(_ reason: PlaybackFailure) async {
        let terminalRun = generation + 1
        let error = await finish(state: .failed(localizedKey: reason.localizedKey), failed: true)
        // Publish the final reason after Stopped completes, unless another playback has taken over.
        guard generation == terminalRun else { return }
        failure = reason
        if error == .unauthorized { await checkCurrentUser(run: terminalRun) }
    }

    private func mediaUnauthorized() async {
        // Invalidate the run before awaiting Stopped. Duplicate player failures cannot start another probe.
        let terminalRun = generation + 1
        _ = await finish(state: .failed(localizedKey: PlaybackCopy.couldNotPlayKey), failed: true)
        guard generation == terminalRun else { return }
        await checkCurrentUser(run: terminalRun)
    }

    private func checkCurrentUser(run: Int) async {
        // Stopping cancels the engine-event task. The one auth probe must survive that cancellation.
        let decision = await Task { [api] in await MediaUnauthorizedPolicy.decide(probe: api) }.value
        guard generation == run else { return }
        switch decision {
        case .logOut: await expireSession(run: run)
        case .playbackError:
            failure = .couldNotPlay
            state = .failed(localizedKey: PlaybackCopy.couldNotPlayKey)
        }
    }

    private func expireSession(run: Int) async {
        guard generation == run, state != .sessionExpired else { return }
        state = .sessionExpired
        await session.sessionExpired()
    }

    isolated deinit {
        firstFrameTask?.cancel()
        retryTask?.cancel()
        eventsTask?.cancel()
        timer.cancel()
        engine.stop()
    }
}
