import CoreModels
import Foundation

public enum HomeTabRoute: Hashable, Sendable {
    case item(ItemID)
    case series(ItemID)

    public static func item(id raw: String) -> HomeTabRoute? {
        guard let id = ItemID(raw) else { return nil }
        return .item(id)
    }

    public static func series(id raw: String) -> HomeTabRoute? {
        guard let id = ItemID(raw) else { return nil }
        return .series(id)
    }
}

public enum LibraryTabRoute: Hashable, Sendable {
    case folder(ItemID)
    case item(ItemID)
    case series(ItemID)
}

public enum SearchTabRoute: Hashable, Sendable {
    case item(ItemID)
}

public enum SettingsTabRoute: Hashable, Sendable {
    case diagnostics
    case server(String)
}

/// Typed path for one tab. SwiftUI's `NavigationStack` binds to ``path`` outside this package.
public struct RouteStack<Route: Hashable & Sendable>: Sendable {
    public private(set) var path: [Route] = []
    private var focusedID: [Int: String] = [:]
    private var scrollID: [Int: String] = [:]

    public init() {}

    public struct RestoredFocus: Sendable, Equatable {
        public var focusedID: String?
        public var scrollID: String?

        public init(focusedID: String?, scrollID: String?) {
            self.focusedID = focusedID
            self.scrollID = scrollID
        }
    }

    /// Saves focus for the screen being left, then pushes `route`.
    public mutating func push(_ route: Route, focusedID: String? = nil, scrollID: String? = nil) {
        self.focusedID[path.count] = focusedID
        self.scrollID[path.count] = scrollID
        path.append(route)
    }

    /// Pops and returns the focus that belonged to the screen now on top.
    public mutating func pop() -> RestoredFocus? {
        guard !path.isEmpty else { return nil }
        path.removeLast()
        return RestoredFocus(focusedID: focusedID[path.count], scrollID: scrollID[path.count])
    }
}

public struct TabNavigationState: Sendable {
    public var home = RouteStack<HomeTabRoute>()
    public var library = RouteStack<LibraryTabRoute>()
    public var search = RouteStack<SearchTabRoute>()
    public var settings = RouteStack<SettingsTabRoute>()

    public init() {}
}
