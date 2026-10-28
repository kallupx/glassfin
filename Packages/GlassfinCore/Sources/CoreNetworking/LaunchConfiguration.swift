import Foundation

#if DEBUG
    /// Debug-only UI-test switches. The string literals must not exist in Release binaries (T00-19).
    public struct LaunchConfiguration: Sendable, Equatable {
        public var useMockServer: Bool
        public var resetState: Bool
        public var startOnHome: Bool

        public init(arguments: [String]) {
            startOnHome = arguments.contains("-uitest-home")
            useMockServer = arguments.contains("-uitest-mock-server") || startOnHome
            resetState = arguments.contains("-uitest-reset")
        }
    }
#endif
