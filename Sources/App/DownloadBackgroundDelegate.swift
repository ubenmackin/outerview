// App — UIApplication delegate bridging background-download wake events to the
// shared session and returning the system launch completion exactly once.

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
}
