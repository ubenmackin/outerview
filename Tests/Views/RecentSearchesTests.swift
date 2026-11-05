// Bookmarks — Recent searches rendering plus library first-tab and suggestion grouping tests.

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class RecentSearchesTests: XCTestCase {
    private func makeDatabase() throws -> OuterViewDatabase {
        try OuterViewDatabase(inMemory: true)
    }

    func testRecentSearchesViewRendersEntries() throws {
        let database = try makeDatabase()
        let store = RecentSearchStore(database: database)
        try store.record(query: "swiftui")
        try store.record(query: "apple")

        let view = RecentSearchesView(recentSearchStore: store)
        view.frame = CGRect(x: 0, y: 0, width: 360, height: 600)
        TestWindow.attach(view)

        let table = try XCTUnwrap(view.subviews.compactMap { $0 as? UITableView }.first)
        XCTAssertEqual(table.numberOfRows(inSection: 0), 2)
    }

    func testLibraryTabBarDynamicIcon() {
        let tabBar = LibraryTabBar()
        tabBar.frame = CGRect(x: 0, y: 0, width: 360, height: 44)
        TestWindow.attach(tabBar)

        tabBar.setStartPageIcon(isSearching: true)
        tabBar.setStartPageIcon(isSearching: false)
    }

    func testBookmarksLibraryFirstTabModeLifecycle() throws {
        let database = try makeDatabase()
        let bookmarkStore = BookmarkStore(database: database)
        let historyStore = HistoryStore(database: database)
        let readingListStore = ReadingListStore(database: database)
        let recentSearchStore = RecentSearchStore(database: database)

        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let library = BookmarksLibraryView(defaults: defaults)
        library.frame = CGRect(x: 0, y: 0, width: 360, height: 600)
        TestWindow.attach(library)
        library.configureStores(
            bookmarkStore: bookmarkStore,
            historyStore: historyStore,
            readingListStore: readingListStore,
            recentSearchStore: recentSearchStore
        )

        // Initial state is Start Page
        XCTAssertEqual(library.firstTabMode, .startPage)

        // Show recent searches
        library.showRecentSearches()
        XCTAssertEqual(library.firstTabMode, .recentSearches)
        XCTAssertEqual(library.activeTab, .startPage)
        XCTAssertFalse(try XCTUnwrap(library.recentSearchesView).isHidden)
        XCTAssertTrue(try XCTUnwrap(library.startPageView).isHidden)

        // Switch to bookmarks tab, then back to start page
        library.open(tab: .bookmarks)
        XCTAssertEqual(library.firstTabMode, .startPage)
        XCTAssertEqual(library.activeTab, .bookmarks)

        library.open(tab: .startPage)
        XCTAssertEqual(library.firstTabMode, .startPage)
        XCTAssertFalse(try XCTUnwrap(library.startPageView).isHidden)
        XCTAssertTrue(try XCTUnwrap(library.recentSearchesView).isHidden)
    }

    func testAddressEditorSectionedSuggestions() throws {
        let editor = AddressEditorView(frame: CGRect(x: 0, y: 0, width: 360, height: 600))
        TestWindow.attach(editor)

        let tabID = UUID()
        let suggestions: [Suggestion] = try [
            Suggestion(kind: .googleSuggest(query: "google search")),
            Suggestion(kind: .openTab(title: "Apple", url: XCTUnwrap(URL(string: "https://apple.com")), tabID: tabID)),
            Suggestion(kind: .site(title: "Google", url: XCTUnwrap(URL(string: "https://google.com")), isFavorite: true))
        ]

        editor.setSuggestions(suggestions)
        XCTAssertEqual(editor.suggestionSections.count, 2)
        XCTAssertEqual(editor.suggestionSections[0].title, "Google Suggestions")
        XCTAssertEqual(editor.suggestionSections[0].items.count, 1)
        XCTAssertEqual(editor.suggestionSections[1].title, "Bookmarks, History, and Tabs")
        XCTAssertEqual(editor.suggestionSections[1].items.count, 2)
    }
}
