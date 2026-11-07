// Privacy — Biometric plus blocker plus closed-tabs feature tests.

@testable import OuterView
import WebKit
import XCTest

@MainActor
final class MockBiometricAuthService: BiometricAuthenticating {
    var isAvailable: Bool = true
    var shouldSucceed: Bool = true
    var authenticateCallCount: Int = 0
    var lastReason: String?

    func authenticate(reason: String) async -> Bool {
        authenticateCallCount += 1
        lastReason = reason
        return shouldSucceed
    }
}

@MainActor
final class Phase2FeaturesTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let name = "Phase2FeaturesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
        }
        return defaults
    }

    private func makeRoot(defaults: UserDefaults? = nil) throws -> (BrowserRootViewController, MockBiometricAuthService) {
        let database = try OuterViewDatabase(inMemory: true)
        let defs = try defaults ?? makeDefaults()
        let root = BrowserRootViewController(database: database, defaults: defs)
        let mockBiometrics = MockBiometricAuthService()
        root.biometricAuthService = mockBiometrics
        TestWindow.attach(root)
        return (root, mockBiometrics)
    }

    // MARK: - Biometric Gating Tests

    func testBiometricGatingRequiresBiometricsOnlyWhenPrivateTabsExist() async throws {
        let defaults = try makeDefaults()
        let (root, mockBiometrics) = try makeRoot(defaults: defaults)

        // Initially only standard tabs (or no tabs)
        XCTAssertFalse(root.tabs.contains(where: \.isPrivate))
        XCTAssertFalse(root.shouldRequireBiometricsForPrivateMode)

        // Switching to private mode when no private tabs exist does not trigger auth
        root.switchToPrivateMode()
        XCTAssertEqual(mockBiometrics.authenticateCallCount, 0)
        XCTAssertEqual(root.overviewMode, .privateMode)

        // Add a private tab
        root.createNewTab(isPrivate: true)
        XCTAssertTrue(root.tabs.contains(where: \.isPrivate))
        XCTAssertTrue(root.shouldRequireBiometricsForPrivateMode)

        // Switch to standard mode
        root.switchToStandardMode()
        XCTAssertEqual(root.overviewMode, .standard)

        // Now switching to private mode with private tabs present MUST trigger authentication
        mockBiometrics.shouldSucceed = true
        root.switchToPrivateMode()
        // Await the gated auth Task before asserting mode plus call count.
        for _ in 0 ..< 100 {
            if mockBiometrics.authenticateCallCount == 1, root.overviewMode == .privateMode {
                break
            }
            await Task.yield()
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(mockBiometrics.authenticateCallCount, 1)
        XCTAssertEqual(root.overviewMode, .privateMode)
    }

    func testBiometricAuthFailurePreventsPrivateModeSwitch() async throws {
        let (root, mockBiometrics) = try makeRoot()
        root.createNewTab(isPrivate: true)
        root.switchToStandardMode()
        XCTAssertEqual(root.overviewMode, .standard)

        mockBiometrics.shouldSucceed = false
        root.tabOverview(root.overviewController, didChangeMode: .privateMode)

        // Await the gated auth Task so failure handling settles before asserting.
        for _ in 0 ..< 100 {
            if mockBiometrics.authenticateCallCount == 1 {
                await Task.yield()
                try await Task.sleep(nanoseconds: 10_000_000)
                if root.overviewMode == .standard {
                    break
                }
            } else {
                await Task.yield()
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }

        XCTAssertEqual(mockBiometrics.authenticateCallCount, 1)
        XCTAssertEqual(root.overviewMode, .standard)
    }

    func testBiometricDisabledInSettingsBypassesAuth() throws {
        let defaults = try makeDefaults()
        defaults.set(false, forKey: SettingsViewModel.requireBiometricsDefaultsKey)
        let (root, mockBiometrics) = try makeRoot(defaults: defaults)

        root.createNewTab(isPrivate: true)
        XCTAssertFalse(root.isBiometricAuthEnabled)
        XCTAssertFalse(root.shouldRequireBiometricsForPrivateMode)

        root.switchToStandardMode()
        root.switchToPrivateMode()
        XCTAssertEqual(mockBiometrics.authenticateCallCount, 0)
        XCTAssertEqual(root.overviewMode, .privateMode)
    }

    // MARK: - Recently Closed Tabs Tests

    func testRecentlyClosedTabsRecordsStandardAndRestores() throws {
        let (root, _) = try makeRoot()
        let url = try XCTUnwrap(URL(string: "https://example.com/test"))
        root.openInNewTab(url: url)

        guard let openedTab = root.tabs.first(where: { $0.url == url }) else {
            XCTFail("Tab not found")
            return
        }

        XCTAssertEqual(root.recentlyClosedTabs.count, 0)
        root.closeTab(id: openedTab.id, replacementIfEmpty: nil)

        XCTAssertEqual(root.recentlyClosedTabs.count, 1)
        let closed = root.recentlyClosedTabs[0]
        XCTAssertEqual(closed.url, url)

        // Restore tab
        root.restoreRecentlyClosedTab(closed)
        XCTAssertEqual(root.recentlyClosedTabs.count, 0)
        XCTAssertTrue(root.tabs.contains(where: { $0.url == url }))
    }

    func testRecentlyClosedTabsIgnoresPrivateTabs() throws {
        let (root, _) = try makeRoot()
        root.createNewTab(isPrivate: true)
        guard let privateTab = root.tabs.first(where: { $0.isPrivate }) else {
            XCTFail("Private tab not found")
            return
        }
        root.closeTab(id: privateTab.id, replacementIfEmpty: nil)
        XCTAssertEqual(root.recentlyClosedTabs.count, 0)
    }

    func testRecentlyClosedMenuHierarchy() throws {
        let (root, _) = try makeRoot()
        let emptyMenu = root.makeRecentlyClosedMenu()
        XCTAssertEqual(emptyMenu.children.count, 1)
        let emptyAction = try XCTUnwrap(emptyMenu.children.first as? UIAction)
        XCTAssertEqual(emptyAction.title, "No Recently Closed Tabs")
        XCTAssertTrue(emptyAction.attributes.contains(.disabled))

        let url = try XCTUnwrap(URL(string: "https://example.com/abc"))
        root.openInNewTab(url: url)
        if let tab = root.tabs.first(where: { $0.url == url }) {
            root.closeTab(id: tab.id, replacementIfEmpty: nil)
        }

        let populatedMenu = root.makeRecentlyClosedMenu()
        XCTAssertEqual(populatedMenu.children.count, 1)
        let restoreAction = try XCTUnwrap(populatedMenu.children.first as? UIAction)
        XCTAssertEqual(restoreAction.title, "example.com")
        XCTAssertFalse(restoreAction.attributes.contains(.disabled))
    }

    // MARK: - Reading List Web Archive Tests

    func testReadingListArchiveManagerSaveAndLifecycle() {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tmpDir)
        }
        let manager = ReadingListArchiveManager(directoryURL: tmpDir)
        let id = UUID()
        let dummyData = Data("<html><body>Offline Content</body></html>".utf8)

        XCTAssertFalse(manager.hasArchive(for: id))
        XCTAssertNil(manager.archiveData(for: id))

        manager.saveArchive(data: dummyData, for: id)
        XCTAssertTrue(manager.hasArchive(for: id))
        XCTAssertEqual(manager.archiveData(for: id), dummyData)

        manager.deleteArchive(for: id)
        XCTAssertFalse(manager.hasArchive(for: id))
        XCTAssertNil(manager.archiveData(for: id))
    }

    // MARK: - Content Blocker Service Tests

    func testContentBlockerServiceCompilation() async {
        let service = ContentBlockerService.shared
        let rules = await service.loadOrCompileRules()
        XCTAssertNotNil(rules)
        XCTAssertNotNil(service.compiledRuleList)

        // Repeat call hits cached instance
        let cached = await service.loadOrCompileRules()
        XCTAssertEqual(rules, cached)

        let controller = WKUserContentController()
        await service.applyRules(to: controller, enabled: true)
        await service.applyRules(to: controller, enabled: false)
    }

    // MARK: - Print & PDF Integration Tests

    func testPrintFormatterAvailableOnWebPage() {
        let page = WebPageController(configuration: WKWebViewConfiguration())
        let formatter = page.webView.viewPrintFormatter()
        XCTAssertNotNil(formatter)
    }
}
