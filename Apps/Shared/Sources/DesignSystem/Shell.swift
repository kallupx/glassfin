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
            #if os(iOS)
                // Keep primary destinations ahead of libraries so More cannot hide their identified buttons.
                searchTab
                settingsTab
            #endif
            ForEach(plan.inline) { library in
                libraryTab(library)
            }
            if !plan.overflow.isEmpty {
                overflowTab
            }
            #if !os(iOS)
                searchTab
                settingsTab
            #endif
        }
        .modifier(PlatformTabChrome())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("design.shell.root")
    }

    @TabContentBuilder<String>
    private var homeTab: some TabContent<String> {
        Tab(value: "home") {
            home
        } label: {
            tabLabel(.tabHome, symbol: "house", identifier: "design.tab.home")
        }
        #if os(iOS)
            // iOS needs the identifier on the Tab, not only its SwiftUI label.
            .accessibilityIdentifier("design.tab.home")
        #endif
    }

    @TabContentBuilder<String>
    private func libraryTab(_ library: LibraryTabItem) -> some TabContent<String> {
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
        #if os(iOS)
            .accessibilityIdentifier("design.tab.library.\(library.id)")
        #endif
    }

    @TabContentBuilder<String>
    private var overflowTab: some TabContent<String> {
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
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("design.libraries.root")
        } label: {
            tabLabel(.tabLibraries, symbol: "square.grid.2x2", identifier: "design.tab.libraries")
        }
        #if os(iOS)
            .accessibilityIdentifier("design.tab.libraries")
        #endif
    }

    @TabContentBuilder<String>
    private var searchTab: some TabContent<String> {
        Tab(value: "search", role: .search) {
            Copy.text(.tabSearch)
                .accessibilityIdentifier("design.search.root")
        } label: {
            tabLabel(.tabSearch, symbol: "magnifyingglass", identifier: "design.tab.search")
        }
        #if os(iOS)
            .accessibilityIdentifier("design.tab.search")
        #endif
    }

    @TabContentBuilder<String>
    private var settingsTab: some TabContent<String> {
        Tab(value: "settings") {
            Copy.text(.tabSettings)
                .accessibilityIdentifier("design.settings.root")
        } label: {
            tabLabel(.tabSettings, symbol: "gearshape", identifier: "design.tab.settings")
        }
        #if os(iOS)
            .accessibilityIdentifier("design.tab.settings")
        #endif
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

    @ViewBuilder
    private func navScreen(_ key: CopyKey, identifier: String) -> some View {
        #if os(tvOS)
            NavigationFocusScreen(title: key, identifier: identifier)
        #else
            Copy.text(key)
                .font(.largeTitle)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier(identifier)
        #endif
    }
}

#if os(tvOS)
    private struct NavigationFocusScreen: View {
        var title: CopyKey
        var identifier: String

        @FocusState private var focused: Bool
        @Namespace private var focusScope

        var body: some View {
            VStack {
                Button(action: {}) {
                    Copy.text(title)
                        .font(.largeTitle)
                        .foregroundStyle(.primary)
                }
                .focused($focused)
                .prefersDefaultFocus(in: focusScope)
                .accessibilityIdentifier(identifier)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focusScope(focusScope)
            .onAppear {
                // Wait until the pushed or revealed screen has joined the focus hierarchy.
                DispatchQueue.main.async {
                    focused = true
                }
            }
        }
    }
#endif
