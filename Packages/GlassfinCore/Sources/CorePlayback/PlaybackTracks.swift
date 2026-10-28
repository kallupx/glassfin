import CoreModels
import Foundation

public struct PlaybackTrack: Identifiable, Sendable, Equatable {
    public enum Kind: String, Sendable { case audio, subtitle }
    public enum Delivery: Sendable { case embedded, externalVTT, burnIn, server }
    public let id: Int
    public let kind: Kind
    public let title: String
    public let language: String?
    public let codec: String
    public let isDefault: Bool
    public let isForced: Bool
    public let delivery: Delivery

    public static func map(_ streams: [MediaStreamDTO], convertASS: Bool = true) -> [Self] {
        var seen: Set<Int> = []
        return streams.compactMap { stream in
            guard let kind = Kind(rawValue: stream.Type?.lowercased() ?? ""),
                let index = stream.Index, index >= 0, seen.insert(index).inserted
            else { return nil }
            let codec = stream.Codec?.lowercased() ?? ""
            let delivery: Delivery
            if kind == .audio {
                delivery = stream.IsExternal == true ? .server : .embedded
            } else if ["pgssub", "pgs", "dvdsub", "vobsub"].contains(codec)
                || (["ass", "ssa"].contains(codec) && !convertASS)
            {
                delivery = .burnIn
            } else if stream.DeliveryMethod?.lowercased() == "external" {
                delivery = .externalVTT
            } else if codec == "mov_text" && stream.IsExternal != true {
                delivery = .embedded
            } else {
                delivery = .externalVTT
            }
            return Self(
                id: index, kind: kind,
                title: MetadataSanitizer.displayText(stream.DisplayTitle ?? stream.Language ?? codec, limit: 200),
                language: stream.Language, codec: codec, isDefault: stream.IsDefault == true,
                isForced: stream.IsForced == true, delivery: delivery)
        }
    }
}

public struct PlaybackTrackSelection: Sendable, Equatable {
    public var audio: Int?
    /// -1 is Jellyfin's explicit subtitles-off value; nil lets the server choose the default.
    public var subtitle: Int?
    public init(audio: Int? = nil, subtitle: Int? = nil) {
        self.audio = audio
        self.subtitle = subtitle
    }

    public static func defaults(tracks: [PlaybackTrack], user: PlaybackUserConfigurationDTO?) -> Self {
        let audio = tracks.filter { $0.kind == .audio }
        let subtitles = tracks.filter { $0.kind == .subtitle }
        let preferredAudio = audio.first { languageMatches($0.language, user?.AudioLanguagePreference) }
        let chosenAudio =
            (user?.PlayDefaultAudioTrack == true ? nil : preferredAudio)
            ?? audio.first { $0.isDefault } ?? audio.first
        let preferredSubtitle = subtitles.first { languageMatches($0.language, user?.SubtitleLanguagePreference) }
        let chosenSubtitle: Int?
        switch user?.SubtitleMode?.lowercased() {
        case "none": chosenSubtitle = -1
        case "always":
            chosenSubtitle = (preferredSubtitle ?? subtitles.first { $0.isDefault } ?? subtitles.first)?.id ?? -1
        case "onlyforced": chosenSubtitle = subtitles.first { $0.isForced }?.id ?? -1
        case "smart":
            chosenSubtitle =
                languageMatches(chosenAudio?.language, user?.SubtitleLanguagePreference)
                ? (subtitles.first { $0.isForced }?.id ?? -1) : (preferredSubtitle?.id ?? -1)
        default:
            // Leave Default mode to Jellyfin's full forced/default/language policy.
            chosenSubtitle = nil
        }
        return Self(audio: chosenAudio?.id, subtitle: chosenSubtitle)
    }

    public static func languageMatches(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs, !lhs.isEmpty, !rhs.isEmpty else { return false }
        func normalized(_ value: String) -> String {
            let code = value.lowercased().split(separator: "-").first.map(String.init) ?? value.lowercased()
            return ["fi": "fin", "en": "eng", "ja": "jpn", "zh": "zho", "chi": "zho", "ko": "kor"][code] ?? code
        }
        return normalized(lhs) == normalized(rhs)
    }
}

/// Return false when native options cannot be matched unambiguously: the caller renegotiates.
@MainActor
public protocol PlaybackTrackSelecting: AnyObject {
    func selectNativeTrack(_ track: PlaybackTrack?, kind: PlaybackTrack.Kind, peers: [PlaybackTrack]) async -> Bool
}
