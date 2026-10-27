import SwiftUI

/// Q5-02: the banner is the container exception. It is not counted as one of the two containers.
struct GlassBanner: View {
    var message: CopyKey
    var systemImage: String
    var identifier: String
    var literalMessage: String? = nil

    var body: some View {
        HStack(spacing: SpacingToken.s) {
            GlassIcon(systemName: systemImage, label: message)
            Text(verbatim: literalMessage ?? Copy.string(message))
                .font(.body)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, SpacingToken.l)
        .padding(.vertical, SpacingToken.s)
        .ownGlassSurface(in: Capsule())
        .focusable(false)
        .accessibilityLabel(Text(verbatim: literalMessage ?? Copy.string(message)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
