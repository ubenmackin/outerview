// App — QuickAction routing with cold-launch buffering.

import Foundation
import UIKit

/// High-level actions triggered by SpringBoard Quick Actions, App Intents, or deep links.
enum QuickAction: Equatable, Sendable {
    case newTab
    case newPrivateTab
    case search(String? = nil)
    case openURL(URL)

    static let newTabType = "com.volcrypt.OuterView.newTab"
    static let newPrivateTabType = "com.volcrypt.OuterView.newPrivateTab"
    static let searchType = "com.volcrypt.OuterView.search"

    init?(shortcutType: String) {
        switch shortcutType {
        case Self.newTabType:
            self = .newTab
        case Self.newPrivateTabType:
            self = .newPrivateTab
        case Self.searchType:
            self = .search(nil)
        default:
            return nil
        }
    }
}

/// Central routing point for Quick Actions, App Intents, and external deep links.
@MainActor
final class QuickActionDispatcher {
    static let shared = QuickActionDispatcher()

    private var actionHandler: (@MainActor (QuickAction) -> Void)?
    private var pendingAction: QuickAction?

    func dispatch(_ action: QuickAction) {
        if let handler = actionHandler {
            handler(action)
        } else {
            pendingAction = action
        }
    }

    func registerHandler(_ handler: @escaping @MainActor (QuickAction) -> Void) {
        self.actionHandler = handler
        if let pending = pendingAction {
            pendingAction = nil
            handler(pending)
        }
    }
}
