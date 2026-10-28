import Foundation

#if canImport(os)
    import os
#endif

/// Fixed names only: callers cannot attach media, account, URL, or credential metadata.
public enum DevicePerformance {
    public static let subsystem = "org.glassfin.app"
    public static let category = "DevicePerformance"

    public enum Mark: String, Sendable {
        case launchHomeRow = "launch.homeRowVisible"
        case launchInteractive = "launch.interactive"
        case homeLoad = "home.load"
        case focusUpdate = "browse.focusUpdate"
        case posterCache = "poster.cacheBytes"
        case posterNetwork = "poster.networkBytes"
        case posterReady = "poster.ready"
        case imageDecode = "image.decode"
        case playbackFirstFrame = "playback.firstFrame"
        case playbackDirectStreamFirstFrame = "playback.directStreamFirstFrame"
        case playbackTranscodeFirstFrame = "playback.transcodeFirstFrame"
        case playbackSeek = "playback.seekResume"
        case playbackLifetime = "playback.lifetime"
        case remoteApply = "home.remoteApply"
        case watchedProjection = "home.watchedProjection"

        fileprivate var name: StaticString {
            switch self {
            case .launchHomeRow: "launch.homeRowVisible"
            case .launchInteractive: "launch.interactive"
            case .homeLoad: "home.load"
            case .focusUpdate: "browse.focusUpdate"
            case .posterCache: "poster.cacheBytes"
            case .posterNetwork: "poster.networkBytes"
            case .posterReady: "poster.ready"
            case .imageDecode: "image.decode"
            case .playbackFirstFrame: "playback.firstFrame"
            case .playbackDirectStreamFirstFrame: "playback.directStreamFirstFrame"
            case .playbackTranscodeFirstFrame: "playback.transcodeFirstFrame"
            case .playbackSeek: "playback.seekResume"
            case .playbackLifetime: "playback.lifetime"
            case .remoteApply: "home.remoteApply"
            case .watchedProjection: "home.watchedProjection"
            }
        }
    }

    /// A scope ends exactly once, including cancellation and early returns. No timer or polling.
    public final class Interval: @unchecked Sendable {
        private let lock = NSLock()
        private let mark: Mark
        #if canImport(os)
            private var state: OSSignpostIntervalState?
        #endif

        fileprivate init(_ mark: Mark) {
            self.mark = mark
            #if canImport(os)
                state = DevicePerformance.poster.beginInterval(mark.name, id: DevicePerformance.poster.makeSignpostID())
            #endif
        }

        public func end(completed: Bool = true) {
            #if canImport(os)
                lock.lock()
                let pending = state
                state = nil
                lock.unlock()
                guard let pending else { return }
                if completed {
                    DevicePerformance.poster.endInterval(mark.name, pending, "completed")
                } else {
                    DevicePerformance.poster.endInterval(mark.name, pending, "cancelled")
                }
            #endif
        }

        deinit { end(completed: false) }
    }

    #if canImport(os)
        private static let poster = OSSignposter(subsystem: subsystem, category: category)
    #endif

    /// Disabled tracing avoids allocating an interval or storing signpost state.
    public static func begin(_ mark: Mark) -> Interval? {
        #if canImport(os)
            guard poster.isEnabled else { return nil }
            return Interval(mark)
        #else
            return nil
        #endif
    }
}
