import SwiftUI

struct GlassfinRootView: View {
    var body: some View {
        #if DEBUG
            switch DesignSystemLaunch.screen {
            case .welcome:
                NavigationStack {
                    WelcomeView()
                }
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
            NavigationStack {
                WelcomeView()
            }
        #endif
    }
}

#if DEBUG
    enum DesignSystemLaunch {
        enum Screen {
            case welcome
            case focus
            case error
            case tabs(Int)
            case navigation
        }

        static var screen: Screen {
            let arguments = ProcessInfo.processInfo.arguments
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
