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
        let monitor = CloudSyncMonitor.shared
        let store = SyncedSettingsStore.shared
        store.onSyncSucceeded = { [weak monitor] in monitor?.noteImportSucceeded() }
        // Refresh first so account state (syncing) precedes the KVS stamp (synced).
        Task { [monitor, store] in
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
        let binding = _pendingURL
        context.coordinator.dispatchPendingURL(pendingURL, into: controller) { url in
            if binding.wrappedValue == url {
                binding.wrappedValue = nil
            }
        }
    }

    @MainActor
    final class Coordinator {
        weak var controller: BrowserRootViewController?
        var lastPhase: ScenePhase
        var pendingDispatchedURL: URL?

        func dispatchPendingURL(
            _ pendingURL: URL?,
            into controller: BrowserRootViewController,
            clearBinding: @escaping @MainActor (URL) -> Void
        ) {
            guard let url = pendingURL else {
                pendingDispatchedURL = nil
                return
            }
            guard pendingDispatchedURL != url else { return }
            pendingDispatchedURL = url
            controller.openExternalURL(url)
            Task { @MainActor in
                clearBinding(url)
                if self.pendingDispatchedURL == url {
                    self.pendingDispatchedURL = nil
                }
            }
        }

        init(scenePhase: ScenePhase) {
            self.lastPhase = scenePhase
        }
    }
}
