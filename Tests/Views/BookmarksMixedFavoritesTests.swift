// Tests — Coverage for the mixed Favorites single-section list and its reorder persistence.

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class BookmarksMixedFavoritesTests: XCTestCase {
    private enum Fixture {
        static let urlA = URL(string: "https://example.com/a")!
        static let urlB = URL(string: "https://example.com/b")!
    }

    func testFavoritesSectionIsSingleMixedListWhileBookmarksSectionPreservesSeparation() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let bookmarkStore = BookmarkStore(database: database)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "BookmarksMixedFavoritesTests-\(UUID())"))

        // Add root items: 1 favorite folder, 1 regular folder, 1 favorite bookmark, 1 regular bookmark
        let favFolder = try bookmarkStore.createFolder(title: "Fav Folder", isFavorite: true, sortOrder: 0)
        _ = try bookmarkStore.createFolder(title: "Normal Folder", isFavorite: false, sortOrder: 1)
        let favBookmark = try XCTUnwrap(bookmarkStore.add(title: "Fav Link", url: Fixture.urlA, isFavorite: true, sortOrder: 2))
        _ = try XCTUnwrap(bookmarkStore.add(title: "Normal Link", url: Fixture.urlB, isFavorite: false, sortOrder: 3))

        let browser = BookmarksBrowserView(bookmarkStore: bookmarkStore, defaults: defaults)
        let table = browser.tableView

        // 1. In Bookmarks section (root)
        XCTAssertFalse(browser.isViewingFavorites)
        // Root Bookmarks has 3 sections: PinnedFavorites (0), Folders (1), Bookmarks (2)
        XCTAssertEqual(browser.numberOfSections(in: table), 3)
        XCTAssertEqual(browser.sectionType(for: 0), .pinnedFavorites)
        XCTAssertEqual(browser.sectionType(for: 1), .folders)
        XCTAssertEqual(browser.sectionType(for: 2), .bookmarks)

        // 2. Navigate to Favorites
        table.delegate?.tableView?(table, didSelectRowAt: IndexPath(row: 0, section: 0))
        XCTAssertTrue(browser.isViewingFavorites)

        // In Favorites: single mixed section (.combinedItems)
        XCTAssertEqual(browser.numberOfSections(in: table), 1)
        XCTAssertEqual(browser.sectionType(for: 0), .combinedItems)
        XCTAssertEqual(browser.tableView(table, numberOfRowsInSection: 0), 2) // favFolder + favBookmark

        // Row 0 should be favFolder (sortOrder 0), Row 1 should be favBookmark (sortOrder 2)
        XCTAssertEqual(browser.visibleFolderID(at: IndexPath(row: 0, section: 0)), favFolder.id)
        XCTAssertEqual(browser.visibleBookmarkID(at: IndexPath(row: 1, section: 0)), favBookmark.id)
    }

    func testReorderingMixedFavoritesUpdatesPersistenceAndStartPage() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let bookmarkStore = BookmarkStore(database: database)
        let historyStore = HistoryStore(database: database)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "BookmarksMixedFavoritesTests-Reorder-\(UUID())"))

        let folder = try bookmarkStore.createFolder(title: "Folder 1", isFavorite: true, sortOrder: 0)
        let bookmark = try XCTUnwrap(bookmarkStore.add(title: "Link 1", url: Fixture.urlA, isFavorite: true, sortOrder: 1))

        let browser = BookmarksBrowserView(bookmarkStore: bookmarkStore, defaults: defaults)
        let table = browser.tableView

        // Enter Favorites
        table.delegate?.tableView?(table, didSelectRowAt: IndexPath(row: 0, section: 0))
        XCTAssertTrue(browser.isViewingFavorites)

        // Can move in combinedItems when sort mode is none
        XCTAssertTrue(browser.tableView(table, canMoveRowAt: IndexPath(row: 0, section: 0)))
        XCTAssertTrue(browser.tableView(table, canMoveRowAt: IndexPath(row: 1, section: 0)))

        // Move bookmark (row 1) ahead of folder (row 0)
        table.dataSource?.tableView?(
            table,
            moveRowAt: IndexPath(row: 1, section: 0),
            to: IndexPath(row: 0, section: 0)
        )

        // Now row 0 should be bookmark, row 1 should be folder
        XCTAssertEqual(browser.visibleBookmarkID(at: IndexPath(row: 0, section: 0)), bookmark.id)
        XCTAssertEqual(browser.visibleFolderID(at: IndexPath(row: 1, section: 0)), folder.id)

        // StartPageViewModel should reflect this order
        let startPageVM = StartPageViewModel(bookmarkStore: bookmarkStore, historyStore: historyStore)
        XCTAssertEqual(startPageVM.favoriteItems.count, 2)
        XCTAssertEqual(startPageVM.favoriteItems[0].id, bookmark.id)
        XCTAssertEqual(startPageVM.favoriteItems[1].id, folder.id)
    }
}
