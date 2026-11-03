//
//  OuterViewApp.swift
//  OuterView
//

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
            // The UIKit root must own the full window: the rail lives in the
            // right system column and the web view runs under every edge. Left
            // inside the SwiftUI safe area, the root is inset by right 84 /
            // bottom 34 and the rail lands on top of page content. Keyboard
            // avoidance is handled in UIKit via keyboardLayoutGuide.
            .ignoresSafeArea()
            .onOpenURL { url in
                pendingURL = url
            }
    }
}
