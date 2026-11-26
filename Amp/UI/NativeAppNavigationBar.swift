import SwiftUI
import UIKit

/// A real system tab bar owns the selection lens and its touch/drag physics.
/// The fourth slot remains an action menu rather than changing the app's route.
@available(iOS 26.0, *)
struct NativeAppNavigationBar: UIViewRepresentable {
    let width: CGFloat
    let selectedIndex: Int
    let selectedTint: UIColor
    let idleTint: UIColor
    let showsSurface: Bool
    let dark: Bool
    let reduceMotion: Bool
    let onSelect: (LibrarySection) -> Void
    let onOpenTool: (Tool) -> Void

    func makeUIView(context: Context) -> NativeNavigationView {
        NativeNavigationView()
    }

    func updateUIView(_ view: NativeNavigationView, context: Context) {
        view.configure(self)
    }
}

@available(iOS 26.0, *)
final class NativeNavigationView: UIView, UITabBarDelegate {
    private let tabBar = PositionedNativeTabBar()
    private var configuration: NativeAppNavigationBar?
    private let menuButton = UIButton(type: .custom)
    private var menuKey = ""
    private var surface: Bool?
    private var previousSelectedTint: UIColor?
    private var previousIdleTint: UIColor?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        insetsLayoutMarginsFromSafeArea = false
        tabBar.insetsLayoutMarginsFromSafeArea = false
        tabBar.directionalLayoutMargins = .zero
        tabBar.delegate = self
        clipsToBounds = false
        tabBar.clipsToBounds = false
        tabBar.accessibilityIdentifier = "ampNativeTabBar"
        let labels = [L("Library"), L("Equalizer"), L("Search"), L("Menu")]
        let ids = ["appSection.library", "appSection.equalizer", "appSection.search", "nativeMenuSlot"]
        tabBar.items = (0..<4).map { index in
            let item = UITabBarItem(title: nil, image: Self.images[index], selectedImage: Self.images[index])
            item.tag = index
            item.accessibilityLabel = labels[index]
            item.accessibilityIdentifier = ids[index]
            if index == 3 { item.isAccessibilityElement = false }
            return item
        }
        addSubview(tabBar)
        // Transparent only in its artwork: the native tab item still draws the
        // menu glyph. UIButton owns the real UIMenu hit target and accessibility.
        menuButton.backgroundColor = .clear
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.preferredMenuElementOrder = .fixed
        menuButton.accessibilityIdentifier = "appMenu"
        menuButton.accessibilityLabel = L("Menu")
        addSubview(menuButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let configuration else { return }
        tabBar.frame = bounds
        tabBar.itemPositioning = .centered
        tabBar.itemWidth = configuration.width * AppNavigationMetrics.selectionWidthFraction
        tabBar.itemSpacing = 0
        let hitSize = AppNavigationMetrics.buttonsHeight
        menuButton.frame = CGRect(x: configuration.width * PlayerLayoutMetrics.navigationCentresW[3] - hitSize / 2,
                                  y: (bounds.height - hitSize) / 2,
                                  width: hitSize, height: hitSize)
        bringSubviewToFront(menuButton)
    }

    func configure(_ configuration: NativeAppNavigationBar) {
        self.configuration = configuration
        overrideUserInterfaceStyle = configuration.dark ? .dark : .light
        let selectedItem = tabBar.items?[configuration.selectedIndex]
        if tabBar.selectedItem !== selectedItem { tabBar.selectedItem = selectedItem }
        menuButton.isSelected = configuration.selectedIndex == 3
        menuButton.accessibilityLabel = L("Menu")
        let key = Tool.available.map { $0.rawValue + ":" + L($0.label) }.joined(separator: "|")
        if key != menuKey {
            menuKey = key
            menuButton.menu = UIMenu(title: L("Menu"), children: Tool.available.map { tool in
                UIAction(title: L(tool.label), image: UIImage(systemName: tool.icon),
                         identifier: UIAction.Identifier("appMenu.\(tool.rawValue)")) { [weak self] _ in
                    self?.configuration?.onOpenTool(tool)
                }
            })
        }
        if surface != configuration.showsSurface
            || previousSelectedTint?.isEqual(configuration.selectedTint) != true
            || previousIdleTint?.isEqual(configuration.idleTint) != true {
            let changesSurface = surface != nil && surface != configuration.showsSurface
            surface = configuration.showsSurface
            previousSelectedTint = configuration.selectedTint
            previousIdleTint = configuration.idleTint
            let appearance = UITabBarAppearance()
            if configuration.showsSurface { appearance.configureWithDefaultBackground() }
            else {
                appearance.configureWithTransparentBackground()
                appearance.selectionIndicatorTintColor = .clear
                appearance.selectionIndicatorImage = Self.clearIndicator
            }
            for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance,
                           appearance.compactInlineLayoutAppearance] {
                layout.normal.iconColor = configuration.idleTint
                layout.selected.iconColor = configuration.selectedTint
            }
            let apply = {
                self.tabBar.standardAppearance = appearance
                self.tabBar.scrollEdgeAppearance = appearance
                self.tabBar.tintColor = configuration.selectedTint
                self.tabBar.unselectedItemTintColor = configuration.idleTint
            }
            if changesSurface {
                // The same native controls stay in place while the surface changes.
                UIView.transition(with: tabBar, duration: configuration.reduceMotion ? 0.12 : 0.25,
                                  options: [.transitionCrossDissolve, .allowUserInteraction, .beginFromCurrentState],
                                  animations: apply)
            } else { apply() }
        }
        setNeedsLayout()
    }

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        guard item.tag < 3 else {
            if let configuration { tabBar.selectedItem = tabBar.items?[configuration.selectedIndex] }
            return
        }
        configuration?.onSelect([.library, .equalizer, .search][item.tag])
    }

    private static let clearIndicator = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }

    private static let images: [UIImage] = [
        glyph(PlayerLibraryGlyph(), width: 32),
        glyph(PlayerEqualizerGlyph(), width: 35),
        glyph(PlayerSearchGlyph(), width: 32),
        glyph(PlayerQueueGlyph(), width: 32),
    ]

    private static func glyph<Content: View>(_ content: Content, width: CGFloat) -> UIImage {
        let scale = PlayerLayoutMetrics.navigationIconScale
        let renderer = ImageRenderer(content: content.foregroundStyle(.white).scaleEffect(scale)
            .frame(width: width * scale, height: 32 * scale))
        renderer.scale = UIScreen.main.scale
        return (renderer.uiImage ?? UIImage()).withRenderingMode(.alwaysTemplate)
    }
}

/// AppFixedNavigation already accounts for the window's bottom safe area.
/// Do not let a nested native bar subtract that inset a second time.
@available(iOS 26.0, *)
private final class PositionedNativeTabBar: UITabBar {
    override var safeAreaInsets: UIEdgeInsets { .zero }
}
