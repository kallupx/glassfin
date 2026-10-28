#if os(tvOS) || os(iOS)
    import GlassfinCore
    import UIKit

    /// Horizontal gestures drive only the custom scrub fallback. Vertical gestures remain AVKit's.
    @MainActor
    final class PlaybackScrubGestures: NSObject, UIGestureRecognizerDelegate {
        private let playback: PlaybackCoordinator
        private let companion: PlaybackCompanion
        private var pan: UIPanGestureRecognizer?
        private var tap: UITapGestureRecognizer?
        private var clicks: [UITapGestureRecognizer] = []
        private var panStart: Duration = .zero
        private var resumeAfterScrub = false
        private var wasScrubbing = false

        init(playback: PlaybackCoordinator, companion: PlaybackCompanion) {
            self.playback = playback
            self.companion = companion
        }

        func install(on view: UIView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            pan.delegate = self
            pan.cancelsTouchesInView = false
            view.addGestureRecognizer(pan)
            self.pan = pan
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            tap.delegate = self
            tap.cancelsTouchesInView = false
            #if os(tvOS)
                tap.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
                for (type, selector) in [
                    (UIPress.PressType.leftArrow, #selector(back)), (.rightArrow, #selector(forward)),
                ] {
                    let click = UITapGestureRecognizer(target: self, action: selector)
                    click.allowedPressTypes = [NSNumber(value: type.rawValue)]
                    click.delegate = self
                    view.addGestureRecognizer(click)
                    clicks.append(click)
                }
            #endif
            view.addGestureRecognizer(tap)
            self.tap = tap
        }

        func update() {
            let enabled = companion.layout != nil && companion.runtime != nil && companion.countdownSeconds == nil
            pan?.isEnabled = enabled
            tap?.isEnabled = enabled && companion.scrubPosition == nil
            for click in clicks { click.isEnabled = enabled && companion.scrubPosition == nil }
            if wasScrubbing && companion.scrubPosition == nil && resumeAfterScrub { playback.resume() }
            wasScrubbing = companion.scrubPosition != nil
        }

        private func beginScrub() {
            guard companion.scrubPosition == nil else { return }
            resumeAfterScrub = playback.state == .playing
            playback.pause()
            companion.scrub(to: playback.engine.position)
        }

        @objc private func tapped() { beginScrub() }
        @objc private func back() { Task { await playback.seek(to: playback.engine.position - .seconds(10)) } }
        @objc private func forward() { Task { await playback.seek(to: playback.engine.position + .seconds(10)) } }

        @objc private func panned(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began {
                beginScrub()
                panStart = companion.scrubPosition ?? playback.engine.position
            }
            if gesture.state == .began || gesture.state == .changed {
                companion.scrub(to: panStart + .seconds(gesture.translation(in: gesture.view).x / 10))
            }
            // Select confirms; Menu cancels. Ending the pan keeps the preview available.
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard !companion.transportVisible else { return false }
            // A contextual Skip button or native panel keeps its own Select/arrow presses.
            if let view = gestureRecognizer.view,
                let focused = UIFocusSystem(for: view)?.focusedItem as? UIView,
                focused.isDescendant(of: view), focused is UIControl
            {
                return false
            }
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
#endif
