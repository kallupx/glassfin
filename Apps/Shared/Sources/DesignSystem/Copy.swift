import SwiftUI

/// Catalog keys for design-system copy.
///
/// English and Finnish text live in `Apps/Shared/Resources/Localizable.xcstrings`
/// (development language `en`). Tests compare these keys, not translated text.
/// The app target resolves them with `LocalizedStringResource` and `bundle: .main`,
/// matching the package catalog's `String(localized:)` / `bundle: .module` pattern.
enum CopyKey: String, CaseIterable, Equatable, Sendable {
    case welcomeTitle = "welcome.title"
    case welcomeConnect = "welcome.connect"
    case welcomeDesignSystem = "welcome.designSystem"
    case actionPlay = "design.action.play"
    case actionResume = "design.action.resume"
    case actionPlayed = "design.action.played"
    case actionFavorite = "design.action.favorite"
    case actionMore = "design.action.more"
    case actionPlayNow = "design.action.playNow"
    case actionRetry = "design.action.retry"
    case actionSwitchServer = "design.action.switchServer"
    case actionMarkPlayed = "design.action.markPlayed"
    case actionMarkUnplayed = "design.action.markUnplayed"
    case actionAddFavorite = "design.action.addFavorite"
    case actionRemoveFavorite = "design.action.removeFavorite"
    case bannerOffline = "design.banner.offline"
    case errorServerUnreachable = "design.error.serverUnreachable"
    case errorUnauthorized = "design.error.unauthorized"
    case errorForbidden = "design.error.forbidden"
    case errorNotFound = "design.error.notFound"
    case errorServer = "design.error.server"
    case errorUnsupported = "design.error.unsupported"
    case errorPlayback = "design.error.playback"
    case badgeWatched = "design.badge.watched"
    case badgeUnplayedCount = "design.badge.unplayedCount"
    case remainingMinutes = "design.remainingMinutes"
    case tabHome = "design.tab.home"
    case tabLibraries = "design.tab.libraries"
    case tabSearch = "design.tab.search"
    case tabSettings = "design.tab.settings"
    case settingsVersion = "settings.version"
    case settingsVersionUnavailable = "settings.versionUnavailable"
    case seasonPicker = "design.season.picker"
    case rowPrimary = "design.row.primary"
    case rowPosters = "design.row.posters"
    case prototypeFocus = "design.prototype.focus"
    case prototypeInteractive = "design.prototype.interactive"
    case prototypeLogin = "design.prototype.login"
    case prototypeNextUp = "design.prototype.nextUp"
    case prototypeSubtitle = "design.prototype.subtitle"
    case navRoot = "design.nav.root"
    case navLibrary = "design.nav.library"
    case navDetail = "design.nav.detail"

    case homeContinue = "home.continueWatching"
    case homeNextUp = "home.nextUp"
    case homeLatest = "home.latest"
    case homeEmpty = "home.empty"
    case homeEmptyGuidance = "home.emptyGuidance"
    case homeRemoveResume = "home.removeResume"
    case homeGoToSeries = "home.goToSeries"
    case homeDetailPending = "home.detailPending"
    case homePlaybackPending = "home.playbackPending"
    case homeLibrariesRetry = "home.librariesRetry"

    case playbackScrub = "playback.scrub"
    case playbackNextTitle = "playback.next.title"
    case playbackCountdown = "playback.next.countdown"
    case playbackCancel = "playback.cancel"
    case playbackAutoplay = "playback.autoplay"

    case playbackSegmentIntro = "playback.segment.intro"
    case playbackSkipIntro = "playback.skip.intro"
    case playbackSegmentRecap = "playback.segment.recap"
    case playbackSkipRecap = "playback.skip.recap"
    case playbackSegmentOutro = "playback.segment.outro"
    case playbackSkipOutro = "playback.skip.outro"
    case playbackSegmentPreview = "playback.segment.preview"
    case playbackSkipPreview = "playback.skip.preview"
    case playbackSegmentCommercial = "playback.segment.commercial"
    case playbackSkipCommercial = "playback.skip.commercial"
    case playbackSegmentBehaviorAsk = "playback.segmentBehavior.ask"
    case playbackSegmentBehaviorAutomatic = "playback.segmentBehavior.automatic"
    case playbackSegmentBehaviorIgnore = "playback.segmentBehavior.ignore"

    var resource: LocalizedStringResource {
        switch self {
        case .playbackSegmentIntro: LocalizedStringResource("playback.segment.intro", bundle: .main)
        case .playbackSkipIntro: LocalizedStringResource("playback.skip.intro", bundle: .main)
        case .playbackSegmentRecap: LocalizedStringResource("playback.segment.recap", bundle: .main)
        case .playbackSkipRecap: LocalizedStringResource("playback.skip.recap", bundle: .main)
        case .playbackSegmentOutro: LocalizedStringResource("playback.segment.outro", bundle: .main)
        case .playbackSkipOutro: LocalizedStringResource("playback.skip.outro", bundle: .main)
        case .playbackSegmentPreview: LocalizedStringResource("playback.segment.preview", bundle: .main)
        case .playbackSkipPreview: LocalizedStringResource("playback.skip.preview", bundle: .main)
        case .playbackSegmentCommercial: LocalizedStringResource("playback.segment.commercial", bundle: .main)
        case .playbackSkipCommercial: LocalizedStringResource("playback.skip.commercial", bundle: .main)
        case .playbackSegmentBehaviorAsk: LocalizedStringResource("playback.segmentBehavior.ask", bundle: .main)
        case .playbackSegmentBehaviorAutomatic:
            LocalizedStringResource("playback.segmentBehavior.automatic", bundle: .main)
        case .playbackSegmentBehaviorIgnore: LocalizedStringResource("playback.segmentBehavior.ignore", bundle: .main)

        case .playbackScrub: LocalizedStringResource("playback.scrub", bundle: .main)
        case .playbackNextTitle: LocalizedStringResource("playback.next.title", bundle: .main)
        case .playbackCountdown: LocalizedStringResource("playback.next.countdown", bundle: .main)
        case .playbackCancel: LocalizedStringResource("playback.cancel", bundle: .main)
        case .playbackAutoplay: LocalizedStringResource("playback.autoplay", bundle: .main)

        case .homeContinue: LocalizedStringResource("home.continueWatching", bundle: .main)
        case .homeNextUp: LocalizedStringResource("home.nextUp", bundle: .main)
        case .homeLatest: LocalizedStringResource("home.latest", bundle: .main)
        case .homeEmpty: LocalizedStringResource("home.empty", bundle: .main)
        case .homeEmptyGuidance: LocalizedStringResource("home.emptyGuidance", bundle: .main)
        case .homeRemoveResume: LocalizedStringResource("home.removeResume", bundle: .main)
        case .homeGoToSeries: LocalizedStringResource("home.goToSeries", bundle: .main)
        case .homeDetailPending: LocalizedStringResource("home.detailPending", bundle: .main)
        case .homePlaybackPending: LocalizedStringResource("home.playbackPending", bundle: .main)
        case .homeLibrariesRetry: LocalizedStringResource("home.librariesRetry", bundle: .main)

        case .welcomeTitle: LocalizedStringResource("welcome.title", bundle: .main)
        case .welcomeConnect: LocalizedStringResource("welcome.connect", bundle: .main)
        case .welcomeDesignSystem: LocalizedStringResource("welcome.designSystem", bundle: .main)
        case .actionPlay: LocalizedStringResource("design.action.play", bundle: .main)
        case .actionResume: LocalizedStringResource("design.action.resume", bundle: .main)
        case .actionPlayed: LocalizedStringResource("design.action.played", bundle: .main)
        case .actionFavorite: LocalizedStringResource("design.action.favorite", bundle: .main)
        case .actionMore: LocalizedStringResource("design.action.more", bundle: .main)
        case .actionPlayNow: LocalizedStringResource("design.action.playNow", bundle: .main)
        case .actionRetry: LocalizedStringResource("design.action.retry", bundle: .main)
        case .actionSwitchServer: LocalizedStringResource("design.action.switchServer", bundle: .main)
        case .actionMarkPlayed: LocalizedStringResource("design.action.markPlayed", bundle: .main)
        case .actionMarkUnplayed: LocalizedStringResource("design.action.markUnplayed", bundle: .main)
        case .actionAddFavorite: LocalizedStringResource("design.action.addFavorite", bundle: .main)
        case .actionRemoveFavorite: LocalizedStringResource("design.action.removeFavorite", bundle: .main)
        case .bannerOffline: LocalizedStringResource("design.banner.offline", bundle: .main)
        case .errorServerUnreachable: LocalizedStringResource("design.error.serverUnreachable", bundle: .main)
        case .errorUnauthorized: LocalizedStringResource("design.error.unauthorized", bundle: .main)
        case .errorForbidden: LocalizedStringResource("design.error.forbidden", bundle: .main)
        case .errorNotFound: LocalizedStringResource("design.error.notFound", bundle: .main)
        case .errorServer: LocalizedStringResource("design.error.server", bundle: .main)
        case .errorUnsupported: LocalizedStringResource("design.error.unsupported", bundle: .main)
        case .errorPlayback: LocalizedStringResource("design.error.playback", bundle: .main)
        case .badgeWatched: LocalizedStringResource("design.badge.watched", bundle: .main)
        case .badgeUnplayedCount: LocalizedStringResource("design.badge.unplayedCount", bundle: .main)
        case .remainingMinutes: LocalizedStringResource("design.remainingMinutes", bundle: .main)
        case .tabHome: LocalizedStringResource("design.tab.home", bundle: .main)
        case .tabLibraries: LocalizedStringResource("design.tab.libraries", bundle: .main)
        case .tabSearch: LocalizedStringResource("design.tab.search", bundle: .main)
        case .tabSettings: LocalizedStringResource("design.tab.settings", bundle: .main)
        case .settingsVersion: LocalizedStringResource("settings.version", bundle: .main)
        case .settingsVersionUnavailable: LocalizedStringResource("settings.versionUnavailable", bundle: .main)
        case .seasonPicker: LocalizedStringResource("design.season.picker", bundle: .main)
        case .rowPrimary: LocalizedStringResource("design.row.primary", bundle: .main)
        case .rowPosters: LocalizedStringResource("design.row.posters", bundle: .main)
        case .prototypeFocus: LocalizedStringResource("design.prototype.focus", bundle: .main)
        case .prototypeInteractive: LocalizedStringResource("design.prototype.interactive", bundle: .main)
        case .prototypeLogin: LocalizedStringResource("design.prototype.login", bundle: .main)
        case .prototypeNextUp: LocalizedStringResource("design.prototype.nextUp", bundle: .main)
        case .prototypeSubtitle: LocalizedStringResource("design.prototype.subtitle", bundle: .main)
        case .navRoot: LocalizedStringResource("design.nav.root", bundle: .main)
        case .navLibrary: LocalizedStringResource("design.nav.library", bundle: .main)
        case .navDetail: LocalizedStringResource("design.nav.detail", bundle: .main)
        }
    }
}

enum Copy {
    static func playbackFeature(_ key: String) -> String {
        guard let value = CopyKey(rawValue: key) else { return key }
        return string(value)
    }

    static func text(_ key: CopyKey) -> Text {
        Text(key.resource)
    }

    static func string(_ key: CopyKey) -> String {
        String(localized: key.resource)
    }

    static func format(_ key: CopyKey, integer: Int) -> String {
        let pattern = string(key)
        return String(format: pattern, locale: .current, Int64(integer))
    }

    static func format(_ key: CopyKey, text: String) -> String {
        let pattern = string(key)
        return String(format: pattern, locale: .current, text)
    }
}

struct GlassIcon: View {
    var systemName: String
    var label: CopyKey

    var body: some View {
        Image(systemName: systemName)
            .accessibilityLabel(Text(label.resource))
            .accessibilityIdentifier(label.rawValue + ".icon")
    }
}
