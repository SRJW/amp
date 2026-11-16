import SwiftUI

enum AppNavigationMetrics {
    static let duration = 0.3
    static let stripHeight: CGFloat = MiniPlayerMetrics.height
    static let buttonsHeight: CGFloat = 48
    static let horizontalInset: CGFloat = Spacing.md
    static let bottomPadding: CGFloat = Spacing.xs
    static func centreY(height: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
        height - max(safeAreaBottom, 0) - bottomPadding - buttonsHeight / 2
    }
    static let reservedHeight: CGFloat = stripHeight + buttonsHeight + 28
    static let menuWidth: CGFloat = 320
    static let menuBottom: CGFloat = 64
    static let emptyTitle = "No song loaded"
    static let menuLabel = "Menu"
}

/// The same song strip and navigation controls are used by every app section and tool.
struct AppBottomBar: View {
    var showsButtons = true
    @Environment(PlayerController.self) private var player
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Group {
                if let song = player.state.currentSong {
                    MiniPlayer(song: song) { router.openPlayer() }
                } else {
                    Label(AppNavigationMetrics.emptyTitle, systemImage: "music.note")
                        .foregroundStyle(palette.onSurfaceVariant)
                        .frame(maxWidth: .infinity, minHeight: AppNavigationMetrics.stripHeight)
                }
            }
            .frame(height: AppNavigationMetrics.stripHeight)
            .background {
                Color.clear.glassSurface(cornerRadius: MiniPlayerMetrics.cornerRadius, enabled: settings.glassEnabled)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: MiniPlayerMetrics.cornerRadius, style: .continuous))
            GeometryReader { geometry in
                if showsButtons { AppNavigationButtons(width: geometry.size.width) }
            }
            .frame(height: AppNavigationMetrics.buttonsHeight)
            .background { Color.clear.chromeSurface(enabled: settings.glassEnabled).allowsHitTesting(false) }
            .clipShape(Capsule())
        }
        .padding(.horizontal, AppNavigationMetrics.horizontalInset).padding(.bottom, AppNavigationMetrics.bottomPadding)
    }
}

/// One persistent row, outside both fading screens. Only the surfaces behind it change.
struct AppFixedNavigation: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.appNavigationBottomInset) private var bottomInset

    var body: some View {
        GeometryReader { geometry in
            AppNavigationButtons(width: max(geometry.size.width - 2 * AppNavigationMetrics.horizontalInset, 0),
                                 inPlayer: router.showsNowPlaying && router.presentedTool == nil)
                .frame(width: geometry.size.width, height: AppNavigationMetrics.buttonsHeight)
                .position(x: geometry.size.width / 2,
                          y: AppNavigationMetrics.centreY(height: geometry.size.height, safeAreaBottom: bottomInset))
        }
        .ignoresSafeArea()
    }
}

/// Inside the full player only these four controls appear, at its existing positions.
struct AppNavigationButtons: View {
    let width: CGFloat
    var inPlayer = false
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            button("Library", section: .library, index: 0) { Image(systemName: "square.grid.2x2.fill") }
            button("Equalizer", section: .equalizer, index: 1) { PlayerEqualizerGlyph().scaleEffect(PlayerLayoutMetrics.navigationIconScale) }
            button("Search", section: .search, index: 2) { Image(systemName: "magnifyingglass") }
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: AppNavigationMetrics.duration)) { router.showsDrawer.toggle() }
            } label: {
                PlayerQueueGlyph().scaleEffect(PlayerLayoutMetrics.navigationIconScale)
                    .frame(width: 48, height: 48).contentShape(Rectangle())
            }
            .foregroundStyle(tint(selected: router.showsDrawer))
            .accessibilityLabel(AppNavigationMetrics.menuLabel)
            .accessibilityIdentifier("appMenu")
            .position(x: width * PlayerLayoutMetrics.navigationCentresW[3], y: 24)
        }
        .font(.system(size: 28 * PlayerLayoutMetrics.navigationIconScale, weight: .heavy))
        .buttonStyle(.plain)
        .frame(width: width, height: AppNavigationMetrics.buttonsHeight)
    }

    private func button<Icon: View>(_ title: String, section: LibrarySection, index: Int, @ViewBuilder icon: () -> Icon) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: AppNavigationMetrics.duration)) { router.activate(section) }
        } label: { icon().frame(width: 48, height: 48).contentShape(Rectangle()) }
            .foregroundStyle(tint(selected: router.presentedTool == nil && router.section == section))
            .accessibilityLabel(title)
            .accessibilityIdentifier("appSection.\(section.rawValue)")
            .accessibilityAddTraits(router.presentedTool == nil && router.section == section ? .isSelected : [])
            .position(x: width * PlayerLayoutMetrics.navigationCentresW[index], y: 24)
    }

    private func tint(selected: Bool) -> Color {
        inPlayer ? .white.opacity(selected ? 1 : 0.6) : (selected ? palette.primary : palette.onSurfaceVariant)
    }
}

struct AppMenu: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black.opacity(0.25).ignoresSafeArea().contentShape(Rectangle())
                .onTapGesture { router.showsDrawer = false }
                .accessibilityLabel("Close menu").accessibilityAddTraits(.isButton)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Button { router.activate(.library) } label: { Label("Library", systemImage: "books.vertical") }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule)
                    Spacer()
                    Button { router.showsDrawer = false } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("Close menu")
                }.padding(.horizontal, Spacing.md)
                ForEach(Tool.available) { tool in
                    Button { router.open(tool) } label: {
                        Label(tool.label, systemImage: tool.icon)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, Spacing.md).contentShape(Rectangle())
                    }.accessibilityIdentifier("appMenu.\(tool.rawValue)")
                }
            }
            .buttonStyle(.plain).foregroundStyle(palette.onSurface)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: AppNavigationMetrics.menuWidth)
            .glassSurface(cornerRadius: Radius.medium, enabled: settings.glassEnabled)
            .padding(.horizontal, Spacing.md).padding(.bottom, AppNavigationMetrics.menuBottom)
        }
    }
}
