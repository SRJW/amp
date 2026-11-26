import SwiftUI
import UIKit

/// A real system tab bar owns the selection lens and its touch/drag physics.
/// The fourth slot remains an action menu rather than changing the app's route.
@available(iOS 26.0, *)
struct NativeAppNavigationBar: UIViewControllerRepresentable {
    let width: CGFloat
    let selectedIndex: Int
    let selectedTint: UIColor
    let idleTint: UIColor
    let showsSurface: Bool
    let dark: Bool
    let reduceMotion: Bool
    let onSelect: (LibrarySection) -> Void
    let onOpenTool: (Tool) -> Void

    func makeUIViewController(context: Context) -> NativeNavigationController {
        NativeNavigationController()
    }

    func updateUIViewController(_ controller: NativeNavigationController, context: Context) {
        controller.configure(self)
    }
}

@available(iOS 26.0, *)
final class NativeNavigationController: UITabBarController, UITabBarControllerDelegate {
    private var configuration: NativeAppNavigationBar?
    private let menuButton = UIButton(type: .custom)
    private var menuKey = ""
    private var surface: Bool?
    private var previousSelectedTint: UIColor?
    private var previousIdleTint: UIColor?

    override func loadView() {
        // This small host is already positioned against the shared bottom safe
        // area by AppFixedNavigation. Do not inset its tab contents a second time.
        view = NavigationHostView()
        view.backgroundColor = .clear
        view.isOpaque = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        mode = .tabBar
        tabBarMinimizeBehavior = .never
        view.clipsToBounds = false
        tabBar.clipsToBounds = false
        tabBar.accessibilityIdentifier = "ampNativeTabBar"
        let labels = [L("Library"), L("Equalizer"), L("Search"), L("Menu")]
        let ids = ["appSection.library", "appSection.equalizer", "appSection.search", "nativeMenuSlot"]
        viewControllers = (0..<4).map { index in
            let child = UIViewController()
            child.view.backgroundColor = .clear
            child.view.isUserInteractionEnabled = false
            child.view.accessibilityElementsHidden = true
            child.tabBarItem = UITabBarItem(title: nil, image: Self.images[index], selectedImage: Self.images[index])
            child.tabBarItem.accessibilityLabel = labels[index]
            child.tabBarItem.accessibilityIdentifier = ids[index]
            if index == 3 { child.tabBarItem.isAccessibilityElement = false }
            return child
        }
        // Transparent only in its artwork: the native tab item still draws the
        // menu glyph. UIButton owns the real UIMenu hit target and accessibility.
        menuButton.backgroundColor = .clear
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.accessibilityIdentifier = "appMenu"
        menuButton.accessibilityLabel = L("Menu")
        view.addSubview(menuButton)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let configuration else { return }
        tabBar.frame = view.bounds
        tabBar.itemPositioning = .centered
        tabBar.itemWidth = configuration.width * AppNavigationMetrics.selectionWidthFraction
        tabBar.itemSpacing = 0
        let hitSize = AppNavigationMetrics.buttonsHeight
        menuButton.frame = CGRect(x: configuration.width * PlayerLayoutMetrics.navigationCentresW[3] - hitSize / 2,
                                  y: (view.bounds.height - hitSize) / 2,
                                  width: hitSize, height: hitSize)
        view.bringSubviewToFront(menuButton)
    }

    func configure(_ configuration: NativeAppNavigationBar) {
        self.configuration = configuration
        loadViewIfNeeded()
        view.overrideUserInterfaceStyle = configuration.dark ? .dark : .light
        if selectedIndex != configuration.selectedIndex { selectedIndex = configuration.selectedIndex }
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
        view.setNeedsLayout()
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        guard let index = viewControllers?.firstIndex(of: viewController) else { return false }
        // A drag toward Menu must not select an empty page. Direct presses land
        // on menuButton, whose system menu is independent of tab selection.
        return index < 3
    }

    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        guard let index = viewControllers?.firstIndex(of: viewController), index < 3 else { return }
        configuration?.onSelect([.library, .equalizer, .search][index])
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

private final class NavigationHostView: UIView {
    override var safeAreaInsets: UIEdgeInsets { .zero }
}
