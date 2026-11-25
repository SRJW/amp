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
        let chroma = min(max((saturation - 0.12) / 0.16, 0), 1)
        let effSat = saturation * chroma
        if effSat < 0.02 {
            return Stops(
                top: Color(uiColor: UIColor(hue: hue, saturation: 0, brightness: 0.22, alpha: 1)),
                mid: Color(uiColor: UIColor(hue: hue, saturation: 0, brightness: 0.14, alpha: 1)),
                bottom: Color(uiColor: UIColor(hue: hue, saturation: 0, brightness: 0.09, alpha: 1))
            )
        }
        let midShift: CGFloat
        let bottomShift: CGFloat
        if hue < 0.08 || hue > 0.88 {
            midShift = -0.04 * chroma
            bottomShift = -0.08 * chroma
        } else if hue < 0.22 {
            midShift = -0.03 * chroma
            bottomShift = -0.06 * chroma
        } else {
            midShift = 0.025 * chroma
            bottomShift = 0.05 * chroma
        }
        let topSat = min(effSat * 0.88, 0.88)
        let midSat = min(effSat * 0.92, 0.92)
        let botSat = min(effSat * 0.88, 0.88)
        let topBright = min(max(brightness * 0.64, 0.24), 0.36)
        let midBright = min(max(brightness * 0.46, 0.17), 0.26)
        let botBright = min(max(brightness * 0.32, 0.12), 0.20)
        return Stops(
            top: Color(uiColor: UIColor(hue: wrapped(hue), saturation: topSat, brightness: topBright, alpha: 1)),
            mid: Color(uiColor: UIColor(hue: wrapped(hue + midShift), saturation: midSat, brightness: midBright, alpha: 1)),
            bottom: Color(uiColor: UIColor(hue: wrapped(hue + bottomShift), saturation: botSat, brightness: botBright, alpha: 1))
        )
    }

    struct ControlColors: Equatable {
        /// Fill for transport button circles and time pills.
        let buttonFill: Color
        /// Icon ink inside transport buttons and time pills.
        let buttonIcon: Color
        /// Fill for the bottom navigation capsule.
        let navCapsule: Color
        /// Ink for the four bottom navigation icons.
        let navIcon: Color
        /// Ink for the waveform bars and audio technical summary.
        let accentInk: Color
    }

    /// Unified control colors shared across transport buttons, waveform, bitrate,
    /// bottom navigation capsule, and navigation icons, faithfully reflecting the cover's
    /// actual hue and chroma (or pure black & white) across Light and Dark appearance.
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
                    buttonFill: Color(white: 0.94),
                    buttonIcon: Color(white: 0.14),
                    navCapsule: Color(white: 0.93).opacity(0.90),
                    navIcon: Color(white: 0.14),
                    accentInk: Color(white: 0.96)
                )
            }
            return ControlColors(
                buttonFill: Color(white: 0.16),
                buttonIcon: Color(white: 0.95),
                navCapsule: Color(white: 0.12).opacity(0.86),
                navIcon: Color(white: 0.92),
                accentInk: Color(white: 0.94)
            )
        }
        // Ramp chroma smoothly from 0 on grayscale/charcoal covers (s <= 0.12) to full on
        // colorful covers (s >= 0.28), never inventing colors or shifting away from the cover hue.
        let chroma = min(max((saturation - 0.12) / 0.16, 0), 1)
        let effSat = saturation * chroma
        let isFrosted = style == .frostedArtwork
        let accentSat = min(effSat * (isFrosted ? 0.18 : 0.24), isFrosted ? 0.16 : 0.22)
        let accentInk = Color(uiColor: UIColor(hue: hue, saturation: accentSat, brightness: isFrosted ? 0.97 : 0.96, alpha: 1))
        if isLight {
            let lightFillSat = min(effSat * (isFrosted ? 0.22 : 0.30), isFrosted ? 0.18 : 0.24)
            let darkInkSat = min(effSat * (isFrosted ? 0.58 : 0.72), isFrosted ? 0.52 : 0.65)
            let capAlpha: CGFloat = isFrosted ? 0.84 : 0.90
            let inkColor = Color(uiColor: UIColor(hue: hue, saturation: darkInkSat, brightness: 0.18, alpha: 1))
            return ControlColors(
                buttonFill: Color(uiColor: UIColor(hue: hue, saturation: lightFillSat, brightness: 0.94, alpha: 1)),
                buttonIcon: inkColor,
                navCapsule: Color(uiColor: UIColor(hue: hue, saturation: lightFillSat, brightness: 0.92, alpha: capAlpha)),
                navIcon: inkColor,
                accentInk: accentInk
            )
        }
        let buttonSat = min(effSat * (isFrosted ? 0.52 : 0.70), isFrosted ? 0.46 : 0.62)
        let buttonBright: CGFloat = isFrosted ? 0.17 : 0.19
        let iconSat = min(effSat * (isFrosted ? 0.16 : 0.22), isFrosted ? 0.14 : 0.20)
        let capSat = min(effSat * (isFrosted ? 0.48 : 0.66), isFrosted ? 0.44 : 0.60)
        let capBright: CGFloat = isFrosted ? 0.14 : 0.15
        let capAlpha: CGFloat = isFrosted ? 0.78 : 0.86
        return ControlColors(
            buttonFill: Color(uiColor: UIColor(hue: hue, saturation: buttonSat, brightness: buttonBright, alpha: 1)),
            buttonIcon: Color(uiColor: UIColor(hue: hue, saturation: iconSat, brightness: isFrosted ? 0.98 : 0.97, alpha: 1)),
            navCapsule: Color(uiColor: UIColor(hue: hue, saturation: capSat, brightness: capBright, alpha: capAlpha)),
            navIcon: Color(uiColor: UIColor(hue: hue, saturation: accentSat, brightness: isFrosted ? 0.96 : 0.94, alpha: 1)),
            accentInk: accentInk
        )
    }

    /// Artwork-tinted capsule color for the bottom player navigation bar: adapts to Light/Dark
    /// appearance while faithfully reflecting the cover's real color.
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
    var onStatusBarScheme: ((ColorScheme) -> Void)? = nil
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
        case .frostedArtwork:
            Color(uiColor: muted(color)).opacity(0.70)
                .background(Color(red: 0.08, green: 0.07, blue: 0.08))
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let isFrosted = appearance.gradientStyle == .frostedArtwork
            let effectiveFadeStart = appearance.fadeStart.clamped(0, 0.96)
            let fadeSpan = 1 - effectiveFadeStart
            let coverHeight = artworkHeightFraction.map { geometry.size.height * $0 }
                ?? PlayerArtworkComposition.artworkHeight(in: geometry.size)
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack(alignment: .top) {
                ZStack(alignment: .top) {
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
                        // STYLE 2 (image_2.png — Apple Music progressive variable-blur mirrored artwork):
                        // 1. Deep lower canvas: vertically mirrored cover (`scaleEffect(y: -1)`) placed across
                        //    the lower half so the bottom edge of the photo (e.g. white dress + green grass)
                        //    continues downward behind Play/Pause and the bottom bar with heavy gaussian blur.
                        let baseBlur = max(appearance.blur, 18)
                        let deepBlur = max(baseBlur * 2.4, 58)
                        let midBlur = max(baseBlur * 0.95, 22)
                        let frostedOpacity = 0.86 + appearance.details * 0.14

                        artwork()
                            .frame(width: width, height: height * 0.72)
                            .scaleEffect(x: 1.14, y: -1.16, anchor: .center)
                            .offset(y: height * 0.34)
                            .frame(width: width, height: height, alignment: .top)
                            .blur(radius: deepBlur, opaque: true)
                            .saturation(1.12)
                            .opacity(frostedOpacity)
                            .clipped()

                        // 2. Mid-transition variable blur bridge (y = 38% -> 76%): medium blur (`~22 pt`)
                        //    that bridges the sharp upper photo into the deep frosted lower field so there is
                        //    zero hard seam at the title/buttons level.
                        artwork()
                            .frame(width: width, height: coverHeight * 1.16)
                            .scaleEffect(x: 1.05, y: 1.08, anchor: .top)
                            .blur(radius: midBlur, opaque: false)
                            .frame(width: width, height: height, alignment: .top)
                            .mask {
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0.0),
                                        .init(color: .clear, location: max(effectiveFadeStart * 0.45, 0.28)),
                                        .init(color: .white.opacity(0.92), location: 0.54),
                                        .init(color: .white.opacity(0.75), location: 0.67),
                                        .init(color: .clear, location: 0.82)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }

                        // Subtle atmospheric readability scrim over the lower controls
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .clear, location: 0.44),
                                .init(color: .black.opacity(0.12), location: 0.65),
                                .init(color: .black.opacity(0.22), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else {
                        // STYLE 1 (image.png — Color-sampled matte backdrop with soft lower-cover halo):
                        // When `details == 0` (the default), project a soft, localized blurred halo of the
                        // cover's bottom edge just into the title/subtitle zone (`50% -> 69%`) while keeping
                        // the exact solid color-sampled matte field around the transport controls and bottom bar.
                        if appearance.details > 0 {
                            artwork()
                                .frame(width: width, height: height)
                                .clipped()
                                .blur(radius: appearance.blur)
                                .opacity(appearance.details * 0.45)
                        } else {
                            let seamBlur = max(appearance.blur * 0.85, 18)
                            artwork()
                                .frame(width: width, height: coverHeight)
                                .scaleEffect(x: 1.02, y: 1.14, anchor: .top)
                                .blur(radius: seamBlur)
                                .frame(width: width, height: height, alignment: .top)
                                .mask {
                                    LinearGradient(
                                        stops: [
                                            .init(color: .clear, location: 0.0),
                                            .init(color: .clear, location: max(effectiveFadeStart * 0.58, 0.38)),
                                            .init(color: .white.opacity(0.34), location: 0.53),
                                            .init(color: .clear, location: 0.595)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                }
                        }
                    }

                    LinearGradient(colors: [.clear, Color(argb: appearance.gradientColor)], startPoint: .top, endPoint: .bottom)
                        .opacity(appearance.gradient)
                    Color.black.opacity(1 - appearance.intensity)
                }.saturation(appearance.saturation)

                artwork()
                    .frame(width: width, height: coverHeight)
                    .clipped()
                    .mask {
                        if isFrosted {
                            LinearGradient(stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white, location: effectiveFadeStart * 0.90),
                                .init(color: .white.opacity(0.82), location: effectiveFadeStart + fadeSpan * 0.24),
                                .init(color: .white.opacity(0.42), location: effectiveFadeStart + fadeSpan * 0.58),
                                .init(color: .white.opacity(0.12), location: effectiveFadeStart + fadeSpan * 0.84),
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
                                            safeAreaTop: max(safeAreaTop, geometry.safeAreaInsets.top),
                                            onSchemeChange: onStatusBarScheme)
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
