// App — App entry plus scene bridge for URLs and Handoff.

import SwiftUI

@main
struct OuterViewApp: App {
    @UIApplicationDelegateAdaptor(DownloadBackgroundDelegate.self) var backgroundDelegate

    var body: some Scene {
        WindowGroup {
            SceneBridgeView()
        }
    }
}

/// Single scene-phase observation point. Forwards changes to the browser root
/// through `BrowserContainerView.updateUIViewController`.
private struct SceneBridgeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingURL: URL?

    var body: some View {
        BrowserContainerView(scenePhase: scenePhase, pendingURL: $pendingURL)
            // Full-window UIKit root: rail in the system column, web view
            // edge-to-edge; SwiftUI safe-area insets ignored. Keyboard
            // avoidance lives in UIKit via keyboardLayoutGuide.
            .ignoresSafeArea()
            .onOpenURL { url in
                pendingURL = url
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                if let url = userActivity.webpageURL {
                    pendingURL = url
                }
            }
    }
}
