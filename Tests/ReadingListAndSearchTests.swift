//
//  ReadingListAndSearchTests.swift
//  OuterViewTests
//

@testable import OuterView
import XCTest

@MainActor
final class ReadingListAndSearchTests: XCTestCase {
    private func makeDatabase() throws -> OuterViewDatabase {
        try OuterViewDatabase(inMemory: true)
    }

    private func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "ReadingListAndSearchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    // MARK: - SentenceExtractor Tests

    func testSentenceExtractorSingleSentence() {
        let input = "This is a single sentence."
        let result = SentenceExtractor.firstSentences(from: input, maxCount: 2)
        XCTAssertEqual(result, "This is a single sentence.")
    }

    func testSentenceExtractorTakesAtMostTwoSentences() {
        let input = "Sentence one. Sentence two! Sentence three? Sentence four."
        let result = SentenceExtractor.firstSentences(from: input, maxCount: 2)
        XCTAssertEqual(result, "Sentence one. Sentence two!")
    }

    func testSentenceExtractorHandlesAbbreviations() {
        let input = "Dr. Smith arrived in the U.S. yesterday. He visited the library today. The trip was great."
        let result = SentenceExtractor.firstSentences(from: input, maxCount: 2)
        XCTAssertTrue(result.contains("yesterday."))
        XCTAssertTrue(result.contains("today."))
        XCTAssertFalse(result.contains("great."))
    }

    func testSentenceExtractorEmptyAndWhitespace() {
        XCTAssertEqual(SentenceExtractor.firstSentences(from: ""), "")
        XCTAssertEqual(SentenceExtractor.firstSentences(from: "   \n\t  "), "")
    }

    func testSentenceExtractorClampsAtMaxLength() {
        let input = String(repeating: "word ", count: 100) + "."
        let result = SentenceExtractor.firstSentences(from: input, maxCount: 2, maxLength: 50)
        XCTAssertLessThanOrEqual(result.count, 50)
    }

    // MARK: - ReadingListView Display Modes & Filters

    func testReadingListViewDisplayModeToggle() throws {
        let database = try makeDatabase()
        let store = ReadingListStore(database: database)
        let view = try ReadingListView(store: store, defaults: makeIsolatedDefaults())

        XCTAssertEqual(view.displayMode, .compact)
        view.setDisplayMode(.large)
        XCTAssertEqual(view.displayMode, .large)
        view.setDisplayMode(.compact)
        XCTAssertEqual(view.displayMode, .compact)
    }

    func testReadingListViewFilterModeToggle() throws {
        let database = try makeDatabase()
        let store = ReadingListStore(database: database)
        let item1 = try XCTUnwrap(try store.add(title: "Unread Item", url: XCTUnwrap(URL(string: "https://a.com"))))
        let item2 = try XCTUnwrap(try store.add(title: "Read Item", url: XCTUnwrap(URL(string: "https://b.com"))))
        try store.setRead(id: item2.id, isRead: true)

        let view = try ReadingListView(store: store, defaults: makeIsolatedDefaults())
        XCTAssertEqual(view.filterMode, .all)
        XCTAssertFalse(item1.isRead)
        XCTAssertTrue(item2.isRead)

        view.setFilterMode(.unreadOnly)
        XCTAssertEqual(view.filterMode, .unreadOnly)

        view.setFilterMode(.all)
        XCTAssertEqual(view.filterMode, .all)
    }

    func testReadingListViewSelectionModeAndBatchDelete() throws {
        let database = try makeDatabase()
        let store = ReadingListStore(database: database)
        let item1 = try XCTUnwrap(try store.add(title: "Item 1", url: XCTUnwrap(URL(string: "https://one.com"))))
        let item2 = try XCTUnwrap(try store.add(title: "Item 2", url: XCTUnwrap(URL(string: "https://two.com"))))

        let view = try ReadingListView(store: store, defaults: makeIsolatedDefaults())
        XCTAssertFalse(view.isSelectionMode)

        var selectionModeNotified = false
        view.onSelectionModeChanged = { isSelected in
            selectionModeNotified = isSelected
        }

        view.enterSelectionMode()
        XCTAssertTrue(view.isSelectionMode)
        XCTAssertTrue(selectionModeNotified)

        // In store.fetchAll(), items are sorted newest-first, so item2 is row 0 and item1 is row 1.
        let tableView = try XCTUnwrap(view.subviews.compactMap { $0 as? UITableView }.first)
        view.tableView(tableView, didSelectRowAt: IndexPath(row: 0, section: 0))
        XCTAssertTrue(view.hasSelectedItems)
        XCTAssertTrue(view.selectedItemIDs.contains(item2.id))

        // Delete selected items
        view.deleteSelectedItems()
        XCTAssertFalse(view.hasSelectedItems)
        XCTAssertEqual(store.count(), 1)
        XCTAssertEqual(store.fetchAll().first?.id, item1.id)

        view.exitSelectionMode()
        XCTAssertFalse(view.isSelectionMode)
    }

    func testReadingListMenuConstruction() throws {
        let database = try makeDatabase()
        let store = ReadingListStore(database: database)
        let view = try ReadingListView(store: store, defaults: makeIsolatedDefaults())

        let menu = view.makeMenu()
        XCTAssertEqual(menu.children.count, 3) // displaySection, filterSection, actionsSection
    }

    // MARK: - Search Filtering Tests

    func testBookmarksSearchFiltersTitleAndURL() throws {
        let database = try makeDatabase()
        let store = BookmarkStore(database: database)
        try store.add(title: "Swift Programming", url: XCTUnwrap(URL(string: "https://swift.org")))
        try store.add(title: "Apple Developer", url: XCTUnwrap(URL(string: "https://developer.apple.com")))
        try store.add(title: "GitHub Home", url: XCTUnwrap(URL(string: "https://github.com")))

        let view = BookmarksBrowserView(bookmarkStore: store)
        let tableView = try XCTUnwrap(view.subviews.compactMap { $0 as? UITableView }.first)
        let searchHeader = tableView.tableHeaderView as? LibrarySearchHeaderView
        XCTAssertNotNil(searchHeader)

        // Search for "swift"
        try searchHeader?.searchBar.delegate?.searchBar?(XCTUnwrap(searchHeader?.searchBar), textDidChange: "swift")
        XCTAssertEqual(view.tableView(tableView, numberOfRowsInSection: 0), 1)

        // Search for "apple.com" URL match
        try searchHeader?.searchBar.delegate?.searchBar?(XCTUnwrap(searchHeader?.searchBar), textDidChange: "apple.com")
        XCTAssertEqual(view.tableView(tableView, numberOfRowsInSection: 0), 1)

        // Cancel search restores normal sections
        try searchHeader?.searchBar.delegate?.searchBarCancelButtonClicked?(XCTUnwrap(searchHeader?.searchBar))
        XCTAssertEqual(view.numberOfSections(in: tableView), 3) // pinnedFavorites, folders, bookmarks
    }

    func testHistorySearchFiltersEntries() throws {
        let database = try makeDatabase()
        let store = HistoryStore(database: database)
        try store.record(visit: PageVisit(url: XCTUnwrap(URL(string: "https://news.ycombinator.com")), title: "Hacker News"))
        try store.record(visit: PageVisit(url: XCTUnwrap(URL(string: "https://reddit.com")), title: "Reddit: Front page"))
        try store.record(visit: PageVisit(url: XCTUnwrap(URL(string: "https://lobste.rs")), title: "Lobsters"))

        let view = HistoryListView(historyStore: store)
        let tableView = try XCTUnwrap(view.subviews.compactMap { $0 as? UITableView }.first)
        let searchHeader = tableView.tableHeaderView as? LibrarySearchHeaderView
        XCTAssertNotNil(searchHeader)

        // Search for "hacker"
        try searchHeader?.searchBar.delegate?.searchBar?(XCTUnwrap(searchHeader?.searchBar), textDidChange: "hacker")
        XCTAssertEqual(view.searchQuery, "hacker")
        XCTAssertGreaterThan(view.numberOfSections(in: tableView), 0)
        XCTAssertEqual(view.tableView(tableView, numberOfRowsInSection: 0), 1)

        // Clear query restores all history
        try searchHeader?.searchBar.delegate?.searchBarCancelButtonClicked?(XCTUnwrap(searchHeader?.searchBar))
        XCTAssertEqual(view.searchQuery, "")
    }
}
