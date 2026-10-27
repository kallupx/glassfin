import CoreModels
import CoreNetworking
import Foundation

public enum MediaDelivery: Sendable, Equatable {
    /// One file (`/Videos/{id}/stream?static=true`). The loader can serve byte ranges.
    case directFile
    /// Server HLS from `TranscodingUrl` (remux or transcode). Same token problem either way.
    case serverHLS
}

public enum MediaFinding: String, Sendable, Equatable, CaseIterable {
    case resourceLoaderServesProgressiveBytes
    case resourceLoaderSeesPlaylistsAndKeysOnly
    case hlsSegmentBytesCannotBeServedByResourceLoader
    case hlsSegmentsStayOnServerURLs
    case serverApiKeyOnSegmentsIsAcceptedRisk
    case headerFieldsKeyIsUndocumentedFallback
    case headerFieldsKeyDoesNotApplyPin
    case headerFieldsKeySegmentBehaviorUnverified
    case headerFieldsKeyUnavailable
    case pinnedTrustAppliesOnlyToLoaderFetches
    case avPlayerBypassesAppURLSession
    case apiKeyDoesNotFixTLS
    case selfSignedHLSNeedsLoopbackProxy
    case cleartextHasNoCertificatePin
    case apiKeyFallbackDisabled
    case deviceMeasurementRequired
}

/// ADR M08-2 scope after Q8-2-01. Case 3 is M08b, not this prototype.
public enum ADRM08Prototype {
    public static let prototypeCases = [1, 2]
    public static let case3Owner = "M08b"
    public static let simulatorServer =
        "In-test mock HTTP(S) server. A self-signed certificate is generated at runtime."
        + " macOS runners do not use Docker."
    public static let linuxDockerScope = "URL construction, token placement, and PlaybackInfo only."
    /// Order for case 1: resource loader, then the undocumented header key, then a credential query.
    public static let case1Order = ["resourceLoader", "assetHeaderFields", "apiKeyQuery"]
    public static let deviceChecklist: [String] = [
        "Direct play through the resource loader against a pinned self-signed server reaches the first frame.",
        "Direct play with the undocumented header key against a publicly trusted server sends Authorization"
            + " and not a credential query.",
        "Server HLS: confirm on tvOS 26 and 27 that the loader is asked for playlists and keys, not segment bytes.",
        "Server HLS against a pinned certificate stays blocked. AVPlayer would fetch segments without the pin.",
    ]
}

public enum SegmentPolicy: Sendable, Equatable {
    case notHLS
    case leaveServerURLs
}

public struct ResourceLoaderCarrier: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public var assetURL: URL
    public var originURL: URL
    public var authorizationHeader: String
    public var trust: ServerTrustClass
    public var segmentPolicy: SegmentPolicy

    public init(
        assetURL: URL,
        originURL: URL,
        authorizationHeader: String,
        trust: ServerTrustClass,
        segmentPolicy: SegmentPolicy
    ) {
        self.assetURL = assetURL
        self.originURL = originURL
        self.authorizationHeader = authorizationHeader
        self.trust = trust
        self.segmentPolicy = segmentPolicy
    }

    public var description: String {
        "ResourceLoaderCarrier(host: \(originURL.host ?? ""), authorization: header, segments: \(segmentPolicy))"
    }

    public var debugDescription: String { description }
}

public struct AssetHeaderCarrier: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public var url: URL
    public var authorizationHeader: String
    public var headerFieldsKey: String

    public init(url: URL, authorizationHeader: String, headerFieldsKey: String) {
        self.url = url
        self.authorizationHeader = authorizationHeader
        self.headerFieldsKey = headerFieldsKey
    }

    public var description: String {
        "AssetHeaderCarrier(host: \(url.host ?? ""), authorization: header)"
    }

    public var debugDescription: String { description }
}

public enum MediaOpenBlock: Sendable, Equatable {
    case unpinnedSelfSigned
    case hlsSegmentsBypassPinnedTrust
    case missingMediaURL
    case missingAuthorization
}

public enum MediaCarrier: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    case resourceLoader(ResourceLoaderCarrier)
    case assetHeaderFields(AssetHeaderCarrier)
    case apiKeyQuery(URL)
    case blocked(MediaOpenBlock)

    public var kindName: String {
        switch self {
        case .resourceLoader: "resourceLoader"
        case .assetHeaderFields: "assetHeaderFields"
        case .apiKeyQuery: "apiKeyQuery"
        case .blocked: "blocked"
        }
    }

    public var block: MediaOpenBlock? {
        if case .blocked(let reason) = self { return reason }
        return nil
    }

    public var description: String { kindName }
    public var debugDescription: String { kindName }
}

public enum HeaderFieldsKeyPolicy {
    public static func isAllowed(buildIsDebug: Bool) -> Bool { buildIsDebug }

    public static var isAllowedInCurrentBuild: Bool {
        #if DEBUG
            isAllowed(buildIsDebug: true)
        #else
            isAllowed(buildIsDebug: false)
        #endif
    }
}

public struct MediaOpenOptions: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public var trust: ServerTrustClass
    public private(set) var headerFieldsKeyAvailable: Bool
    /// Opt-in media URL that already contains `ApiKey`. Descriptions never print it.
    public private(set) var apiKeyFallbackURL: URL?

    public init(trust: ServerTrustClass, headerFieldsKeyAvailable: Bool, apiKeyFallbackURL: URL? = nil) {
        self.trust = trust
        self.headerFieldsKeyAvailable = headerFieldsKeyAvailable && HeaderFieldsKeyPolicy.isAllowedInCurrentBuild
        #if DEBUG
            self.apiKeyFallbackURL = apiKeyFallbackURL
        #else
            self.apiKeyFallbackURL = nil
        #endif
    }

    public var description: String {
        let fallback = apiKeyFallbackURL == nil ? "off" : "on"
        let headerKey = headerFieldsKeyAvailable
        return "MediaOpenOptions(trust: \(trust), headerKey: \(headerKey), apiKeyFallback: \(fallback))"
    }

    public var debugDescription: String { description }
}

public struct MediaOpenPlan: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public var primary: MediaCarrier
    /// Tried in order when the primary loader cannot be used. Empty when neither fallback can help.
    public var measuredFallbacks: [MediaCarrier]
    /// Playlists could be fetched with the pin. Segments still cannot, so this is not opened.
    public var insufficientPinnedPlaylistFetch: ResourceLoaderCarrier?
    public var findings: [MediaFinding]

    public init(
        primary: MediaCarrier,
        measuredFallbacks: [MediaCarrier],
        insufficientPinnedPlaylistFetch: ResourceLoaderCarrier?,
        findings: [MediaFinding]
    ) {
        self.primary = primary
        self.measuredFallbacks = measuredFallbacks
        self.insufficientPinnedPlaylistFetch = insufficientPinnedPlaylistFetch
        self.findings = findings
    }

    public var description: String {
        let fallback = measuredFallbacks.map(\.kindName).joined(separator: "+")
        let names = findings.map(\.rawValue).joined(separator: ",")
        let shown = fallback.isEmpty ? "none" : fallback
        return "MediaOpenPlan(primary: \(primary.kindName), fallback: \(shown), findings: \(names))"
    }

    public var debugDescription: String { description }
}

public enum MediaOpenPlanner {
    /// Chooses how AVPlayer is opened. Codec selection is intentionally not done here.
    public static func plan(
        delivery: MediaDelivery,
        resolvedURL: URL?,
        authorizationHeader: String?,
        options: MediaOpenOptions
    ) -> MediaOpenPlan {
        switch delivery {
        case .directFile:
            return directFile(resolvedURL: resolvedURL, authorizationHeader: authorizationHeader, options: options)
        case .serverHLS:
            return serverHLS(resolvedURL: resolvedURL, authorizationHeader: authorizationHeader, options: options)
        }
    }

    private static func directFile(
        resolvedURL: URL?,
        authorizationHeader: String?,
        options: MediaOpenOptions
    ) -> MediaOpenPlan {
        if case .unpinnedSelfSigned = options.trust {
            return blocked(
                .unpinnedSelfSigned,
                findings: [.avPlayerBypassesAppURLSession, .apiKeyDoesNotFixTLS, .deviceMeasurementRequired]
            )
        }
        guard let resolvedURL, let header = authorizationHeader, !header.isEmpty else {
            return blocked(.missingAuthorization, findings: [.deviceMeasurementRequired])
        }
        let origin = MediaCredentialQuery.stripping(resolvedURL)
        guard let asset = MediaAssetScheme.wrap(origin) else {
            return blocked(.missingMediaURL, findings: [.deviceMeasurementRequired])
        }
        let loader = ResourceLoaderCarrier(
            assetURL: asset,
            originURL: origin,
            authorizationHeader: header,
            trust: options.trust,
            segmentPolicy: .notHLS
        )
        var findings: [MediaFinding] = [
            .resourceLoaderServesProgressiveBytes,
            .avPlayerBypassesAppURLSession,
            .headerFieldsKeyDoesNotApplyPin,
            .deviceMeasurementRequired,
        ]
        if case .pinnedSelfSigned = options.trust {
            findings.append(.pinnedTrustAppliesOnlyToLoaderFetches)
            findings.append(.apiKeyDoesNotFixTLS)
            return MediaOpenPlan(
                primary: .resourceLoader(loader),
                measuredFallbacks: [],
                insufficientPinnedPlaylistFetch: nil,
                findings: findings
            )
        }
        if case .cleartext = options.trust {
            findings.append(.cleartextHasNoCertificatePin)
        }
        return MediaOpenPlan(
            primary: .resourceLoader(loader),
            measuredFallbacks: fallbacks(url: origin, header: header, options: options, findings: &findings),
            insufficientPinnedPlaylistFetch: nil,
            findings: findings
        )
    }

    private static func serverHLS(
        resolvedURL: URL?,
        authorizationHeader: String?,
        options: MediaOpenOptions
    ) -> MediaOpenPlan {
        if case .unpinnedSelfSigned = options.trust {
            return blocked(
                .unpinnedSelfSigned,
                findings: [
                    .avPlayerBypassesAppURLSession,
                    .apiKeyDoesNotFixTLS,
                    .hlsSegmentBytesCannotBeServedByResourceLoader,
                    .deviceMeasurementRequired,
                ]
            )
        }
        guard let resolvedURL, let header = authorizationHeader, !header.isEmpty else {
            return blocked(.missingAuthorization, findings: [.deviceMeasurementRequired])
        }
        let origin = MediaCredentialQuery.stripping(resolvedURL)
        guard let asset = MediaAssetScheme.wrap(origin) else {
            return blocked(.missingMediaURL, findings: [.deviceMeasurementRequired])
        }
        let loader = ResourceLoaderCarrier(
            assetURL: asset,
            originURL: origin,
            authorizationHeader: header,
            trust: options.trust,
            segmentPolicy: .leaveServerURLs
        )
        var findings: [MediaFinding] = [
            .resourceLoaderSeesPlaylistsAndKeysOnly,
            .hlsSegmentBytesCannotBeServedByResourceLoader,
            .hlsSegmentsStayOnServerURLs,
            .serverApiKeyOnSegmentsIsAcceptedRisk,
            .avPlayerBypassesAppURLSession,
            .headerFieldsKeySegmentBehaviorUnverified,
            .deviceMeasurementRequired,
        ]
        if case .pinnedSelfSigned = options.trust {
            findings.append(.pinnedTrustAppliesOnlyToLoaderFetches)
            findings.append(.headerFieldsKeyDoesNotApplyPin)
            findings.append(.apiKeyDoesNotFixTLS)
            findings.append(.selfSignedHLSNeedsLoopbackProxy)
            return MediaOpenPlan(
                primary: .blocked(.hlsSegmentsBypassPinnedTrust),
                measuredFallbacks: [],
                insufficientPinnedPlaylistFetch: loader,
                findings: findings
            )
        }
        if case .cleartext = options.trust {
            findings.append(.cleartextHasNoCertificatePin)
        }
        return MediaOpenPlan(
            primary: .resourceLoader(loader),
            measuredFallbacks: fallbacks(url: origin, header: header, options: options, findings: &findings),
            insufficientPinnedPlaylistFetch: nil,
            findings: findings
        )
    }

    /// Header key, then an opt-in credential query. Neither is used for a pinned certificate.
    private static func fallbacks(
        url: URL,
        header: String,
        options: MediaOpenOptions,
        findings: inout [MediaFinding]
    ) -> [MediaCarrier] {
        var result: [MediaCarrier] = []
        if options.headerFieldsKeyAvailable {
            findings.append(.headerFieldsKeyIsUndocumentedFallback)
            result.append(
                .assetHeaderFields(
                    AssetHeaderCarrier(
                        url: url,
                        authorizationHeader: header,
                        headerFieldsKey: ResolvedMediaURL.httpHeaderFieldsKey
                    )
                )
            )
        } else {
            findings.append(.headerFieldsKeyUnavailable)
        }
        if let fallbackURL = options.apiKeyFallbackURL {
            result.append(.apiKeyQuery(fallbackURL))
        } else {
            findings.append(.apiKeyFallbackDisabled)
        }
        return result
    }

    private static func blocked(_ reason: MediaOpenBlock, findings: [MediaFinding]) -> MediaOpenPlan {
        MediaOpenPlan(
            primary: .blocked(reason),
            measuredFallbacks: [],
            insufficientPinnedPlaylistFetch: nil,
            findings: findings
        )
    }
}

public enum DirectPlayURL {
    public static func make(
        server: URL,
        identity: ClientIdentity,
        itemID: String,
        mediaSourceID: String,
        playSessionID: String
    ) throws(APIError) -> PreparedMediaRequest {
        let item = try ItemID.require(itemID).value
        let source = try ItemID.require(mediaSourceID).value
        do {
            return try MediaRequestBuilder.prepare(
                server: server,
                path: "/Videos/\(item)/stream",
                query: [
                    URLQueryItem(name: "static", value: "true"),
                    URLQueryItem(name: "mediaSourceId", value: source),
                    URLQueryItem(name: "playSessionId", value: playSessionID),
                    URLQueryItem(name: "deviceId", value: identity.deviceID),
                ],
                identity: identity,
                mode: .header
            )
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.invalidURL
        }
    }
}

public enum PlaybackPreparationResult: Sendable, Equatable {
    case open(MediaOpenPlan)
    case rejected(PlaybackResolutionFailure)
}

public struct PlaybackPreparation: Sendable {
    public var client: any MediaOriginClient
    public var log: any GlassfinLog
    public var maxRedirects: Int

    public init(client: any MediaOriginClient, log: any GlassfinLog = SilentLog(), maxRedirects: Int = 5) {
        self.client = client
        self.log = log
        self.maxRedirects = maxRedirects
    }

    public func prepare(
        delivery: MediaDelivery,
        initialURL: URL,
        authorizationHeader: String?,
        options: MediaOpenOptions
    ) async throws(APIError) -> PlaybackPreparationResult {
        let method = delivery == .directFile ? "HEAD" : "GET"
        let resolver = PlaybackURLResolver(client: client, log: log, maxRedirects: maxRedirects)
        let resolution = try await resolver.resolve(
            start: initialURL,
            method: method,
            authorizationHeader: authorizationHeader,
            trust: options.trust
        )
        switch resolution {
        case .rejected(let failure):
            return .rejected(failure)
        case .resolved(let url):
            return .open(
                MediaOpenPlanner.plan(
                    delivery: delivery,
                    resolvedURL: url,
                    authorizationHeader: authorizationHeader,
                    options: options
                )
            )
        }
    }
}

/// Transport only. Container and codec selection stays a follow-up: it does not change the token path.
public enum PlaybackTransportSelector {
    public static func delivery(method: PlayMethod, hasURL: Bool) -> MediaDelivery? {
        switch method {
        case .directPlay:
            return .directFile
        case .directStream, .transcode:
            return hasURL ? .serverHLS : nil
        }
    }
}
