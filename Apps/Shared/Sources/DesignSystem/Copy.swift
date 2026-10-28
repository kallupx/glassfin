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
    case playbackBuffer = "playback.tracks.buffer"
    case playbackAudio = "playback.tracks.audio"
    case playbackSubtitle = "playback.tracks.subtitle"
    case playbackOff = "playback.tracks.off"
    case playbackConvertASS = "playback.tracks.convertASS"
    case playbackOptions = "playback.tracks.options"
    case playbackRemoteBitrate = "playback.tracks.remoteBitrate"
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

    case librarySort = "library.sort"
    case libraryName = "library.sort.name"
    case libraryDateAdded = "library.sort.dateAdded"
    case libraryReleaseYear = "library.sort.releaseYear"
    case libraryRating = "library.sort.rating"
    case libraryRandom = "library.sort.random"
    case libraryDescending = "library.sort.descending"
    case libraryUnplayed = "library.filter.unplayed"
    case libraryFavorites = "library.filter.favorites"
    case libraryFilterOn = "library.filter.on"
    case libraryFilterOff = "library.filter.off"
    case libraryGenre = "library.filter.genre"
    case libraryYear = "library.filter.year"
    case libraryAll = "library.filter.all"
    case libraryMoviesCount = "library.count.movies"
    case librarySeriesCount = "library.count.series"
    case libraryItemsCount = "library.count.items"
    case libraryEmpty = "library.empty"
    case libraryNoLibraries = "library.noLibraries"
    case detailCast = "detail.cast"
    case detailSimilar = "detail.similar"
    case detailTechnical = "detail.technical"
    case detailStartOver = "detail.startOver"
    case detailTracks = "detail.tracks"
    case detailAudio = "detail.audio"
    case detailSubtitles = "detail.subtitles"
    case detailDefault = "detail.default"
    case detailNone = "detail.none"
    case detailPlayEpisode = "detail.playEpisode"
    case detailResumeEpisode = "detail.resumeEpisode"
    case detailResumeTime = "detail.resumeTime"
    case detailSeasonNumber = "detail.seasonNumber"
    case detailSpecials = "detail.specials"
    case detailEpisodeNumber = "detail.episodeNumber"
    case detailRuntime = "detail.runtime"
    case detailPlaybackPending = "detail.playbackPending"
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

    case searchPrompt = "search.prompt"
    case searchMovies = "search.movies"
    case searchSeries = "search.series"
    case searchEpisodes = "search.episodes"
    case searchRecent = "search.recent"
    case searchClearRecent = "search.clearRecent"
    case searchEmpty = "search.empty"
    case searchMinimum = "search.minimum"
    case searchHistoryFailure = "search.historyFailure"
    case searchBack = "search.back"

    var resource: LocalizedStringResource {
        switch self {
        case .playbackBuffer: LocalizedStringResource("playback.tracks.buffer", bundle: .main)
        case .playbackAudio: LocalizedStringResource("playback.tracks.audio", bundle: .main)
        case .playbackSubtitle: LocalizedStringResource("playback.tracks.subtitle", bundle: .main)
        case .playbackOff: LocalizedStringResource("playback.tracks.off", bundle: .main)
        case .playbackConvertASS: LocalizedStringResource("playback.tracks.convertASS", bundle: .main)
        case .playbackOptions: LocalizedStringResource("playback.tracks.options", bundle: .main)
        case .playbackRemoteBitrate: LocalizedStringResource("playback.tracks.remoteBitrate", bundle: .main)
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

        case .searchPrompt: LocalizedStringResource("search.prompt", bundle: .main)
        case .searchMovies: LocalizedStringResource("search.movies", bundle: .main)
        case .searchSeries: LocalizedStringResource("search.series", bundle: .main)
        case .searchEpisodes: LocalizedStringResource("search.episodes", bundle: .main)
        case .searchRecent: LocalizedStringResource("search.recent", bundle: .main)
        case .searchClearRecent: LocalizedStringResource("search.clearRecent", bundle: .main)
        case .searchEmpty: LocalizedStringResource("search.empty", bundle: .main)
        case .searchMinimum: LocalizedStringResource("search.minimum", bundle: .main)
        case .searchHistoryFailure: LocalizedStringResource("search.historyFailure", bundle: .main)
        case .searchBack: LocalizedStringResource("search.back", bundle: .main)
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

        case .librarySort: LocalizedStringResource("library.sort", bundle: .main)
        case .libraryName: LocalizedStringResource("library.sort.name", bundle: .main)
        case .libraryDateAdded: LocalizedStringResource("library.sort.dateAdded", bundle: .main)
        case .libraryReleaseYear: LocalizedStringResource("library.sort.releaseYear", bundle: .main)
        case .libraryRating: LocalizedStringResource("library.sort.rating", bundle: .main)
        case .libraryRandom: LocalizedStringResource("library.sort.random", bundle: .main)
        case .libraryDescending: LocalizedStringResource("library.sort.descending", bundle: .main)
        case .libraryUnplayed: LocalizedStringResource("library.filter.unplayed", bundle: .main)
        case .libraryFavorites: LocalizedStringResource("library.filter.favorites", bundle: .main)
        case .libraryFilterOn: LocalizedStringResource("library.filter.on", bundle: .main)
        case .libraryFilterOff: LocalizedStringResource("library.filter.off", bundle: .main)
        case .libraryGenre: LocalizedStringResource("library.filter.genre", bundle: .main)
        case .libraryYear: LocalizedStringResource("library.filter.year", bundle: .main)
        case .libraryAll: LocalizedStringResource("library.filter.all", bundle: .main)
        case .libraryMoviesCount: LocalizedStringResource("library.count.movies", bundle: .main)
        case .librarySeriesCount: LocalizedStringResource("library.count.series", bundle: .main)
        case .libraryItemsCount: LocalizedStringResource("library.count.items", bundle: .main)
        case .libraryEmpty: LocalizedStringResource("library.empty", bundle: .main)
        case .libraryNoLibraries: LocalizedStringResource("library.noLibraries", bundle: .main)
        case .detailCast: LocalizedStringResource("detail.cast", bundle: .main)
        case .detailSimilar: LocalizedStringResource("detail.similar", bundle: .main)
        case .detailTechnical: LocalizedStringResource("detail.technical", bundle: .main)
        case .detailStartOver: LocalizedStringResource("detail.startOver", bundle: .main)
        case .detailTracks: LocalizedStringResource("detail.tracks", bundle: .main)
        case .detailAudio: LocalizedStringResource("detail.audio", bundle: .main)
        case .detailSubtitles: LocalizedStringResource("detail.subtitles", bundle: .main)
        case .detailDefault: LocalizedStringResource("detail.default", bundle: .main)
        case .detailNone: LocalizedStringResource("detail.none", bundle: .main)
        case .detailPlayEpisode: LocalizedStringResource("detail.playEpisode", bundle: .main)
        case .detailResumeEpisode: LocalizedStringResource("detail.resumeEpisode", bundle: .main)
        case .detailResumeTime: LocalizedStringResource("detail.resumeTime", bundle: .main)
        case .detailSeasonNumber: LocalizedStringResource("detail.seasonNumber", bundle: .main)
        case .detailSpecials: LocalizedStringResource("detail.specials", bundle: .main)
        case .detailEpisodeNumber: LocalizedStringResource("detail.episodeNumber", bundle: .main)
        case .detailRuntime: LocalizedStringResource("detail.runtime", bundle: .main)
        case .detailPlaybackPending: LocalizedStringResource("detail.playbackPending", bundle: .main)

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
