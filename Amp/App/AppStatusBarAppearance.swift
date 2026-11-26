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
    @Environment(\.colorScheme) private var inheritedScheme
    @State private var systemScheme: ColorScheme? = Self.currentSystemScheme()
    @State private var playerScheme: ColorScheme?

    /// Reads the physical screen's userInterfaceStyle synchronously before the first SwiftUI frame renders,
    /// avoiding a 1-frame light-to-dark flash on app launch when the iPhone is in Dark Mode.
    static func currentSystemScheme() -> ColorScheme? {
        if let screen = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first?.screen,
           screen.traitCollection.userInterfaceStyle != .unspecified {
            return screen.traitCollection.userInterfaceStyle == .dark ? .dark : .light
        }
        let mainStyle = UIScreen.main.traitCollection.userInterfaceStyle
        if mainStyle != .unspecified {
            return mainStyle == .dark ? .dark : .light
        }
        let currentStyle = UITraitCollection.current.userInterfaceStyle
        if currentStyle != .unspecified {
            return currentStyle == .dark ? .dark : .light
        }
        return nil
    }

    func body(content: Content) -> some View {
        let resolvedSystem = systemScheme ?? Self.currentSystemScheme() ?? inheritedScheme
        let theme = settings.colorScheme ?? resolvedSystem
        let playerVisible = router.showsNowPlaying && router.presentedTool == nil
        let activePlayerScheme = router.showsLyrics ? .dark : (router.playerStatusBarScheme ?? playerScheme)
        content
            .environment(\.colorScheme, theme)
            .preferredColorScheme(playerVisible ? (activePlayerScheme ?? theme) : settings.colorScheme)
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active else { return }
                // The window can keep its status-ink override while Control Center
                // changes the display appearance in the background.
                if let current = Self.currentSystemScheme(), systemScheme != current {
                    systemScheme = current
                }
            }
            .onPreferenceChange(PlayerStatusBarSchemeKey.self) { playerScheme = $0 }
            .background {
                SystemAppearanceProbe(activeTheme: theme) { detected in
                    if systemScheme != detected {
                        systemScheme = detected
                    }
                }
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }
}

/// Read the display's system appearance. A scene inherits the preferred window
/// scheme used for status ink, so reading the scene creates a light/dark feedback loop.
private struct SystemAppearanceProbe: UIViewRepresentable {
    let activeTheme: ColorScheme
    let changed: (ColorScheme) -> Void
    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.activeTheme = activeTheme
        view.changed = changed
        return view
    }
    func updateUIView(_ view: Probe, context: Context) {
        view.activeTheme = activeTheme
        view.changed = changed
        view.read()
    }
    final class Probe: UIView {
        var activeTheme: ColorScheme = .dark
        var changed: ((ColorScheme) -> Void)?
        private var last: UIUserInterfaceStyle?
        override func didMoveToWindow() { super.didMoveToWindow(); read() }
        override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
            super.traitCollectionDidChange(previousTraitCollection); read()
        }
        func read() {
            let darkBg = UIColor(red: 0x10 / 255.0, green: 0x12 / 255.0, blue: 0x16 / 255.0, alpha: 1)
            let lightBg = UIColor(red: 0xF4 / 255.0, green: 0xF5 / 255.0, blue: 0xF8 / 255.0, alpha: 1)
            let targetBg = activeTheme == .dark ? darkBg : lightBg
            if window?.backgroundColor != targetBg {
                window?.backgroundColor = targetBg
            }
            guard let style = window?.windowScene?.screen.traitCollection.userInterfaceStyle,
                  style != .unspecified,
                  style != last else { return }
            last = style
            let resolved: ColorScheme = style == .dark ? .dark : .light
            DispatchQueue.main.async { [weak self] in self?.changed?(resolved) }
        }
    }
}
