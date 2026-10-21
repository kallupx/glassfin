import Foundation

#if DEBUG
    /// Debug-only UI-test switches. The string literals must not exist in Release binaries (T00-19).
    public struct LaunchConfiguration: Sendable, Equatable {
        public var useMockServer: Bool
        public var resetState: Bool

        public init(arguments: [String]) {
            useMockServer = arguments.contains("-uitest-mock-server")
            resetState = arguments.contains("-uitest-reset")
        }
    }
#endif
