import SwiftUI
import UIKit

enum AppNavigationMetrics {
    static let duration = 0.3
    static let stripHeight: CGFloat = MiniPlayerMetrics.height
    static let buttonsHeight: CGFloat = 48
    static let horizontalInset: CGFloat = Spacing.md
    static let capsuleHeight: CGFloat = 60
    static let stripSpacing: CGFloat = 12
    static let selectionInset: CGFloat = 3
    static let selectionWidthFraction: CGFloat = 0.238
    static let selectionDuration = 0.30
    static let bottomPadding: CGFloat = Spacing.xs
    static func centreY(height: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
        height - max(safeAreaBottom, 0) - bottomPadding - buttonsHeight / 2
    }
    static let reservedHeight: CGFloat = stripHeight + buttonsHeight + 36
    static let emptyTitle = "No song loaded"
    static let menuLabel = "Menu"
}

/// The same song strip and navigation controls are used by every app section and tool.
struct AppBottomBar: View {
    var showsButtons = true
    @Environment(\.appKeyboardVisible) private var keyboardVisible
    @Environment(PlayerController.self) private var player
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: AppNavigationMetrics.stripSpacing) {
            Group {
                if let song = player.state.currentSong {
                    MiniPlayer(song: song) { router.openPlayer() }
                } else {
                    Label(L(AppNavigationMetrics.emptyTitle), systemImage: "music.note")
                        .foregroundStyle(palette.onSurfaceVariant)
                        .frame(maxWidth: .infinity, minHeight: AppNavigationMetrics.stripHeight)
                }
            }
            .frame(height: AppNavigationMetrics.stripHeight)
            .modifier(FloatingControlGlass(enabled: settings.glassEnabled, cornerRadius: MiniPlayerMetrics.cornerRadius))
            if !keyboardVisible {
            GeometryReader { geometry in
                if showsButtons { AppNavigationButtons(width: geometry.size.width) }
            }
            .frame(height: AppNavigationMetrics.buttonsHeight)
            }
        }
        .padding(.horizontal, AppNavigationMetrics.horizontalInset).padding(.bottom, AppNavigationMetrics.bottomPadding)
    }
}

/// One persistent row, outside both fading screens. Only the surfaces behind it change.
struct AppFixedNavigation: View {
    @Environment(\.appKeyboardVisible) private var keyboardVisible
    @Environment(AppRouter.self) private var router
    @Environment(PlayerDragState.self) private var playerMotion
    @Environment(\.appNavigationBottomInset) private var bottomInset
    @Environment(\.playerReduceMotion) private var reduceMotion

    var body: some View {
        let playerProgress: CGFloat = (playerMotion.isPresented && router.presentedTool == nil) ? playerMotion.progress : 0
        Group {
            if !keyboardVisible {
                GeometryReader { geometry in
                    AppNavigationButtons(
                        width: max(geometry.size.width - 2 * AppNavigationMetrics.horizontalInset, 0),
                        inPlayer: router.showsNowPlaying && router.presentedTool == nil,
                        playerProgress: playerProgress
                    )
                    .frame(width: geometry.size.width, height: AppNavigationMetrics.buttonsHeight)
                    .position(x: geometry.size.width / 2,
                              y: AppNavigationMetrics.centreY(height: geometry.size.height, safeAreaBottom: bottomInset))
                }
                .ignoresSafeArea()
                .animation(reduceMotion ? nil : .easeInOut(duration: AppNavigationMetrics.duration), value: router.presentedTool == nil)
            }
        }
    }
}

/// Inside the full player only these four controls appear, at its existing positions.
struct AppNavigationButtons: View {
    let width: CGFloat
    var inPlayer = false
    var playerProgress: CGFloat? = nil
    @Environment(\.playerForegroundInk) private var playerInk
    @Environment(\.playerArtworkPresent) private var playerArtworkPresent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(PlayerController.self) private var player
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppSettings.self) private var settings
    @State private var contact: NavigationGlassContact?
    @State private var artworkDominant: UInt32 = LyricsPalette.fallback.artworkDominant
    @State private var artworkRevision = 0

    private var selectedIndex: Int {
        if router.presentedTool != nil { return 3 }
        switch router.section { case .library: return 0; case .equalizer: return 1; case .search: return 2 }
    }
    private func activate(_ index: Int) {
        router.activate([LibrarySection.library, .equalizer, .search][index])
    }

    private var usesArtworkControlPalette: Bool {
        guard playerArtworkPresent, settings.customTheme == nil else { return false }
        let bg = settings.playerBackground
        return bg.controlColorStyle == .monochrome || bg.navBarCapsule || bg.gradientStyle != .classic || settings.theme == .artwork
    }

    private var controlColors: PlayerBackdropPalette.ControlColors {
        PlayerBackdropPalette.controlColors(
            for: Color(argb: artworkDominant),
            style: settings.playerBackground.gradientStyle,
            scheme: colorScheme,
            colorStyle: settings.playerBackground.controlColorStyle
        )
    }

    private var playerCapsuleFill: Color {
        if !playerArtworkPresent {
            return colorScheme == .light ? Color.black.opacity(0.06) : Color.white.opacity(0.10)
        }
        return controlColors.navCapsule
    }

    private func playerTint(selected: Bool) -> Color {
        if usesArtworkControlPalette {
            return settings.playerBackground.navBarCapsule
                ? controlColors.navIcon
                : controlColors.accentInk.opacity(selected ? 1 : 0.68)
        }
        return settings.playerBackground.navBarCapsule
            ? playerInk.opacity(0.88)
            : playerInk.opacity(selected ? 1 : 0.6)
    }

    private func libraryTint(selected: Bool) -> Color {
        selected ? palette.primary : palette.onSurfaceVariant
    }

    var body: some View {
        let artworkURL = player.state.currentSong?.url
        let resolvedProgress = playerProgress ?? (inPlayer ? 1 : 0)
        let activeSectionIndex: Int = switch router.section {
        case .library: 0
        case .equalizer: 1
        case .search: 2
        }
        AppNavigationBarContent(
            width: width,
            playerProgress: resolvedProgress,
            selectedIndex: selectedIndex,
            activeSectionIndex: activeSectionIndex,
            hasPresentedTool: router.presentedTool != nil,
            showsPlayerCapsule: settings.playerBackground.navBarCapsule,
            glassEnabled: settings.glassEnabled,
            contact: contact,
            playerCapsuleFill: playerCapsuleFill,
            selectionFallbackFill: palette.onSurface.opacity(0.10),
            librarySelectedColor: libraryTint(selected: true),
            libraryIdleColor: libraryTint(selected: false),
            playerSelectedColor: playerTint(selected: true),
            playerIdleColor: playerTint(selected: false),
            onSelectSection: { section in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: AppNavigationMetrics.duration)) { router.activate(section) }
            },
            onOpenTool: { tool in router.open(tool) }
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: artworkDominant)
        .animation(reduceMotion ? nil : .spring(response: AppNavigationMetrics.selectionDuration, dampingFraction: 0.86), value: selectedIndex)
        .onReceive(NotificationCenter.default.publisher(for: ArtworkLoader.didChange)) { note in
            if note.object as? String == artworkURL?.path { artworkRevision += 1 }
        }
        .task(id: "\(settings.customTheme == nil)|\(artworkURL?.path ?? "")|\(artworkRevision)") {
            guard settings.customTheme == nil, let artworkURL else { return }
            let sampled = await LyricsPaletteCache.shared.palette(for: artworkURL)
            guard !Task.isCancelled else { return }
            artworkDominant = sampled.artworkDominant
        }
        .background {
            NavigationGlassTouchObserver(enabled: resolvedProgress < 0.5, changed: { sample in
                guard abs(sample.width - width) < 0.5 else { return }
                let height = AppNavigationMetrics.buttonsHeight
                guard sample.point.y >= -height / 2, sample.point.y <= height * 1.5 else {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { contact = nil }
                    return
                }
                if contact == nil {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.82)) { contact = sample }
                } else {
                    var instant = Transaction(animation: nil)
                    instant.disablesAnimations = true
                    withTransaction(instant) { contact = sample }
                }
            }, ended: { sample, cancelled in
                let destination = !cancelled && abs(sample.width - width) < 0.5
                    ? sample.draggedSection(height: AppNavigationMetrics.buttonsHeight) : nil
                withAnimation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.82)) {
                    contact = nil
                    if let destination { activate(destination) }
                }
            })
            .accessibilityHidden(true)
        }
        .onChange(of: resolvedProgress >= 0.5) { _, presented in if presented { contact = nil } }
        .onChange(of: width) { _, _ in contact = nil }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in contact = nil }

    }
}

/// Continuously interpolates the bottom navigation capsule, selection pill, and icon colors
/// in lockstep with Now Playing's presentation progress during both drags and animations.
private struct AppNavigationBarContent: View, Animatable {
    let width: CGFloat
    var playerProgress: CGFloat
    let selectedIndex: Int
    let activeSectionIndex: Int
    let hasPresentedTool: Bool
    let showsPlayerCapsule: Bool
    let glassEnabled: Bool
    let contact: NavigationGlassContact?
    let playerCapsuleFill: Color
    let selectionFallbackFill: Color
    let librarySelectedColor: Color
    let libraryIdleColor: Color
    let playerSelectedColor: Color
    let playerIdleColor: Color
    let onSelectSection: (LibrarySection) -> Void
    let onOpenTool: (Tool) -> Void
    @Environment(\.self) private var environment

    var animatableData: CGFloat {
        get { playerProgress }
        set { playerProgress = newValue }
    }

    var body: some View {
        let blend = PlayerCoverGeometry.chromeOpacity(playerProgress)
        ZStack {
            Capsule().fill(selectionFallbackFill)
                .frame(width: lensWidth, height: lensHeight)
                .position(x: usesFloatingLens ? width * PlayerLayoutMetrics.navigationCentresW[selectedIndex]
                          : contact?.lensX ?? width * PlayerLayoutMetrics.navigationCentresW[selectedIndex], y: 24)
                .opacity((1 - blend) * (contact == nil || !usesFloatingLens ? 1 : 0))
                .animation(environment.accessibilityReduceMotion ? nil : .easeOut(duration: 0.16), value: contact != nil)
                .allowsHitTesting(false)
            button(L("Library"), section: .library, index: 0, blend: blend) { PlayerLibraryGlyph().scaleEffect(PlayerLayoutMetrics.navigationIconScale) }
            button(L("Equalizer"), section: .equalizer, index: 1, blend: blend) { PlayerEqualizerGlyph().scaleEffect(PlayerLayoutMetrics.navigationIconScale) }
            button(L("Search"), section: .search, index: 2, blend: blend) { PlayerSearchGlyph().scaleEffect(PlayerLayoutMetrics.navigationIconScale) }
            Menu {
                Section(L(AppNavigationMetrics.menuLabel)) {
                    ForEach(Tool.available) { tool in
                        Button { onOpenTool(tool) } label: {
                            Label(L(tool.label), systemImage: tool.icon)
                        }
                        .accessibilityIdentifier("appMenu.\(tool.rawValue)")
                    }
                }
            } label: {
                navigationLabel(L("Menu")) { PlayerQueueGlyph().scaleEffect(PlayerLayoutMetrics.navigationIconScale) }
                    .foregroundStyle(blendedColor(
                        from: libraryColor(at: 3),
                        to: playerIdleColor,
                        amount: blend
                    ))
            }
            .menuStyle(.button)
            .menuOrder(.fixed)
            .accessibilityLabel(L(AppNavigationMetrics.menuLabel))
            .accessibilityIdentifier("appMenu")
            .position(x: width * PlayerLayoutMetrics.navigationCentresW[3], y: 24)
        }
        .font(.system(size: 28 * PlayerLayoutMetrics.navigationIconScale, weight: .heavy))
        .buttonStyle(FloatingControlPressStyle(enabled: playerProgress < 0.5))
        .frame(width: width, height: AppNavigationMetrics.buttonsHeight)
        .modifier(FloatingControlGlass(enabled: glassEnabled,
                                       verticalOutset: (AppNavigationMetrics.capsuleHeight - AppNavigationMetrics.buttonsHeight) / 2,
                                       surfaceOpacity: 1 - blend))
        .background {
            if showsPlayerCapsule {
                Capsule()
                    .fill(playerCapsuleFill)
                    .frame(width: width, height: 54)
                    .opacity(blend)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            raisedLens
                .frame(width: lensWidth * lensScaleX, height: lensHeight * lensScaleY)
                .position(x: contact?.lensX ?? width * PlayerLayoutMetrics.navigationCentresW[selectedIndex], y: 24)
                .opacity((1 - blend) * (contact == nil ? 0 : 1))
                .animation(environment.accessibilityReduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.82), value: contact != nil)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var lensWidth: CGFloat { width * AppNavigationMetrics.selectionWidthFraction - AppNavigationMetrics.selectionInset * 2 }
    private var lensHeight: CGFloat { AppNavigationMetrics.capsuleHeight - AppNavigationMetrics.selectionInset * 2 }
    private var lensScaleX: CGFloat {
        guard let contact, !environment.accessibilityReduceMotion else { return 1 }
        return 1.14 + contact.speed * 0.10
    }
    private var lensScaleY: CGFloat {
        guard let contact, !environment.accessibilityReduceMotion else { return 1 }
        return 1.22 - contact.speed * 0.06
    }
    private func libraryColor(at index: Int) -> Color {
        let focus = contact?.focus(at: index) ?? (selectedIndex == index ? 1 : 0)
        return blendedColor(from: libraryIdleColor, to: librarySelectedColor, amount: focus)
    }
    private var usesFloatingLens: Bool {
        if #available(iOS 26.0, *) { return glassEnabled && !environment.accessibilityReduceTransparency }
        return false
    }
    @ViewBuilder private var raisedLens: some View {
        if #available(iOS 26.0, *), usesFloatingLens {
            Capsule().fill(.clear).glassEffect(.clear.interactive(), in: .capsule)
        } else { Color.clear }
    }

    private func navigationLabel<Icon: View>(_ title: String, @ViewBuilder icon: () -> Icon) -> some View {
        ZStack {
            icon().position(x: 24, y: 24)
        }
        .frame(width: 48, height: 48).contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
    }

    private func button<Icon: View>(_ title: String, section: LibrarySection, index: Int, blend: Double, @ViewBuilder icon: () -> Icon) -> some View {
        let isPlayerSelected = !hasPresentedTool && activeSectionIndex == index
        return Button { onSelectSection(section) } label: { navigationLabel(title, icon: icon) }
            .foregroundStyle(blendedColor(
                from: libraryColor(at: index),
                to: isPlayerSelected ? playerSelectedColor : playerIdleColor,
                amount: blend
            ))
            .accessibilityLabel(title)
            .accessibilityIdentifier("appSection.\(section.rawValue)")
            .accessibilityAddTraits(isPlayerSelected ? .isSelected : [])
            .position(x: width * PlayerLayoutMetrics.navigationCentresW[index], y: 24)
    }

    private func blendedColor(from a: Color, to b: Color, amount: Double) -> Color {
        let t = amount.clamped(0, 1)
        if t <= 0 { return a }
        if t >= 1 { return b }
        let ca = a.resolve(in: environment)
        let cb = b.resolve(in: environment)
        return Color(
            .sRGB,
            red: Double(ca.red) + (Double(cb.red) - Double(ca.red)) * t,
            green: Double(ca.green) + (Double(cb.green) - Double(ca.green)) * t,
            blue: Double(ca.blue) + (Double(cb.blue) - Double(ca.blue)) * t,
            opacity: Double(ca.opacity) + (Double(cb.opacity) - Double(ca.opacity)) * t
        )
    }
}
