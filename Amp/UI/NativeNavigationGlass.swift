import SwiftUI
import UIKit

/// Keep UIKit's floating bar in its intended full-window controller context.
/// Only its placement is adapted to amp's existing fixed action row.
@available(iOS 26.0, *)
struct NativeNavigationGlass: View, Animatable {
    let selectedIndex: Int
    let canvasSize: CGSize
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
    var body: some View {
        GeometryReader { geometry in
            let target = geometry.frame(in: .global)
            NativeGlassControllerBridge(configuration: self, target: target)
                .frame(width: canvasSize.width, height: canvasSize.height)
                .contentShape(Path { $0.addRect(target) })
                .position(x: canvasSize.width / 2 - target.minX,
                          y: canvasSize.height / 2 - target.minY)
        }
    }
}

@available(iOS 26.0, *)
private struct NativeGlassControllerBridge: UIViewControllerRepresentable {
    let configuration: NativeNavigationGlass
    let target: CGRect
    func makeUIViewController(context: Context) -> NativeGlassHost { NativeGlassHost() }
    func updateUIViewController(_ controller: NativeGlassHost, context: Context) {
        controller.configure(configuration, target: target)
    }
}

@available(iOS 26.0, *)
private final class GlassNavigationHitView: UIView {
    var target = CGRect.zero
    var menu = CGRect.zero
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        target.contains(point) && !menu.contains(point)
    }
}

@available(iOS 26.0, *)
private final class NativeGlassHost: UIViewController, UITabBarControllerDelegate {
    private let tabs = UITabBarController()
    private var bar: UITabBar { tabs.tabBar }
    private var configuration: NativeNavigationGlass?
    private var target = CGRect.zero
    private var calibratedTarget = CGRect.zero
    private var calibratedSize = CGSize.zero
    private var calibrating = false
    private var imageScale = CGSize(width: 1, height: 1)
    private var appliedSelected: UIColor?
    private var appliedIdle: UIColor?
    private let identifiers = ["amp.native.library", "amp.native.equalizer", "amp.native.search", "amp.native.menu"]

    override func loadView() { view = GlassNavigationHitView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.accessibilityElementsHidden = true
        tabs.mode = .tabBar
        tabs.tabBarMinimizeBehavior = .never
        tabs.delegate = self
        tabs.viewControllers = (0..<4).map { index in
            let child = UIViewController()
            child.view.backgroundColor = .clear
            child.view.isOpaque = false
            child.view.isUserInteractionEnabled = false
            child.tabBarItem = UITabBarItem(title: nil, image: Self.image(index, inverseScale: imageScale, displayScale: traitCollection.displayScale), tag: index)
            child.tabBarItem.accessibilityIdentifier = identifiers[index]
            return child
        }
        addChild(tabs)
        tabs.view.backgroundColor = .clear
        tabs.view.isOpaque = false
        tabs.view.frame = view.bounds
        tabs.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(tabs.view)
        tabs.didMove(toParent: self)
    }

    func configure(_ configuration: NativeNavigationGlass, target: CGRect) {
        loadViewIfNeeded()
        self.configuration = configuration
        self.target = target
        view.alpha = configuration.opacity
        view.isHidden = configuration.opacity <= 0.001
        view.isUserInteractionEnabled = configuration.interactive
        view.overrideUserInterfaceStyle = configuration.dark ? .dark : .light
        if tabs.selectedIndex != configuration.selectedIndex { tabs.selectedIndex = configuration.selectedIndex }
        if let hitView = view as? GlassNavigationHitView {
            hitView.target = target
            let side = AppNavigationMetrics.buttonsHeight
            hitView.menu = CGRect(x: target.minX + target.width * PlayerLayoutMetrics.navigationCentresW[3] - side / 2,
                                  y: target.midY - side / 2, width: side, height: side)
        }
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
        if calibratedTarget != target { view.setNeedsLayout() }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        calibratedSize = .zero
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !calibrating, view.window != nil, target.width > 0, target.height > 0 else { return }
        guard calibratedSize != view.bounds.size || calibratedTarget != target else { return }
        calibrating = true
        defer { calibrating = false }
        let animationsEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(animationsEnabled) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        tabs.view.frame = view.bounds
        bar.layer.sublayerTransform = CATransform3DIdentity
        tabs.view.layoutIfNeeded()
        let controls = itemControls()
        guard controls.count == 4 else { writeMetrics(controls: controls, surface: .zero); return }
        let surface = nativeSurface(controls: controls)
        guard surface.width > 0 else { return }
        let targetInBar = bar.convert(target, from: view)
        // Never scale the native bar vertically: doing so also magnifies its
        // contact deformation, producing the oversized lens from the report.
        imageScale = CGSize(width: target.width / surface.width, height: 1)
        let centreY = controls[0].convert(CGPoint(x: controls[0].bounds.midX, y: controls[0].bounds.midY), to: bar).y
        let transform = CGAffineTransform(a: imageScale.width, b: 0, c: 0, d: 1,
            tx: targetInBar.midX - bar.bounds.midX - imageScale.width * (surface.midX - bar.bounds.midX),
            ty: targetInBar.midY - centreY)
        bar.layer.sublayerTransform = CATransform3DMakeAffineTransform(transform)
        for (index, control) in controls.enumerated() {
            guard let icon = Self.imageView(in: control) else { continue }
            let centre = icon.convert(CGPoint(x: icon.bounds.midX, y: icon.bounds.midY), to: view)
            let destination = CGPoint(x: target.minX + target.width * PlayerLayoutMetrics.navigationCentresW[index], y: target.midY)
            let offset = CGPoint(x: (destination.x - centre.x) / imageScale.width,
                                 y: destination.y - centre.y)
            // The floating UIKit appearance ignores legacy item.imageInsets.
            // Move pixels inside their bitmap canvas instead of moving controls.
            bar.items?[index].image = Self.image(index, inverseScale: imageScale,
                displayScale: traitCollection.displayScale, offset: offset)
        }
        bar.setNeedsLayout()
        bar.layoutIfNeeded()
        calibratedSize = view.bounds.size
        calibratedTarget = target
        #if DEBUG
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.bar.layoutIfNeeded()
            self.writeMetrics(controls: self.itemControls(), surface: surface)
        }
        #endif
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        guard let index = tabs.viewControllers?.firstIndex(of: viewController) else { return false }
        return index < 3
    }
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        guard let index = tabs.viewControllers?.firstIndex(of: viewController), index < 3 else { return }
        configuration?.onSelect(index)
    }

    private func nativeSurface(controls: [UIControl]) -> CGRect {
        var roundedSurfaces: [CGRect] = []
        let minimumHeight = controls.map { $0.convert($0.bounds, to: bar).height }.min() ?? 0
        func visit(_ view: UIView) {
            let rect = view.convert(view.bounds, to: bar)
            if max(view.layer.cornerRadius, view.effectiveRadius(corner: .topLeft)) > 0, rect.width > bar.bounds.width / 2,
               rect.height >= minimumHeight, rect.height <= bar.bounds.height, rect.width <= bar.bounds.width {
                roundedSurfaces.append(rect)
            }
            view.subviews.forEach(visit)
        }
        bar.subviews.forEach(visit)
        if let surface = roundedSurfaces.max(by: { $0.width * $0.height < $1.width * $1.height }) { return surface }
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

    private static func image(_ index: Int, inverseScale: CGSize, displayScale: CGFloat, offset: CGPoint = .zero) -> UIImage {
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
            .offset(x: offset.x, y: offset.y)
            .frame(width: width * scale + 1, height: 32 * scale + 1))
        renderer.scale = max(displayScale, 1) * max(1, max(inverseScale.width, inverseScale.height))
        return (renderer.uiImage ?? UIImage()).withRenderingMode(.alwaysTemplate)
    }

    private static func imageView(in view: UIView) -> UIImageView? {
        if let image = view as? UIImageView, image.image != nil, !image.isHidden { return image }
        return view.subviews.compactMap { imageView(in: $0) }.first
    }

    #if DEBUG
    /// Read actual alpha pixels; a canvas centre alone cannot detect an
    /// ignored image inset or a clipped/displaced glyph.
    private static func alphaBounds(_ image: UIImage) -> CGRect? {
        guard let bitmap = image.cgImage, bitmap.bitsPerComponent == 8,
              let data = bitmap.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return nil }
        guard CFDataGetLength(data) >= bitmap.bytesPerRow * bitmap.height else { return nil }
        let pixelStride = bitmap.bitsPerPixel / 8
        let little = bitmap.bitmapInfo.contains(.byteOrder32Little)
        let alphaIndex: Int
        switch bitmap.alphaInfo {
        case .premultipliedFirst, .first: alphaIndex = little ? 3 : 0
        case .premultipliedLast, .last: alphaIndex = little ? 0 : 3
        case .alphaOnly: alphaIndex = 0
        default: return nil
        }
        guard alphaIndex < pixelStride else { return nil }
        var minX = bitmap.width, minY = bitmap.height, maxX = -1, maxY = -1
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width where bytes[y * bitmap.bytesPerRow + x * pixelStride + alphaIndex] > 16 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x: CGFloat(minX) / CGFloat(bitmap.width), y: CGFloat(minY) / CGFloat(bitmap.height),
                      width: CGFloat(maxX - minX + 1) / CGFloat(bitmap.width), height: CGFloat(maxY - minY + 1) / CGFloat(bitmap.height))
    }

    private static func contentRect(_ icon: UIImageView, image: UIImage) -> CGRect {
        let size: CGSize
        switch icon.contentMode {
        case .center: size = image.size
        case .scaleAspectFit, .scaleAspectFill:
            let x = icon.bounds.width / image.size.width, y = icon.bounds.height / image.size.height
            let scale = icon.contentMode == .scaleAspectFit ? min(x, y) : max(x, y)
            size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        default: return icon.bounds
        }
        return CGRect(x: icon.bounds.midX - size.width / 2, y: icon.bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
    #endif

    private func writeMetrics(controls: [UIControl], surface: CGRect) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--amp-interaction-probe=") }),
              let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let glyphs: [[String: Double]] = controls.enumerated().compactMap { index, control in
            guard index < 4, let icon = Self.imageView(in: control), let image = icon.image,
                  let pixels = Self.alphaBounds(image) else { return nil }
            let reference = Self.image(index, inverseScale: CGSize(width: 1, height: 1), displayScale: traitCollection.displayScale)
            guard let original = Self.alphaBounds(reference) else { return nil }
            let content = Self.contentRect(icon, image: image)
            let local = CGRect(x: content.minX + pixels.minX * content.width,
                               y: content.minY + pixels.minY * content.height,
                               width: pixels.width * content.width, height: pixels.height * content.height)
            let visible = icon.layer.convert(local, to: view.window?.layer ?? view.layer)
            let originalOffset = CGPoint(x: (original.midX - 0.5) * reference.size.width,
                                         y: (original.midY - 0.5) * reference.size.height)
            return ["index": Double(index), "x": Double(visible.midX - target.minX - originalOffset.x),
                    "y": Double(visible.midY - target.minY - originalOffset.y),
                    "targetX": Double(target.width * PlayerLayoutMetrics.navigationCentresW[index]),
                    "targetY": Double(target.height / CGFloat(2)),
                    "width": Double(visible.width), "height": Double(visible.height),
                    "originalWidth": Double(original.width * reference.size.width),
                    "originalHeight": Double(original.height * reference.size.height)]
        }
        let formats: [[String: Int]] = controls.prefix(4).map { control in
            guard let bitmap = Self.imageView(in: control)?.image?.cgImage else { return [:] }
            return ["bits": bitmap.bitsPerComponent, "pixelBits": bitmap.bitsPerPixel,
                    "alpha": Int(bitmap.alphaInfo.rawValue), "order": Int(bitmap.bitmapInfo.rawValue)]
        }
        let report: [String: Any] = ["backend": "UITabBarController", "controls": controls.count, "glyphs": glyphs,
                                     "width": target.width, "height": target.height,
                                     "surface": [surface.minX, surface.minY, surface.width, surface.height],
                                     "scale": [imageScale.width, imageScale.height], "formats": formats,
                                     "canvas": [view.bounds.width, view.bounds.height],
                                     "barFrame": [bar.frame.minX, bar.frame.minY, bar.frame.width, bar.frame.height]]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("amp-native-navigation-probe.json"), options: .atomic)
        }
        #endif
    }
}
