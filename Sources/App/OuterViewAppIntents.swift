// App — App Intents dispatching QuickActions plus Siri shortcuts.

import AppIntents
import Foundation

struct OpenURLIntent: AppIntent {
    static let title: LocalizedStringResource = "Open URL in OuterView"
    static let description = IntentDescription("Opens the specified web page in OuterView.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "URL")
    var url: URL

    init() {
        self.url = URL(string: "https://example.com") ?? URL(fileURLWithPath: "/")
    }

    init(url: URL) {
        self.url = url
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickActionDispatcher.shared.dispatch(.openURL(url))
        return .result()
    }
}

struct NewTabIntent: AppIntent {
    static let title: LocalizedStringResource = "New Tab in OuterView"
    static let description = IntentDescription("Opens a new standard browsing tab in OuterView.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickActionDispatcher.shared.dispatch(.newTab)
        return .result()
    }
}

struct NewPrivateTabIntent: AppIntent {
    static let title: LocalizedStringResource = "New Private Tab in OuterView"
    static let description = IntentDescription("Opens a new private tab in OuterView.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickActionDispatcher.shared.dispatch(.newPrivateTab)
        return .result()
    }
}

struct SearchWebIntent: AppIntent {
    static let title: LocalizedStringResource = "Search in OuterView"
    static let description = IntentDescription("Searches the web using OuterView.")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Query")
    var query: String

    init() {
        self.query = ""
    }

    init(query: String) {
        self.query = query
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickActionDispatcher.shared.dispatch(.search(query))
        return .result()
    }
}

struct OuterViewShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewTabIntent(),
            phrases: [
                "New tab in \(.applicationName)",
                "Open new tab in \(.applicationName)"
            ],
            shortTitle: "New Tab",
            systemImageName: "plus"
        )
        AppShortcut(
            intent: NewPrivateTabIntent(),
            phrases: [
                "New private tab in \(.applicationName)",
                "Open private tab in \(.applicationName)"
            ],
            shortTitle: "New Private Tab",
            systemImageName: "hand.raised"
        )
        AppShortcut(
            intent: SearchWebIntent(),
            phrases: [
                "Search in \(.applicationName)",
                "Search with \(.applicationName)"
            ],
            shortTitle: "Search",
            systemImageName: "magnifyingglass"
        )
    }
}
