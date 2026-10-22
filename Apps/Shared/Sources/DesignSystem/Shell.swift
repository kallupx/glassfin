import SwiftUI

struct LibraryTabShell: View {
    var libraries: [LibraryTabItem]
    var home: AnyView
    @State private var selection: String = "home"

    private var plan: LibraryTabPlan {
        LibraryTabModel.plan(libraries: libraries)
    }

    var body: some View {
        TabView(selection: $selection) {
            homeTab
            ForEach(plan.inline) { library in
                libraryTab(library)
            }
            if !plan.overflow.isEmpty {
                overflowTab
            }
            searchTab
            settingsTab
        }
        .modifier(PlatformTabChrome())
        .accessibilityIdentifier("design.shell.root")
    }

    private var homeTab: some View {
        Tab(value: "home") {
            home
        } label: {
            tabLabel(.tabHome, symbol: "house", identifier: "design.tab.home")
        }
    }

    private func libraryTab(_ library: LibraryTabItem) -> some View {
        Tab(value: library.id) {
            Text(verbatim: library.title)
                .accessibilityIdentifier("design.library.\(library.id)")
        } label: {
            Label {
                Text(verbatim: library.title)
            } icon: {
                GlassIcon(systemName: "rectangle.stack", label: .tabLibraries)
            }
            .accessibilityIdentifier("design.tab.library.\(library.id)")
        }
    }

    private var overflowTab: some View {
        Tab(value: "libraries") {
            VStack(alignment: .leading, spacing: SpacingToken.m) {
                Copy.text(.tabLibraries)
                    .font(.title2)
                    .foregroundStyle(.primary)
                ForEach(plan.overflow) { library in
                    Text(verbatim: library.title)
                        .accessibilityIdentifier("design.libraryOverflow.\(library.id)")
                }
            }
            .accessibilityIdentifier("design.libraries.root")
        } label: {
            tabLabel(.tabLibraries, symbol: "square.grid.2x2", identifier: "design.tab.libraries")
        }
    }

    private var searchTab: some View {
        Tab(value: "search", role: .search) {
            Copy.text(.tabSearch)
                .accessibilityIdentifier("design.search.root")
        } label: {
            tabLabel(.tabSearch, symbol: "magnifyingglass", identifier: "design.tab.search")
        }
    }

    private var settingsTab: some View {
        Tab(value: "settings") {
            Copy.text(.tabSettings)
                .accessibilityIdentifier("design.settings.root")
        } label: {
            tabLabel(.tabSettings, symbol: "gearshape", identifier: "design.tab.settings")
        }
    }

    private func tabLabel(_ key: CopyKey, symbol: String, identifier: String) -> some View {
        Label {
            Copy.text(key)
        } icon: {
            GlassIcon(systemName: symbol, label: key)
        }
        .accessibilityIdentifier(identifier)
    }
}

private struct PlatformTabChrome: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
            content
                .tabViewStyle(.sidebarAdaptable)
                .modifier(PhoneTabBarMinimize())
        #else
            content
        #endif
    }
}

#if os(iOS)
    private struct PhoneTabBarMinimize: ViewModifier {
        @Environment(\.horizontalSizeClass) private var sizeClass

        @ViewBuilder
        func body(content: Content) -> some View {
            if sizeClass == .compact {
                content.tabBarMinimizeBehavior(.onScrollDown)
            } else {
                content.tabBarMinimizeBehavior(.automatic)
            }
        }
    }
#endif

enum NavRoute: Hashable {
    case library
    case detail
}

struct NavigationPrototype: View {
    @State private var path: [NavRoute] = [.library, .detail]

    var body: some View {
        LibraryTabShell(libraries: [], home: AnyView(stack))
    }

    private var stack: some View {
        NavigationStack(path: $path) {
            navScreen(.navRoot, identifier: "design.nav.root")
                .navigationDestination(for: NavRoute.self) { route in
                    switch route {
                    case .library:
                        navScreen(.navLibrary, identifier: "design.nav.library")
                    case .detail:
                        navScreen(.navDetail, identifier: "design.nav.detail")
                    }
                }
        }
    }

    private func navScreen(_ key: CopyKey, identifier: String) -> some View {
        Copy.text(key)
            .font(.largeTitle)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier(identifier)
    }
}
