import SwiftUI
import UIKit

struct PlayerStatusBarSchemeKey: PreferenceKey {
    static let defaultValue: ColorScheme? = nil
    static func reduce(value: inout ColorScheme?, nextValue: () -> ColorScheme?) {
        if let next = nextValue() { value = next }
    }
}

/// Let the native status bar follow the artwork without changing the app's theme.
struct AppStatusBarAppearance: ViewModifier {
    let settings: AppSettings
    let router: AppRouter
    @Environment(\.scenePhase) private var scenePhase
    @State private var systemScheme: ColorScheme = .light
    @State private var playerScheme: ColorScheme?

    func body(content: Content) -> some View {
        let theme = settings.colorScheme ?? systemScheme
        let playerVisible = router.showsNowPlaying && router.presentedTool == nil
        let activePlayerScheme = router.showsLyrics ? .dark : (router.playerStatusBarScheme ?? playerScheme)
        content
            .environment(\.colorScheme, theme)
            .preferredColorScheme(playerVisible ? (activePlayerScheme ?? theme) : settings.colorScheme)
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                // The window can keep its status-ink override while Control Center
                // changes the display appearance in the background.
                if let screen = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first?.screen {
                    systemScheme = screen.traitCollection.userInterfaceStyle == .dark ? .dark : .light
                }
            }
            .onPreferenceChange(PlayerStatusBarSchemeKey.self) { playerScheme = $0 }
            .background {
                SystemAppearanceProbe { systemScheme = $0 }.frame(width: 0, height: 0)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
    }
}

/// Read the display's system appearance. A scene inherits the preferred window
/// scheme used for status ink, so reading the scene creates a light/dark feedback loop.
private struct SystemAppearanceProbe: UIViewRepresentable {
    let changed: (ColorScheme) -> Void
    func makeUIView(context: Context) -> Probe {
        let view = Probe(); view.changed = changed; return view
    }
    func updateUIView(_ view: Probe, context: Context) { view.changed = changed; view.read() }
    final class Probe: UIView {
        var changed: ((ColorScheme) -> Void)?
        private var last: UIUserInterfaceStyle?
        override func didMoveToWindow() { super.didMoveToWindow(); read() }
        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection); read()
        }
        func read() {
            guard let style = window?.windowScene?.screen.traitCollection.userInterfaceStyle, style != last else { return }
            last = style
            DispatchQueue.main.async { [weak self] in self?.changed?(style == .dark ? .dark : .light) }
        }
    }
}
