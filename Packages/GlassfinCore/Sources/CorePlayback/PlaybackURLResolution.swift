import CoreModels
import CoreNetworking
import Foundation

public enum PlaybackResolution: Sendable, Equatable {
    case resolved(URL)
    case rejected(PlaybackResolutionFailure)
}

public enum PlaybackResolutionFailure: Sendable, Equatable {
    /// Cross-origin, HTTPS→HTTP, or a credential query leaving its origin. Not given to AVPlayer.
    case insecureRedirect
    case tooManyHops
    case loop
    case transport(status: Int)
    case missingAuthorization
}

public enum MediaCredentialMode: Sendable, Equatable {
    /// Token in `Authorization`. Credential queries are stripped before the fetch.
    case authorizationHeader
    /// Opt-in fallback. No `Authorization` header. A same-origin redirect keeps the credential query.
    case queryCredential
}

/// Follows redirects with Glassfin's client before a URL is given to AVPlayer.
///
/// The original request plus five followed redirects are allowed. The sixth redirect fails
/// closed. Q8-2-06: the same rule applies to every resource-loader fetch, including variant
/// playlists, keys, and segments. AVPlayer is given only the resolved URL.
public struct PlaybackURLResolver: Sendable {
    public var client: any MediaOriginClient
    public var log: any GlassfinLog
    public var maxRedirects: Int

    public init(
        client: any MediaOriginClient,
        log: any GlassfinLog = SilentLog(),
        maxRedirects: Int = RedirectFollowLimit.maximum
    ) {
        self.client = client
        self.log = log
        self.maxRedirects = maxRedirects
    }

    public func resolve(
        start: URL,
        method: String,
        authorizationHeader: String?,
        trust: ServerTrustClass,
        mode: MediaCredentialMode = .authorizationHeader
    ) async throws(APIError) -> PlaybackResolution {
        let header: String? = mode == .authorizationHeader ? authorizationHeader : nil
        if mode == .authorizationHeader, header == nil || header?.isEmpty == true {
            return .rejected(.missingAuthorization)
        }
        var current = mode == .authorizationHeader ? MediaCredentialQuery.stripping(start) : start
        var seen: Set<String> = [current.absoluteString]
        var redirects = 0
        var verb = method
        var retriedMethod = false
        while true {
            guard
                let request = OriginMediaRequest(
                    method: verb,
                    url: current,
                    authorizationHeader: header,
                    range: retriedMethod ? HTTPByteRange(start: 0, end: 1) : nil,
                    trust: trust
                )
            else {
                return .rejected(.missingAuthorization)
            }
            let response = try await client.fetch(request)
            // TODO(Q8-2-05): 10.10 and 10.11 may not implement HEAD. Until that is closed, retry once with GET.
            if response.status == 405 || response.status == 501, verb == "HEAD", !retriedMethod {
                retriedMethod = true
                verb = "GET"
                continue
            }
            if (200..<300).contains(response.status) {
                log.debug("Playback URL resolved: \(MediaLogRedactor.redact(current.absoluteString))")
                return .resolved(current)
            }
            guard (300..<400).contains(response.status), let location = response.location else {
                log.debug("Playback URL probe failed with status \(response.status)")
                return .rejected(.transport(status: response.status))
            }
            let absolute = Self.absolute(location, base: current)
            redirects += 1
            if redirects > maxRedirects {
                log.debug("Playback redirect limit reached: \(MediaLogRedactor.redact(absolute.absoluteString))")
                return .rejected(.tooManyHops)
            }
            let next: URL
            switch RedirectPolicy.decide(originalURL: current, redirectURL: absolute) {
            case .reject:
                log.debug("Playback redirect rejected: \(MediaLogRedactor.redact(absolute.absoluteString))")
                return .rejected(.insecureRedirect)
            case .follow(let stripAuthorization):
                if stripAuthorization && !Self.isHTTPUpgrade(current, absolute) {
                    log.debug("Playback cross-origin redirect: \(MediaLogRedactor.redact(absolute.absoluteString))")
                    return .rejected(.insecureRedirect)
                }
                let downgrade = MediaOrigin.isHTTPSDowngrade(current, absolute)
                let differentOrigin = !MediaOrigin.matches(current, absolute)
                let upgrade = Self.isHTTPUpgrade(current, absolute)
                if downgrade || (differentOrigin && !upgrade) {
                    return .rejected(.insecureRedirect)
                }
                if mode == .queryCredential {
                    next = Self.preservingCredentials(from: current, to: absolute)
                } else {
                    next = MediaCredentialQuery.stripping(absolute)
                }
            }
            if seen.contains(next.absoluteString) {
                return .rejected(.loop)
            }
            seen.insert(next.absoluteString)
            current = next
            verb = method
            retriedMethod = false
        }
    }

    private static func preservingCredentials(from current: URL, to location: URL) -> URL {
        guard var components = URLComponents(url: location, resolvingAgainstBaseURL: false) else { return location }
        let carried = URLComponents(url: current, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let credentials = carried.filter { MediaCredentialQuery.isCredentialName($0.name) }
        guard !credentials.isEmpty else { return location }
        var items = components.queryItems ?? []
        if items.contains(where: { MediaCredentialQuery.isCredentialName($0.name) }) {
            return location
        }
        items.append(contentsOf: credentials)
        components.queryItems = items
        return components.url ?? location
    }

    private static func absolute(_ location: URL, base: URL) -> URL {
        if location.scheme != nil { return location.absoluteURL }
        return URL(string: location.relativeString, relativeTo: base)?.absoluteURL ?? location
    }

    private static func isHTTPUpgrade(_ original: URL, _ redirect: URL) -> Bool {
        guard original.scheme?.lowercased() == "http", redirect.scheme?.lowercased() == "https" else { return false }
        return original.host?.lowercased() == redirect.host?.lowercased()
    }
}
