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
    let opacity: Double
    let accessibilityActive: Bool
    let dark: Bool
    let reduceMotion: Bool
    let onSelect: (LibrarySection) -> Void
    let onOpenTool: (Tool) -> Void

    func makeUIViewController(context: Context) -> NativeNavigationHost {
        NativeNavigationHost()
    }

    func updateUIViewController(_ controller: NativeNavigationHost, context: Context) {
        controller.configure(self)
    }
}

@available(iOS 26.0, *)
final class NativeNavigationView: UIView, UITabBarDelegate {
    private let tabBar = UITabBar()
    private var configuration: NativeAppNavigationBar?
    private let menuButton = UIButton(type: .custom)
    private var menuKey = ""
    private var surface: Bool?
    private var previousSelectedTint: UIColor?
    private var previousIdleTint: UIColor?
    private var previousWidth: CGFloat?

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
        if tabBar.frame != bounds { tabBar.frame = bounds }
        if tabBar.itemPositioning != .centered { tabBar.itemPositioning = .centered }
        let itemWidth = configuration.width * AppNavigationMetrics.selectionWidthFraction
        if tabBar.itemWidth != itemWidth { tabBar.itemWidth = itemWidth }
        if tabBar.itemSpacing != 0 { tabBar.itemSpacing = 0 }
        let hitSize = AppNavigationMetrics.buttonsHeight
        menuButton.frame = CGRect(x: configuration.width * PlayerLayoutMetrics.navigationCentresW[3] - hitSize / 2,
                                  y: (bounds.height - hitSize) / 2,
                                  width: hitSize, height: hitSize)
        bringSubviewToFront(menuButton)
        #if DEBUG
        tabBar.accessibilityValue = "host=\(bounds); safe=\(safeAreaInsets); barSafe=\(tabBar.safeAreaInsets); margins=\(layoutMargins); fit=\(tabBar.sizeThatFits(bounds.size))"
        #endif

    }

    func configure(_ configuration: NativeAppNavigationBar) {
        self.configuration = configuration
        accessibilityElementsHidden = !configuration.accessibilityActive
        isUserInteractionEnabled = configuration.accessibilityActive
        isHidden = configuration.opacity <= 0.001
        tabBar.accessibilityElementsHidden = !configuration.accessibilityActive
        tabBar.items?.forEach { $0.isAccessibilityElement = configuration.accessibilityActive && $0.tag < 3 }
        menuButton.isAccessibilityElement = configuration.accessibilityActive
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
        if previousWidth != configuration.width || surface != configuration.showsSurface
            || previousSelectedTint?.isEqual(configuration.selectedTint) != true
            || previousIdleTint?.isEqual(configuration.idleTint) != true {
            let changesSurface = surface != nil && surface != configuration.showsSurface
            previousWidth = configuration.width
            surface = configuration.showsSurface
            previousSelectedTint = configuration.selectedTint
            previousIdleTint = configuration.idleTint
            let appearance = UITabBarAppearance()
            appearance.stackedItemPositioning = .centered
            appearance.stackedItemWidth = configuration.width * AppNavigationMetrics.selectionWidthFraction
            appearance.stackedItemSpacing = 0
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

/// A hosting controller can publicly disable safe-area propagation for this
/// already positioned control without changing the app's main content insets.
@available(iOS 26.0, *)
final class NativeNavigationHost: UIHostingController<NativeNavigationSurface> {
    init() {
        super.init(rootView: NativeNavigationSurface(configuration: nil))
        safeAreaRegions = []
    }

    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.clipsToBounds = false
        viewRespectsSystemMinimumLayoutMargins = false
        view.directionalLayoutMargins = .zero
        view.insetsLayoutMarginsFromSafeArea = false
    }

    func configure(_ configuration: NativeAppNavigationBar) {
        loadViewIfNeeded()
        rootView = NativeNavigationSurface(configuration: configuration)
        view.alpha = configuration.opacity
        view.isHidden = configuration.opacity <= 0.001
        view.accessibilityElementsHidden = !configuration.accessibilityActive
        view.isUserInteractionEnabled = configuration.accessibilityActive
    }
}

@available(iOS 26.0, *)
struct NativeNavigationSurface: View {
    let configuration: NativeAppNavigationBar?
    var body: some View { NativeNavigationUIKitView(configuration: configuration).ignoresSafeArea() }
}

@available(iOS 26.0, *)
private struct NativeNavigationUIKitView: UIViewRepresentable {
    let configuration: NativeAppNavigationBar?
    func makeUIView(context: Context) -> NativeNavigationView { NativeNavigationView() }
    func updateUIView(_ view: NativeNavigationView, context: Context) {
        if let configuration { view.configure(configuration) }
    }
}
