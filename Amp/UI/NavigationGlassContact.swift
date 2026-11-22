import SwiftUI
import UIKit

/// Contact drives only the glass and tint preview. Icon layout always uses the
/// original AppNavigationMetrics / PlayerLayoutMetrics coordinates.
struct NavigationGlassContact {
    let start: CGPoint
    var point: CGPoint
    var velocityX: CGFloat
    let width: CGFloat

    private var centres: [CGFloat] { PlayerLayoutMetrics.navigationCentresW.map { $0 * width } }
    var startsOnMenu: Bool { start.x >= (centres[2] + centres[3]) / 2 }
    var speed: CGFloat { min(abs(velocityX) / max(width * 6, 1), 1) }
    var lensX: CGFloat {
        if startsOnMenu { return centres[3] }
        let edge = min(max(point.x, centres[0]), centres[2])
        let excess = point.x - edge
        let pitch = max(centres[1] - centres[0], 1)
        // Let the lens stretch a little beyond an end, without moving an icon.
        return edge + excess * 0.12 / (1 + abs(excess) / pitch)
    }
    func focus(at index: Int) -> Double {
        if startsOnMenu { return index == 3 ? 1 : 0 }
        guard index < 3 else { return 0 }
        let pitch = max(centres[1] - centres[0], 1)
        return Double(max(1 - abs(lensX - centres[index]) / pitch, 0))
    }
    func draggedSection(height: CGFloat) -> Int? {
        let dx = point.x - start.x, dy = point.y - start.y
        // A tap belongs to its Button/Menu, never to this observer. Vertical exits
        // cancel the preview rather than accidentally switching destinations.
        guard !startsOnMenu, abs(dx) >= 8, abs(dx) > abs(dy),
              point.y >= -height / 2, point.y <= height * 1.5 else { return nil }
        let target = (0..<3).min { abs(centres[$0] - point.x) < abs(centres[$1] - point.x) }
        let origin = (0..<3).min { abs(centres[$0] - start.x) < abs(centres[$1] - start.x) }
        // Inside its original button the native tap remains the sole action owner.
        return target == origin ? nil : target
    }
}

/// Observe the real touch stream without replacing a Button's tap or a native
/// Menu's recognizers. The small probe is transparent to hit testing; its window
/// recognizer accepts only contacts that begin inside this particular bar.
struct NavigationGlassTouchObserver: UIViewRepresentable {
    let enabled: Bool
    let changed: (NavigationGlassContact) -> Void
    let ended: (NavigationGlassContact, Bool) -> Void

    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {
        view.changed = changed; view.ended = ended
        view.isTrackingEnabled = enabled
    }
    static func dismantleUIView(_ view: Probe, coordinator: ()) { view.detach() }

    final class Probe: UIView, UIGestureRecognizerDelegate {
        var changed: ((NavigationGlassContact) -> Void)?
        var ended: ((NavigationGlassContact, Bool) -> Void)?
        var isTrackingEnabled = true {
            didSet { if oldValue != isTrackingEnabled { observer.isEnabled = isTrackingEnabled } }
        }
        private weak var observedWindow: UIWindow?
        private var contact: NavigationGlassContact?
        private var lastTime: TimeInterval = 0
        private lazy var observer: PassiveContactRecognizer = {
            let recognizer = PassiveContactRecognizer(target: self, action: #selector(receive(_:)))
            recognizer.minimumPressDuration = 0
            recognizer.allowableMovement = .greatestFiniteMagnitude
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false; recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            return recognizer
        }()
        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear; isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard observedWindow !== window else { return }
            detach()
            if let window { window.addGestureRecognizer(observer); observedWindow = window }
        }
        func detach() {
            observedWindow?.removeGestureRecognizer(observer); observedWindow = nil
            if let contact {
                self.contact = nil
                let callback = ended
                DispatchQueue.main.async { callback?(contact, true) }
            }
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard isTrackingEnabled, window != nil, bounds.width > 0, !isHidden else { return false }
            let outset = (AppNavigationMetrics.capsuleHeight - AppNavigationMetrics.buttonsHeight) / 2
            return bounds.insetBy(dx: 0, dy: -outset).contains(touch.location(in: self))
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        @objc private func receive(_ recognizer: UILongPressGestureRecognizer) {
            let point = recognizer.location(in: self)
            let time = ProcessInfo.processInfo.systemUptime
            switch recognizer.state {
            case .began:
                let sample = NavigationGlassContact(start: point, point: point, velocityX: 0, width: bounds.width)
                contact = sample; lastTime = time; changed?(sample)
            case .changed, .ended:
                guard var sample = contact else { return }
                let dt = max(time - lastTime, 1.0 / 240)
                let velocity = (point.x - sample.point.x) / CGFloat(dt)
                sample.velocityX = sample.velocityX * 0.7 + velocity * 0.3
                sample.point = point; lastTime = time; contact = sample
                if recognizer.state == .ended {
                    contact = nil; ended?(sample, false)
                } else { changed?(sample) }
            case .cancelled, .failed:
                guard let sample = contact else { return }
                contact = nil
                let callback = ended
                DispatchQueue.main.async { callback?(sample, true) }
            default: break
            }
        }
    }
    /// This recognizer is observational: it must never win against an actual control.
    private final class PassiveContactRecognizer: UILongPressGestureRecognizer {
        override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
        override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    }
}
