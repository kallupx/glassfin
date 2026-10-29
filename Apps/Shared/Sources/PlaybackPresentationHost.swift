import GlassfinCore
import SwiftUI

typealias PlaybackAction = @MainActor (PlaybackRequest, String) -> Void

struct PlaybackFocusReturn: Equatable {
    let id: String
    let sequence: UUID
    let stop: PlaybackStop?
}

extension EnvironmentValues {
    @Entry var startPlayback: PlaybackAction? = nil
    @Entry var playbackFocusReturn: PlaybackFocusReturn? = nil
}

/// Home, library detail and episode cards share this single presentation path.
struct PlaybackPresentationHost<Content: View>: View {
    let makeCoordinator: @MainActor () throws -> PlaybackCoordinator
    var librarySession: LibrarySession? = nil
    @ViewBuilder var content: (@escaping PlaybackAction) -> Content
    @State private var presentation: Presentation?
    @State private var pendingReturn: PlaybackFocusReturn?
    @State private var focusReturn: PlaybackFocusReturn?

    var body: some View {
        content(start)
            .environment(\.startPlayback, start)
            .environment(\.playbackFocusReturn, focusReturn)
            .fullScreenCover(
                item: $presentation,
                onDismiss: {
                    if let pendingReturn {
                        focusReturn = pendingReturn
                    }
                    pendingReturn = nil
                },
                content: { value in
                    PlaybackDestination(
                        request: value.request, returnFocusID: value.returnFocusID, makeCoordinator: makeCoordinator
                    ) { focusID, stop in
                        pendingReturn = PlaybackFocusReturn(id: focusID, sequence: UUID(), stop: stop)
                        if let stop { librarySession?.playbackDidEnd(itemID: stop.itemID, finished: stop.finished) }
                        presentation = nil
                    }
                })
    }

    private func start(_ request: PlaybackRequest, returnFocusID: String) {
        guard presentation == nil else { return }
        presentation = Presentation(request: request, returnFocusID: returnFocusID)
    }

    private struct Presentation: Identifiable {
        let id = UUID()
        let request: PlaybackRequest
        let returnFocusID: String
    }
}

private struct PlaybackDestination: View {
    let request: PlaybackRequest
    let returnFocusID: String
    let makeCoordinator: @MainActor () throws -> PlaybackCoordinator
    let onClose: (String, PlaybackStop?) -> Void
    @State private var coordinator: PlaybackCoordinator?
    @State private var companion: PlaybackCompanion?
    @State private var failed = false
    @State private var closing = false

    var body: some View {
        ZStack {
            if let coordinator, let companion {
                PlaybackView(
                    coordinator: coordinator, companion: companion, startTicks: request.startTicks, onClose: close)
            } else if failed {
                PlaybackErrorView(messageKey: PlaybackCopy.couldNotPlayKey, onClose: close)
            } else {
                ProgressView()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("playback.root")
        .interactiveDismissDisabled()
        .task {
            guard coordinator == nil, !failed, !closing else { return }
            do {
                let value = try makeCoordinator()
                companion = value.makeCompanion(
                    settings: .load(from: UserDefaultsSettingsStore(defaults: .standard)))
                coordinator = value
                await value.play(request, returnFocusID: returnFocusID)
            } catch {
                failed = true
            }
        }
        #if os(tvOS)
            .onExitCommand { close() }
        #endif
        .onDisappear {
            Task {
                await companion?.shutdown()
                await coordinator?.stop()
            }
        }
    }

    private func close() {
        guard !closing else { return }
        closing = true
        Task {
            let nextFocusID = companion?.returnFocusItemID.map { "series.episode.\($0)" }
            await companion?.shutdown()
            let focusID = await coordinator?.dismiss() ?? returnFocusID
            onClose(nextFocusID ?? focusID, coordinator?.lastStop)
        }
    }
}
