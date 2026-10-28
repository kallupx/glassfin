import CoreModels
import CoreNetworking
import Foundation

extension PlaybackAPI {
    public func userConfiguration() async throws(APIError) -> PlaybackUserConfigurationDTO? {
        try await client.send(APIRequest(method: "GET", path: "/Users/Me"), as: UserDTO.self).Configuration
    }

    public func negotiate(
        itemID: String, userID: String, start: Duration, profile: RuntimeDeviceProfile,
        maxBitrate: Int, attempt: PlaybackAttempt, selection: PlaybackTrackSelection, mediaSourceID: String?
    ) async throws(APIError) -> PlaybackInfoResponseDTO {
        let item = try ItemID.require(itemID).value
        let body = NegotiationBody(
            UserId: try ItemID.require(userID).value, StartTimeTicks: Ticks.outboundPositionTicks(from: start),
            MaxStreamingBitrate: max(1, maxBitrate), DeviceProfile: profile,
            EnableDirectPlay: attempt == .automatic, AllowVideoStreamCopy: attempt != .transcode,
            AudioStreamIndex: selection.audio, SubtitleStreamIndex: selection.subtitle,
            MediaSourceId: mediaSourceID)
        return try await client.send(
            APIRequest(method: "POST", path: "/Items/\(item)/PlaybackInfo", body: try Self.encode(body)),
            as: PlaybackInfoResponseDTO.self)
    }

    public func subtitles(
        itemID: String, mediaSourceID: String, index: Int, clock: any GlassfinClock = SystemGlassfinClock()
    ) async throws(APIError) -> [SubtitleCue] {
        let item = try ItemID.require(itemID).value
        let source = try ItemID.require(mediaSourceID).value
        guard index >= 0 else { throw .invalidURL }
        let request = APIRequest(
            method: "GET", path: "/Videos/\(item)/\(source)/Subtitles/\(index)/Stream.vtt",
            query: [URLQueryItem(name: "format", value: "vtt")], maximumResponseBytes: WebVTT.maximumBytes)
        do {
            let data = try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask { try await client.send(request) }
                group.addTask {
                    try await clock.sleep(for: .seconds(15))
                    throw APIError.timeout
                }
                defer { group.cancelAll() }
                guard let data = try await group.next() else { throw APIError.cancelled }
                return data
            }
            return try WebVTT.parse(data)
        } catch let error as APIError {
            throw error
        } catch {
            throw Task.isCancelled ? .cancelled : .network
        }
    }
}

private struct NegotiationBody: Encodable {
    let UserId: String
    let StartTimeTicks: Int64
    let MaxStreamingBitrate: Int
    let DeviceProfile: RuntimeDeviceProfile
    let EnableDirectPlay: Bool
    let EnableDirectStream = true
    let EnableTranscoding = true
    let AllowVideoStreamCopy: Bool
    let AllowAudioStreamCopy = true
    let AudioStreamIndex: Int?
    let SubtitleStreamIndex: Int?
    let MediaSourceId: String?
}
