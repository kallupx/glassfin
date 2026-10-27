import SwiftUI

/// Q5-02: the banner is the container exception. It is not counted as one of the two containers.
struct GlassBanner: View {
    var messageOverride: String? = nil
    var message: CopyKey
    var systemImage: String
    var identifier: String

    var body: some View {
        HStack(spacing: SpacingToken.s) {
            GlassIcon(systemName: systemImage, label: message)
            Group {
                if let messageOverride { Text(verbatim: messageOverride) } else { Copy.text(message) }
            }
            .font(.body)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, SpacingToken.l)
        .padding(.vertical, SpacingToken.s)
        .ownGlassSurface(in: Capsule())
        .focusable(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(messageOverride ?? Copy.string(message))
        .accessibilityIdentifier(identifier)
    }
}
