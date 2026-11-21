import SwiftUI
import UIKit
import AVFoundation

struct PlayerFullBleedBackground<Artwork: View>: View, Animatable {
    let dominant: Color
    var secondaryDominant: Color? = nil
    var blend = 0.0
    var appearance = PlayerBackgroundSettings()
    var statusProfile: PlayerArtworkStatusProfile? = nil
    var secondaryStatusProfile: PlayerArtworkStatusProfile? = nil
    var safeAreaTop: CGFloat = 0
    var showsStatusProtection = true
    @ViewBuilder var artwork: () -> Artwork

    var animatableData: Double {
        get { blend }
        set { blend = newValue }
    }

    private struct BackdropStops {
        let top: Color
        let mid: Color
        let bottom: Color
    }

    private func backdropStops(for color: Color) -> BackdropStops {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return BackdropStops(
                top: Color(red: 0.28, green: 0.12, blue: 0.16),
                mid: Color(red: 0.18, green: 0.08, blue: 0.18),
                bottom: Color(red: 0.10, green: 0.06, blue: 0.16)
            )
        }
        func wrapped(_ value: CGFloat) -> CGFloat {
            let mod = value.truncatingRemainder(dividingBy: 1)
            return mod < 0 ? mod + 1 : mod
        }
        if saturation < 0.08 {
            let neutralSat = saturation * 0.4
            return BackdropStops(
                top: Color(uiColor: UIColor(hue: hue, saturation: neutralSat, brightness: 0.24, alpha: 1)),
                mid: Color(uiColor: UIColor(hue: hue, saturation: neutralSat, brightness: 0.16, alpha: 1)),
                bottom: Color(uiColor: UIColor(hue: hue, saturation: neutralSat, brightness: 0.10, alpha: 1))
            )
        }
        let midShift: CGFloat
        let bottomShift: CGFloat
        if hue < 0.08 || hue > 0.88 {
            // Warm crimsons/reds drift smoothly toward plum and deep nocturnal indigo.
            midShift = -0.075
            bottomShift = -0.175
        } else if hue < 0.22 {
            // Warm oranges/golds deepen toward burnished burgundy instead of muddy olive.
            midShift = -0.055
            bottomShift = -0.115
        } else {
            // Greens, teals, blues, and violets drift gently into deeper adjacent cool tones.
            midShift = 0.04
            bottomShift = 0.085
        }
        let topSat = min(max(saturation * 0.88, 0.55), 0.92)
        let midSat = min(max(saturation * 0.92, 0.62), 0.95)
        let botSat = min(max(saturation * 0.88, 0.58), 0.92)
        let topBright = min(max(brightness * 0.64, 0.26), 0.38)
        let midBright = min(max(brightness * 0.46, 0.19), 0.27)
        let botBright = min(max(brightness * 0.32, 0.14), 0.21)
        return BackdropStops(
            top: Color(uiColor: UIColor(hue: wrapped(hue), saturation: topSat, brightness: topBright, alpha: 1)),
            mid: Color(uiColor: UIColor(hue: wrapped(hue + midShift), saturation: midSat, brightness: midBright, alpha: 1)),
            bottom: Color(uiColor: UIColor(hue: wrapped(hue + bottomShift), saturation: botSat, brightness: botBright, alpha: 1))
        )
    }

    private func chromaticGradient(for color: Color) -> LinearGradient {
        let stops = backdropStops(for: color)
        return LinearGradient(
            stops: [
                .init(color: stops.top, location: 0.0),
                .init(color: stops.top, location: 0.34),
                .init(color: stops.mid, location: 0.60),
                .init(color: stops.bottom, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let fadeStart = appearance.fadeStart.clamped(0, 0.96)
            let fadeSpan = 1 - fadeStart
            ZStack(alignment: .top) {
                ZStack {
                    chromaticGradient(for: dominant)
                    if let secondaryDominant {
                        let phase = min(max(blend, 0), 1)
                        // Introduce the next palette near the cover first, then let
                        // it flow into the controls. Both ends settle to one colour.
                        let spread = 0.22 * sin(.pi * phase)
                        chromaticGradient(for: secondaryDominant)
                            .mask {
                                LinearGradient(colors: [
                                    .white.opacity(min(phase + spread, 1)),
                                    .white.opacity(max(phase - spread, 0))
                                ], startPoint: .top, endPoint: .bottom)
                            }
                    }
                    if appearance.details > 0 {
                        artwork()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .blur(radius: appearance.blur)
                            .opacity(appearance.details * 0.45)
                    }
                    LinearGradient(colors: [.clear, Color(argb: appearance.gradientColor)], startPoint: .top, endPoint: .bottom)
                        .opacity(appearance.gradient)
                    Color.black.opacity(1 - appearance.intensity)
                }.saturation(appearance.saturation)
                artwork()
                    .frame(width: geometry.size.width, height: PlayerArtworkComposition.artworkHeight(in: geometry.size))
                    .clipped()
                    .mask {
                        LinearGradient(stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white, location: fadeStart),
                            .init(color: .white.opacity(0.68), location: fadeStart + fadeSpan * 0.42),
                            .init(color: .white.opacity(0.22), location: fadeStart + fadeSpan * 0.76),
                            .init(color: .clear, location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                    }
                if showsStatusProtection {
                PlayerAdaptiveStatusBar(current: statusProfile ?? PlayerArtworkStatusProfile(solid: UIColor(dominant)),
                                            next: secondaryStatusProfile, blend: blend, size: geometry.size,
                                            safeAreaTop: max(safeAreaTop, geometry.safeAreaInsets.top))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct PlayerLibraryGlyph: View {
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous).frame(width: 14, height: 14)
                RoundedRectangle(cornerRadius: 4.5, style: .continuous).frame(width: 14, height: 14)
            }
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous).frame(width: 14, height: 14)
                RoundedRectangle(cornerRadius: 4.5, style: .continuous).frame(width: 14, height: 14)
            }
        }
        .frame(width: 32, height: 32)
    }
}

struct PlayerEqualizerGlyph: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            Capsule().frame(width: 10, height: 11.5)
            Capsule().frame(width: 10, height: 31)
            Capsule().frame(width: 10, height: 25.5)
        }
        .frame(width: 35, height: 32, alignment: .bottom)
    }
}

struct PlayerSearchGlyph: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 7.5)
                .frame(width: 19, height: 19)
                .position(x: 13.25, y: 13.25)
            Path { path in
                path.move(to: CGPoint(x: 20.0, y: 20.0))
                path.addLine(to: CGPoint(x: 28.25, y: 28.25))
            }
            .stroke(style: StrokeStyle(lineWidth: 7.5, lineCap: .round))
        }
        .frame(width: 32, height: 32)
    }
}

struct PlayerQueueGlyph: View {
    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                Capsule().frame(width: 31, height: 8.5)
            }
        }
        .frame(width: 32, height: 32)
    }
}
