import SwiftUI
import UIKit

/// One appearance for tools and settings, regardless of which navigation link opened them.
struct ToolPageAppearance: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .scrollContentBackground(.hidden)
            .foregroundStyle(palette.onSurface)
            .tint(palette.primary)
            .background(palette.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .modifier(AdaptiveNavigationBarGlass(forceVisibleFallback: true))
    }
}

private struct ToolSectionAppearance: ViewModifier {
    @Environment(\.palette) private var palette
    func body(content: Content) -> some View { content.listRowBackground(palette.surface) }
}

extension View {
    func toolSectionAppearance() -> some View { modifier(ToolSectionAppearance()) }
}

extension AppPalette {
    /// Derives a cohesive sheet palette tinted subtly by the current artwork or artist color,
    /// keeping contrast crisp in both Light and Dark modes and staying neutral for grayscale covers.
    func tinted(for dominant: Color, scheme: ColorScheme) -> AppPalette {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(dominant).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }
        let chroma = min(max((saturation - 0.12) / 0.16, 0), 1)
        let effSat = saturation * chroma
        guard effSat >= 0.02 else { return self }

        if scheme == .light {
            let bg = Color(uiColor: UIColor(hue: hue, saturation: min(effSat * 0.10, 0.08), brightness: 0.96, alpha: 1))
            let card = Color(uiColor: UIColor(hue: hue, saturation: min(effSat * 0.05, 0.04), brightness: 0.995, alpha: 1))
            let variant = Color(uiColor: UIColor(hue: hue, saturation: min(effSat * 0.16, 0.14), brightness: 0.91, alpha: 1))
            let primary = Color(uiColor: UIColor(hue: hue, saturation: min(effSat * 0.78, 0.72), brightness: 0.36, alpha: 1))
            let onSurface = Color(uiColor: UIColor(hue: hue, saturation: min(effSat * 0.30, 0.24), brightness: 0.14, alpha: 1))
            let onSurfaceVar = Color(uiColor: UIColor(hue: hue, saturation: min(effSat * 0.22, 0.18), brightness: 0.42, alpha: 1))
            let outline = Color(uiColor: UIColor(hue: hue, saturation: min(effSat * 0.20, 0.16), brightness: 0.78, alpha: 1))
            return AppPalette(
                primary: primary,
                onPrimary: .white,
                background: bg,
                surface: card,
                surfaceVariant: variant,
                onSurface: onSurface,
                onSurfaceVariant: onSurfaceVar,
                outline: outline
            )
        } else {
            let bg = Color(uiColor: UIColor(hue: hue, saturation: min(effSat * 0.56, 0.48), brightness: 0.11, alpha: 1))
            let card = Color(uiColor: UIColor(hue: hue, saturation: min(effSat * 0.46, 0.40), brightness: 0.17, alpha: 1))
            let variant = Color(uiColor: UIColor(hue: hue, saturation: min(effSat * 0.40, 0.34), brightness: 0.23, alpha: 1))
            let primary = Color(uiColor: UIColor(hue: hue, saturation: min(effSat * 0.42, 0.36), brightness: 0.88, alpha: 1))
            let onPrimary = Color(uiColor: UIColor(hue: hue, saturation: min(effSat * 0.58, 0.50), brightness: 0.14, alpha: 1))
            let onSurface = Color(uiColor: UIColor(hue: hue, saturation: min(effSat * 0.14, 0.12), brightness: 0.96, alpha: 1))
            let onSurfaceVar = Color(uiColor: UIColor(hue: hue, saturation: min(effSat * 0.18, 0.16), brightness: 0.70, alpha: 1))
            let outline = Color(uiColor: UIColor(hue: hue, saturation: min(effSat * 0.28, 0.24), brightness: 0.34, alpha: 1))
            return AppPalette(
                primary: primary,
                onPrimary: onPrimary,
                background: bg,
                surface: card,
                surfaceVariant: variant,
                onSurface: onSurface,
                onSurfaceVariant: onSurfaceVar,
                outline: outline
            )
        }
    }
}
