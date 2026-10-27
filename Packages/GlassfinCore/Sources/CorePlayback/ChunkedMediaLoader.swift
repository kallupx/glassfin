import CoreModels
import Foundation

public enum MediaLoaderLimits {
    public static let chunkBytes = 2 * 1_024 * 1_024
    public static let playlistBytes = 4 * 1_024 * 1_024
}

/// Caps bytes while they arrive, even when an origin ignores the Range header.
public struct BoundedMediaBody: Sendable {
    public private(set) var data = Data()
    private let contentType: String?
    private var playlist: Bool
    private let byteLimit: Int

    public init(contentType: String?, url: URL, range: HTTPByteRange?) {
        self.contentType = contentType
        self.playlist =
            PlaylistSniffer.isPlaylistURL(url)
            || PlaylistSniffer.isPlaylist(contentType: contentType, body: Data())
        if let range, let end = range.end, range.start >= 0, end >= range.start {
            self.byteLimit = Int(min(Int64(MediaLoaderLimits.chunkBytes - 1), end - range.start)) + 1
        } else {
            self.byteLimit = MediaLoaderLimits.chunkBytes
        }
    }

    public mutating func append(_ byte: UInt8) throws(APIError) {
        // Sniff before enforcing the progressive limit, including very short range probes.
        if !playlist, data.count <= 64 {
            playlist = PlaylistSniffer.isPlaylist(contentType: contentType, body: data)
        }
        guard remainingByteCount > 0 else { throw .decoding }
        data.append(byte)
    }

    /// Keeps the same accepted prefix on failure as repeated single-byte appends.
    public mutating func append(contentsOf bytes: Data) throws(APIError) {
        var pending = bytes[...]
        // Preserve prefix sniffing before each limit check, even across chunks.
        while !pending.isEmpty, !playlist, data.count <= 64 {
            try append(pending.removeFirst())
        }
        let accepted = min(pending.count, remainingByteCount)
        data.append(contentsOf: pending.prefix(accepted))
        guard accepted == pending.count else { throw .decoding }
    }

    var remainingByteCount: Int {
        (playlist ? MediaLoaderLimits.playlistBytes : byteLimit) - data.count
    }
}

/// Each progressive fetch is bounded, including a request for all remaining bytes.
public enum ChunkedRangePlanner {
    public static func next(range: HTTPByteRange?, received: Int64, totalLength: Int64?) -> HTTPByteRange? {
        let initial = range?.start ?? 0
        guard initial >= 0, received >= 0 else { return nil }
        let (start, overflow) = initial.addingReportingOverflow(received)
        guard !overflow, start < Int64.max else { return nil }
        var end = start + min(Int64(MediaLoaderLimits.chunkBytes - 1), Int64.max - start)
        if let requestedEnd = range?.end {
            guard requestedEnd >= start else { return nil }
            end = min(end, requestedEnd)
        }
        if let totalLength {
            guard totalLength > start else { return nil }
            end = min(end, totalLength - 1)
        }
        return HTTPByteRange(start: start, end: end)
    }
}

/// A media 401 must be handed to `MediaUnauthorizedPolicy`, which probes `/Users/Me`.
/// Other failures never request a session check or logout.
public enum ResourceLoaderOutcome: Sendable, Equatable {
    case reply(PlayerByteReply)
    case failure(APIError)

    public static func classify(_ response: OriginMediaResponse, requestURL: URL) -> ResourceLoaderOutcome {
        if let error = HTTPStatusMapper.failure(for: response.status) { return .failure(error) }
        let playlist = PlaylistSniffer.isPlaylist(contentType: response.contentType, body: response.body)
        let limit = playlist ? MediaLoaderLimits.playlistBytes : MediaLoaderLimits.chunkBytes
        guard response.body.count <= limit,
            let reply = PlayerResponseBuilder.build(origin: response, requestURL: requestURL)
        else { return .failure(.decoding) }
        return .reply(reply)
    }
}

/// Fetches and delivers one chunk at a time. No preceding body is retained across fetches.
public enum ChunkedMediaLoader {
    public static func load(
        request: OriginMediaRequest,
        range: HTTPByteRange?,
        client: any MediaOriginClient,
        isCancelled: @Sendable () -> Bool,
        receive: @Sendable (PlayerByteReply) async throws(APIError) -> Void
    ) async throws(APIError) {
        var received: Int64 = 0
        var totalLength: Int64?
        while let next = ChunkedRangePlanner.next(range: range, received: received, totalLength: totalLength) {
            try checkCancellation(isCancelled)
            var chunkRequest = request
            chunkRequest.range = PlaylistSniffer.isPlaylistURL(request.url) ? nil : next
            var response = try await client.fetch(chunkRequest)
            try checkCancellation(isCancelled)
            // A MIME type or sniffed prefix can identify a playlist without an m3u8 extension.
            // Refetch it whole before rewriting: a partial playlist must never reach the player.
            if chunkRequest.range != nil,
                PlaylistSniffer.isPlaylist(contentType: response.contentType, body: response.body)
            {
                chunkRequest.range = nil
                response.body = Data()
                response = try await client.fetch(chunkRequest)
                try checkCancellation(isCancelled)
            }
            // An exact multiple of the chunk cap with an unknown total needs an EOF probe.
            if response.status == 416, let total = response.totalLength, total >= 0, next.start >= total { return }
            switch ResourceLoaderOutcome.classify(response, requestURL: request.url) {
            case .failure(let error):
                throw error
            case .reply(var reply):
                let playlist = !reply.isByteRangeAccessSupported
                if !playlist {
                    guard let end = next.end, response.body.count <= end - next.start + 1,
                        next.start == 0 || response.status == 206
                    else { throw .decoding }
                    totalLength = response.totalLength ?? totalLength
                    reply.contentLength = totalLength ?? 0
                }
                try checkCancellation(isCancelled)
                try await receive(reply)
                try checkCancellation(isCancelled)
                received += Int64(reply.data.count)
                if playlist || reply.data.isEmpty { return }
                if totalLength == nil, let end = next.end, Int64(reply.data.count) < end - next.start + 1 {
                    return
                }
            }
        }
    }

    private static func checkCancellation(_ isCancelled: @Sendable () -> Bool) throws(APIError) {
        if Task.isCancelled || isCancelled() { throw .cancelled }
    }
}
