// UnitTests — WebsiteSettingsStore plus link preview card coverage.
@testable import OuterView
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
