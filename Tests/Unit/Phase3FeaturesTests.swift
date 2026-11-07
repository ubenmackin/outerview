// Tests — Phase 3 ecosystem coverage for quick actions, deep links, and Handoff.

import Foundation
@testable import OuterView
import XCTest

@MainActor
final class Phase3FeaturesTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let name = "Phase3FeaturesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
        }
        return defaults
    }

    private func makeRoot(defaults: UserDefaults? = nil) throws -> BrowserRootViewController {
        let database = try OuterViewDatabase(inMemory: true)
        let defs = try defaults ?? makeDefaults()
        let root = BrowserRootViewController(database: database, defaults: defs)
        TestWindow.attach(root)
        return root
    }

    // MARK: - Quick Action Dispatcher Tests

    func testQuickActionInitializationFromShortcutTypes() {
        XCTAssertEqual(QuickAction(shortcutType: QuickAction.newTabType), .newTab)
        XCTAssertEqual(QuickAction(shortcutType: QuickAction.newPrivateTabType), .newPrivateTab)
        XCTAssertEqual(QuickAction(shortcutType: QuickAction.searchType), .search(nil))
        XCTAssertNil(QuickAction(shortcutType: "unknown.type"))
    }

    func testQuickActionDispatcherBufferingAndImmediateDelivery() {
        let dispatcher = QuickActionDispatcher()
        var receivedAction: QuickAction?

        // Dispatch before handler registered
        dispatcher.dispatch(.newTab)
        XCTAssertNil(receivedAction)

        // Handler registers; buffered action delivered immediately
        dispatcher.registerHandler { action in
            receivedAction = action
        }
        XCTAssertEqual(receivedAction, .newTab)

        // Subsequent dispatches delivered immediately
        dispatcher.dispatch(.newPrivateTab)
        XCTAssertEqual(receivedAction, .newPrivateTab)
    }

    // MARK: - Browser Root Quick Action Handling Tests

    func testHandleQuickActionNewTab() throws {
        let root = try makeRoot()
        let initialTabCount = root.tabs.count

        root.handleQuickAction(.newTab)
        XCTAssertEqual(root.tabs.count, initialTabCount + 1)
        let newTab = root.tabs.last
        XCTAssertEqual(newTab?.isPrivate, false)
    }

    func testHandleQuickActionNewPrivateTab() throws {
        let root = try makeRoot()
        let initialTabCount = root.tabs.count

        root.handleQuickAction(.newPrivateTab)
        XCTAssertEqual(root.tabs.count, initialTabCount + 1)
        let newTab = root.tabs.last
        XCTAssertEqual(newTab?.isPrivate, true)
    }

    func testHandleQuickActionSearchWithQuery() throws {
        let root = try makeRoot()
        let initialTabCount = root.tabs.count

        root.handleQuickAction(.search("swift concurrency"))
        XCTAssertEqual(root.tabs.count, initialTabCount + 1)
        let activePage = root.activePage()
        XCTAssertNotNil(activePage)
    }

    func testHandleQuickActionSearchWithoutQueryBeginsEditing() throws {
        let root = try makeRoot()
        root.handleQuickAction(.search(nil))
        XCTAssertTrue(root.isEditingAddress)
    }

    // MARK: - Deep Link OuterView Action Schemes Tests

    func testOpenExternalURLSchemeQuickActions() throws {
        let root = try makeRoot()

        let newTabURL = try XCTUnwrap(URL(string: "outerview://newtab"))
        let tabCountBefore = root.tabs.count
        root.openExternalURL(newTabURL)
        XCTAssertEqual(root.tabs.count, tabCountBefore + 1)
        XCTAssertEqual(root.tabs.last?.isPrivate, false)

        let privateTabURL = try XCTUnwrap(URL(string: "outerview://newprivatetab"))
        let tabCountBeforePrivate = root.tabs.count
        root.openExternalURL(privateTabURL)
        XCTAssertEqual(root.tabs.count, tabCountBeforePrivate + 1)
        XCTAssertEqual(root.tabs.last?.isPrivate, true)

        let searchURL = try XCTUnwrap(URL(string: "outerview://search?q=outerview+browser"))
        let tabCountBeforeSearch = root.tabs.count
        root.openExternalURL(searchURL)
        XCTAssertEqual(root.tabs.count, tabCountBeforeSearch + 1)
    }

    // MARK: - Apple Handoff (NSUserActivity) Tests

    func testHandoffActivityPopulatedForStandardLoadablePage() throws {
        let root = try makeRoot()
        let testURL = try XCTUnwrap(URL(string: "https://example.com/handoff-test"))

        let snapshot = WebPageSnapshot(
            url: testURL,
            title: "Handoff Test Page",
            progress: 1.0,
            canGoBack: false,
            canGoForward: false,
            isSecure: true
        )

        root.updateHandoffActivity(for: snapshot, isPrivate: false, showStart: false)

        XCTAssertNotNil(root.userActivity)
        XCTAssertEqual(root.userActivity?.activityType, NSUserActivityTypeBrowsingWeb)
        XCTAssertEqual(root.userActivity?.webpageURL, testURL)
        XCTAssertEqual(root.userActivity?.title, "Handoff Test Page")
        XCTAssertTrue(root.userActivity?.isEligibleForHandoff ?? false)
    }

    func testHandoffActivityInvalidatedForPrivateTab() throws {
        let root = try makeRoot()
        let testURL = try XCTUnwrap(URL(string: "https://example.com/secret"))

        let snapshot = WebPageSnapshot(
            url: testURL,
            title: "Secret Page",
            progress: 1.0,
            canGoBack: false,
            canGoForward: false,
            isSecure: true
        )

        // Private tab must never broadcast handoff
        root.updateHandoffActivity(for: snapshot, isPrivate: true, showStart: false)
        XCTAssertNil(root.userActivity)
    }

    func testHandoffActivityInvalidatedOnStartPage() throws {
        let root = try makeRoot()
        let testURL = try XCTUnwrap(URL(string: "https://example.com/article"))

        let snapshot = WebPageSnapshot(
            url: testURL,
            title: "Article",
            progress: 1.0,
            canGoBack: false,
            canGoForward: false,
            isSecure: true
        )

        root.updateHandoffActivity(for: snapshot, isPrivate: false, showStart: true)
        XCTAssertNil(root.userActivity)
    }

    // MARK: - App Intents & Shortcuts Tests

    func testAppIntentsDispatchQuickActions() async throws {
        var receivedAction: QuickAction?
        QuickActionDispatcher.shared.registerHandler { action in
            receivedAction = action
        }
        // Teardown resets shared routing so later tests never see this capture.
        defer { QuickActionDispatcher.shared.registerHandler { _ in } }

        let newTabIntent = NewTabIntent()
        _ = try await newTabIntent.perform()
        XCTAssertEqual(receivedAction, .newTab)

        let privateTabIntent = NewPrivateTabIntent()
        _ = try await privateTabIntent.perform()
        XCTAssertEqual(receivedAction, .newPrivateTab)

        let searchIntent = SearchWebIntent(query: "deepmind")
        _ = try await searchIntent.perform()
        XCTAssertEqual(receivedAction, .search("deepmind"))

        let targetURL = try XCTUnwrap(URL(string: "https://example.com/intent"))
        let openURLIntent = OpenURLIntent(url: targetURL)
        _ = try await openURLIntent.perform()
        XCTAssertEqual(receivedAction, .openURL(targetURL))
    }

    func testAppShortcutsDefinitions() {
        let shortcuts = OuterViewShortcuts.appShortcuts
        XCTAssertEqual(shortcuts.count, 3)
    }
}
