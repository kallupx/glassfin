import CoreModels
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

public struct UserDataChange: Sendable, Equatable {
    public var itemID: String
    public var played: Bool
    public var positionTicks: Int64
    public var isFavorite: Bool
    public var unplayedCount: Int?
    public var playedPercentage: Double?

    public init(
        itemID: String,
        played: Bool,
        positionTicks: Int64,
        isFavorite: Bool,
        unplayedCount: Int? = nil,
        playedPercentage: Double? = nil
    ) {
        self.itemID = itemID
        self.played = played
        self.positionTicks = positionTicks
        self.isFavorite = isFavorite
        self.unplayedCount = unplayedCount
        self.playedPercentage = playedPercentage
    }
}

public enum ServerEvent: Sendable, Equatable {
    case userDataChanged(items: [UserDataChange])
    case libraryChanged
    case play
    case playstate
    case generalCommand
    case serverShuttingDown
    case serverRestarting
}

public enum ConnectionPhase: Sendable, Equatable {
    case idle
    case connecting
    case connected
    case reconnecting
    case stopped
}

public enum ServerEventParser {
    public static func parse(_ data: Data) -> ServerEvent? {
        guard let type = messageType(in: data) else { return nil }
        switch type {
        case "UserDataChanged": return .userDataChanged(items: userDataChanges(in: data))
        case "LibraryChanged": return .libraryChanged
        case "Play": return .play
        case "Playstate": return .playstate
        case "GeneralCommand": return .generalCommand
        case "ServerShuttingDown": return .serverShuttingDown
        case "ServerRestarting": return .serverRestarting
        default:
            return nil
        }
    }

    public static func isForceKeepAlive(_ data: Data) -> Bool {
        messageType(in: data) == "ForceKeepAlive"
    }

    static func messageType(in data: Data) -> String? {
        struct Envelope: Decodable { var MessageType: String? }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.MessageType
    }

    public static let keepAliveReply = Data("{\"MessageType\":\"KeepAlive\"}".utf8)

    /// Item ids that are not 32-hex GUIDs are dropped (S3, including WebSocket payloads).
    /// The raw JSON is never logged.
    public static func userDataChanges(in data: Data) -> [UserDataChange] {
        struct Envelope: Decodable {
            struct Payload: Decodable {
                struct Entry: Decodable {
                    var ItemId: String?
                    var UserData: UserItemDataDTO?
                }

                var UserDataList: [Entry]?
            }

            var Data: Payload?
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return [] }
        return (envelope.Data?.UserDataList ?? []).compactMap { entry in
            guard let raw = entry.ItemId, let id = ItemID(raw), let userData = entry.UserData else { return nil }
            return UserDataChange(
                itemID: id.value,
                played: userData.Played ?? false,
                positionTicks: userData.PlaybackPositionTicks ?? 0,
                isFavorite: userData.IsFavorite ?? false,
                unplayedCount: userData.UnplayedItemCount,
                playedPercentage: userData.PlayedPercentage
            )
        }
    }
}

public protocol RealtimeSocket: Sendable {
    func connect() async throws
    func receive() async throws -> Data
    func send(_ data: Data) async throws
    func close() async
}

public protocol RealtimeSocketFactory: Sendable {
    func makeSocket(url: URL) -> any RealtimeSocket
}

public protocol ServerEventStream: Sendable {
    var events: AsyncStream<ServerEvent> { get }
    var phase: ConnectionPhase { get }
    func applicationDidBecomeActive()
    func stop()
}

public final class ReconnectGate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// A foreground signal that arrived before `wait()` is remembered once.
    private var pendingFire = false

    public init() {}

    public func fire() {
        lock.lock()
        let pending = waiters
        waiters.removeAll()
        if pending.isEmpty {
            pendingFire = true
        }
        lock.unlock()
        for waiter in pending {
            waiter.resume()
        }
    }

    public func wait() async {
        if consumePendingFire() { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if self.enqueue(continuation) {
                    continuation.resume()
                }
            }
        } onCancel: {
            self.fire()
        }
    }

    /// `true` when the caller must resume `continuation` itself.
    private func enqueue(_ continuation: CheckedContinuation<Void, Never>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if pendingFire {
            pendingFire = false
            return true
        }
        waiters.append(continuation)
        return false
    }

    private func consumePendingFire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if pendingFire {
            pendingFire = false
            return true
        }
        return false
    }
}

public final class PhaseStore: @unchecked Sendable {
    private let lock = NSLock()
    private var value: ConnectionPhase
    public init(_ value: ConnectionPhase = .idle) { self.value = value }
    public func set(_ phase: ConnectionPhase) {
        lock.lock()
        value = phase
        lock.unlock()
    }

    public func get() -> ConnectionPhase {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

public final class ReconnectingServerEventStream: ServerEventStream, @unchecked Sendable {
    public let events: AsyncStream<ServerEvent>
    public var phase: ConnectionPhase { phases.get() }
    private let continuation: AsyncStream<ServerEvent>.Continuation
    private let gate: ReconnectGate
    private let phases: PhaseStore
    private let task: Task<Void, Never>

    public init(
        request: URLRequest,
        sockets: any RealtimeSocketFactory,
        clock: any GlassfinClock,
        jitter: any JitterSource
    ) {
        let pair = AsyncStream<ServerEvent>.makeStream()
        let gate = ReconnectGate()
        let phases = PhaseStore()
        events = pair.stream
        continuation = pair.continuation
        self.gate = gate
        self.phases = phases
        task = Task {
            await ReconnectLoop.run(
                request: request,
                sockets: sockets,
                clock: clock,
                jitter: jitter,
                gate: gate,
                phases: phases,
                continuation: pair.continuation
            )
        }
    }

    public func applicationDidBecomeActive() {
        gate.fire()
    }

    public func stop() {
        task.cancel()
        gate.fire()
        continuation.finish()
        phases.set(.stopped)
    }
}

enum StreamDrop: Error {
    case serverRestart
}

enum ReconnectLoop {
    static func run(
        request: URLRequest,
        sockets: any RealtimeSocketFactory,
        clock: any GlassfinClock,
        jitter: any JitterSource,
        gate: ReconnectGate,
        phases: PhaseStore,
        continuation: AsyncStream<ServerEvent>.Continuation
    ) async {
        var controller = ReconnectController()
        let url = request.url ?? URL(fileURLWithPath: "/")
        while !Task.isCancelled {
            let socket = sockets.makeSocket(url: url)
            do {
                phases.set(.connecting)
                try await socket.connect()
                controller.didConnect(now: clock.now())
                phases.set(.connected)
                while !Task.isCancelled {
                    controller.markStableIfNeeded(now: clock.now())
                    let data = try await socket.receive()
                    if let event = ServerEventParser.parse(data) {
                        continuation.yield(event)
                        if event == .serverShuttingDown || event == .serverRestarting {
                            phases.set(.reconnecting)
                            await socket.close()
                            throw StreamDrop.serverRestart
                        }
                    } else if ServerEventParser.isForceKeepAlive(data) {
                        try await socket.send(ServerEventParser.keepAliveReply)
                    }
                }
            } catch is CancellationError {
                await socket.close()
                break
            } catch {
                await socket.close()
                if Task.isCancelled { break }
                phases.set(.reconnecting)
                let delay = controller.delayAfterFailure(now: clock.now(), jitterUnit: jitter.nextUnitInterval())
                await sleepOrForeground(delay, clock: clock, gate: gate)
                if Task.isCancelled { break }
            }
        }
        phases.set(.stopped)
        continuation.finish()
    }

    static func sleepOrForeground(_ duration: Duration, clock: any GlassfinClock, gate: ReconnectGate) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                try? await clock.sleep(for: duration)
            }
            group.addTask {
                await gate.wait()
            }
            await group.next()
            group.cancelAll()
        }
    }
}
