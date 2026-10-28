import GlassfinCore
import SwiftUI

typealias PlaybackAction = @MainActor (PlaybackRequest, String) -> Void

struct PlaybackFocusReturn: Equatable {
    let id: String
    let sequence: UUID
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
    @State private var pendingReturn: String?
    @State private var focusReturn: PlaybackFocusReturn?

    var body: some View {
        content(start)
            .environment(\.startPlayback, start)
            .environment(\.playbackFocusReturn, focusReturn)
            .fullScreenCover(
                item: $presentation,
                onDismiss: {
                    if let pendingReturn {
                        focusReturn = PlaybackFocusReturn(id: pendingReturn, sequence: UUID())
                    }
                    pendingReturn = nil
                },
                content: { value in
                    PlaybackDestination(
                        request: value.request, returnFocusID: value.returnFocusID, makeCoordinator: makeCoordinator
                    ) { focusID, stop in
                        pendingReturn = focusID
                        if let stop { librarySession?.playbackDidEnd(itemID: stop.itemID, finished: stop.finished) }
                        presentation = nil
                    }
                    // Retain the Home automation container while exposing the player's own root.
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("home.playback")
                    .accessibilityValue(String(value.request.startTicks))
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
    @State private var failed = false
    @State private var closing = false

    var body: some View {
        Group {
            if let coordinator {
                PlaybackView(coordinator: coordinator, onClose: close)
            } else if failed {
                PlaybackErrorView(messageKey: PlaybackCopy.couldNotPlayKey, onClose: close)
                    .accessibilityIdentifier("playback.root")
            } else {
                ProgressView().accessibilityIdentifier("playback.root")
            }
        }
        .interactiveDismissDisabled()
        .task {
            do {
                let value = try makeCoordinator()
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
            if let coordinator { Task { await coordinator.stop() } }
        }
    }

    private func close() {
        guard !closing else { return }
        closing = true
        Task {
            let focusID = await coordinator?.dismiss() ?? returnFocusID
            onClose(focusID, coordinator?.lastStop)
        }
    }
}
