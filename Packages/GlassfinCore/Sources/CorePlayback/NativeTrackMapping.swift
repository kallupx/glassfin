import Foundation

/// Portable matching policy shared by AVPlayer's live selection and unit tests.
public struct NativeTrackOption: Sendable {
    public let title: String
    public let language: String?
    public init(title: String, language: String?) {
        self.title = title
        self.language = language
    }
}

public enum NativeTrackMapping {
    public static func optionIndex(for track: PlaybackTrack, options: [NativeTrackOption], peers: [PlaybackTrack])
        -> Int?
    {
        let titled = options.indices.filter { options[$0].title == track.title }
        if titled.count == 1 { return titled.first }
        let language = options.indices.filter {
            PlaybackTrackSelection.languageMatches(options[$0].language, track.language)
        }
        let sameLanguagePeers = peers.filter {
            $0.kind == track.kind && PlaybackTrackSelection.languageMatches($0.language, track.language)
        }
        if language.count == 1 && sameLanguagePeers.count == 1 { return language.first }
        if options.count == 1 && peers.filter({ $0.kind == track.kind }).count == 1 { return 0 }
        return nil
    }
}
