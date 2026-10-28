import GlassfinCore
import SwiftUI

struct GlassfinRootView: View {
    var flow: AuthFlow

    var body: some View {
        #if DEBUG
            switch DesignSystemLaunch.screen {
            case .search:
                SearchUITestRoot()
            case .welcome:
                AuthRootView(flow: flow)
            case .focus:
                DesignSystemFocusDemo()
            case .error:
                DesignSystemErrorDemo()
            case .tabs(let count):
                LibraryTabShell(
                    libraries: (0..<count).map { LibraryTabItem(id: "\($0)", title: "\($0 + 1)") },
                    home: AnyView(Copy.text(.tabHome).accessibilityIdentifier("design.home.root"))
                )
            case .navigation:
                NavigationPrototype()
            }
        #else
            AuthRootView(flow: flow)
        #endif
    }
}

#if DEBUG
    enum DesignSystemLaunch {
        enum Screen {
            case welcome
            case search
            case focus
            case error
            case tabs(Int)
            case navigation
        }

        static var screen: Screen {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-uitest-search") { return .search }
            if arguments.contains("-uitest-design-system-error") {
                return .error
            }
            if arguments.contains("-uitest-design-system-tabs-7") {
                return .tabs(7)
            }
            if arguments.contains("-uitest-design-system-tabs-3") {
                return .tabs(3)
            }
            if arguments.contains("-uitest-design-system-nav") {
                return .navigation
            }
            if arguments.contains("-uitest-design-system") {
                return .focus
            }
            return .welcome
        }
    }
#endif
