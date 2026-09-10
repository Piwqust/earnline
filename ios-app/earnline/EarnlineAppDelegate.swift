import UIKit

extension Notification.Name {
    static let earnlineQuickAction = Notification.Name("earnline.quickAction")
}

/// Scene connection options carry cold-launch shortcuts on iOS 26+.
final class EarnlineAppDelegate: NSObject, UIApplicationDelegate {
    static let pendingQuickActionKey = "earnline.pendingQuickAction"

    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem { _ = Self.receive(item) }
        let configuration = session.configuration
        configuration.delegateClass = EarnlineSceneDelegate.self
        return configuration
    }

    @discardableResult
    static func receive(_ item: UIApplicationShortcutItem) -> Bool {
        let action: AppModel.QuickAction
        switch item.type {
        case "com.earnline.add-income": action = .addIncome
        case "com.earnline.search": action = .search
        default: return false
        }
        let defaults = EarnlineRuntime.shared.app?.defaults ?? .standard
        defaults.set(action.rawValue, forKey: pendingQuickActionKey)
        EarnlineRuntime.shared.app?.consumeQuickAction()
        return true
    }
}

final class EarnlineSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(EarnlineAppDelegate.receive(shortcutItem))
    }
}
