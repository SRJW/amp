import SwiftUI

/// Apple Music–style favorite star glyph with 120 Hz GPU-only keyframe choreography:
/// anticipation dip -> 72° symmetric star spin-pop -> soft glow + 5 valley rays + 5 tip micro-dots.
struct FavoriteStarIcon: View {
    let isFavorite: Bool
    let size: CGFloat
    let ink: Color
    let reduceMotion: Bool
    let addPulse: Int
    let removePulse: Int
    var outlineWeight: Font.Weight = .semibold

    private struct AddAnimValues {
        var scale: CGFloat = 1.0
        var rotation: Double = 0.0
        var glowScale: CGFloat = 0.55
        var glowOpacity: Double = 0.0
        var raysScale: CGFloat = 0.42
        var raysOpacity: Double = 0.0
        var dotsScale: CGFloat = 0.48
        var dotsOpacity: Double = 0.0
    }

    private struct RemoveAnimValues {
        var scale: CGFloat = 1.0
        var rotation: Double = 0.0
    }

    var body: some View {
        ZStack {
            if !reduceMotion {
                burstGlow
                valleyRays
                tipDots
            }
            starGlyph
        }
        .allowsHitTesting(false)
    }

    private var burstGlow: some View {
        Circle()
            .fill(ink)
            .frame(width: size * 1.35, height: size * 1.35)
            .keyframeAnimator(initialValue: AddAnimValues(), trigger: addPulse) { view, v in
                view
                    .scaleEffect(v.glowScale)
                    .opacity(v.glowOpacity)
            } keyframes: { _ in
                KeyframeTrack(\.glowScale) {
                    LinearKeyframe(0.55, duration: 0.03)
                    CubicKeyframe(1.52, duration: 0.36)
                    LinearKeyframe(0.55, duration: 0.01)
                }
                KeyframeTrack(\.glowOpacity) {
                    LinearKeyframe(0.0, duration: 0.02)
                    LinearKeyframe(0.32, duration: 0.06)
                    CubicKeyframe(0.0, duration: 0.31)
                }
            }
    }

    /// Five crisp rays radiating from the valleys between the 5 points of the star.
    private var valleyRays: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                let angle: Double = Double(index) * (.pi * 2.0 / 5.0) - (.pi / 2.0) + (.pi / 5.0)
                Capsule()
                    .fill(ink)
                    .frame(width: max(1.8, size * 0.085), height: max(4.5, size * 0.24))
                    .offset(y: -size * 0.84)
                    .rotationEffect(.radians(angle))
            }
        }
        .keyframeAnimator(initialValue: AddAnimValues(), trigger: addPulse) { view, v in
            view
                .scaleEffect(v.raysScale)
                .opacity(v.raysOpacity)
        } keyframes: { _ in
            KeyframeTrack(\.raysScale) {
                LinearKeyframe(0.45, duration: 0.05)
                CubicKeyframe(1.46, duration: 0.34)
                LinearKeyframe(0.45, duration: 0.01)
            }
            KeyframeTrack(\.raysOpacity) {
                LinearKeyframe(0.0, duration: 0.04)
                LinearKeyframe(0.95, duration: 0.05)
                CubicKeyframe(0.0, duration: 0.30)
            }
        }
    }

    /// Five micro sparkle dots shooting outward off the 5 tips of the star.
    private var tipDots: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                let angle: Double = Double(index) * (.pi * 2.0 / 5.0) - (.pi / 2.0)
                Circle()
                    .fill(ink)
                    .frame(width: max(2.2, size * 0.11), height: max(2.2, size * 0.11))
                    .offset(y: -size * 0.92)
                    .rotationEffect(.radians(angle))
            }
        }
        .keyframeAnimator(initialValue: AddAnimValues(), trigger: addPulse) { view, v in
            view
                .scaleEffect(v.dotsScale)
                .opacity(v.dotsOpacity)
        } keyframes: { _ in
            KeyframeTrack(\.dotsScale) {
                LinearKeyframe(0.50, duration: 0.07)
                CubicKeyframe(1.58, duration: 0.36)
                LinearKeyframe(0.50, duration: 0.01)
            }
            KeyframeTrack(\.dotsOpacity) {
                LinearKeyframe(0.0, duration: 0.06)
                LinearKeyframe(0.85, duration: 0.06)
                CubicKeyframe(0.0, duration: 0.31)
            }
        }
    }

    /// Symmetric 72° clockwise spin-pop (360° / 5 = 72° maps every star tip onto the next seamlessly).
    private var starGlyph: some View {
        Image(systemName: isFavorite ? "star.fill" : "star")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .font(.system(size: size, weight: isFavorite ? .bold : outlineWeight))
            .foregroundStyle(ink)
            .keyframeAnimator(initialValue: AddAnimValues(), trigger: addPulse) { view, v in
                view
                    .scaleEffect(reduceMotion ? 1.0 : v.scale)
                    .rotationEffect(.degrees(reduceMotion ? 0.0 : v.rotation))
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(0.72, duration: 0.06)
                    SpringKeyframe(1.32, duration: 0.16, spring: .bouncy(duration: 0.22, extraBounce: 0.16))
                    SpringKeyframe(1.0, duration: 0.20, spring: .smooth(duration: 0.20))
                }
                KeyframeTrack(\.rotation) {
                    CubicKeyframe(-16.0, duration: 0.06)
                    SpringKeyframe(78.0, duration: 0.18, spring: .bouncy(duration: 0.22, extraBounce: 0.12))
                    SpringKeyframe(72.0, duration: 0.18, spring: .smooth(duration: 0.18))
                }
            }
            .keyframeAnimator(initialValue: RemoveAnimValues(), trigger: removePulse) { view, v in
                view
                    .scaleEffect(reduceMotion ? 1.0 : v.scale)
                    .rotationEffect(.degrees(reduceMotion ? 0.0 : v.rotation))
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(0.78, duration: 0.07)
                    SpringKeyframe(1.0, duration: 0.18, spring: .smooth(duration: 0.18))
                }
                KeyframeTrack(\.rotation) {
                    CubicKeyframe(-10.0, duration: 0.07)
                    SpringKeyframe(0.0, duration: 0.18, spring: .smooth(duration: 0.18))
                }
            }
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
        .sensoryFeedback(.success, trigger: addPulse)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.55), trigger: removePulse)
        .onChange(of: itemID) { _, _ in optimisticFavorite = nil }
        .onChange(of: isFavorite) { _, actual in
            if optimisticFavorite == actual { optimisticFavorite = nil }
        }
    }
}
