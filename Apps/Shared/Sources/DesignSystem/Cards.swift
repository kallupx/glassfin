import SwiftUI

struct PosterFace: View {
    var image: Image? = nil
    var placeholderImage: Image? = nil
    var content: PosterContent
    var style: CardStyle
    var isFocused: Bool
    var titleHeight = CardMetrics.titleHeight

    private var size: CGSize {
        CardMetrics.size(for: style)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingToken.xs) {
            ZStack(alignment: .bottom) {
                AsyncPoster(
                    blurHash: content.blurHash,
                    image: image,
                    placeholderImage: placeholderImage,
                    failed: false,
                    size: size
                )
                .overlay(alignment: .topLeading) {
                    if content.isWatched {
                        GlassIcon(systemName: "checkmark.circle.fill", label: .badgeWatched)
                            .padding(SpacingToken.xs)
                            .background(ContentPaint.subtitleBacking, in: Capsule())
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let count = content.unplayedCount, count > 0 {
                        Text(verbatim: Copy.format(.badgeUnplayedCount, integer: count))
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, SpacingToken.xs)
                            .padding(.vertical, SpacingToken.xxs)
                            .background(ContentPaint.subtitleBacking, in: Capsule())
                    }
                }
                if content.progress.showsBar, let fraction = content.progress.fraction {
                    ProgressTrack(fraction: fraction)
                        .padding(SpacingToken.xs)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(ContentShape.concentric)
            title
                .frame(width: size.width, height: titleHeight, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var title: some View {
        let visible = style == .landscape || isFocused
        VStack(alignment: .leading, spacing: SpacingToken.xxs) {
            Text(verbatim: content.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .opacity(visible ? 1 : 0)
            if style == .landscape, let minutes = content.progress.remainingMinutes, content.remainingKey != nil {
                Text(verbatim: Copy.format(.remainingMinutes, integer: minutes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

struct ProgressTrack: View {
    var fraction: Double

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(ContentPaint.progressTrack)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(ContentPaint.progressFill)
                        .frame(width: proxy.size.width * min(1, max(0, fraction)))
                }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

struct AsyncPoster: View {
    var blurHash: String?
    var image: Image?
    var placeholderImage: Image? = nil
    var failed: Bool
    var size: CGSize

    @DesignAccessibility private var accessibility

    var body: some View {
        ZStack {
            placeholder
            if let image, !failed {
                image
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .clipShape(ContentShape.concentric)
        .animation(fade, value: image != nil && !failed)
        .accessibilityHidden(true)
    }

    private var fade: Animation? {
        let duration = MotionToken.imageFade(reduceMotion: accessibility.reduceMotion)
        if duration == 0 {
            return nil
        }
        return .easeInOut(duration: duration)
    }

    @ViewBuilder
    private var placeholder: some View {
        if let placeholderImage {
            placeholderImage.resizable().scaledToFill()
        } else if let blurHash, let cgImage = BlurHash.image(from: blurHash, width: 32, height: 32) {
            Image(decorative: cgImage, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            ContentPaint.progressTrack
        }
    }
}

struct PosterCard: View {
    var content: PosterContent
    var style: CardStyle
    var identifier: String
    var isFocused: Bool
    var onSelect: () -> Void
    var onTogglePlayed: () -> Void
    var onToggleFavorite: () -> Void

    var body: some View {
        Button(action: onSelect) {
            PosterFace(content: content, style: style, isFocused: isFocused)
        }
        .posterButtonStyle()
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(content.title)
        .contextMenu {
            Button(action: onSelect) {
                Copy.text(.actionPlay)
            }
            .accessibilityIdentifier("design.context.play")
            Button(action: onTogglePlayed) {
                Copy.text(content.isWatched ? .actionMarkUnplayed : .actionMarkPlayed)
            }
            .accessibilityIdentifier("design.context.played")
            Button(action: onToggleFavorite) {
                Copy.text(.actionAddFavorite)
            }
            .accessibilityIdentifier("design.context.favorite")
        }
    }
}

struct SkeletonRow: View {
    var style: CardStyle
    var count: Int
    var phase: Double
    var identifier = "design.skeleton.row"

    @DesignAccessibility private var accessibility

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingToken.s) {
            RoundedRectangle(cornerRadius: SpacingToken.xs, style: .continuous)
                .fill(Color.primary.opacity(0.18))
                .frame(width: 220, height: 28)
            HStack(spacing: CardMetrics.spacing) {
                ForEach(0..<count, id: \.self) { index in
                    skeleton(index: index)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
        .accessibilityHidden(true)
    }

    private func skeleton(index: Int) -> some View {
        let size = CardMetrics.size(for: style)
        return VStack(alignment: .leading, spacing: SpacingToken.xs) {
            RoundedRectangle(cornerRadius: SpacingToken.s, style: .continuous)
                .fill(Color.primary.opacity(0.16))
                .frame(width: size.width, height: size.height)
                .overlay {
                    if !accessibility.reduceMotion {
                        shimmer(index: index)
                    }
                }
                .clipShape(ContentShape.concentric)
            RoundedRectangle(cornerRadius: SpacingToken.xxs, style: .continuous)
                .fill(Color.primary.opacity(0.12))
                .frame(width: size.width * 0.7, height: CardMetrics.titleHeight * 0.45)
                .frame(height: CardMetrics.titleHeight, alignment: .top)
        }
    }

    private func shimmer(index: Int) -> some View {
        let travel = CGFloat(phase.truncatingRemainder(dividingBy: 1))
        return LinearGradient(
            colors: [Color.clear, Color.primary.opacity(0.18), Color.clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .offset(x: (travel - 0.5) * CardMetrics.size(for: style).width)
        .allowsHitTesting(false)
    }
}
