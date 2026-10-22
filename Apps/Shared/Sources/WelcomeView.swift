import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: SpacingToken.l) {
            Copy.text(.welcomeTitle)
                .font(.title)
                .accessibilityIdentifier("welcome.root")
            Button(action: {}) {
                Copy.text(.welcomeConnect)
            }
            .accessibilityIdentifier(CopyKey.welcomeConnect.rawValue)
            NavigationLink {
                DesignSystemFocusDemo()
            } label: {
                Copy.text(.welcomeDesignSystem)
            }
            .accessibilityIdentifier(CopyKey.welcomeDesignSystem.rawValue)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
