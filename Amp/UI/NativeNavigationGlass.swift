import SwiftUI
import UIKit

/// UIKit owns the glass and touch physics. The existing SwiftUI row remains
/// the accessibility/action owner, so its 48 pt targets never change position.
@available(iOS 26.0, *)
struct NativeNavigationGlass: UIViewRepresentable, Animatable {
    let selectedIndex: Int
    let selectedTint: UIColor
    let idleTint: UIColor
    var opacity: Double
    let interactive: Bool
    let dark: Bool
    let onSelect: (Int) -> Void

    var animatableData: Double {
        get { opacity }
        set { opacity = newValue }
    }
    func makeUIView(context: Context) -> NativeNavigationGlassView { NativeNavigationGlassView() }
    func updateUIView(_ view: NativeNavigationGlassView, context: Context) { view.configure(self) }
}

@available(iOS 26.0, *)
final class NativeNavigationGlassView: UIView, UITabBarDelegate {
    private let bar = UITabBar()
    private var configuration: NativeNavigationGlass?
    private var calibratedSize = CGSize.zero
    private var calibrating = false
    private var imageScale = CGSize(width: 1, height: 1)
    private var appliedSelected: UIColor?
    private var appliedIdle: UIColor?
    private let identifiers = ["amp.native.library", "amp.native.equalizer", "amp.native.search", "amp.native.menu"]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false
        accessibilityElementsHidden = true
        bar.accessibilityElementsHidden = true
        bar.clipsToBounds = false
        bar.delegate = self
        bar.items = (0..<4).map { index in
            let item = UITabBarItem(title: nil, image: Self.image(index, inverseScale: imageScale, displayScale: traitCollection.displayScale), tag: index)
            item.accessibilityIdentifier = identifiers[index]
            return item
        }
        addSubview(bar)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        calibratedSize = .zero
        setNeedsLayout()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        calibratedSize = .zero
        setNeedsLayout()
    }

    func configure(_ configuration: NativeNavigationGlass) {
        self.configuration = configuration
        alpha = configuration.opacity
        isHidden = configuration.opacity <= 0.001
        isUserInteractionEnabled = configuration.interactive
        overrideUserInterfaceStyle = configuration.dark ? .dark : .light
        let selected = bar.items?[configuration.selectedIndex]
        if bar.selectedItem !== selected { bar.selectedItem = selected }
        if appliedSelected?.isEqual(configuration.selectedTint) != true || appliedIdle?.isEqual(configuration.idleTint) != true {
            appliedSelected = configuration.selectedTint
            appliedIdle = configuration.idleTint
            let appearance = UITabBarAppearance()
            appearance.configureWithDefaultBackground()
            for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
                layout.normal.iconColor = configuration.idleTint
                layout.selected.iconColor = configuration.selectedTint
            }
            bar.standardAppearance = appearance
            bar.scrollEdgeAppearance = appearance
            bar.tintColor = configuration.selectedTint
            bar.unselectedItemTintColor = configuration.idleTint
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !calibrating, bounds.width > 0, bounds.height > 0, window != nil else { return }
        guard calibratedSize != bounds.size else { return }
        calibrating = true
        defer { calibrating = false }
        let animationsEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsEnabled) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        bar.layer.sublayerTransform = CATransform3DIdentity
        bar.frame = bounds
        bar.layoutIfNeeded()
        let controls = itemControls()
        guard controls.count == 4 else { writeMetrics(controls: controls, surface: .zero); return }

        // Read public UIView geometry only; never replace or reposition UIKit's
        // private child views. Its common content surface excludes the system
        // floating margins that caused the earlier compact contour.
        let surface = nativeSurface(controls: controls)
        guard surface.width > 0, surface.height > 0 else { return }
        imageScale = CGSize(width: bounds.width / surface.width, height: bounds.height / surface.height)
        let transform = CGAffineTransform(a: imageScale.width, b: 0, c: 0, d: imageScale.height,
                                          tx: -imageScale.width * (surface.midX - bounds.midX),
                                          ty: -imageScale.height * (surface.midY - bounds.midY))
        // Transform the rendered native content, not the UIView's frame. UIKit's
        // safe-area calculation therefore stays stable during press and drag.
        bar.layer.sublayerTransform = CATransform3DMakeAffineTransform(transform)
        for (index, control) in controls.enumerated() {
            let centre = control.convert(CGPoint(x: control.bounds.midX, y: control.bounds.midY), to: self)
            let target = CGPoint(x: bounds.width * PlayerLayoutMetrics.navigationCentresW[index], y: bounds.midY)
            let dx = (target.x - centre.x) / imageScale.width
            let dy = (target.y - centre.y) / imageScale.height
            bar.items?[index].imageInsets = UIEdgeInsets(top: dy, left: dx, bottom: -dy, right: -dx)
            // Keep the image canvas unchanged for UIKit layout. Only the glyph
            // inside is inversely rendered, preserving amp's actual icon size.
            bar.items?[index].image = Self.image(index, inverseScale: imageScale, displayScale: traitCollection.displayScale)
        }
        bar.layoutIfNeeded()
        calibratedSize = bounds.size
        writeMetrics(controls: controls, surface: surface)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Menu remains the existing SwiftUI Menu, including its native popup.
        let side = AppNavigationMetrics.buttonsHeight
        let menu = CGRect(x: bounds.width * PlayerLayoutMetrics.navigationCentresW[3] - side / 2,
                          y: bounds.midY - side / 2, width: side, height: side)
        if menu.contains(point) { return nil }
        return super.hitTest(point, with: event)
    }

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        guard item.tag < 3 else {
            if let configuration { bar.selectedItem = bar.items?[configuration.selectedIndex] }
            return
        }
        configuration?.onSelect(item.tag)
    }

    private func nativeSurface(controls: [UIControl]) -> CGRect {
        var roundedSurfaces: [CGRect] = []
        let minimumHeight = controls.map { $0.convert($0.bounds, to: bar).height }.min() ?? 0
        func visit(_ view: UIView) {
            let rect = view.convert(view.bounds, to: bar)
            if max(view.layer.cornerRadius, view.effectiveRadius(corner: .topLeft)) > 0, rect.width > bounds.width / 2,
               rect.height >= minimumHeight, rect.height <= bounds.height, rect.width <= bounds.width {
                roundedSurfaces.append(rect)
            }
            view.subviews.forEach(visit)
        }
        bar.subviews.forEach(visit)
        if let surface = roundedSurfaces.min(by: { $0.width * $0.height < $1.width * $1.height }) { return surface }
        var ancestor = controls[0].superview
        while let candidate = ancestor, !controls.allSatisfy({ $0.isDescendant(of: candidate) }) { ancestor = candidate.superview }
        return (ancestor ?? bar).convert((ancestor ?? bar).bounds, to: bar)
    }

    private func itemControls() -> [UIControl] {
        var matches: [UIControl] = []
        var candidates: [UIControl] = []
        func visit(_ view: UIView) {
            if let control = view as? UIControl, control.bounds.width > 0, control.bounds.height > 0 {
                candidates.append(control)
                if identifiers.contains(control.accessibilityIdentifier ?? "") { matches.append(control) }
            }
            view.subviews.forEach(visit)
        }
        bar.subviews.forEach(visit)
        let result = matches.count == 4 ? matches : candidates.filter { control in
            !candidates.contains { $0 !== control && $0.isDescendant(of: control) }
        }
        let sorted = result.sorted { $0.convert($0.bounds, to: bar).midX < $1.convert($1.bounds, to: bar).midX }
        // UIKit retains stacked/inline presentation copies as sibling controls.
        // They share a tab centre; count the resting tab once, not each copy.
        let pixel = 1 / max(traitCollection.displayScale, 1)
        return sorted.reduce(into: [UIControl]()) { tabs, control in
            let x = control.convert(control.bounds, to: bar).midX
            if let previous = tabs.last, abs(previous.convert(previous.bounds, to: bar).midX - x) <= pixel { return }
            tabs.append(control)
        }
    }

    private static func image(_ index: Int, inverseScale: CGSize, displayScale: CGFloat) -> UIImage {
        let width: CGFloat = index == 1 ? 35 : 32
        let scale = PlayerLayoutMetrics.navigationIconScale
        let glyph = Group {
            switch index {
            case 0: PlayerLibraryGlyph()
            case 1: PlayerEqualizerGlyph()
            case 2: PlayerSearchGlyph()
            default: PlayerQueueGlyph()
            }
        }
        let renderer = ImageRenderer(content: glyph.foregroundStyle(.white)
            .scaleEffect(x: scale / inverseScale.width, y: scale / inverseScale.height)
            .frame(width: width * scale, height: 32 * scale))
        renderer.scale = max(displayScale, 1) * max(1, max(inverseScale.width, inverseScale.height))
        return (renderer.uiImage ?? UIImage()).withRenderingMode(.alwaysTemplate)
    }

    private func writeMetrics(controls: [UIControl], surface: CGRect) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--amp-interaction-probe=") }),
              let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        func imageView(in view: UIView) -> UIImageView? {
            if let image = view as? UIImageView, image.image != nil, !image.isHidden { return image }
            return view.subviews.compactMap { imageView(in: $0) }.first
        }
        let glyphs: [[String: Double]] = controls.enumerated().compactMap { index, control in
            guard index < 4, let image = imageView(in: control) else { return nil }
            let centre = image.convert(CGPoint(x: image.bounds.midX, y: image.bounds.midY), to: self)
            return ["index": Double(index), "x": centre.x, "y": centre.y,
                    "targetX": bounds.width * PlayerLayoutMetrics.navigationCentresW[index], "targetY": bounds.midY]
        }
        let report: [String: Any] = ["backend": "UITabBar", "controls": controls.count, "glyphs": glyphs,
                                     "width": bounds.width, "height": bounds.height,
                                     "surface": [surface.minX, surface.minY, surface.width, surface.height],
                                     "scale": [imageScale.width, imageScale.height]]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("amp-native-navigation-probe.json"), options: .atomic)
        }
        #endif
    }
}
