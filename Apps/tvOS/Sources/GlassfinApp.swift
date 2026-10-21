import GlassfinCore
import SwiftUI

@main
struct GlassfinApp: App {
    init() {
        #if DEBUG
            let configuration = LaunchConfiguration(arguments: ProcessInfo.processInfo.arguments)
            if configuration.resetState || configuration.useMockServer {
                _ = GlassfinCoreModule.name
            }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            WelcomeView()
        }
    }
}
