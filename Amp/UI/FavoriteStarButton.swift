import SwiftUI

/// Apple Music–exact favorite star glyph derived frame-by-frame from iOS 26 Now Playing:
/// - Add favorite: instant outline -> filled swap with a pure centered elastic bounce
///   (1.00 -> 1.22 -> 0.91 -> 1.00 over ~0.35 s, 0° rotation, zero particles) and subtle filled glow.
/// - Remove favorite: crisp instant swap back to outline at 1.00× scale with no bounce.
struct FavoriteStarIcon: View {
    let isFavorite: Bool
    let size: CGFloat
    let ink: Color
    let reduceMotion: Bool
    let addPulse: Int
    let removePulse: Int
    var outlineWeight: Font.Weight = .semibold

    private struct BounceValues {
        var scale: CGFloat = 1.0
    }

    var body: some View {
        Image(systemName: isFavorite ? "star.fill" : "star")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .font(.system(size: size, weight: isFavorite ? .bold : outlineWeight))
            .foregroundStyle(ink)
            .shadow(color: ink.opacity(isFavorite ? 0.28 : 0.0), radius: size * 0.26, x: 0, y: 0)
            .keyframeAnimator(initialValue: BounceValues(), trigger: addPulse) { view, v in
                view.scaleEffect(reduceMotion ? 1.0 : v.scale)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1.22, duration: 0.12)
                    CubicKeyframe(0.91, duration: 0.10)
                    SpringKeyframe(1.00, duration: 0.13, spring: .smooth(duration: 0.13))
                }
            }
            .allowsHitTesting(false)
    }
}

/// Reusable Apple Music favorite star button with instant optimistic UI state (0 ms response)
/// and synchronized tactile haptics.
struct AppleMusicFavoriteButton: View {
    let itemID: Int64
    let isFavorite: Bool
    let iconSize: CGFloat
    var hitSize: CGFloat = 44
    let ink: Color
    let reduceMotion: Bool
    var addLabel: String? = nil
    var removeLabel: String? = nil
    let action: () -> Void

    @State private var optimisticFavorite: Bool?
    @State private var addPulse = 0
    @State private var removePulse = 0

    private var displayedFavorite: Bool { optimisticFavorite ?? isFavorite }

    var body: some View {
        let active = displayedFavorite
        Button {
            let nextState = !active
            optimisticFavorite = nextState
            if nextState {
                addPulse += 1
            } else {
                removePulse += 1
            }
            action()
        } label: {
            Color.clear
                .frame(width: hitSize, height: hitSize)
                .overlay {
                    FavoriteStarIcon(
                        isFavorite: active,
                        size: iconSize,
                        ink: ink,
                        reduceMotion: reduceMotion,
                        addPulse: addPulse,
                        removePulse: removePulse
                    )
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(active ? (removeLabel ?? L("Remove from favorites")) : (addLabel ?? L("Add to favorites")))
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.65), trigger: addPulse)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.40), trigger: removePulse)
        .onChange(of: itemID) { _, _ in optimisticFavorite = nil }
        .onChange(of: isFavorite) { _, actual in
            if optimisticFavorite == actual { optimisticFavorite = nil }
        }
    }
}
