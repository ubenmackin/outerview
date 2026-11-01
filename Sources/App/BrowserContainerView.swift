//
//  BrowserContainerView.swift
//  OuterView
//

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
        let browserRoot = BrowserRootViewController()
        let host = BrowserChromeHostViewController(browserRoot: browserRoot)
        context.coordinator.controller = browserRoot
        return host
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
