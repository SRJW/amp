import SwiftUI

enum AppNavigationMetrics {
    static let duration = 0.3
    static let stripHeight: CGFloat = MiniPlayerMetrics.height
    static let buttonsHeight: CGFloat = 48
    static let horizontalInset: CGFloat = Spacing.md
    static let capsuleHeight: CGFloat = 60
    static let stripSpacing: CGFloat = 12
    static let selectionInset: CGFloat = 3
    static let selectionWidthFraction: CGFloat = 0.238
    static let labelSize: CGFloat = 9
    static let labelCentreY: CGFloat = 43
    static let selectionDuration = 0.30
    static let bottomPadding: CGFloat = Spacing.xs
    static func centreY(height: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
        height - max(safeAreaBottom, 0) - bottomPadding - buttonsHeight / 2
    }
    static let reservedHeight: CGFloat = stripHeight + buttonsHeight + 36
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
        VStack(spacing: AppNavigationMetrics.stripSpacing) {
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
            .background { Color.clear.frame(height: AppNavigationMetrics.capsuleHeight).chromeSurface(enabled: settings.glassEnabled).allowsHitTesting(false) }
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
    @Environment(AppSettings.self) private var settings
    @GestureState private var dragX: CGFloat?

    private var selectedIndex: Int {
        if router.showsDrawer || router.presentedTool != nil { return 3 }
        switch router.section { case .library: return 0; case .equalizer: return 1; case .search: return 2 }
    }
    private func nearestIndex(_ x: CGFloat) -> Int {
        PlayerLayoutMetrics.navigationCentresW.indices.min {
            abs(width * PlayerLayoutMetrics.navigationCentresW[$0] - x) < abs(width * PlayerLayoutMetrics.navigationCentresW[$1] - x)
        } ?? 0
    }
    private func activate(_ index: Int) {
        if index == 3 { router.showsDrawer = true }
        else { router.activate([LibrarySection.library, .equalizer, .search][index]) }
    }

    var body: some View {
        ZStack {
            if !inPlayer {
                selectionPill
                    .frame(width: width * AppNavigationMetrics.selectionWidthFraction - AppNavigationMetrics.selectionInset * 2,
                           height: AppNavigationMetrics.capsuleHeight - AppNavigationMetrics.selectionInset * 2)
                    .position(x: dragX.map { min(max($0, width * PlayerLayoutMetrics.navigationCentresW[0]), width * PlayerLayoutMetrics.navigationCentresW[3]) }
                              ?? width * PlayerLayoutMetrics.navigationCentresW[selectedIndex], y: 24)
                    .allowsHitTesting(false)
            }
            button("Library", section: .library, index: 0) { Image(systemName: "square.grid.2x2.fill") }
            button("Equalizer", section: .equalizer, index: 1) { PlayerEqualizerGlyph().scaleEffect(PlayerLayoutMetrics.navigationIconScale) }
            button("Search", section: .search, index: 2) { Image(systemName: "magnifyingglass") }
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: AppNavigationMetrics.duration)) { router.showsDrawer.toggle() }
            } label: {
                navigationLabel("Menu") { PlayerQueueGlyph().scaleEffect(PlayerLayoutMetrics.navigationIconScale) }
            }
            .foregroundStyle(tint(selected: inPlayer ? router.showsDrawer : selectedIndex == 3))
            .accessibilityLabel(AppNavigationMetrics.menuLabel)
            .accessibilityIdentifier("appMenu")
            .position(x: width * PlayerLayoutMetrics.navigationCentresW[3], y: 24)
        }
        .font(.system(size: 28 * PlayerLayoutMetrics.navigationIconScale, weight: .heavy))
        .buttonStyle(.plain)
        .frame(width: width, height: AppNavigationMetrics.buttonsHeight)
        .animation(reduceMotion ? nil : .spring(response: AppNavigationMetrics.selectionDuration, dampingFraction: 0.86), value: selectedIndex)
        .simultaneousGesture(DragGesture(minimumDistance: 8)
            .updating($dragX) { value, state, _ in
                guard !inPlayer, abs(value.translation.width) > abs(value.translation.height) else { return }
                state = value.location.x
            }
            .onEnded { value in
                guard !inPlayer, abs(value.translation.width) > abs(value.translation.height) else { return }
                withAnimation(reduceMotion ? nil : .smooth(duration: AppNavigationMetrics.selectionDuration)) { activate(nearestIndex(value.location.x)) }
            })
    }

    @ViewBuilder private var selectionPill: some View {
        if #available(iOS 26.0, *), settings.glassEnabled {
            Capsule().fill(palette.onSurface.opacity(0.05))
                .glassEffect(.regular.interactive(), in: .capsule)
        } else { Capsule().fill(palette.onSurface.opacity(0.10)) }
    }

    private func navigationLabel<Icon: View>(_ title: String, @ViewBuilder icon: () -> Icon) -> some View {
        ZStack {
            icon().position(x: 24, y: 24)
            if !inPlayer {
                Text(title).font(.system(size: AppNavigationMetrics.labelSize, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: width * AppNavigationMetrics.selectionWidthFraction)
                    .position(x: 24, y: AppNavigationMetrics.labelCentreY)
            }
        }
        .frame(width: 48, height: 48).contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
    }

    private func button<Icon: View>(_ title: String, section: LibrarySection, index: Int, @ViewBuilder icon: () -> Icon) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: AppNavigationMetrics.duration)) { router.activate(section) }
        } label: { navigationLabel(title, icon: icon) }
            .foregroundStyle(tint(selected: inPlayer ? router.presentedTool == nil && router.section == section : selectedIndex == index))
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
