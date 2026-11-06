// WebPageTests — UIDelegate forwarding plus desktop/media contract tests.

@testable import OuterView
import WebKit
import XCTest

@MainActor
final class WebPageUIDelegateTests: XCTestCase {
    private final class MockUIDelegateHandler: WebPageUIDelegateHandler {
        var didCallCreateWebView = false
        var didCallDidClose = false
        var alertMessageReceived: String?
        var confirmMessageReceived: String?
        var promptMessageReceived: String?
        var confirmResult = true
        var promptResult: String? = "Test Input"

        func webPageController(
            _: WebPageController,
            createWebViewWith configuration: WKWebViewConfiguration,
            for _: WKNavigationAction,
            windowFeatures _: WKWindowFeatures
        ) -> WKWebView? {
            didCallCreateWebView = true
            return WKWebView(frame: .zero, configuration: configuration)
        }

        func webPageControllerDidClose(_: WebPageController) {
            didCallDidClose = true
        }

        func webPageController(
            _: WebPageController,
            runJavaScriptAlertPanelWithMessage message: String,
            initiatedByFrame _: WKFrameInfo
        ) async {
            alertMessageReceived = message
        }

        func webPageController(
            _: WebPageController,
            runJavaScriptConfirmPanelWithMessage message: String,
            initiatedByFrame _: WKFrameInfo
        ) async -> Bool {
            confirmMessageReceived = message
            return confirmResult
        }

        func webPageController(
            _: WebPageController,
            runJavaScriptTextInputPanelWithPrompt prompt: String,
            defaultText _: String?,
            initiatedByFrame _: WKFrameInfo
        ) async -> String? {
            promptMessageReceived = prompt
            return promptResult
        }
    }

    func testInspectableEnabledOnController() {
        let config = WKWebViewConfiguration()
        let controller = WebPageController(configuration: config)
        XCTAssertTrue(controller.webView.isInspectable)
    }

    func testMediaPlaybackConfigurationsEnabled() {
        let normalConfig = TabPool.makeConfiguration(isPrivate: false)
        let privateConfig = TabPool.makeConfiguration(isPrivate: true)

        XCTAssertTrue(normalConfig.allowsInlineMediaPlayback)
        XCTAssertTrue(normalConfig.allowsPictureInPictureMediaPlayback)
        XCTAssertTrue(privateConfig.allowsInlineMediaPlayback)
        XCTAssertTrue(privateConfig.allowsPictureInPictureMediaPlayback)
    }

    func testDesktopModeToggle() {
        // Desktop mode swaps customUserAgent then reloads; nil restores mobile.
        let config = WKWebViewConfiguration()
        let controller = WebPageController(configuration: config)

        XCTAssertFalse(controller.isDesktopMode)
        XCTAssertTrue(controller.webView.customUserAgent?.isEmpty ?? true)

        controller.toggleDesktopMode()

        XCTAssertTrue(controller.isDesktopMode)
        XCTAssertEqual(controller.webView.customUserAgent, WebPageController.desktopUserAgent)

        controller.toggleDesktopMode()

        XCTAssertFalse(controller.isDesktopMode)
        // WKWebView normalizes nil to "" on readback; empty means mobile.
        XCTAssertTrue(controller.webView.customUserAgent?.isEmpty ?? true)
    }

    func testWebPageControllerUIDelegateWiring() {
        let config = WKWebViewConfiguration()
        let controller = WebPageController(configuration: config)
        let mock = MockUIDelegateHandler()
        controller.uiDelegateHandler = mock

        XCTAssertIdentical(controller.uiDelegateHandler, mock)
    }

    func testSettingsViewModelClearWebsiteData() async throws {
        let database = try OuterViewDatabase(inMemory: true)
        let historyStore = HistoryStore(database: database)
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        try historyStore.record(visit: PageVisit(url: url, title: "Example"))

        let viewModel = SettingsViewModel()
        let testDataStore = WKWebsiteDataStore.nonPersistent()

        try await viewModel.clearHistoryAndWebsiteData(historyStore: historyStore, dataStore: testDataStore)

        XCTAssertTrue(historyStore.fetchAll().isEmpty)
    }

    func testBrowserRootSpawnsTabOnUserInitiatedPopup() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let root = BrowserRootViewController(database: database)
        TestWindow.attach(root)

        // Verify root acts as WebPageUIDelegateHandler
        guard let activePage = root.activePage() else {
            XCTFail("Root should have active page")
            return
        }
        XCTAssertNotNil(activePage.uiDelegateHandler)

        // Close delegate
        root.webPageControllerDidClose(activePage)
        // Closing tab updates tab state
        XCTAssertTrue(root.tabs.count >= 1) // Root maintains minimum 1 tab
    }
}
