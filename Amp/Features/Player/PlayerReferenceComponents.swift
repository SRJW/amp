import SwiftUI
import UIKit
import AVFoundation

enum PlayerBackdropPalette {
    struct Stops {
        let top: Color
        let mid: Color
        let bottom: Color
    }

    private static func wrapped(_ value: CGFloat) -> CGFloat {
        let mod = value.truncatingRemainder(dividingBy: 1)
        return mod < 0 ? mod + 1 : mod
    }

    static func deepStops(for color: Color) -> Stops {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return Stops(
                top: Color(red: 0.28, green: 0.12, blue: 0.16),
                mid: Color(red: 0.18, green: 0.08, blue: 0.18),
                bottom: Color(red: 0.10, green: 0.06, blue: 0.16)
            )
        }
        if saturation < 0.08 {
            let neutralSat = saturation * 0.4
            return Stops(
                top: Color(uiColor: UIColor(hue: hue, saturation: neutralSat, brightness: 0.24, alpha: 1)),
                mid: Color(uiColor: UIColor(hue: hue, saturation: neutralSat, brightness: 0.16, alpha: 1)),
                bottom: Color(uiColor: UIColor(hue: hue, saturation: neutralSat, brightness: 0.10, alpha: 1))
            )
        }
        let midShift: CGFloat
        let bottomShift: CGFloat
        if hue < 0.08 || hue > 0.88 {
            midShift = -0.075
            bottomShift = -0.175
        } else if hue < 0.22 {
            midShift = -0.055
            bottomShift = -0.115
        } else {
            midShift = 0.04
            bottomShift = 0.085
        }
        let topSat = min(max(saturation * 0.88, 0.55), 0.92)
        let midSat = min(max(saturation * 0.92, 0.62), 0.95)
        let botSat = min(max(saturation * 0.88, 0.58), 0.92)
        let topBright = min(max(brightness * 0.64, 0.26), 0.38)
        let midBright = min(max(brightness * 0.46, 0.19), 0.27)
        let botBright = min(max(brightness * 0.32, 0.14), 0.21)
        return Stops(
            top: Color(uiColor: UIColor(hue: wrapped(hue), saturation: topSat, brightness: topBright, alpha: 1)),
            mid: Color(uiColor: UIColor(hue: wrapped(hue + midShift), saturation: midSat, brightness: midBright, alpha: 1)),
            bottom: Color(uiColor: UIColor(hue: wrapped(hue + bottomShift), saturation: botSat, brightness: botBright, alpha: 1))
        )
    }

    struct ControlColors: Equatable {
        /// Deep artwork-tinted fill for transport button circles and time pills.
        let buttonFill: Color
        /// Soft pastel artwork-tinted ink for icons inside transport buttons and time pills.
        let buttonIcon: Color
        /// Deep artwork-tinted fill for the bottom navigation capsule.
        let navCapsule: Color
        /// Soft pastel artwork-tinted ink for the four bottom navigation icons.
        let navIcon: Color
        /// Soft pastel artwork-tinted ink for the waveform bars and audio technical summary.
        let accentInk: Color
    }

    /// Unified control colors shared across transport buttons, waveform, bitrate,
    /// bottom navigation capsule, and navigation icons, supporting both artwork-tinted
    /// and pure black & white modes across Light and Dark appearance.
    static func controlColors(
        for dominant: Color,
        style: PlayerGradientStyle,
        scheme: ColorScheme = .dark,
        colorStyle: PlayerControlColorStyle = .tinted
    ) -> ControlColors {
        let isLight = scheme == .light
        if colorStyle == .monochrome {
            if isLight {
                return ControlColors(
                    buttonFill: .white,
                    buttonIcon: Color(red: 0.06, green: 0.06, blue: 0.07),
                    navCapsule: Color.white.opacity(0.90),
                    navIcon: Color(red: 0.06, green: 0.06, blue: 0.07),
                    accentInk: .white
                )
            }
            return ControlColors(
                buttonFill: Color(red: 0.06, green: 0.06, blue: 0.07),
                buttonIcon: .white,
                navCapsule: Color(red: 0.06, green: 0.06, blue: 0.07).opacity(0.86),
                navIcon: .white,
                accentInk: .white
            )
        }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(dominant).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            if isLight {
                return ControlColors(
                    buttonFill: Color(red: 0.92, green: 0.91, blue: 0.96),
                    buttonIcon: Color(red: 0.14, green: 0.12, blue: 0.24),
                    navCapsule: Color(red: 0.93, green: 0.92, blue: 0.96).opacity(0.88),
                    navIcon: Color(red: 0.14, green: 0.12, blue: 0.24),
                    accentInk: Color(red: 0.90, green: 0.91, blue: 0.98)
                )
            }
            return ControlColors(
                buttonFill: Color(red: 0.11, green: 0.10, blue: 0.21),
                buttonIcon: Color(red: 0.86, green: 0.88, blue: 0.99),
                navCapsule: Color(red: 0.09, green: 0.06, blue: 0.15).opacity(0.84),
                navIcon: Color(red: 0.78, green: 0.80, blue: 0.94),
                accentInk: Color(red: 0.80, green: 0.82, blue: 0.95)
            )
        }
        if saturation < 0.08 {
            let bgSat = saturation * 0.30
            let fgSat = saturation * 0.15
            if isLight {
                return ControlColors(
                    buttonFill: Color(uiColor: UIColor(hue: hue, saturation: fgSat, brightness: 0.93, alpha: 1)),
                    buttonIcon: Color(uiColor: UIColor(hue: hue, saturation: bgSat, brightness: 0.16, alpha: 1)),
                    navCapsule: Color(uiColor: UIColor(hue: hue, saturation: fgSat, brightness: 0.94, alpha: 0.88)),
                    navIcon: Color(uiColor: UIColor(hue: hue, saturation: bgSat, brightness: 0.16, alpha: 1)),
                    accentInk: Color(uiColor: UIColor(hue: hue, saturation: fgSat, brightness: 0.94, alpha: 1))
                )
            }
            return ControlColors(
                buttonFill: Color(uiColor: UIColor(hue: hue, saturation: bgSat, brightness: 0.16, alpha: 1)),
                buttonIcon: Color(uiColor: UIColor(hue: hue, saturation: fgSat, brightness: 0.96, alpha: 1)),
                navCapsule: Color(uiColor: UIColor(hue: hue, saturation: bgSat, brightness: 0.12, alpha: 0.84)),
                navIcon: Color(uiColor: UIColor(hue: hue, saturation: fgSat, brightness: 0.91, alpha: 1)),
                accentInk: Color(uiColor: UIColor(hue: hue, saturation: fgSat, brightness: 0.92, alpha: 1))
            )
        }
        let shift: CGFloat
        if style == .deepChromatic {
            if hue < 0.08 || hue > 0.88 { shift = -0.175 }
            else if hue < 0.22 { shift = -0.115 }
            else { shift = 0.085 }
        } else {
            shift = 0
        }
        let controlHue = wrapped(hue + shift)
        let isFrosted = style == .frostedArtwork
        let accentSat = isFrosted ? min(max(saturation * 0.14, 0.08), 0.16) : min(max(saturation * 0.22, 0.16), 0.24)
        let accentInk = Color(uiColor: UIColor(hue: controlHue, saturation: accentSat, brightness: isFrosted ? 0.97 : 0.94, alpha: 1))
        if isLight {
            let lightFillSat = isFrosted ? min(max(saturation * 0.18, 0.10), 0.22) : min(max(saturation * 0.24, 0.14), 0.28)
            let darkInkSat = isFrosted ? min(max(saturation * 0.50, 0.28), 0.58) : min(max(saturation * 0.68, 0.42), 0.72)
            let capAlpha: CGFloat = isFrosted ? 0.84 : 0.90
            let inkColor = Color(uiColor: UIColor(hue: controlHue, saturation: darkInkSat, brightness: 0.20, alpha: 1))
            return ControlColors(
                buttonFill: Color(uiColor: UIColor(hue: controlHue, saturation: lightFillSat, brightness: 0.94, alpha: 1)),
                buttonIcon: inkColor,
                navCapsule: Color(uiColor: UIColor(hue: controlHue, saturation: lightFillSat, brightness: 0.92, alpha: capAlpha)),
                navIcon: inkColor,
                accentInk: accentInk
            )
        }
        let buttonSat = isFrosted ? min(max(saturation * 0.45, 0.22), 0.50) : min(max(saturation * 0.65, 0.42), 0.68)
        let buttonBright: CGFloat = style == .deepChromatic ? 0.21 : (isFrosted ? 0.16 : 0.19)
        let iconSat = isFrosted ? min(max(saturation * 0.14, 0.08), 0.16) : min(max(saturation * 0.20, 0.14), 0.22)
        let capSat = isFrosted ? min(max(saturation * 0.42, 0.20), 0.48) : min(max(saturation * 0.62, 0.35), 0.68)
        let capBright: CGFloat = style == .deepChromatic ? 0.14 : (isFrosted ? 0.14 : 0.16)
        let capAlpha: CGFloat = isFrosted ? 0.76 : 0.86
        return ControlColors(
            buttonFill: Color(uiColor: UIColor(hue: controlHue, saturation: buttonSat, brightness: buttonBright, alpha: 1)),
            buttonIcon: Color(uiColor: UIColor(hue: controlHue, saturation: iconSat, brightness: isFrosted ? 0.99 : 0.98, alpha: 1)),
            navCapsule: Color(uiColor: UIColor(hue: controlHue, saturation: capSat, brightness: capBright, alpha: capAlpha)),
            navIcon: Color(uiColor: UIColor(hue: controlHue, saturation: accentSat, brightness: isFrosted ? 0.96 : 0.93, alpha: 1)),
            accentInk: accentInk
        )
    }

    /// Artwork-tinted capsule color for the bottom player navigation bar: adapts to Light/Dark
    /// appearance while visibly shifting hue with every cover.
    static func navCapsuleColor(for dominant: Color, style: PlayerGradientStyle, scheme: ColorScheme = .dark) -> Color {
        controlColors(for: dominant, style: style, scheme: scheme).navCapsule
    }
}

struct PlayerFullBleedBackground<Artwork: View>: View, Animatable {
    let dominant: Color
    var secondaryDominant: Color? = nil
    var blend = 0.0
    var appearance = PlayerBackgroundSettings()
    var statusProfile: PlayerArtworkStatusProfile? = nil
    var secondaryStatusProfile: PlayerArtworkStatusProfile? = nil
    var safeAreaTop: CGFloat = 0
    var showsStatusProtection = true
    var artworkHeightFraction: CGFloat? = nil
    @ViewBuilder var artwork: () -> Artwork

    var animatableData: Double {
        get { blend }
        set { blend = newValue }
    }

    private func muted(_ color: Color) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return UIColor(red: 0.50, green: 0.31, blue: 0.29, alpha: 1)
        }
        let mutedHue = hue < 0.12 ? hue * 0.5 : hue
        return UIColor(hue: mutedHue, saturation: saturation * 0.55,
                       brightness: min(max(brightness, 0.50), 0.58), alpha: 1)
    }

    @ViewBuilder
    private func backdropLayer(for color: Color) -> some View {
        switch appearance.gradientStyle {
        case .classic:
            let base = Color(uiColor: muted(color))
            LinearGradient(colors: [base, base, base.opacity(0.18)],
                           startPoint: .top, endPoint: .bottom)
                .background(Color(red: 0.10, green: 0.045, blue: 0.035))
        case .deepChromatic:
            let stops = PlayerBackdropPalette.deepStops(for: color)
            LinearGradient(
                stops: [
                    .init(color: stops.top, location: 0.0),
                    .init(color: stops.top, location: 0.34),
                    .init(color: stops.mid, location: 0.60),
                    .init(color: stops.bottom, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .frostedArtwork:
            Color(uiColor: muted(color)).opacity(0.75)
                .background(Color(red: 0.08, green: 0.07, blue: 0.08))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let isDeep = appearance.gradientStyle == .deepChromatic
            let isFrosted = appearance.gradientStyle == .frostedArtwork
            let effectiveFadeStart: Double = {
                if isFrosted { return min(appearance.fadeStart, 0.56).clamped(0, 0.94) }
                if isDeep { return min(appearance.fadeStart, 0.58).clamped(0, 0.96) }
                return appearance.fadeStart.clamped(0, 0.96)
            }()
            let fadeSpan = 1 - effectiveFadeStart
            let coverHeight = artworkHeightFraction.map { geometry.size.height * $0 }
                ?? PlayerArtworkComposition.artworkHeight(in: geometry.size)
            ZStack(alignment: .top) {
                ZStack {
                    backdropLayer(for: dominant)
                    if let secondaryDominant {
                        let phase = min(max(blend, 0), 1)
                        // Introduce the next palette near the cover first, then let
                        // it flow into the controls. Both ends settle to one colour.
                        let spread = 0.22 * sin(.pi * phase)
                        backdropLayer(for: secondaryDominant)
                            .mask {
                                LinearGradient(colors: [
                                    .white.opacity(min(phase + spread, 1)),
                                    .white.opacity(max(phase - spread, 0))
                                ], startPoint: .top, endPoint: .bottom)
                            }
                    }
                    if isFrosted {
                        let frostedBlur = max(appearance.blur * 1.45, 18)
                        let frostedOpacity = 0.72 + appearance.details * 0.28
                        artwork()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .scaleEffect(1.18)
                            .blur(radius: frostedBlur, opaque: true)
                            .saturation(1.16)
                            .opacity(frostedOpacity)
                            .clipped()
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .black.opacity(0.14), location: 0.45),
                                .init(color: .black.opacity(0.28), location: 0.78),
                                .init(color: .black.opacity(0.36), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else if appearance.details > 0 {
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
                    .frame(width: geometry.size.width, height: coverHeight)
                    .clipped()
                    .mask {
                        if isFrosted {
                            LinearGradient(stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white, location: effectiveFadeStart),
                                .init(color: .white.opacity(0.76), location: effectiveFadeStart + fadeSpan * 0.32),
                                .init(color: .white.opacity(0.34), location: effectiveFadeStart + fadeSpan * 0.68),
                                .init(color: .clear, location: 1)
                            ], startPoint: .top, endPoint: .bottom)
                        } else if isDeep {
                            LinearGradient(stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white, location: effectiveFadeStart),
                                .init(color: .white.opacity(0.68), location: effectiveFadeStart + fadeSpan * 0.42),
                                .init(color: .white.opacity(0.22), location: effectiveFadeStart + fadeSpan * 0.76),
                                .init(color: .clear, location: 1)
                            ], startPoint: .top, endPoint: .bottom)
                        } else {
                            LinearGradient(stops: [.init(color: .white, location: 0),
                                                   .init(color: .white, location: effectiveFadeStart),
                                                   .init(color: .clear, location: 1)],
                                           startPoint: .top, endPoint: .bottom)
                        }
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
        VStack(spacing: 3.6) {
            HStack(spacing: 3.6) {
                RoundedRectangle(cornerRadius: 4.2, style: .continuous).frame(width: 13.5, height: 13.5)
                RoundedRectangle(cornerRadius: 4.2, style: .continuous).frame(width: 13.5, height: 13.5)
            }
            HStack(spacing: 3.6) {
                RoundedRectangle(cornerRadius: 4.2, style: .continuous).frame(width: 13.5, height: 13.5)
                RoundedRectangle(cornerRadius: 4.2, style: .continuous).frame(width: 13.5, height: 13.5)
            }
        }
        .frame(width: 32, height: 32)
    }
}

struct PlayerEqualizerGlyph: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 2.2) {
            RoundedRectangle(cornerRadius: 4.0, style: .continuous).frame(width: 10.2, height: 11.5)
            RoundedRectangle(cornerRadius: 4.0, style: .continuous).frame(width: 10.2, height: 29.5)
            RoundedRectangle(cornerRadius: 4.0, style: .continuous).frame(width: 10.2, height: 24.5)
        }
        .frame(width: 35, height: 32, alignment: .bottom)
    }
}

struct PlayerSearchGlyph: View {
    var body: some View {
        Rectangle()
            .frame(width: 32, height: 32)
            .mask {
                ZStack {
                    Circle()
                        .stroke(.white, lineWidth: 7.2)
                        .frame(width: 19, height: 19)
                        .position(x: 13.2, y: 13.2)
                    Path { path in
                        path.move(to: CGPoint(x: 20.0, y: 20.0))
                        path.addLine(to: CGPoint(x: 27.6, y: 27.6))
                    }
                    .stroke(.white, style: StrokeStyle(lineWidth: 7.2, lineCap: .round))
                }
                .frame(width: 32, height: 32)
            }
    }
}

struct PlayerQueueGlyph: View {
    var body: some View {
        VStack(spacing: 3.2) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 3.8, style: .continuous).frame(width: 29, height: 8.2)
            }
        }
        .frame(width: 32, height: 32)
    }
}
