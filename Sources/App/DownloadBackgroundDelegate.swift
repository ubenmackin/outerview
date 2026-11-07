// App — Background download wake plus quick-action lifecycle.

import UIKit

@MainActor
final class DownloadBackgroundDelegate: NSObject, UIApplicationDelegate, BackgroundLaunchHandlerStore {
    /// Keyed by identifier: multiple sessions could wake before finish-events drains them.
    private var storedHandlers: [String: () -> Void] = [:]

    func application(
        _ _: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        // Only the owned session identifier may store a handler; mismatches drop.
        guard identifier == BackgroundDownloadService.sessionIdentifier else { return }
        storedHandlers[identifier] = completionHandler
        let service = BackgroundDownloadService.shared
        service.launchHandlerStore = self
        // Own rows before rejoin so wake without a scene still finalizes.
        _ = service.ensureManagerForBackgroundWake()
        // Rejoin the daemon by identifier so finish-events can pop exactly once.
        service.rejoin()
    }

    /// Sole drain point for the session delegate's finish-events; popping clears the slot once.
    func popLaunchHandler(for identifier: String) -> (() -> Void)? {
        storedHandlers.removeValue(forKey: identifier)
    }

    // MARK: - Quick Actions

    func application(
        _: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let shortcutItem = options.shortcutItem,
           let action = QuickAction(shortcutType: shortcutItem.type)
        {
            QuickActionDispatcher.shared.dispatch(action)
        }
        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }

    func application(
        _: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        if let action = QuickAction(shortcutType: shortcutItem.type) {
            QuickActionDispatcher.shared.dispatch(action)
            completionHandler(true)
        } else {
            completionHandler(false)
        }
    }
}
