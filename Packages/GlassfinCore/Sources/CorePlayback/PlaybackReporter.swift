import CoreModels
import CoreNetworking
import Foundation

struct PlaybackReportContext: Sendable {
    let itemID: String
    let mediaSourceID: String
    let playSessionID: String
    let method: PlayMethod
    var audioStreamIndex: Int? = nil
    var subtitleStreamIndex: Int? = nil
}

/// Serializes reports across actor reentrancy so Stopped cannot overtake Playing or Progress.
actor PlaybackReporter {
    private let client: any JellyfinAPIClient
    private let log: PlaybackLog
    private var tail: Task<APIError?, Never>?

    init(client: any JellyfinAPIClient, log: any GlassfinLog) {
        self.client = client
        self.log = PlaybackLog(sink: log)
    }

    func send(
        _ event: String, context: PlaybackReportContext, position: Duration,
        paused: Bool, canSeek: Bool, failed: Bool = false
    ) async -> APIError? {
        let previous = tail
        let task = Task { [client, log] () -> APIError? in
            _ = await previous?.value
            let body = PlaybackReportBody(
                ItemId: context.itemID, MediaSourceId: context.mediaSourceID,
                PlaySessionId: context.playSessionID, PlayMethod: context.method.reportValue,
                PositionTicks: Ticks.outboundPositionTicks(from: position), IsPaused: paused,
                CanSeek: canSeek, Failed: failed,
                AudioStreamIndex: context.audioStreamIndex, SubtitleStreamIndex: context.subtitleStreamIndex
            )
            for attempt in 0...1 {
                do {
                    _ = try await client.send(
                        APIRequest(
                            method: "POST", path: "/Sessions/Playing" + event, body: try PlaybackAPI.encode(body))
                    )
                    return nil
                } catch {
                    log.error("Playback report failed: \(error)")
                    // Only transient reporting errors get one retry. A 401 is never retried.
                    let apiError = (error as? APIError) ?? .network
                    let transient: Bool
                    switch apiError {
                    case .network, .timeout: transient = true
                    case .server(let status): transient = status >= 500
                    default: transient = false
                    }
                    if attempt == 1 || !transient { return apiError }
                }
            }
            return nil
        }
        tail = task
        return await task.value
    }
}

private struct PlaybackReportBody: Encodable {
    let ItemId: String
    let MediaSourceId: String
    let PlaySessionId: String
    let PlayMethod: String
    let PositionTicks: Int64
    let IsPaused: Bool
    let CanSeek: Bool
    let Failed: Bool
    let AudioStreamIndex: Int?
    let SubtitleStreamIndex: Int?
}

extension PlayMethod {
    public var reportValue: String {
        switch self {
        case .directPlay: "DirectPlay"
        case .directStream: "DirectStream"
        case .transcode: "Transcode"
        }
    }
}
