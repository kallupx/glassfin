import CoreModels
import CoreNetworking
import Observation

@MainActor
@Observable
public final class HomeBackdropModel {
    public private(set) var item: MediaItem?
    @ObservationIgnored private let clock: any GlassfinClock
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    public init(clock: any GlassfinClock = SystemGlassfinClock()) { self.clock = clock }

    public func focus(_ item: MediaItem?) {
        task?.cancel()
        generation += 1
        let current = generation
        task = Task {
            do { try await clock.sleep(for: HomePolicy.backdropDebounce) } catch { return }
            guard !Task.isCancelled, current == generation else { return }
            self.item = item.map(HomeMetadata.item)
        }
    }

    public func cancel() {
        generation += 1
        task?.cancel()
    }
}
