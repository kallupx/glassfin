import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("Glassfin")
                .font(.title)
                .accessibilityIdentifier("welcome.root")
            Button("Connect") {}
                .accessibilityIdentifier("welcome.connect")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
