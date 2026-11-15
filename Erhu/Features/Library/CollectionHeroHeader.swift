import SwiftUI

/// Collection artwork and metadata; albums place their text below the image.
/// The artwork fills a rectangular canvas; it is never inset in a square or circle.
struct CollectionHeroHeader<Cover: View>: View {
    let title: String
    let subtitle: String?
    let facts: String
    var separatesMetadata = false
    let canPlay: Bool
    let onPlay: () -> Void
    let onShuffle: () -> Void
    @ViewBuilder let cover: () -> Cover
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            CollectionHeroLayout(separatesMetadata: separatesMetadata) {
                cover()
                    .mask(alignment: .bottom) {
                        if separatesMetadata {
                            LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.82),
                                                   .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                        } else { Color.white }
                    }
                    .accessibilityHidden(true)
                metadata
            }
            .clipped()
            HStack(spacing: Spacing.md) {
                Button(action: onPlay) {
                    Label("Play", systemImage: "play.fill")
                        .frame(maxWidth: .infinity).foregroundStyle(palette.onFilledButton)
                }
                .modifier(PaletteFilledButton())
                .tint(palette.filledButton)
                Button(action: onShuffle) {
                    Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .font(.headline)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .disabled(!canPlay)
            .padding(.horizontal, Spacing.heroGutter)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xl)
        }
        .frame(maxWidth: .infinity)
    }

    private var metadata: some View {
        VStack(spacing: Spacing.sm) {
            Text(separatesMetadata ? CollectionDisplayTitle.normalized(title) : title)
                .font(.largeTitle.weight(.bold)).lineLimit(separatesMetadata ? 2 : 3)
                .accessibilityIdentifier("collectionHeroTitle")
            if let subtitle { Text(subtitle).font(.title3.weight(.semibold)) }
            Text(facts).font(.subheadline).foregroundStyle(palette.onSurfaceVariant)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(palette.onSurface)
        .shadow(color: separatesMetadata ? .clear : .black.opacity(0.45), radius: 2, y: 1)
        .padding(.horizontal, Spacing.heroGutter)
        .padding(.bottom, Spacing.lg)
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { geometry in
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: palette.background.opacity(0.18), location: 0.3),
                    .init(color: palette.background.opacity(0.75), location: 0.75),
                    .init(color: palette.background, location: 1),
                ], startPoint: .top, endPoint: .bottom)
                .frame(height: geometry.size.height + 48)
                .offset(y: -48)
            }
        }
    }
}

/// Measure the metadata too, so large text and long titles can grow the header without clipping.
struct CollectionHeroLayout: Layout {
    var separatesMetadata = false
    static func artworkHeight(width: CGFloat) -> CGFloat { width.clamped(280, 560) }
    static func height(width: CGFloat, metadataHeight: CGFloat) -> CGFloat {
        max((width * 1.08).clamped(320, 560), metadataHeight + 160)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(proposal.width ?? 390, 1)
        let metadata = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let height = separatesMetadata ? Self.artworkHeight(width: width) + metadata.height : Self.height(width: width, metadataHeight: metadata.height)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: separatesMetadata ? Self.artworkHeight(width: bounds.width) : bounds.height))
        subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.maxY), anchor: .bottomLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}

enum CollectionDisplayTitle {
    /// Display cleanup only: preserve distinct edition names and leave file tags untouched.
    static func normalized(_ title: String) -> String {
        title.replacingOccurrences(of: #"(?i)(\([^()]+\)|\[[^\[\]]+\])(?:\s*\1)+"#,
                                   with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct CollectionPageBackground: View {
    @Environment(\.palette) private var palette
    var body: some View { palette.background.ignoresSafeArea() }
}

/// Preserve crisp artwork behind the navigation controls rather than the system's top haze.
struct CollectionTopEdgeEffect: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .top)
        } else {
            content
        }
    }
}
