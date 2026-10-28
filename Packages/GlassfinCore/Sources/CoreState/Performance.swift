import Foundation

#if canImport(os)
    import os
#endif

public enum PerformanceMark: String, Sendable, CaseIterable, Equatable {
    case coldStartHomeFirstRow = "launch.homeFirstRow"
    case homeSectionsLoaded = "home.sections"
    case focusScroll = "browse.focusScroll"
    case posterCache = "image.poster.cache"
    case posterNetwork = "image.poster.network"
    case playbackFirstFrame = "playback.firstFrame"
    case playbackTranscodeFirstFrame = "playback.transcodeFirstFrame"
    case playbackScrub = "playback.scrub"
    case trickplayPreview = "playback.trickplay"
    case trackSwitch = "playback.trackSwitch"
    case searchResults = "search.results"
    case memoryBrowse = "memory.browse"
    case memoryPlayback = "memory.playback"
    case memoryRemux = "memory.remux"
    case memoryLeakCycle = "memory.leakCycle"
    case watchedStateHome = "home.watchedState"
    case remoteUserData = "home.remoteUserData"
}

public struct SignpostInterval: Sendable, Equatable {
    public var mark: PerformanceMark
    public var id: UInt64

    public init(mark: PerformanceMark, id: UInt64) {
        self.mark = mark
        self.id = id
    }
}

public protocol Signposting: Sendable {
    func begin(_ mark: PerformanceMark) -> SignpostInterval
    func end(_ interval: SignpostInterval)
    func event(_ mark: PerformanceMark)
}

public struct NoopSignposter: Signposting {
    public init() {}

    public func begin(_ mark: PerformanceMark) -> SignpostInterval {
        SignpostInterval(mark: mark, id: 0)
    }

    public func end(_ interval: SignpostInterval) {}

    public func event(_ mark: PerformanceMark) {}
}

public final class RecordingSignposter: Signposting, @unchecked Sendable {
    public struct Sample: Sendable, Equatable {
        public var mark: PerformanceMark
        public var phase: String

        public init(mark: PerformanceMark, phase: String) {
            self.mark = mark
            self.phase = phase
        }
    }

    private let lock = NSLock()
    private var samples: [Sample] = []
    private var next: UInt64 = 0
    private var open: Set<UInt64> = []

    public init() {}

    public func begin(_ mark: PerformanceMark) -> SignpostInterval {
        lock.lock()
        next &+= 1
        let id = next
        open.insert(id)
        samples.append(Sample(mark: mark, phase: "begin"))
        lock.unlock()
        return SignpostInterval(mark: mark, id: id)
    }

    public func end(_ interval: SignpostInterval) {
        lock.lock()
        defer { lock.unlock() }
        guard open.remove(interval.id) != nil else { return }
        samples.append(Sample(mark: interval.mark, phase: "end"))
    }

    public func event(_ mark: PerformanceMark) {
        lock.lock()
        samples.append(Sample(mark: mark, phase: "event"))
        lock.unlock()
    }

    public func snapshot() -> [Sample] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }
}

public enum Signposters {
    public static let subsystem = "org.glassfin.app"
    public static let category = "Performance"

    public static func production() -> any Signposting {
        #if canImport(os)
            SystemSignposter()
        #else
            NoopSignposter()
        #endif
    }
}

#if canImport(os)
    public final class SystemSignposter: Signposting, @unchecked Sendable {
        private let poster = OSSignposter(subsystem: Signposters.subsystem, category: Signposters.category)
        private let lock = NSLock()
        private var next: UInt64 = 0
        private var states: [UInt64: OSSignpostIntervalState] = [:]

        public init() {}

        public func begin(_ mark: PerformanceMark) -> SignpostInterval {
            lock.lock()
            next &+= 1
            let id = next
            lock.unlock()
            let state = poster.beginInterval(Self.staticName(mark), id: poster.makeSignpostID())
            lock.lock()
            states[id] = state
            lock.unlock()
            return SignpostInterval(mark: mark, id: id)
        }

        public func end(_ interval: SignpostInterval) {
            lock.lock()
            let state = states.removeValue(forKey: interval.id)
            lock.unlock()
            guard let state else { return }
            poster.endInterval(Self.staticName(interval.mark), state)
        }

        public func event(_ mark: PerformanceMark) {
            poster.emitEvent(Self.staticName(mark))
        }

        private static func staticName(_ mark: PerformanceMark) -> StaticString {
            switch mark {
            case .coldStartHomeFirstRow: "launch.homeFirstRow"
            case .homeSectionsLoaded: "home.sections"
            case .focusScroll: "browse.focusScroll"
            case .posterCache: "image.poster.cache"
            case .posterNetwork: "image.poster.network"
            case .playbackFirstFrame: "playback.firstFrame"
            case .playbackTranscodeFirstFrame: "playback.transcodeFirstFrame"
            case .playbackScrub: "playback.scrub"
            case .trickplayPreview: "playback.trickplay"
            case .trackSwitch: "playback.trackSwitch"
            case .searchResults: "search.results"
            case .memoryBrowse: "memory.browse"
            case .memoryPlayback: "memory.playback"
            case .memoryRemux: "memory.remux"
            case .memoryLeakCycle: "memory.leakCycle"
            case .watchedStateHome: "home.watchedState"
            case .remoteUserData: "home.remoteUserData"
            }
        }
    }
#endif

public struct PerformanceBudgetEntry: Sendable, Equatable {
    public var id: String
    public var mark: PerformanceMark
    public var summary: String
    public var a15Milliseconds: Double?
    public var oldestMilliseconds: Double?
    public var a15Megabytes: Int?
    public var oldestMegabytes: Int?
    public var hitchMillisecondsPerSecondA15: Double?
    public var hitchMillisecondsPerSecondOldest: Double?

    public init(
        id: String,
        mark: PerformanceMark,
        summary: String,
        a15Milliseconds: Double? = nil,
        oldestMilliseconds: Double? = nil,
        a15Megabytes: Int? = nil,
        oldestMegabytes: Int? = nil,
        hitchMillisecondsPerSecondA15: Double? = nil,
        hitchMillisecondsPerSecondOldest: Double? = nil
    ) {
        self.id = id
        self.mark = mark
        self.summary = summary
        self.a15Milliseconds = a15Milliseconds
        self.oldestMilliseconds = oldestMilliseconds
        self.a15Megabytes = a15Megabytes
        self.oldestMegabytes = oldestMegabytes
        self.hitchMillisecondsPerSecondA15 = hitchMillisecondsPerSecondA15
        self.hitchMillisecondsPerSecondOldest = hitchMillisecondsPerSecondOldest
    }
}

public enum PerformanceCatalog {
    public static let all: [PerformanceBudgetEntry] = [
        entry("P1", .coldStartHomeFirstRow, "Cold start to the first home row", ms: (1_500, 3_000)),
        entry("P2", .homeSectionsLoaded, "Home sections loaded", ms: (1_000, 2_000)),
        PerformanceBudgetEntry(
            id: "P3", mark: .focusScroll, summary: "Focus move and scroll hitch ratio",
            hitchMillisecondsPerSecondA15: 5, hitchMillisecondsPerSecondOldest: 10),
        entry("P4", .posterCache, "Poster from cache", ms: (100, 200)),
        entry("P4", .posterNetwork, "Poster from the LAN", ms: (500, 800)),
        entry("P5", .playbackFirstFrame, "Direct play first frame", ms: (1_500, 2_500)),
        entry("P6", .playbackTranscodeFirstFrame, "Transcode first frame", ms: (4_000, 6_000)),
        entry("P7", .playbackScrub, "Scrub to resumed playback", ms: (1_000, 2_000)),
        entry("P8", .trickplayPreview, "Trickplay tile", ms: (150, 300)),
        entry("P9", .trackSwitch, "Audio or subtitle switch", ms: (1_000, 2_000)),
        entry("P10", .searchResults, "Search results after debounce", ms: (500, 1_000)),
        PerformanceBudgetEntry(
            id: "P11", mark: .memoryBrowse, summary: "Memory while browsing", a15Megabytes: 250,
            oldestMegabytes: 200),
        PerformanceBudgetEntry(
            id: "P12", mark: .memoryPlayback, summary: "Memory during AVPlayer playback", a15Megabytes: 400,
            oldestMegabytes: 300),
        PerformanceBudgetEntry(
            id: "P12", mark: .memoryRemux, summary: "Memory during remux playback", a15Megabytes: 500,
            oldestMegabytes: 400),
        PerformanceBudgetEntry(
            id: "P13", mark: .memoryLeakCycle, summary: "Growth across 10 play-stop cycles", a15Megabytes: 20,
            oldestMegabytes: 20),
        entry("P14", .watchedStateHome, "Watched state on Home after playback", ms: (2_000, 2_000)),
        entry("P15", .remoteUserData, "Other client's user-data change", ms: (5_000, 5_000)),
    ]

    public static var identifiers: [String] {
        var seen: [String] = []
        for item in all where !seen.contains(item.id) {
            seen.append(item.id)
        }
        return seen
    }

    public static func meets(elapsed: Duration, targetMilliseconds: Double) -> Bool {
        let milliseconds = Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
        return milliseconds <= targetMilliseconds
    }

    private static func entry(
        _ id: String, _ mark: PerformanceMark, _ summary: String, ms: (Double, Double)
    ) -> PerformanceBudgetEntry {
        PerformanceBudgetEntry(
            id: id, mark: mark, summary: summary, a15Milliseconds: ms.0, oldestMilliseconds: ms.1)
    }
}

public enum ImageRequestSizing {
    /// `maxWidth` is the displayed point width times the screen scale. Full-size images are not requested.
    public static func maxPixelWidth(displayPoints: Int, screenScale: Int) -> Int {
        let points = max(displayPoints, 1)
        let scale = max(screenScale, 1)
        let product = points.multipliedReportingOverflow(by: scale)
        if product.overflow { return Int.max }
        return max(product.partialValue, 1)
    }
}

public enum ListPaging {
    public static let pageSize = 50
    public static let prefetchRemaining = 10

    public static func shouldPrefetch(index: Int, loaded: Int, total: Int?) -> Bool {
        guard loaded > 0, index >= 0, index < loaded else { return false }
        if let total, loaded >= total { return false }
        let remaining = loaded - index - 1
        return remaining <= prefetchRemaining
    }
}

public struct BrowseInstrumentation: Sendable {
    public var signposter: any Signposting

    public init(signposter: any Signposting) {
        self.signposter = signposter
    }

    public func measureFocusScroll<T>(_ body: () throws -> T) rethrows -> T {
        let interval = signposter.begin(.focusScroll)
        defer { signposter.end(interval) }
        return try body()
    }

    public func noteBrowseMemorySample() {
        signposter.event(.memoryBrowse)
    }

    public func notePlaybackMemorySample() {
        signposter.event(.memoryPlayback)
    }

    public func noteRemuxMemorySample() {
        signposter.event(.memoryRemux)
    }

    public func noteLeakCycleSample() {
        signposter.event(.memoryLeakCycle)
    }
}
