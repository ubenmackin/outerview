//
//  SessionRestoreCoordinator.swift
//  OuterView
//

import Foundation
import os
import SwiftUI

/// Persists the tab strip on backgrounding and rebuilds it lazily on launch.
/// Private tabs never reach the store, so restore only ever yields non-private rows.
@MainActor
final class SessionRestoreCoordinator {
    private let tabStore: TabStore

    var tabsProvider: (@MainActor () -> [TabRecord])?
    var selectionProvider: (@MainActor () -> UUID?)?

    init(tabStore: TabStore) {
        self.tabStore = tabStore
    }

    func restore() -> (tabs: [TabRecord], selected: UUID?) {
        tabStore.loadSession()
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            saveNow()
        case .active, .inactive:
            break
        @unknown default:
            break
        }
        // Foregrounding never touches chrome state; the FSM keeps its value
        // across background and foreground.
    }

    func saveNow() {
        guard let tabsProvider, let selectionProvider else { return }
        saveNow(tabs: tabsProvider(), selected: selectionProvider())
    }

    func saveNow(tabs: [TabRecord], selected: UUID?) {
        do {
            try tabStore.saveSession(tabs: tabs, selected: selected)
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                .error("saveSession failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
