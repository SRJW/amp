import SwiftUI
import UIKit

private struct AppNavigationBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}
private struct AppNavigationSharedKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var appNavigationIsShared: Bool {
        get { self[AppNavigationSharedKey.self] }
        set { self[AppNavigationSharedKey.self] = newValue }
    }
    var appNavigationBottomInset: CGFloat {
        get { self[AppNavigationBottomInsetKey.self] }
        set { self[AppNavigationBottomInsetKey.self] = newValue }
    }
}

/// Read once at the app root, before the full player ignores the container safe area.
struct AppNavigationSafeArea: ViewModifier {
    @State private var bottomInset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .environment(\.appNavigationBottomInset, bottomInset)
            .background {
                AppNavigationInsetProbe { bottomInset = $0 }
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
    }
}

private struct AppNavigationInsetProbe: UIViewRepresentable {
    let changed: (CGFloat) -> Void

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.changed = changed
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: Probe, context: Context) { view.changed = changed; view.report() }

    final class Probe: UIView {
        var changed: ((CGFloat) -> Void)?
        private var reported: CGFloat?
        override func didMoveToWindow() { super.didMoveToWindow(); report() }
        override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); report() }
        override func layoutSubviews() { super.layoutSubviews(); report() }
        func report() {
            guard let inset = window?.safeAreaInsets.bottom, inset != reported else { return }
            reported = inset
            DispatchQueue.main.async { [weak self] in self?.changed?(inset) }
        }
    }
}
