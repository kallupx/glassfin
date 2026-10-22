import CoreModels
import Foundation

/// S4.6 for a URL that would be handed to AVPlayer.
///
/// AVPlayer follows redirects on its own, so only an already-resolved same-origin URL may leave
/// this function. See `spec/adr/M08-2.md`. Direct play is probed with HEAD and HLS with GET.
public enum MediaRedirectResolution: Sendable, Equatable {
    case playable(URL)
    case rejected(RedirectRejection)
}

public enum MediaURLSecurity {
    public static func resolve(start: URL, hops: [URL]) -> MediaRedirectResolution {
        var followed = 0
        var seen = [start]
        var current = start
        for hop in hops {
            if followed >= RedirectFollowLimit.maximum {
                return .rejected(.notFollowed)
            }
            if seen.contains(where: { RedirectFollowLimit.same($0, hop) }) {
                return .rejected(.notFollowed)
            }
            switch RedirectPolicy.decide(originalURL: start, redirectURL: hop) {
            case .reject(let reason):
                return .rejected(reason)
            case .follow(let strip):
                if strip {
                    return .rejected(.notFollowed)
                }
                followed += 1
                seen.append(hop)
                current = hop
            }
        }
        return .playable(current)
    }
}

public enum PlayerMediaHandoff {
    /// Nil means do not create the player item.
    public static func urlForPlayer(start: URL, hops: [URL]) -> URL? {
        guard case .playable(let url) = MediaURLSecurity.resolve(start: start, hops: hops) else {
            return nil
        }
        return url
    }
}

public enum MediaProbeMethod: Sendable, Equatable {
    /// `HEAD /Videos/{id}/stream`
    case directPlay
    /// GET of the master playlist.
    case hlsMaster

    public var httpMethod: String {
        switch self {
        case .directPlay:
            return "HEAD"
        case .hlsMaster:
            return "GET"
        }
    }
}
