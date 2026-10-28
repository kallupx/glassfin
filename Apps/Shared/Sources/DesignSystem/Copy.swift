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

    var resource: LocalizedStringResource {
        switch self {
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
