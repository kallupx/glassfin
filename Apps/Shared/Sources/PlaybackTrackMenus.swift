#if (os(tvOS) || os(iOS)) && canImport(UIKit)
    import AVKit
    import GlassfinCore
    import UIKit

    /// Uses the native transport bar, keeping every server track reachable with Siri Remote.
    @MainActor
    enum PlaybackTrackMenus {
        static func items(playback: PlaybackCoordinator) -> [UIMenuElement] {
            #if os(tvOS)
                let audio = menu(kind: .audio, playback: playback)
                let subtitles = menu(kind: .subtitle, playback: playback)
                let conversion = UIAction(
                    title: Copy.string(.playbackConvertASS),
                    identifier: UIAction.Identifier("playback.tracks.convertASS"),
                    state: playback.convertsASS ? .on : .off
                ) { _ in
                    Task { await playback.setASSConversion(!playback.convertsASS) }
                }
                conversion.accessibilityIdentifier = "playback.tracks.convertASS"
                var info = [playback.playMethod?.reportValue ?? ""]
                info += playback.transcodeReasons
                if let diagnostic = playback.diagnostics {
                    info.append(diagnostic.sourceVideo + " → " + diagnostic.targetVideo)
                    info.append(diagnostic.sourceAudio + " → " + diagnostic.targetAudio)
                    if let bitrate = diagnostic.bitrate { info.append("\(bitrate / 1000) kbps") }
                    info.append(Copy.string(.playbackBuffer) + ": " + playback.bufferedDuration.formatted())
                }
                let diagnostics = UIAction(
                    title: info.filter { !$0.isEmpty }.joined(separator: " · "), attributes: .disabled
                ) { _ in }
                diagnostics.accessibilityIdentifier = "playback.tracks.diagnostics"
                return [
                    audio, subtitles,
                    UIMenu(
                        title: Copy.string(.playbackOptions),
                        identifier: UIMenu.Identifier("playback.tracks.options"), children: [conversion, diagnostics]),
                ]
            #else
                return []
            #endif
        }

        private static func menu(kind: PlaybackTrack.Kind, playback: PlaybackCoordinator) -> UIMenu {
            let key = "playback.tracks." + kind.rawValue
            var children: [UIMenuElement] = []
            if kind == .subtitle {
                let off = action(
                    title: Copy.string(.playbackOff), id: nil,
                    kind: kind, playback: playback)
                children.append(off)
            }
            children += playback.tracks.filter { $0.kind == kind }.map { track in
                action(title: track.title, id: track.id, kind: kind, playback: playback)
            }
            return UIMenu(
                title: Copy.string(kind == .audio ? .playbackAudio : .playbackSubtitle),
                identifier: UIMenu.Identifier(key),
                options: .singleSelection, children: children)
        }

        private static func action(
            title: String, id: Int?, kind: PlaybackTrack.Kind, playback: PlaybackCoordinator
        ) -> UIAction {
            let identifier = "playback.tracks." + kind.rawValue + "." + (id.map(String.init) ?? "off")
            let selected = kind == .audio ? playback.selection.audio : playback.selection.subtitle
            let action = UIAction(
                title: title, identifier: UIAction.Identifier(identifier),
                state: (selected ?? -1) == (id ?? -1) ? .on : .off
            ) { _ in
                Task { await playback.selectTrack(id: id, kind: kind) }
            }
            action.accessibilityIdentifier = identifier
            return action
        }
    }
#endif
