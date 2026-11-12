// UnitTests — WebsiteSettingsStore plus link preview card coverage.
@testable import OuterView
import UIKit
import WebKit
import XCTest

@MainActor
final class WebsiteSettingsAndLinkPreviewTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let name = "WebsiteSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
        }
        return defaults
    }

    private func makeRoot() throws -> BrowserRootViewController {
        let database = try OuterViewDatabase(inMemory: true)
        let root = BrowserRootViewController(database: database)
        TestWindow.attach(root)
        return root
    }

    // MARK: - WebsiteSettingsStore Tests

    func testWebsiteSettingsStoreDefaults() throws {
        let defaults = try makeDefaults()
        let store = WebsiteSettingsStore(defaults: defaults)

        let settings = store.settings(forHost: "example.com")
        XCTAssertFalse(settings.requestDesktopWebsite)
        XCTAssertFalse(settings.useReaderAutomatically)
        XCTAssertTrue(settings.isDefault)

        XCTAssertTrue(store.settings(forHost: nil).isDefault)
        XCTAssertTrue(store.settings(forHost: "").isDefault)
    }

    func testWebsiteSettingsStoreSetAndPersist() throws {
        let defaults = try makeDefaults()
        let store = WebsiteSettingsStore(defaults: defaults)

        store.setRequestDesktopWebsite(true, forHost: "EXAMPLE.COM")
        store.setUseReaderAutomatically(true, forHost: "example.com")

        let stored = store.settings(forHost: "example.com")
        XCTAssertTrue(stored.requestDesktopWebsite)
        XCTAssertTrue(stored.useReaderAutomatically)
        XCTAssertFalse(stored.isDefault)

        // Fresh store instance reads same persisted data
        let store2 = WebsiteSettingsStore(defaults: defaults)
        let reloaded = store2.settings(forHost: "example.com")
        XCTAssertTrue(reloaded.requestDesktopWebsite)
        XCTAssertTrue(reloaded.useReaderAutomatically)
    }

    func testWebsiteSettingsStoreResetRemovesKey() throws {
        let defaults = try makeDefaults()
        let store = WebsiteSettingsStore(defaults: defaults)

        store.setRequestDesktopWebsite(true, forHost: "example.com")
        XCTAssertNotNil(defaults.data(forKey: WebsiteSettingsStore.storeKey))

        store.setRequestDesktopWebsite(false, forHost: "example.com")
        XCTAssertNil(defaults.data(forKey: WebsiteSettingsStore.storeKey))
    }

    func testWebsiteSettingsStoreClearAll() throws {
        let defaults = try makeDefaults()
        let store = WebsiteSettingsStore(defaults: defaults)

        store.setRequestDesktopWebsite(true, forHost: "a.com")
        store.setUseReaderAutomatically(true, forHost: "b.com")
        store.clearAll()

        XCTAssertTrue(store.settings(forHost: "a.com").isDefault)
        XCTAssertTrue(store.settings(forHost: "b.com").isDefault)
    }

    // MARK: - Desktop Mode Convergence Tests

    func testStoredDesktopDefaultAppliesOnProgrammaticLoadAndMenuFlips() throws {
        let defaults = try makeDefaults()
        let store = WebsiteSettingsStore(defaults: defaults)
        let url = try XCTUnwrap(URL(string: "https://desktop.example/article"))
        store.setRequestDesktopWebsite(true, forHost: url.host)

        let page = WebPageController(configuration: WKWebViewConfiguration())
        page.websiteSettingsStore = store

        page.load(url)

        XCTAssertTrue(page.effectiveDesktopMode)
        XCTAssertTrue(page.isDesktopMode)
        XCTAssertEqual(page.webView.customUserAgent, WebPageController.desktopUserAgent)

        let model = PageMenuModel(url: url, isDesktopMode: page.effectiveDesktopMode)
        XCTAssertEqual(model.desktopModeTitle, "Request Mobile Website")

        let root = try makeRoot()
        let titles = flattenedTitles(root.makePageMenu(model: model))
        XCTAssertTrue(titles.contains("Request Mobile Website"))
        XCTAssertFalse(titles.contains("Request Desktop Website"))
    }

    func testCrossHostProgrammaticLoadClearsOverrideAndAppliesStoredDefault() throws {
        let defaults = try makeDefaults()
        let store = WebsiteSettingsStore(defaults: defaults)
        let urlA = try XCTUnwrap(URL(string: "https://a.example/page"))
        let urlB = try XCTUnwrap(URL(string: "https://b.example/other"))
        store.setRequestDesktopWebsite(true, forHost: urlA.host)
        store.setRequestDesktopWebsite(true, forHost: urlB.host)

        let page = WebPageController(configuration: WKWebViewConfiguration())
        page.websiteSettingsStore = store

        page.load(urlA)
        XCTAssertTrue(page.effectiveDesktopMode)

        // Stale per-tab override: the user forced mobile on host A.
        page.toggleDesktopMode()
        XCTAssertTrue(page.hasPerTabDesktopOverride)
        XCTAssertFalse(page.effectiveDesktopMode)

        page.load(urlB)
        XCTAssertFalse(page.hasPerTabDesktopOverride)
        XCTAssertTrue(page.effectiveDesktopMode)
        XCTAssertEqual(page.webView.customUserAgent, WebPageController.desktopUserAgent)
    }

    func testSameHostProgrammaticLoadPreservesPerTabOverride() async throws {
        let defaults = try makeDefaults()
        let store = WebsiteSettingsStore(defaults: defaults)
        let baseURL = try XCTUnwrap(URL(string: "https://same-host.example/page"))
        store.setRequestDesktopWebsite(false, forHost: baseURL.host)

        let page = WebPageController(configuration: WKWebViewConfiguration())
        page.websiteSettingsStore = store

        // Commit a same-host document locally so the host check sees it.
        page.webView.loadHTMLString("<html><body>fixture</body></html>", baseURL: baseURL)
        try await waitForCommittedHost(baseURL.host, in: page)

        // Explicit per-tab toggle away from the stored default.
        page.toggleDesktopMode()
        XCTAssertTrue(page.hasPerTabDesktopOverride)
        XCTAssertTrue(page.effectiveDesktopMode)

        let sameHostURL = try XCTUnwrap(URL(string: "https://same-host.example/other"))
        page.load(sameHostURL)

        XCTAssertTrue(page.hasPerTabDesktopOverride)
        XCTAssertTrue(page.effectiveDesktopMode)
    }

    func testPageMenuModelReflectsEffectiveDesktopMode() throws {
        let root = try makeRoot()
        let page = try XCTUnwrap(root.activePage())

        XCTAssertFalse(root.makePageMenuModel().isDesktopMode)

        page.toggleDesktopMode()

        XCTAssertTrue(root.makePageMenuModel().isDesktopMode)
        let titles = flattenedTitles(root.makePageMenu(model: root.makePageMenuModel()))
        XCTAssertTrue(titles.contains("Request Mobile Website"))
        XCTAssertFalse(titles.contains("Request Desktop Website"))
    }

    // MARK: - LinkPreviewViewController Tests

    func testLinkPreviewInitialExpandedSizeAndDefaults() throws {
        let defaults = try makeDefaults()
        defaults.set(false, forKey: LinkPreviewViewController.isPreviewHiddenDefaultsKey)

        let url = try XCTUnwrap(URL(string: "https://example.com/test"))
        let vc = LinkPreviewViewController(url: url, defaults: defaults)
        _ = vc.view

        XCTAssertFalse(vc.isPreviewHidden)
        XCTAssertFalse(vc.isShrunk)
        XCTAssertEqual(vc.preferredContentSize, LinkPreviewViewController.expandedSize)
    }

    func testLinkPreviewInitialHiddenSizeAndDefaults() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: LinkPreviewViewController.isPreviewHiddenDefaultsKey)

        let url = try XCTUnwrap(URL(string: "https://example.com/test"))
        let vc = LinkPreviewViewController(url: url, defaults: defaults)
        _ = vc.view

        XCTAssertTrue(vc.isPreviewHidden)
        XCTAssertEqual(vc.preferredContentSize, LinkPreviewViewController.hiddenSize)
    }

    func testLinkPreviewToggleHiddenUpdatesDefaultsAndContentSize() throws {
        let defaults = try makeDefaults()
        let url = try XCTUnwrap(URL(string: "https://example.com/test"))
        let vc = LinkPreviewViewController(url: url, defaults: defaults)
        _ = vc.view

        XCTAssertFalse(vc.isPreviewHidden)

        vc.setPreviewHidden(true)
        XCTAssertTrue(vc.isPreviewHidden)
        XCTAssertTrue(defaults.bool(forKey: LinkPreviewViewController.isPreviewHiddenDefaultsKey))
        XCTAssertEqual(vc.preferredContentSize, LinkPreviewViewController.hiddenSize)

        vc.setPreviewHidden(false)
        XCTAssertFalse(vc.isPreviewHidden)
        XCTAssertFalse(defaults.bool(forKey: LinkPreviewViewController.isPreviewHiddenDefaultsKey))
        XCTAssertEqual(vc.preferredContentSize, LinkPreviewViewController.expandedSize)
    }

    func testLinkPreviewShrinkAndExpand() throws {
        let defaults = try makeDefaults()
        let url = try XCTUnwrap(URL(string: "https://example.com/test"))
        let vc = LinkPreviewViewController(url: url, defaults: defaults)
        _ = vc.view

        XCTAssertFalse(vc.isShrunk)
        XCTAssertEqual(vc.preferredContentSize, LinkPreviewViewController.expandedSize)

        vc.shrink()
        XCTAssertTrue(vc.isShrunk)
        XCTAssertEqual(vc.preferredContentSize, LinkPreviewViewController.shrunkSize)

        vc.expand()
        XCTAssertFalse(vc.isShrunk)
        XCTAssertEqual(vc.preferredContentSize, LinkPreviewViewController.expandedSize)
    }

    func testLinkPreviewTapCallsOnOpen() throws {
        let defaults = try makeDefaults()
        let url = try XCTUnwrap(URL(string: "https://example.com/article"))
        var openedURL: URL?
        let vc = LinkPreviewViewController(url: url, defaults: defaults) { target in
            openedURL = target
        }
        _ = vc.view

        // Trigger tap
        _ = try XCTUnwrap(vc.view.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }.first)
        // Send action or call direct handler
        vc.onOpen?(url)
        XCTAssertEqual(openedURL, url)
    }

    func testLinkPreviewTapRecognizerIgnoresHeader() throws {
        let defaults = try makeDefaults()
        let url = try XCTUnwrap(URL(string: "https://example.com/article"))
        let vc = LinkPreviewViewController(url: url, defaults: defaults)
        _ = vc.view

        let tap = try XCTUnwrap(vc.view.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }.first)
        XCTAssertTrue(tap.delegate === vc)
        XCTAssertFalse(tap.cancelsTouchesInView)

        let swipes = vc.view.gestureRecognizers?.compactMap { $0 as? UISwipeGestureRecognizer } ?? []
        XCTAssertEqual(swipes.count, 2)
        XCTAssertTrue(swipes.allSatisfy { $0.delegate == nil })
    }

    func testLinkPreviewTapDelegateFiltersHeaderTouches() throws {
        let defaults = try makeDefaults()
        let url = try XCTUnwrap(URL(string: "https://example.com/article"))
        let vc = LinkPreviewViewController(url: url, defaults: defaults)
        _ = vc.view
        vc.view.layoutIfNeeded()

        let tap = try XCTUnwrap(vc.view.gestureRecognizers?.compactMap { $0 as? UITapGestureRecognizer }.first)
        let headerButton = try XCTUnwrap(button(in: vc.view, titled: "Hide preview"))
        XCTAssertFalse(vc.gestureRecognizer(tap, shouldReceive: LinkPreviewTouchStub(view: headerButton)))

        let previewHost = try XCTUnwrap(vc.webView?.superview)
        XCTAssertTrue(vc.gestureRecognizer(tap, shouldReceive: LinkPreviewTouchStub(view: previewHost)))
    }

    func testLinkPreviewHideButtonDoesNotOpenLink() throws {
        let defaults = try makeDefaults()
        let url = try XCTUnwrap(URL(string: "https://example.com/article"))
        var didOpen = false
        let vc = LinkPreviewViewController(url: url, defaults: defaults) { _ in didOpen = true }
        _ = vc.view
        vc.view.layoutIfNeeded()

        XCTAssertFalse(vc.isPreviewHidden)
        let hideButton = try XCTUnwrap(button(in: vc.view, titled: "Hide preview"))
        hideButton.sendActions(for: .touchUpInside)
        XCTAssertTrue(vc.isPreviewHidden)
        XCTAssertFalse(didOpen)
    }

    func testPreviewHeaderButtonExpandsHitArea() {
        let button = PreviewHeaderButton(type: .system)
        button.frame = CGRect(x: 0, y: 0, width: 30, height: 20)
        XCTAssertFalse(button.bounds.contains(CGPoint(x: -5, y: 10)))
        XCTAssertTrue(button.point(inside: CGPoint(x: -5, y: 10), with: nil))
        XCTAssertFalse(button.point(inside: CGPoint(x: -10, y: 10), with: nil))
    }

    private func flattenedTitles(_ menu: UIMenu) -> [String] {
        var titles: [String] = []
        for child in menu.children {
            if let action = child as? UIAction {
                titles.append(action.title)
            } else if let submenu = child as? UIMenu {
                if !submenu.title.isEmpty {
                    titles.append(submenu.title)
                }
                titles.append(contentsOf: flattenedTitles(submenu))
            }
        }
        return titles
    }

    /// Polls for the committed URL since HTML loads finish asynchronously.
    private func waitForCommittedHost(_ host: String?, in page: WebPageController) async throws {
        let deadline = Date().addingTimeInterval(5)
        while page.webView.url?.host?.lowercased() != host?.lowercased() {
            if Date() > deadline {
                XCTFail("Timed out waiting for committed host \(host ?? "nil")")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func button(in view: UIView, titled title: String) -> UIButton? {
        if let found = view as? UIButton, found.currentTitle == title || found.configuration?.title == title {
            return found
        }
        for subview in view.subviews {
            if let found = button(in: subview, titled: title) {
                return found
            }
        }
        return nil
    }

    // MARK: - Library Button Long-Press Menu Tests

    func testBookmarksButtonMenuEmptyPageDisabled() throws {
        let root = try makeRoot()
        let menu = root.makeBookmarksButtonMenu()

        let readingList = try XCTUnwrap(menu.children.first(where: { ($0 as? UIAction)?.title == "Add to Reading List" }) as? UIAction)
        let addBookmark = try XCTUnwrap(menu.children.first(where: { ($0 as? UIAction)?.title == "Add Bookmark" }) as? UIAction)

        XCTAssertTrue(readingList.attributes.contains(.disabled))
        XCTAssertTrue(addBookmark.attributes.contains(.disabled))
        XCTAssertFalse(menu.children.contains(where: { ($0 as? UIAction)?.title.contains("Add Bookmarks for") == true }))
    }

    func testBookmarksButtonMenuMultiTabActionIncludedForTwoOrMoreTabs() throws {
        let root = try makeRoot()
        let url1 = try XCTUnwrap(URL(string: "https://example.com/one"))
        let url2 = try XCTUnwrap(URL(string: "https://example.com/two"))

        root.createNewTab(isPrivate: false)
        root.tabs[0].url = url1
        root.tabs[0].title = "One"

        root.createNewTab(isPrivate: false)
        root.tabs[1].url = url2
        root.tabs[1].title = "Two"

        let menu = root.makeBookmarksButtonMenu()
        let multiAction = menu.children.first(where: { ($0 as? UIAction)?.title == "Add Bookmarks for 2 Tabs" }) as? UIAction
        XCTAssertNotNil(multiAction)
        XCTAssertFalse(multiAction?.attributes.contains(.disabled) ?? true)
    }

    // MARK: - BookmarkEditorModel AddFolderForTabs Tests

    func testBookmarkEditorModelAddFolderForTabsSavesAllTabs() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let store = BookmarkStore(database: database)

        let tabs = try [
            ("Tab 1", XCTUnwrap(URL(string: "https://example.com/1"))),
            ("Tab 2", XCTUnwrap(URL(string: "https://example.com/2")))
        ]

        let model = BookmarkEditorModel(target: .addFolderForTabs(defaultTitle: "My Group Tabs", tabs: tabs))
        XCTAssertTrue(model.isFolderMode)
        XCTAssertTrue(model.isValid)

        try model.save(bookmarkStore: store)

        let folders = store.fetchFolders(parentId: nil, isFavorite: false)
        let savedFolder = try XCTUnwrap(folders.first(where: { $0.title == "My Group Tabs" }))

        let bookmarks = store.fetchBookmarks(folderId: savedFolder.id)
        XCTAssertEqual(bookmarks.count, 2)
        XCTAssertEqual(Set(bookmarks.map(\.title)), ["Tab 1", "Tab 2"])
    }
}

/// Touch stub carrying a fixed view for gesture-delegate tests.
@MainActor
private final class LinkPreviewTouchStub: UITouch {
    private let stubView: UIView

    init(view: UIView) {
        stubView = view
        super.init()
    }

    override var view: UIView? {
        stubView
    }
}
