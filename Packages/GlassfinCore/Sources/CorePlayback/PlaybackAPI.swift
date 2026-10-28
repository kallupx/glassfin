import CoreModels
import CoreNetworking
import Foundation

/// All API traffic uses the auth provider's CoreNetworking client, including its trust policy.
public struct PlaybackAPI: Sendable, CurrentUserProbing {
    public let client: any JellyfinAPIClient

    public init(client: any JellyfinAPIClient) { self.client = client }

    public func item(itemID: String, userID: String) async throws(APIError) -> BaseItemDTO {
        let item = try ItemID.require(itemID).value
        let user = try ItemID.require(userID).value
        return try await client.send(
            APIRequest(
                method: "GET", path: "/Users/\(user)/Items/\(item)",
                query: [URLQueryItem(name: "Fields", value: "MediaStreams")]
            ), as: BaseItemDTO.self
        )
    }

    public func playbackInfo(
        itemID: String, userID: String, start: Duration, maxBitrate: Int, enableDirectPlay: Bool = true,
        audioStreamIndex: Int? = nil, subtitleStreamIndex: Int = -1
    ) async throws(APIError) -> PlaybackInfoResponseDTO {
        let item = try ItemID.require(itemID).value
        let body = PlaybackInfoBody(
            UserId: try ItemID.require(userID).value,
            StartTimeTicks: Ticks.outboundPositionTicks(from: start),
            MaxStreamingBitrate: max(1, maxBitrate), EnableDirectPlay: enableDirectPlay,
            AudioStreamIndex: audioStreamIndex, SubtitleStreamIndex: subtitleStreamIndex
        )
        return try await client.send(
            APIRequest(method: "POST", path: "/Items/\(item)/PlaybackInfo", body: try Self.encode(body)),
            as: PlaybackInfoResponseDTO.self
        )
    }

    public func currentUser() async throws(APIError) {
        _ = try await client.send(APIRequest(method: "GET", path: "/Users/Me"))
    }

    static func encode(_ value: some Encodable) throws(APIError) -> Data {
        do { return try JSONEncoder().encode(value) } catch { throw .decoding }
    }
}

private struct PlaybackInfoBody: Encodable {
    let UserId: String
    let StartTimeTicks: Int64
    let MaxStreamingBitrate: Int
    let DeviceProfile = PlaybackDeviceProfile()
    let EnableDirectPlay: Bool
    let EnableDirectStream = true
    let EnableTranscoding = true
    let AllowVideoStreamCopy = true
    let AllowAudioStreamCopy = true
    let AudioStreamIndex: Int?
    // Default to no forced/burn-in subtitles unless the caller explicitly selects a track.
    let SubtitleStreamIndex: Int
}
