#if os(tvOS) || os(iOS)
    import GlassfinCore
    import SwiftUI
    import UIKit

    /// One custom surface at a time (G-3). Native contextual actions own Skip's focus behavior.
    struct PlaybackFeatureOverlay: View {
        let companion: PlaybackCompanion
        let itemID: String?
        let mediaSourceID: String?
        @State private var image: CGImage?
        @State private var nextImage: CGImage?
        @State private var decoder = TrickplayImageDecoder()
        @State private var dragStart: Duration?
        @FocusState private var playFocused: Bool
        @FocusState private var scrubFocused: Bool
        @DesignAccessibility private var accessibility

        var body: some View {
            VStack {
                Spacer()
                if let position = companion.scrubPosition, let runtime = companion.runtime {
                    scrubPanel(position: position, runtime: runtime)
                } else if let seconds = companion.countdownSeconds, let next = companion.next {
                    nextPanel(next: next, seconds: seconds)
                }
            }
            .padding(SpacingToken.xl)
            .task(id: previewIdentity) { await decodePreview() }
            .task(id: companion.next?.id) {
                nextImage = nil
                if let data = await companion.nextImageData(), !Task.isCancelled {
                    nextImage = try? await HomeImageDecoder.downsample(data, width: 360, height: 202)
                }
            }
            .onChange(of: companion.scrubPosition != nil) { _, shown in
                // A direct clickpad interaction explicitly enters the scrub control.
                if shown { scrubFocused = true }
            }
            .onChange(of: companion.countdownSeconds != nil) { _, shown in
                // Never pull focus away from an active transport bar or Info/menu panel.
                if shown && !companion.transportVisible { playFocused = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) {
                _ in
                image = nil
                nextImage = nil
                Task {
                    await companion.clearImages()
                    await decoder.removeAll()
                }
            }
            .onChange(of: itemID) { _, _ in
                image = nil
                Task { await decoder.removeAll() }
            }
        }

        private func scrubPanel(position: Duration, runtime: Duration) -> some View {
            ContainedGlass {
                VStack(spacing: SpacingToken.s) {
                    GeometryReader { geometry in
                        VStack(spacing: SpacingToken.s) {
                            if let image {
                                Image(decorative: image, scale: 1)
                                    .resizable().aspectRatio(contentMode: .fit)
                                    .frame(width: 320, height: 180)
                                    .clipShape(ContentShape.concentric)
                                    .accessibilityIdentifier("playback.trickplay.thumbnail")
                            }
                            Text(verbatim: timestamp(position))
                                .monospacedDigit()
                                .accessibilityIdentifier("playback.trickplay.timestamp")
                        }
                        .position(
                            x: max(
                                160,
                                min(
                                    geometry.size.width - 160,
                                    geometry.size.width * seconds(position) / max(1, seconds(runtime)))), y: 110)
                    }
                    .frame(height: 220)
                    Button {
                        Task { await companion.endScrubbing(commit: true) }
                    } label: {
                        ProgressView(value: seconds(position), total: max(1, seconds(runtime)))
                            .frame(maxWidth: .infinity)
                            .padding(SpacingToken.m)
                    }
                    .accessibilityLabel(Copy.string(.playbackScrub))
                    .accessibilityValue(timestamp(position))
                    .accessibilityIdentifier("playback.scrub.timeline")
                    .focused($scrubFocused)
                    #if os(tvOS)
                        .onMoveCommand { direction in
                            if direction == .left { companion.scrub(to: position - .seconds(10)) }
                            if direction == .right { companion.scrub(to: position + .seconds(10)) }
                        }
                        .onExitCommand { Task { await companion.endScrubbing(commit: false) } }
                    #endif
                    .gesture(
                        DragGesture().onChanged { gesture in
                            if dragStart == nil { dragStart = position }
                            companion.scrub(to: (dragStart ?? position) + .seconds(gesture.translation.width / 10))
                        }.onEnded { _ in dragStart = nil })
                }
                .padding(SpacingToken.l)
                .ownGlassSurface(in: ContentShape.concentric)
            }
            .accessibilityIdentifier("playback.trickplay.panel")
        }

        private func nextPanel(next: NextEpisode, seconds: Int) -> some View {
            ContainedGlass {
                HStack(spacing: SpacingToken.l) {
                    if let nextImage {
                        Image(decorative: nextImage, scale: 1).resizable().aspectRatio(contentMode: .fit)
                            .frame(width: 240, height: 135).clipShape(ContentShape.concentric)
                    }
                    VStack(alignment: .leading, spacing: SpacingToken.s) {
                        Text(verbatim: Copy.format(.playbackNextTitle, text: next.title))
                            .font(.headline).lineLimit(2)
                        Text(verbatim: Copy.format(.playbackCountdown, integer: seconds))
                            .monospacedDigit()
                            .accessibilityIdentifier("playback.next.countdown")
                        HStack {
                            Button {
                                companion.playNext()
                            } label: {
                                Copy.text(.actionPlayNow)
                            }
                            .glassButtonChrome(prominent: true, contrast: accessibility.contrast)
                            .focused($playFocused)
                            .accessibilityIdentifier("playback.next.play")
                            Button {
                                companion.cancelNext()
                            } label: {
                                Copy.text(.playbackCancel)
                            }
                            .glassButtonChrome(prominent: false, contrast: accessibility.contrast)
                            .accessibilityIdentifier("playback.next.cancel")
                        }
                    }
                }
                .padding(SpacingToken.l)
                .ownGlassSurface(in: ContentShape.concentric)
            }
            .defaultFocus($playFocused, true, priority: .automatic)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("playback.next.card")
        }

        private var previewIdentity: String {
            "\(itemID ?? ""):\(companion.previewFrame?.tile ?? -1):\(companion.previewFrame?.row ?? -1):\(companion.previewFrame?.column ?? -1):\(companion.previewBytes?.count ?? 0)"
        }

        private func decodePreview() async {
            guard let data = companion.previewBytes, let frame = companion.previewFrame,
                let layout = companion.layout, let itemID, let mediaSourceID
            else {
                image = nil
                return
            }
            let resource = TrickplayTileResource(
                itemID: itemID, mediaSourceID: mediaSourceID, width: layout.width, index: frame.tile)
            let signposter = SystemSignposter()
            let interval = signposter.begin(.trickplayPreview)
            defer { signposter.end(interval) }
            guard let tile = try? await decoder.image(data: data, resource: resource, layout: layout), !Task.isCancelled
            else { return }
            let width = Double(tile.width) / Double(layout.columns)
            let height = Double(tile.height) / Double(layout.rows)
            image = tile.cropping(
                to: CGRect(
                    x: Double(frame.column) * width, y: Double(frame.row) * height, width: width, height: height))
        }

        private func seconds(_ duration: Duration) -> Double {
            Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        }

        private func timestamp(_ duration: Duration) -> String {
            let total = max(0, Int(duration.components.seconds))
            return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
        }
    }
#endif
