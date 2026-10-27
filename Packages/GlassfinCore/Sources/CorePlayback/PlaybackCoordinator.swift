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
    public let engine: any PlaybackEngine

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

    public init(
        session: any PlaybackSessionProviding, engine: any PlaybackEngine, origin: any MediaOriginClient,
        timer: any PlaybackProgressScheduling = PlaybackProgressTimer(),
        maxBitrate: Int = 120_000_000, log: any GlassfinLog = SilentLog()
    ) {
        self.session = session
        self.engine = engine
        self.origin = origin
        self.timer = timer
        self.maxBitrate = maxBitrate
        self.log = PlaybackLog(sink: log)
        self.api = PlaybackAPI(client: session.apiClient)
        self.reporter = PlaybackReporter(client: session.apiClient, log: log)
    }

    public func play(itemID: String, choice: PlaybackStartChoice = .resume) async {
        await stop()
        generation += 1
        let run = generation
        failure = nil
        paused = false
        state = .loading
        do {
            let item = try await api.item(itemID: itemID, userID: session.userID)
            guard await continueStartup(run) else { return }
            let metadata = item.MediaSources?.first
            guard
                PlaybackDecision.supportsVideo(
                    streams: metadata?.MediaStreams ?? item.MediaStreams,
                    defaultIndex: metadata?.DefaultVideoStreamIndex
                )
            else { throw PlaybackFailure.unsupportedVideo }
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
            let info = try await api.playbackInfo(
                itemID: itemID, userID: session.userID, start: start, maxBitrate: maxBitrate
            )
            guard await continueStartup(run) else { return }
            guard info.ErrorCode == nil, let source = info.MediaSources?.first,
                let sourceID = source.Id, let playSessionID = info.PlaySessionId, !playSessionID.isEmpty
            else { throw PlaybackFailure.couldNotPlay }
            let decision = PlaybackDecision.decide(mediaSource: source)
            let delivery: MediaDelivery
            let url: URL
            switch decision {
            case .unsupported(let reason): throw reason
            case .directPlay:
                delivery = source.Container?.lowercased() == "hls" ? .serverHLS : .directFile
                url = try MediaURLBuilder.directPlay(
                    server: session.serverURL, identity: session.identity,
                    itemID: itemID, mediaSourceID: sourceID, playSessionID: playSessionID
                ).url
            case .directStream(let conversion):
                delivery = .serverHLS
                url = try MediaURLBuilder.videoCopyHLS(
                    server: session.serverURL, transcodingURL: source.TranscodingUrl ?? "", conversion: conversion
                )
            }
            context = PlaybackReportContext(
                itemID: try ItemID.require(itemID).value, mediaSourceID: try ItemID.require(sourceID).value,
                playSessionID: playSessionID, method: decision == .directPlay ? .directPlay : .directStream
            )
            if delivery == .serverHLS, case .pinnedSelfSigned = session.trust {
                throw PlaybackFailure.hlsSegmentsBypassPinnedTrust
            }
            let header = try session.identity.authorizationHeader()
            let result = try await PlaybackPreparation(client: origin, log: log).prepare(
                delivery: delivery, initialURL: url, authorizationHeader: header,
                options: MediaOpenOptions(trust: session.trust, headerFieldsKeyAvailable: false)
            )
            guard await continueStartup(run) else { return }
            let carrier: ResourceLoaderCarrier
            switch result {
            case .open(let plan):
                // No fallback chain in M08a-PoC, including in Debug builds.
                if plan.primary.block == .hlsSegmentsBypassPinnedTrust {
                    throw PlaybackFailure.hlsSegmentsBypassPinnedTrust
                }
                guard case .resourceLoader(let value) = plan.primary else { throw PlaybackFailure.couldNotPlay }
                carrier = value
            case .rejected(.transport(status: 401)): throw APIError.unauthorized
            case .rejected(.insecureRedirect): throw PlaybackFailure.insecureRedirect
            case .rejected: throw PlaybackFailure.couldNotPlay
            }
            let events = engine.events
            eventsTask = Task { [weak self] in
                for await event in events {
                    guard let self, !Task.isCancelled, self.isCurrent(run) else { return }
                    await self.handle(event, run: run)
                }
            }
            try await engine.load(carrier, startAt: start)
            guard await continueStartup(run) else { return }
            engine.play()
        } catch {
            guard generation == run else { return }
            if Task.isCancelled || error as? APIError == .cancelled {
                await finish(state: .idle, failed: false)
                return
            }
            if let error = error as? APIError, error == .unauthorized {
                if context != nil {
                    await mediaUnauthorized()
                } else {
                    await expireSession(run: run)
                }
            } else {
                await fail((error as? PlaybackFailure) ?? .couldNotPlay)
            }
        }
    }

    public func stop() async {
        // SwiftUI disappearance and AVKit dismissal can both stop the same presentation.
        guard context != nil || state == .loading else { return }
        let terminalRun = generation + 1
        let error = await finish(state: .idle, failed: false)
        if error == .unauthorized, generation == terminalRun { await checkCurrentUser(run: terminalRun) }
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
            started = true
            let error = await report("")
            guard isCurrent(run) else { return }
            if error == .unauthorized {
                await mediaUnauthorized()
                return
            }
            guard isCurrent(run), context != nil else { return }
            timer.start { [weak self] in await self?.progress() }
        case .playing:
            state = .playing
            if paused {
                paused = false
                await progress()
            }
        case .paused:
            guard started, !paused else { return }
            paused = true
            state = .paused
            await progress()
        case .buffering: state = .buffering
        case .seeked: await progress()
        case .ended:
            let terminalRun = generation + 1
            let error = await finish(state: .ended, failed: false)
            if error == .unauthorized, generation == terminalRun { await checkCurrentUser(run: terminalRun) }
        case .failed(.unauthorized): await mediaUnauthorized()
        case .failed: await fail(.couldNotPlay)
        }
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
        generation += 1
        timer.cancel()
        eventsTask?.cancel()
        eventsTask = nil
        let stopped = context
        context = nil
        let position = engine.position
        let canSeek = engine.canSeek
        engine.stop()
        started = false
        state = terminal
        guard let stopped else { return nil }
        return await reporter.send(
            "/Stopped", context: stopped, position: position, paused: paused, canSeek: canSeek, failed: failed
        )
    }

    private func fail(_ reason: PlaybackFailure) async {
        failure = reason
        let terminalRun = generation + 1
        let error = await finish(state: .failed(localizedKey: reason.localizedKey), failed: true)
        if error == .unauthorized, generation == terminalRun { await checkCurrentUser(run: terminalRun) }
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
        eventsTask?.cancel()
        timer.cancel()
        engine.stop()
    }
}
