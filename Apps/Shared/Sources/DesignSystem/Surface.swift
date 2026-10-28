import Foundation

enum SurfaceRole: String, Equatable, Sendable {
    case systemTabBar
    case glassContainer
    case customGlassBanner
    case content
    case subtitle
}

enum SurfaceAssignment {
    static let materials: [String: SurfaceRole] = [
        "tabBar": .systemTabBar,
        "heroActions": .glassContainer,
        "seasonPicker": .glassContainer,
        "filterBar": .glassContainer,
        "errorActions": .glassContainer,
        "nextUp": .glassContainer,
        "loginPanel": .glassContainer,
        "focusProbe": .glassContainer,
        "banner": .customGlassBanner,
        "posterCard": .content,
        "landscapeCard": .content,
        "subtitle": .subtitle,
    ]

    static func allowsGlass(_ role: SurfaceRole) -> Bool {
        switch role {
        case .systemTabBar, .glassContainer, .customGlassBanner:
            true
        case .content, .subtitle:
            false
        }
    }
}

enum GlassBudget {
    static let maximumContainers = 2
    static let maximumElementsPerContainer = 8

    /// Q5-07: the cap is reported and not enforced. Rendering still includes every action.
    static func exceedsElementLimit(_ count: Int) -> Bool {
        count > maximumElementsPerContainer
    }

    static func displayedCount(of proposed: Int) -> Int {
        proposed
    }
}

enum GlassContainerUse: String, Equatable, CaseIterable, Sendable {
    case heroActions
    case seasonPicker
    case errorActions
    case nextUp
    case loginPanel
    case focusProbe
}

enum ScreenGlassPlan {
    /// Detail shows the action row and the season picker. The banner is not a container (Q5-02).
    static func detail() -> [GlassContainerUse] {
        [.heroActions, .seasonPicker]
    }

    /// Playback keeps a single custom overlay beside the system transport bar.
    static func playback() -> [GlassContainerUse] {
        [.nextUp]
    }
}

struct PlaybackProgress: Equatable, Sendable {
    var fraction: Double?
    var remainingMinutes: Int?

    var showsBar: Bool {
        fraction != nil
    }

    static func measure(position: Duration, runtime: Duration?) -> PlaybackProgress {
        guard let runtime else {
            return PlaybackProgress(fraction: nil, remainingMinutes: nil)
        }
        let total = seconds(runtime)
        if total <= 0 {
            return PlaybackProgress(fraction: nil, remainingMinutes: nil)
        }
        let elapsed = min(total, max(0, seconds(position)))
        let remaining = total - elapsed
        let minutes = remaining > 0 ? Int((remaining / 60).rounded(.up)) : nil
        return PlaybackProgress(fraction: elapsed / total, remainingMinutes: minutes)
    }

    private static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}

struct PosterContent: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var progress: PlaybackProgress
    var isWatched: Bool
    var unplayedCount: Int?
    var blurHash: String?

    var remainingKey: CopyKey? {
        guard let minutes = progress.remainingMinutes, minutes > 0 else {
            return nil
        }
        return .remainingMinutes
    }
}

enum FailureScreen: Equatable, Sendable {
    case hidden
    case banner(CopyKey)
    case inline(CopyKey)
    case blocking(CopyKey, retry: Bool, switchServer: Bool)
}

enum DesignFailure: Equatable, Sendable {
    case offline
    case serverUnreachable
    case unauthorized
    case forbidden
    case notFound
    case server(status: Int)
    case unsupported(required: String)
    case playback
    case decoding
    case cancelled

    var screen: FailureScreen {
        switch self {
        case .offline:
            .banner(.bannerOffline)
        case .cancelled, .decoding:
            .hidden
        case .forbidden:
            .inline(.errorForbidden)
        case .unauthorized:
            .blocking(.errorUnauthorized, retry: false, switchServer: false)
        case .serverUnreachable:
            .blocking(.errorServerUnreachable, retry: true, switchServer: true)
        case .notFound:
            .blocking(.errorNotFound, retry: true, switchServer: false)
        case .server:
            .blocking(.errorServer, retry: true, switchServer: false)
        case .unsupported:
            .blocking(.errorUnsupported, retry: false, switchServer: true)
        case .playback:
            .blocking(.errorPlayback, retry: true, switchServer: false)
        }
    }

    var messageKey: CopyKey? {
        switch screen {
        case .hidden:
            nil
        case .banner(let key), .inline(let key), .blocking(let key, _, _):
            key
        }
    }
}

enum LoadPhase<Value: Equatable>: Equatable {
    case idle
    case loading(Value?)
    case loaded(Value)
    case failed(DesignFailure, Value?)
}

enum ScreenMode: Equatable, Sendable {
    case empty
    case skeleton
    case content(banner: CopyKey?)
    case failure(DesignFailure)
}

enum LoadPresentation {
    /// Offline keeps the previous screen and adds a banner.
    /// A dead server replaces the screen. Cancelled and decoding stay quiet.
    static func mode<Value>(for phase: LoadPhase<Value>) -> ScreenMode {
        switch phase {
        case .idle:
            .empty
        case .loading(nil):
            .skeleton
        case .loading(.some):
            .content(banner: nil)
        case .loaded:
            .content(banner: nil)
        case .failed(let failure, let previous):
            switch failure.screen {
            case .hidden:
                previous == nil ? .empty : .content(banner: nil)
            case .banner(let key):
                .content(banner: key)
            case .inline:
                previous == nil ? .failure(failure) : .content(banner: nil)
            case .blocking:
                .failure(failure)
            }
        }
    }
}

struct LibraryTabItem: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
}

struct LibraryTabPlan: Equatable, Sendable {
    var inline: [LibraryTabItem]
    var overflow: [LibraryTabItem]
}

enum LibraryTabModel {
    /// Spec default until Q5-09 is confirmed. Zero libraries produce no library tab.
    static let maximumInlineLibraries = 5

    static func plan(libraries: [LibraryTabItem]) -> LibraryTabPlan {
        if libraries.count <= maximumInlineLibraries {
            return LibraryTabPlan(inline: libraries, overflow: [])
        }
        let inline = Array(libraries.prefix(maximumInlineLibraries))
        let overflow = Array(libraries.dropFirst(maximumInlineLibraries))
        return LibraryTabPlan(inline: inline, overflow: overflow)
    }
}

struct GlassAction: Identifiable, Equatable, Sendable {
    var id: String
    var title: CopyKey
    var systemImage: String
    var iconLabel: CopyKey
    var prominent: Bool
    var identifier: String
}

enum TruncationPolicy {
    static let playButtonLineLimit: Int? = nil
    static let errorMessageLineLimit: Int? = nil
    static let codeLineLimit: Int? = nil
}

enum PosterPhase: Equatable, Sendable {
    case placeholder
    case image
    /// Q5-08: the failure screen is unspecified. The placeholder stays up and no error chrome is invented.
    case failed
}
