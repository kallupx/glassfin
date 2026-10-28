#if canImport(AVFoundation) && canImport(Security)
    import AVFoundation
    import Foundation

    extension AVPlayerEngine: PlaybackTrackSelecting, PlaybackBufferReporting {
        public var bufferedDuration: Duration {
            guard let player, let item = player.currentItem else { return .zero }
            let current = player.currentTime().seconds
            guard current.isFinite else { return .zero }
            let end =
                item.loadedTimeRanges.map { $0.timeRangeValue }.filter {
                    $0.start.seconds <= current && $0.end.seconds >= current
                }.map { $0.end.seconds }.max() ?? current
            guard end.isFinite else { return .zero }
            return .seconds(max(0, end - current))
        }

        /// System-provided audio/subtitle menus can also change the native selection.
        /// Suppress our own selections; report unambiguous user changes through the coordinator.
        func nativeSelectionChanged() async {
            guard let item = player?.currentItem, !trackSelectionPeers.isEmpty else { return }
            for kind in [PlaybackTrack.Kind.audio, .subtitle] {
                let characteristic: AVMediaCharacteristic = kind == .audio ? .audible : .legible
                guard let group = try? await item.asset.loadMediaSelectionGroup(for: characteristic),
                    player?.currentItem === item
                else { continue }
                let selected = item.currentMediaSelection.selectedMediaOption(in: group)
                let expected = kind == .audio ? expectedNativeAudio : expectedNativeSubtitle
                guard selected !== expected else { continue }
                let options = group.options.map {
                    NativeTrackOption(
                        title: $0.displayName, language: $0.extendedLanguageTag ?? $0.locale?.languageCode)
                }
                let matches = trackSelectionPeers.filter { track in
                    guard track.kind == kind,
                        let index = NativeTrackMapping.optionIndex(
                            for: track, options: options, peers: trackSelectionPeers)
                    else { return false }
                    return group.options[index] === selected
                }
                if matches.count == 1 || (kind == .subtitle && selected == nil) {
                    if kind == .audio { expectedNativeAudio = selected } else { expectedNativeSubtitle = selected }
                    emitNativeSelection(kind: kind, id: matches.first?.id)
                }
            }
        }

        public func selectNativeTrack(
            _ track: PlaybackTrack?, kind: PlaybackTrack.Kind, peers: [PlaybackTrack]
        ) async -> Bool {
            trackSelectionPeers = peers
            guard let item = player?.currentItem else { return false }
            let characteristic: AVMediaCharacteristic = kind == .audio ? .audible : .legible
            let group = try? await item.asset.loadMediaSelectionGroup(for: characteristic)
            guard player?.currentItem === item else { return false }
            guard let group else { return kind == .subtitle && track == nil }
            guard let track else {
                guard kind == .subtitle else { return false }
                expectedNativeSubtitle = nil
                item.select(nil, in: group)
                return true
            }
            let options = group.options.map {
                NativeTrackOption(title: $0.displayName, language: $0.extendedLanguageTag ?? $0.locale?.languageCode)
            }
            // Jellyfin stream indexes are not AVMediaSelectionGroup offsets.
            guard let index = NativeTrackMapping.optionIndex(for: track, options: options, peers: peers) else {
                return false
            }
            let option = group.options[index]
            if kind == .audio { expectedNativeAudio = option } else { expectedNativeSubtitle = option }
            item.select(option, in: group)
            return true
        }
    }
#endif
