import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text(LocalizedStringResource("welcome.title", bundle: .main))
                .font(.title)
                .accessibilityIdentifier("welcome.root")
            Button(action: {}) {
                Text(LocalizedStringResource("welcome.connect", bundle: .main))
            }
            .accessibilityIdentifier("welcome.connect")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
