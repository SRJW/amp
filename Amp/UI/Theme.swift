import SwiftUI

/// Spacing scale (Android's Spacing: 4/8/12/16/24/32).
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    /// Default horizontal gutter between screen edge and content.
    static let gutter: CGFloat = lg
    /// Wider gutter for hero layouts (Now Playing).
    static let heroGutter: CGFloat = xl
}

enum Radius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
}

enum ArtworkSize {
    static let compact: CGFloat = 40
    static let list: CGFloat = 48
    static let miniPlayer: CGFloat = 64
    static let gridMin: CGFloat = 140
    static let shelf: CGFloat = 144
    static let heroMax: CGFloat = 480
}

/// The app's colours, from the Android built-in themes (monochrome, near-black or near-white).
struct AppPalette: Equatable {
    let primary: Color
    let onPrimary: Color
    let background: Color
    let surface: Color
    let surfaceVariant: Color
    let onSurface: Color
    let onSurfaceVariant: Color
    let outline: Color
    var buttonFill: Color? = nil
    var onButtonFill: Color? = nil

    var filledButton: Color { buttonFill ?? primary }
    var onFilledButton: Color { onButtonFill ?? onPrimary }

    static let dark = AppPalette(
        primary: Color(argb: 0xFFF8F9FA), onPrimary: Color(argb: 0xFF101216), background: Color(argb: 0xFF101216),
        surface: Color(argb: 0xFF1E222A), surfaceVariant: Color(argb: 0xFF2D3748), onSurface: Color(argb: 0xFFF8F9FA),
        onSurfaceVariant: Color(argb: 0xFFA0AEC0), outline: Color(argb: 0xFF4A5568)
    )
    static let light = AppPalette(
        primary: Color(argb: 0xFF121316), onPrimary: Color(argb: 0xFFFFFFFF), background: Color(argb: 0xFFF4F5F8),
        surface: Color(argb: 0xFFFFFFFF), surfaceVariant: Color(argb: 0xFFE2E8F0), onSurface: Color(argb: 0xFF121316),
        onSurfaceVariant: Color(argb: 0xFF4A5568), outline: Color(argb: 0xFFCBD5E0)
    )
}

extension AppPalette {
    /// Share the player card's appearance-aware artwork tones and filled controls.
    static func artwork(_ sampled: LyricsPalette, scheme: ColorScheme = .dark) -> AppPalette {
        let sampled = sampled.forScheme(scheme)
        let colors = LyricsColors(sampled)
        return AppPalette(primary: colors.accent, onPrimary: colors.surface,
                          background: colors.gradient.last ?? colors.surface,
                          surface: colors.surface, surfaceVariant: colors.surface,
                          onSurface: colors.content, onSurfaceVariant: colors.secondary, outline: colors.rim,
                          buttonFill: Color(argb: sampled.buttonFill), onButtonFill: Color(argb: sampled.onButtonFill))
    }

}

/// The theme the listener picked (Settings › Appearance).
enum ThemeChoice: String, CaseIterable, Codable, Identifiable {
    case system, light, dark
    /// Artwork colours follow the device's light/dark appearance.
    case artwork
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System default"
        case .light: "Light"
        case .dark: "Dark"
        case .artwork: "Colors from artwork"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system, .artwork: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = AppPalette.dark
}

private struct PlaybackPaletteKey: EnvironmentKey { static let defaultValue = AppPalette.dark }

extension EnvironmentValues {
    var palette: AppPalette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
    /// The song's theme remains available to playback sheets opened from a local page theme.
    var playbackPalette: AppPalette {
        get { self[PlaybackPaletteKey.self] }
        set { self[PlaybackPaletteKey.self] = newValue }
    }
}

/// Supplies the palette that matches the effective colour scheme, or the artwork's.
struct ThemedRoot<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(AppSettings.self) private var settings
    @Environment(PlayerController.self) private var player
    @ViewBuilder let content: Content
    @State private var artworkPalette = ArtworkPaletteState()
    @State private var artworkRevision = 0

    var body: some View {
        let followsArtwork = settings.customTheme == nil && settings.theme == .artwork
        let source = ArtworkPaletteSource.track(followsArtwork ? player.state.currentSong?.url : nil)
        let artworkURL = source.url
        let palette = settings.customTheme?.palette
            ?? (followsArtwork ? .artwork(artworkPalette.palette(for: source), scheme: scheme) : (scheme == .dark ? .dark : .light))
        content
            .buttonStyle(.plain)
            .fontDesign(settings.typeface.design)
            .fontWeight(settings.boldText ? .bold : nil)
            .environment(\.legibilityWeight, settings.boldText ? .bold : nil)
            .environment(\.palette, palette)
            .environment(\.playbackPalette, palette)
            .environment(\.locale, settings.language.locale)
            .environment(\.layoutDirection, settings.language.layoutDirection)
            .tint(palette.primary).toggleStyle(PaletteToggleStyle())
            .onReceive(NotificationCenter.default.publisher(for: ArtworkLoader.didChange)) { note in
                if note.object as? String == artworkURL?.path { artworkRevision += 1 }
            }
            .task(id: "\(source.isImage)|\(artworkURL?.path ?? "")|\(artworkRevision)") {
                guard let artworkURL else { return }
                let revision = ArtworkLoader.shared.revision(for: artworkURL.path)
                let sampled = await LyricsPaletteCache.shared.palette(for: source)
                guard !Task.isCancelled else { return }
                artworkPalette.set(sampled, for: source, revision: revision)
            }
    }
}

extension View {
    /// An album/artist theme belongs only to that page's subtree, never to its parent or chrome.
    func collectionArtworkTheme(_ source: ArtworkPaletteSource, alwaysFollowArtwork: Bool = false) -> some View {
        modifier(CollectionArtworkTheme(source: source, alwaysFollowArtwork: alwaysFollowArtwork))
    }

    /// A floating Liquid Glass surface with continuous rounded corners on iOS 26+,
    /// specular material on older iOS, and a cohesive palette surface when glass is off.
    func glassSurface(cornerRadius: CGFloat, enabled: Bool = true, interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(LiquidGlassSurface(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                                    enabled: enabled, interactive: interactive, tint: tint))
    }

    /// A native capsule-shaped Liquid Glass control surface.
    func glassCapsule(enabled: Bool = true, interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(LiquidGlassSurface(shape: Capsule(), enabled: enabled, interactive: interactive, tint: tint))
    }

    /// A native circular Liquid Glass control surface.
    func glassCircle(enabled: Bool = true, interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(LiquidGlassSurface(shape: Circle(), enabled: enabled, interactive: interactive, tint: tint))
    }

    /// A small press-down scale, like the Android cards' pressScale.
    func pressable() -> some View { buttonStyle(PressScaleStyle()) }
}

/// Groups adjacent floating Liquid Glass controls in one native optical pass on iOS 26+.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = Spacing.sm
    var enabled = true
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if #available(iOS 26.0, *), enabled, !reduceTransparency {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

private struct LiquidGlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let enabled: Bool
    let interactive: Bool
    let tint: Color?
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        if !enabled || reduceTransparency {
            content
                .background {
                    shape.fill(palette.surface)
                        .overlay {
                            if let tint {
                                shape.fill(tint.opacity(colorScheme == .dark ? 0.24 : 0.16))
                            }
                        }
                        .allowsHitTesting(false)
                }
                .overlay {
                    shape.strokeBorder(palette.outline.opacity(colorScheme == .dark ? 0.34 : 0.24), lineWidth: 0.75)
                        .allowsHitTesting(false)
                }
        } else if #available(iOS 26.0, *) {
            content.glassEffect(resolvedGlass, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background {
                    if let tint {
                        shape.fill(tint.opacity(0.18)).allowsHitTesting(false)
                    }
                }
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.26 : 0.56),
                                Color.white.opacity(colorScheme == .dark ? 0.06 : 0.14),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.65
                    )
                    .allowsHitTesting(false)
                }
        }
    }

    @available(iOS 26.0, *)
    private var resolvedGlass: Glass {
        var glass: Glass = .regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// Uses native iOS 26+ floating Liquid Glass navigation bars with soft scroll-under refraction
/// when glass is enabled, falling back to the themed solid bar on older iOS or when glass is off.
struct AdaptiveNavigationBarGlass: ViewModifier {
    var forceVisibleFallback = false
    @Environment(\.palette) private var palette
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *), settings.glassEnabled, !reduceTransparency {
            content
                .toolbarBackground(.automatic, for: .navigationBar)
                .scrollEdgeEffectStyle(.soft, for: .top)
        } else if forceVisibleFallback {
            content
                .toolbarBackground(palette.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        } else {
            content
                .toolbarBackground(palette.background, for: .navigationBar)
        }
    }
}

struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// "1 song", "12 songs".
func countLabel(_ count: Int, _ noun: String) -> String { "\(count) \(noun)\(count == 1 ? "" : "s")" }

/// m:ss, or h:mm:ss for an hour or more.
func formatDuration(_ ms: Int64) -> String {
    let total = max(ms, 0) / 1000
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds) : String(format: "%d:%02d", minutes, seconds)
}

private struct ArtworkSectionKey: EnvironmentKey { static let defaultValue: LibrarySection? = nil }
extension EnvironmentValues {
    var artworkSection: LibrarySection? {
        get { self[ArtworkSectionKey.self] }
        set { self[ArtworkSectionKey.self] = newValue }
    }
}

struct CollectionArtworkTheme: ViewModifier {
    let source: ArtworkPaletteSource
    var alwaysFollowArtwork = false
    @Environment(AppSettings.self) private var settings
    @Environment(\.colorScheme) private var scheme
    @Environment(\.palette) private var inheritedPalette
    @State private var artworkPalette = ArtworkPaletteState()
    @State private var artworkRevision = 0

    func body(content: Content) -> some View {
        let followsArtwork = alwaysFollowArtwork || (settings.customTheme == nil && settings.theme == .artwork)
        let palette = followsArtwork ? AppPalette.artwork(artworkPalette.palette(for: source), scheme: scheme) : inheritedPalette
        content.environment(\.palette, palette).tint(palette.primary).toggleStyle(PaletteToggleStyle())
            .onReceive(NotificationCenter.default.publisher(for: ArtworkLoader.didChange)) { note in
                if note.object as? String == source.url?.path { artworkRevision += 1 }
            }
            .task(id: "\(followsArtwork)|\(source.isImage)|\(source.url?.path ?? "")|\(artworkRevision)") {
                guard followsArtwork, let url = source.url else { return }
                let revision = ArtworkLoader.shared.revision(for: url.path)
                let sampled = await LyricsPaletteCache.shared.palette(for: source)
                guard !Task.isCancelled else { return }
                artworkPalette.set(sampled, for: source, revision: revision)
            }
    }
}
