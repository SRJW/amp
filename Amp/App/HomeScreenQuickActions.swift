import Foundation
import UIKit

/// Home Screen Quick Actions shown when the user long-presses the amp icon on the iOS Home Screen or Dock.
enum HomeScreenQuickAction: String, CaseIterable, Sendable {
    case shuffleAll = "com.amp.shortcut.shuffle"
    case search = "com.amp.shortcut.search"
    case favorites = "com.amp.shortcut.favorites"
    case wifiTransfer = "com.amp.shortcut.wifiTransfer"

    @MainActor
    var title: String {
        switch self {
        case .shuffleAll: L("Shuffle All")
        case .search: L("Search")
        case .favorites: L("Favorites")
        case .wifiTransfer: L("Wi-Fi Transfer")
        }
    }

    var systemImageName: String {
        switch self {
        case .shuffleAll: "shuffle"
        case .search: "magnifyingglass"
        case .favorites: "star.fill"
        case .wifiTransfer: "wifi"
        }
    }

    @MainActor
    func shortcutItem() -> UIApplicationShortcutItem {
        UIApplicationShortcutItem(
            type: rawValue,
            localizedTitle: title,
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: systemImageName),
            userInfo: nil
        )
    }
}

/// Manages registering and routing iOS Home Screen Quick Actions across cold and warm launches.
@MainActor
final class HomeScreenQuickActionManager {
    static let shared = HomeScreenQuickActionManager()
    static let didRequestNotification = Notification.Name("amp.homeScreenQuickActionDidRequest")

    private var pendingAction: HomeScreenQuickAction?

    private init() {}

    /// Updates the dynamic Home Screen quick actions using the active in-app localization.
    func refreshShortcutItems() {
        UIApplication.shared.shortcutItems = HomeScreenQuickAction.allCases.map { $0.shortcutItem() }
    }

    /// Queues a shortcut item triggered from the Home Screen or Dock and notifies the active scene.
    @discardableResult
    func handle(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let action = HomeScreenQuickAction(rawValue: shortcutItem.type) else { return false }
        pendingAction = action
        NotificationCenter.default.post(name: Self.didRequestNotification, object: action)
        return true
    }

    /// Consumes the pending quick action if the required app services are ready.
    /// Note: `.shuffleAll` waits until `restoreFinished` is true so state restoration doesn't overwrite playback.
    func consumePending(restored: Bool) -> HomeScreenQuickAction? {
        guard let action = pendingAction else { return nil }
        if action == .shuffleAll && !restored {
            return nil
        }
        pendingAction = nil
        return action
    }
}

/// Forwarding scene delegate that captures Home Screen Quick Actions in a SwiftUI `WindowGroup` scene lifecycle.
@MainActor
final class AppSceneShortcutDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let shortcut = connectionOptions.shortcutItem {
            HomeScreenQuickActionManager.shared.handle(shortcut)
        }
    }

    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        let handled = HomeScreenQuickActionManager.shared.handle(shortcutItem)
        completionHandler(handled)
    }
}
