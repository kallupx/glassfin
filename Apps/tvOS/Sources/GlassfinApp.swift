import GlassfinCore
import SwiftUI

@main
struct GlassfinApp: App {
    @State private var flow: AuthFlow

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        #if DEBUG
            let configuration = LaunchConfiguration(arguments: arguments)
            if configuration.resetState || configuration.useMockServer {
                _ = GlassfinCoreModule.name
            }
        #endif
        _flow = State(initialValue: AuthAssembly.make(arguments: arguments))
    }

    var body: some Scene {
        WindowGroup {
            GlassfinRootView(flow: flow)
        }
    }
}
