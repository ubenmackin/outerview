// App — SwiftUI bridge hosting the browser root.

import SwiftUI

/// Bridges the UIKit browser root into the SwiftUI window so the app keeps a
/// single `UIViewController` hierarchy, as no navigation/tab controllers are
/// used anywhere in the browser surface.
struct BrowserContainerView: UIViewControllerRepresentable {
    var scenePhase: ScenePhase
    @Binding var pendingURL: URL?

    init(scenePhase: ScenePhase = .active, pendingURL: Binding<URL?>) {
        self.scenePhase = scenePhase
        self._pendingURL = pendingURL
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(scenePhase: scenePhase)
    }

    func makeUIViewController(context: Context) -> BrowserChromeHostViewController {
        Self.activateSyncIfNeeded()
        let browserRoot = BrowserRootViewController()
        let host = BrowserChromeHostViewController(browserRoot: browserRoot)
        context.coordinator.controller = browserRoot
        return host
    }

    /// Launch owns KVS backfill/pull plus account refresh so sync runs
    /// without opening Settings; the settings model only reads.
    @MainActor
    private static func activateSyncIfNeeded() {
        guard !AppEnvironment.isTestHost, SyncedSettingsStore.isSyncEnabled() else { return }
        let monitor = iCloudSyncMonitor.shared
        let store = SyncedSettingsStore.shared
        store.onSyncSucceeded = { [weak monitor] in monitor?.noteImportSucceeded() }
        // Refresh first so account state (syncing) precedes the KVS stamp (synced).
        Task { @MainActor [monitor, store] in
            await monitor.refreshAccountStatus()
            store.startSync()
        }
    }

    func updateUIViewController(_ host: BrowserChromeHostViewController, context: Context) {
        let controller = host.browserRoot
        if context.coordinator.lastPhase != scenePhase {
            context.coordinator.lastPhase = scenePhase
            controller.handleScenePhase(scenePhase)
        }
        if let url = pendingURL {
            controller.openExternalURL(url)
            // Consuming clears the binding so repeated deep links reload.
            let binding = _pendingURL
            Task { @MainActor in
                binding.wrappedValue = nil
            }
        }
    }

    @MainActor
    final class Coordinator {
        weak var controller: BrowserRootViewController?
        var lastPhase: ScenePhase

        init(scenePhase: ScenePhase) {
            self.lastPhase = scenePhase
        }
    }
}
