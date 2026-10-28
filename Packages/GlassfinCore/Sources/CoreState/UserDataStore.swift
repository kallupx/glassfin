import CoreModels
import CoreNetworking
import Foundation

/// In-memory source of truth for played, resume position, and favorite state.
///
/// A pending optimistic edit wins over a list refetch. A WebSocket user-data
/// payload replaces the pending edit, because that message is a newer server fact.
public actor UserDataStore {
    private struct Slot {
        var base: UserItemState
        var overlay: UserItemState?
        var pending: Bool

        var visible: UserItemState { overlay ?? base }
    }

    private var slots: [String: Slot] = [:]
    private var warnedNegativePosition: Set<String> = []

    private var playbackObservers: [UUID: AsyncStream<Void>.Continuation] = [:]

    public init() {}

    /// M06 observes playback stops without coupling the player to a particular screen.
    public func playbackChanges() -> AsyncStream<Void> {
        let id = UUID()
        return AsyncStream { continuation in
            playbackObservers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removePlaybackObserver(id) }
            }
        }
    }

    private func removePlaybackObserver(_ id: UUID) { playbackObservers[id] = nil }

    public func state(for id: String) -> UserItemState? {
        slots[id]?.visible
    }

    public func isPending(id: String) -> Bool {
        slots[id]?.pending ?? false
    }

    /// Inserts server state only when the id is unknown, then returns items using the visible state.
    public func project(_ items: [MediaItem]) -> [MediaItem] {
        items.map { item in
            var copy = item
            if slots[item.id] == nil {
                slots[item.id] = Slot(base: item.userData, overlay: nil, pending: false)
            }
            copy.userData = slots[item.id]?.visible ?? item.userData
            return copy
        }
    }

    @discardableResult
    public func applyOptimistic(id: String, next: UserItemState) -> UserItemState {
        var slot = slots[id] ?? Slot(base: UserItemState(), overlay: nil, pending: false)
        let previous = slot.visible
        slot.overlay = next
        slot.pending = true
        slots[id] = slot
        return previous
    }

    public func commit(id: String) {
        guard var slot = slots[id] else { return }
        if let overlay = slot.overlay {
            slot.base = overlay
        }
        slot.overlay = nil
        slot.pending = false
        slots[id] = slot
    }

    public func rollback(id: String, to previous: UserItemState) {
        var slot = slots[id] ?? Slot(base: previous, overlay: nil, pending: false)
        slot.base = previous
        slot.overlay = nil
        slot.pending = false
        slots[id] = slot
    }

    /// List/refetch data. Does not clobber a pending optimistic overlay.
    public func replaceFromServer(id: String, _ state: UserItemState) {
        guard ItemID(id) != nil else { return }
        guard var slot = slots[id] else {
            slots[id] = Slot(base: state, overlay: nil, pending: false)
            return
        }
        slot.base = state
        if !slot.pending {
            slot.overlay = nil
        }
        slots[id] = slot
    }

    public func applyRemote(_ change: UserDataChange, log: any GlassfinLog) {
        guard ItemID(change.itemID) != nil else { return }
        let position = clamped(ticks: change.positionTicks, id: change.itemID, log: log)
        let state = UserItemState(
            played: change.played,
            playbackPosition: position,
            isFavorite: change.isFavorite,
            unplayedCount: change.unplayedCount,
            playedPercentage: change.playedPercentage
        )
        slots[change.itemID] = Slot(base: state, overlay: nil, pending: false)
    }

    public func recordPlayback(id: String, position: Duration, played: Bool, log: any GlassfinLog) {
        guard ItemID(id) != nil else { return }
        var safe = position
        if position < .zero {
            safe = .zero
            if warnedNegativePosition.insert(id).inserted {
                log.warning("Negative position ticks were clamped to zero for item \(id).")
            }
        }
        var slot = slots[id] ?? Slot(base: UserItemState(), overlay: nil, pending: false)
        var visible = slot.visible
        visible.playbackPosition = safe
        visible.played = played
        slot.overlay = visible
        slot.pending = true
        slots[id] = slot
        for observer in playbackObservers.values { observer.yield(()) }
    }

    private func clamped(ticks: Int64, id: String, log: any GlassfinLog) -> Duration {
        if ticks < 0 {
            if warnedNegativePosition.insert(id).inserted {
                log.warning("Negative position ticks were clamped to zero for item \(id).")
            }
            return .zero
        }
        return Ticks.positionDuration(from: ticks, log: SilentLog())
    }
}
