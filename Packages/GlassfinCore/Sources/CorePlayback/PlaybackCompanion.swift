import CoreModels
import CoreNetworking
import Foundation
import Observation

/// Optional playback features have an independent lifetime from stream negotiation and track selection.
@MainActor
@Observable
public final class PlaybackCompanion {
    public private(set) var segment: TimedSegment?
    public private(set) var next: NextEpisode?
    public private(set) var countdownSeconds: Int?
    public private(set) var runtime: Duration?
    public private(set) var layout: TrickplayLayout?
    public private(set) var scrubPosition: Duration?
    public private(set) var previewBytes: Data?
    public private(set) var previewFrame: TrickplayFrame?
    public private(set) var returnFocusItemID: String?
    public private(set) var advancing = false
    public var transportVisible = false
    public var settings: PlaybackFeatureSettings
    public let cache = TrickplayCache()

    private let client: any JellyfinAPIClient
    private let userID: String
    private let seek: @MainActor (Duration) async -> Void
    private let stop: @MainActor () async -> Void
    private let play: @MainActor (String) async -> Void
    private let unauthorized: @MainActor () async -> Void
    private let completed: @MainActor (String, Duration) async -> Void
    private var itemID: String?
    private var sourceID: String?
    private var segments: [TimedSegment] = []
    private var countdown = NextEpisodeCountdown()
    private var run = 0
    private var previewTask: Task<Void, Never>?
    private var advanceTask: Task<Void, Never>?
    private var autoSkipped: TimedSegment?
    private var runtimeTicks: Int64?
    private var handoffStarted = false

    public init(
        client: any JellyfinAPIClient, userID: String, settings: PlaybackFeatureSettings = .init(),
        seek: @escaping @MainActor (Duration) async -> Void,
        stop: @escaping @MainActor () async -> Void,
        play: @escaping @MainActor (String) async -> Void,
        unauthorized: @escaping @MainActor () async -> Void,
        completed: @escaping @MainActor (String, Duration) async -> Void = { _, _ in }
    ) {
        self.client = client
        self.userID = userID
        self.settings = settings
        self.seek = seek
        self.stop = stop
        self.play = play
        self.unauthorized = unauthorized
        self.completed = completed
    }

    public func load(itemID: String, mediaSourceID: String) async {
        run += 1
        let current = run
        previewTask?.cancel()
        self.itemID = itemID
        sourceID = mediaSourceID
        segment = nil
        next = nil
        countdownSeconds = nil
        runtime = nil
        runtimeTicks = nil
        layout = nil
        segments = []
        scrubPosition = nil
        previewBytes = nil
        previewFrame = nil
        returnFocusItemID = nil
        countdown = NextEpisodeCountdown()
        autoSkipped = nil
        handoffStarted = false
        await cache.removeAll()
        guard let item = ItemID(itemID), let user = ItemID(userID), ItemID(mediaSourceID) != nil else { return }
        do {
            let metadata = try await optional(
                APIRequest(
                    method: "GET", path: "/Users/\(user.value)/Items/\(item.value)",
                    query: [URLQueryItem(name: "Fields", value: "Trickplay")], maximumResponseBytes: 1_048_576),
                as: BaseItemDTO.self)
            guard current == run, !Task.isCancelled else { return }
            runtimeTicks = metadata?.RunTimeTicks
            runtime = Ticks.runtimeDuration(from: runtimeTicks)
            if let values = metadata?.Trickplay?[mediaSourceID] { layout = TrickplayLayout.select(values) }
            let response = try await optional(
                APIRequest(method: "GET", path: "/MediaSegments/\(item.value)", maximumResponseBytes: 1_048_576),
                as: SegmentResponse.self)
            guard current == run, !Task.isCancelled else { return }
            segments = SegmentTimeline.ordered(
                (response?.items ?? []).compactMap { dto in
                    guard let kind = SegmentKind(rawValue: dto.Type ?? ""), let start = dto.StartTicks,
                        let end = dto.EndTicks
                    else { return nil }
                    return TimedSegment(kind: kind, start: start, end: end, runtime: runtimeTicks)
                })
            if let series = metadata?.SeriesId, let seriesID = ItemID(series), metadata?.Type == "Episode" {
                let response = try await optional(
                    APIRequest(
                        method: "GET", path: "/Shows/\(seriesID.value)/Episodes",
                        query: [
                            URLQueryItem(name: "userId", value: user.value),
                            URLQueryItem(name: "startItemId", value: item.value),
                            URLQueryItem(name: "limit", value: "2"),
                            URLQueryItem(name: "isMissing", value: "false"),
                        ], maximumResponseBytes: 1_048_576), as: QueryResultDTO.self)
                guard current == run, !Task.isCancelled else { return }
                next = NextEpisodeResolver.resolve(
                    currentID: item.value, seriesID: series, items: response?.Items ?? [])
            }
        } catch {
            if error as? APIError == .unauthorized, current == run, !Task.isCancelled { await unauthorized() }
        }
    }

    private func optional<T: Decodable & Sendable>(_ request: APIRequest, as type: T.Type) async throws -> T? {
        do { return try await client.send(request, as: type) } catch {
            if error == .unauthorized || error == .cancelled { throw error }
            // Missing/unsupported optional endpoints never interrupt playback.
            return nil
        }
    }

    public func update(position: Duration, isPlaying: Bool, now: Duration) async {
        guard itemID != nil, !advancing else { return }
        let ticks = Ticks.outboundPositionTicks(from: position)
        let active = SegmentTimeline.active(
            at: ticks, segments: segments.filter { settings.behavior(for: $0.kind) != .ignore })
        if autoSkipped != active { autoSkipped = nil }
        segment = active.flatMap { settings.behavior(for: $0.kind) == .ask ? $0 : nil }
        let trigger = SegmentTimeline.nextEpisodeTrigger(segments: segments, runtime: runtimeTicks)
        let eligible =
            settings.autoplay && next != nil && isPlaying && scrubPosition == nil
            && trigger.map { ticks >= $0 } == true
        let advance = countdown.update(now: now, eligible: eligible)
        countdownSeconds = countdown.remaining(now: now)
        if advance {
            playNext()
            return
        }
        // Next Up takes precedence over an automatic Outro skip so it gets its full countdown.
        if let active, settings.behavior(for: active.kind) == .automatic, active != autoSkipped,
            isPlaying, scrubPosition == nil, !(active.kind == .outro && eligible)
        {
            autoSkipped = active
            await seek(Ticks.positionDuration(from: active.end, log: SilentLog()))
        }
    }

    public func skipSegment() async {
        guard let segment else { return }
        self.segment = nil
        await seek(Ticks.positionDuration(from: segment.end, log: SilentLog()))
    }

    public func cancelNext() {
        countdown.cancel()
        countdownSeconds = nil
        returnFocusItemID = next?.id
    }

    public func playNext() {
        guard !advancing, !handoffStarted, let next, let itemID, let user = ItemID(userID) else { return }
        handoffStarted = true
        advancing = true
        countdown.consume()
        countdownSeconds = nil
        let position = runtime ?? .zero
        advanceTask = Task { [weak self] in
            guard let self else { return }
            // Stopped must complete before marking played and negotiating the following episode.
            await stop()
            guard !Task.isCancelled else {
                advancing = false
                return
            }
            do {
                _ = try await client.send(
                    APIRequest(method: "POST", path: "/Users/\(user.value)/PlayedItems/\(itemID)"))
            } catch {
                if error as? APIError == .unauthorized {
                    await unauthorized()
                    advancing = false
                    return
                }
            }
            await completed(itemID, position)
            guard !Task.isCancelled else {
                advancing = false
                return
            }
            await play(next.id)
            advancing = false
        }
    }

    public func scrub(to position: Duration) {
        guard let layout, let runtime, let itemID, let sourceID else { return }
        let position = min(max(.zero, position), runtime)
        scrubPosition = position
        let frame = layout.frame(at: position)
        if previewFrame?.tile != frame.tile { previewBytes = nil }
        previewFrame = frame
        let previous = previewTask
        previous?.cancel()
        let current = run
        previewTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            // At most one request at a time; replacing the scrub task cancels the bounded download.
            for index in layout.prefetchTiles(at: position) {
                guard !Task.isCancelled, current == run else { return }
                let resource = TrickplayTileResource(
                    itemID: itemID, mediaSourceID: sourceID, width: layout.width, index: index)
                do {
                    let cached = await cache.data(for: resource)
                    let data: Data
                    if let cached { data = cached } else { data = try await client.send(resource.request()) }
                    guard !Task.isCancelled, current == run else { return }
                    try ImageDataPolicy.validate(data)
                    if cached == nil { await cache.store(data, for: resource) }
                    if index == frame.tile { previewBytes = data }
                } catch {
                    if error as? APIError == .unauthorized, current == run, !Task.isCancelled {
                        await unauthorized()
                        return
                    }
                    if Task.isCancelled { return }
                }
            }
        }
    }

    public func endScrubbing(commit: Bool) async {
        let position = scrubPosition
        scrubPosition = nil
        previewBytes = nil
        previewFrame = nil
        previewTask?.cancel()
        if commit, let position { await seek(position) }
    }

    public func clearImages() async {
        previewTask?.cancel()
        previewBytes = nil
        await cache.removeAll()
    }

    public func nextImageData() async -> Data? {
        guard let next, let tag = next.imageTag else { return nil }
        let current = run
        do {
            return try await client.send(
                JellyfinImageResource(
                    serverID: "playback", itemID: next.id, type: .primary, tag: tag, width: 360, height: 202
                ).request())
        } catch {
            if error == .unauthorized, current == run, !Task.isCancelled { await unauthorized() }
            return nil
        }
    }

    public func shutdown() async {
        run += 1
        itemID = nil
        advanceTask?.cancel()
        await clearImages()
    }

    isolated deinit {
        previewTask?.cancel()
        advanceTask?.cancel()
    }
}

private struct SegmentResponse: Decodable, Sendable {
    let items: [MediaSegmentDTO]
    private enum CodingKeys: String, CodingKey { case Items }
    init(from decoder: Decoder) throws {
        // Jellyfin returns a query-result envelope; tolerate the legacy fixture's bare array too.
        if let array = try? decoder.singleValueContainer().decode([MediaSegmentDTO].self) {
            items = array
        } else {
            items =
                try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent([MediaSegmentDTO].self, forKey: .Items)
                ?? []
        }
    }
}
