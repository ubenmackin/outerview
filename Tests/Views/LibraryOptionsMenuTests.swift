// Bookmarks & History — Safari inner-display (`•••`) options menu, display density, sorting, folders-on-top, and multi-selection tests.

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class LibraryOptionsMenuTests: XCTestCase {
    private struct RegularRootFixture {
        let parent: UIViewController
        let root: BrowserRootViewController
        let defaults: UserDefaults
    }

    private func makeRegularRoot() throws -> RegularRootFixture {
        let database = try OuterViewDatabase(inMemory: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let root = BrowserRootViewController(database: database, defaults: defaults)
        let parent = UIViewController()
        let innerFrame = CGRect(x: 0, y: 0, width: 951, height: 669)
        TestWindow.attach(parent, frame: innerFrame)
        parent.addChild(root)
        root.traitOverrides.horizontalSizeClass = .regular
        parent.view.addSubview(root.view)
        root.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            root.view.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
            root.view.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
            root.view.topAnchor.constraint(equalTo: parent.view.topAnchor),
            root.view.bottomAnchor.constraint(equalTo: parent.view.bottomAnchor)
        ])
        root.didMove(toParent: parent)
        parent.view.layoutIfNeeded()
        root.applyStructuralLayout()
        root.view.layoutIfNeeded()
        return RegularRootFixture(parent: parent, root: root, defaults: defaults)
    }

    func testHistorySelectWebsitesBatchDeletesSelectedEntriesAndExitsWithDone() throws {
        let fixture = try makeRegularRoot()
        let root = fixture.root
        let historyStore = try XCTUnwrap(root.historyStore)
        let appleURL = try XCTUnwrap(URL(string: "https://apple.com"))
        let devURL = try XCTUnwrap(URL(string: "https://developer.apple.com"))
        let now = Date()
        try historyStore.record(visit: PageVisit(url: appleURL, title: "Apple", visitedAt: now.addingTimeInterval(-60)))
        try historyStore.record(visit: PageVisit(url: devURL, title: "Developer", visitedAt: now))

        root.openBookmarksLibrary(tab: .history)
        root.view.layoutIfNeeded()
        let library = root.bookmarksLibraryView
        let historyView = try XCTUnwrap(library.historyListView)

        let actions = library.currentOptionsMenu?.children.compactMap { $0 as? UIAction } ?? []
        XCTAssertEqual(actions.map(\.title), ["Select Websites", "Clear History…"])
        XCTAssertFalse(actions[0].attributes.contains(.disabled))
        XCTAssertFalse(actions[1].attributes.contains(.disabled))

        library.enterHistorySelectionMode()
        XCTAssertTrue(library.isHistoryInSelectionMode)
        XCTAssertFalse(library.isOptionsMenuVisible)
        XCTAssertTrue(library.isInlineDeleteVisible)
        XCTAssertFalse(library.isInlineDeleteEnabled)
        XCTAssertEqual(library.closeButtonAccessibilityLabel, "Done")
        XCTAssertFalse(library.hasAnyVisibleButtonTitle)

        let firstRow = IndexPath(row: 0, section: 0)
        historyView.tableView.layoutIfNeeded()
        let cellBefore = try XCTUnwrap(
            historyView.tableView.dataSource?.tableView(historyView.tableView, cellForRowAt: firstRow) as? LibrarySubtitleCell
        )
        XCTAssertTrue(cellBefore.isShowingSelectionIndicator)
        XCTAssertFalse(cellBefore.isSelectionIndicatorChecked)

        historyView.tableView.delegate?.tableView?(historyView.tableView, didSelectRowAt: firstRow)
        XCTAssertEqual(historyView.selectedEntryIDs.count, 1)
        XCTAssertTrue(library.isInlineDeleteEnabled)
        let cellAfter = try XCTUnwrap(
            historyView.tableView.dataSource?.tableView(historyView.tableView, cellForRowAt: firstRow) as? LibrarySubtitleCell
        )
        XCTAssertTrue(cellAfter.isSelectionIndicatorChecked)

        library.performInlineDelete()
        let remaining = historyStore.fetchAll()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.url, appleURL)
        XCTAssertTrue(library.isHistoryInSelectionMode)
        XCTAssertFalse(library.isInlineDeleteEnabled)

        library.performDone()
        XCTAssertFalse(library.isHistoryInSelectionMode)
        XCTAssertTrue(root.isLibraryVisible)
        XCTAssertTrue(library.isOptionsMenuVisible)
        XCTAssertFalse(library.isInlineDeleteVisible)
        root.closeBookmarksLibrary()
    }

    func testBookmarksDisplayModeSwitchesBetweenCompactAndLargeAndPersists() throws {
        let fixture = try makeRegularRoot()
        let root = fixture.root
        let bookmarkStore = try XCTUnwrap(root.bookmarkStore)

        try bookmarkStore.add(title: "Fav 1", url: XCTUnwrap(URL(string: "https://one.example.com")), isFavorite: true)
        try bookmarkStore.add(title: "Fav 2", url: XCTUnwrap(URL(string: "https://two.example.com")), isFavorite: true)
        let folder = try bookmarkStore.createFolder(title: "News")
        try bookmarkStore.add(title: "Inside News", url: XCTUnwrap(URL(string: "https://news.example.com")), folderId: folder.id)
        try bookmarkStore.add(title: "Apple News", url: XCTUnwrap(URL(string: "https://appleinsider.com/articles/1")))

        root.openBookmarksLibrary(tab: .bookmarks)
        root.view.layoutIfNeeded()
        let library = root.bookmarksLibraryView
        let browser = try XCTUnwrap(library.bookmarksBrowserView)
        let table = browser.tableView

        XCTAssertEqual(library.bookmarksDisplayMode, .compact)

        let favCell = try XCTUnwrap(table.dataSource?.tableView(table, cellForRowAt: IndexPath(row: 0, section: 0)))
        let favConfig = try XCTUnwrap(favCell.contentConfiguration as? UIListContentConfiguration)
        XCTAssertEqual(favConfig.text, "Favorites")
        XCTAssertEqual(favConfig.secondaryText, "2")

        let folderCell = try XCTUnwrap(table.dataSource?.tableView(table, cellForRowAt: IndexPath(row: 0, section: 1)))
        let folderConfig = try XCTUnwrap(folderCell.contentConfiguration as? UIListContentConfiguration)
        XCTAssertEqual(folderConfig.text, "News")
        XCTAssertEqual(folderConfig.secondaryText, "1")

        let compactBookmarkCell = try XCTUnwrap(table.dataSource?.tableView(table, cellForRowAt: IndexPath(row: 0, section: 2)))
        let compactConfig = try XCTUnwrap(compactBookmarkCell.contentConfiguration as? UIListContentConfiguration)
        XCTAssertEqual(compactConfig.text, "Apple News")
        XCTAssertNil(compactConfig.secondaryText)

        library.setBookmarksDisplayMode(.large)
        XCTAssertEqual(BookmarksBrowserView.storedDisplayMode(defaults: fixture.defaults), .large)
        let sections = library.currentOptionsMenu?.children.compactMap { $0 as? UIMenu } ?? []
        let largeAction = try XCTUnwrap(sections.first?.children.first as? UIAction)
        XCTAssertEqual(largeAction.state, .on)

        let largeBookmarkCell = try XCTUnwrap(table.dataSource?.tableView(table, cellForRowAt: IndexPath(row: 0, section: 2)))
        let largeConfig = try XCTUnwrap(largeBookmarkCell.contentConfiguration as? UIListContentConfiguration)
        XCTAssertEqual(largeConfig.text, "Apple News")
        XCTAssertEqual(largeConfig.secondaryText, "appleinsider.com")

        // Outer display (`.compact`) keeps its classic subtitle cell layout untouched.
        library.applyPlacement(for: .compact)
        let outerDisplayCell = try XCTUnwrap(table.dataSource?.tableView(table, cellForRowAt: IndexPath(row: 0, section: 2)))
        XCTAssertNil(outerDisplayCell.contentConfiguration)
        XCTAssertEqual(outerDisplayCell.textLabel?.text, "Apple News")
        XCTAssertEqual(outerDisplayCell.detailTextLabel?.text, "appleinsider.com")
        root.closeBookmarksLibrary()
    }

    func testBookmarksSortByOrdersByNameAndWebsiteWithoutMutatingManualOrder() throws {
        let fixture = try makeRegularRoot()
        let root = fixture.root
        let bookmarkStore = try XCTUnwrap(root.bookmarkStore)

        let zebraApple = try XCTUnwrap(bookmarkStore.add(
            title: "Zebra",
            url: XCTUnwrap(URL(string: "https://apple.com")),
            sortOrder: 0
        ))
        let alphaZebra = try XCTUnwrap(bookmarkStore.add(
            title: "Alpha",
            url: XCTUnwrap(URL(string: "https://zebra.org")),
            sortOrder: 1
        ))

        root.openBookmarksLibrary(tab: .bookmarks)
        let library = root.bookmarksLibraryView
        let browser = try XCTUnwrap(library.bookmarksBrowserView)
        let table = browser.tableView

        XCTAssertEqual(library.bookmarksSortMode, .none)
        XCTAssertEqual(browser.visibleBookmarkID(at: IndexPath(row: 0, section: 2)), zebraApple.id)
        XCTAssertEqual(browser.visibleBookmarkID(at: IndexPath(row: 1, section: 2)), alphaZebra.id)
        XCTAssertEqual(table.dataSource?.tableView?(table, canMoveRowAt: IndexPath(row: 0, section: 2)), true)

        library.setBookmarksSortMode(.name)
        XCTAssertEqual(BookmarksBrowserView.storedSortMode(defaults: fixture.defaults), .name)
        XCTAssertEqual(browser.visibleBookmarkID(at: IndexPath(row: 0, section: 2)), alphaZebra.id)
        XCTAssertEqual(browser.visibleBookmarkID(at: IndexPath(row: 1, section: 2)), zebraApple.id)
        XCTAssertEqual(table.dataSource?.tableView?(table, canMoveRowAt: IndexPath(row: 0, section: 2)), false)
        let orgMenuAfterName = try XCTUnwrap(library.currentOptionsMenu?.children[1] as? UIMenu)
        let sortMenuAfterName = try XCTUnwrap(orgMenuAfterName.children.first as? UIMenu)
        XCTAssertEqual(sortMenuAfterName.subtitle, "Name")

        library.setBookmarksSortMode(.website)
        XCTAssertEqual(browser.visibleBookmarkID(at: IndexPath(row: 0, section: 2)), zebraApple.id)
        XCTAssertEqual(browser.visibleBookmarkID(at: IndexPath(row: 1, section: 2)), alphaZebra.id)
        XCTAssertEqual(table.dataSource?.tableView?(table, canMoveRowAt: IndexPath(row: 0, section: 2)), false)

        library.setBookmarksSortMode(.none)
        XCTAssertEqual(browser.visibleBookmarkID(at: IndexPath(row: 0, section: 2)), zebraApple.id)
        XCTAssertEqual(browser.visibleBookmarkID(at: IndexPath(row: 1, section: 2)), alphaZebra.id)
        XCTAssertEqual(table.dataSource?.tableView?(table, canMoveRowAt: IndexPath(row: 0, section: 2)), true)
        root.closeBookmarksLibrary()
    }

    func testBookmarksShowFoldersOnTopMergesOnRegularAndPreservesCompactOuterDisplay() throws {
        let fixture = try makeRegularRoot()
        let root = fixture.root
        let bookmarkStore = try XCTUnwrap(root.bookmarkStore)

        let alpha = try XCTUnwrap(bookmarkStore.add(
            title: "Alpha Site",
            url: XCTUnwrap(URL(string: "https://alpha.example.com")),
            sortOrder: 0
        ))
        let betaFolder = try bookmarkStore.createFolder(title: "Beta Folder")
        let gamma = try XCTUnwrap(bookmarkStore.add(
            title: "Gamma Site",
            url: XCTUnwrap(URL(string: "https://gamma.example.com")),
            sortOrder: 2
        ))

        root.openBookmarksLibrary(tab: .bookmarks)
        let library = root.bookmarksLibraryView
        let browser = try XCTUnwrap(library.bookmarksBrowserView)
        let table = browser.tableView

        XCTAssertEqual(table.dataSource?.numberOfSections?(in: table), 3)

        library.setBookmarksSortMode(.name)
        library.setBookmarksShowsFoldersOnTop(false)
        XCTAssertFalse(BookmarksBrowserView.storedShowsFoldersOnTop(defaults: fixture.defaults))
        XCTAssertEqual(table.dataSource?.numberOfSections?(in: table), 2)
        XCTAssertEqual(table.dataSource?.tableView(table, numberOfRowsInSection: 1), 3)
        XCTAssertEqual(browser.visibleBookmarkID(at: IndexPath(row: 0, section: 1)), alpha.id)
        XCTAssertEqual(browser.visibleFolderID(at: IndexPath(row: 1, section: 1)), betaFolder.id)
        XCTAssertEqual(browser.visibleBookmarkID(at: IndexPath(row: 2, section: 1)), gamma.id)
        XCTAssertEqual(table.dataSource?.tableView?(table, canMoveRowAt: IndexPath(row: 0, section: 1)), false)

        // Outer display (`.compact`) always shows separate Folders & Bookmarks sections in manual order.
        library.applyPlacement(for: .compact)
        XCTAssertEqual(table.dataSource?.numberOfSections?(in: table), 3)
        XCTAssertEqual(table.dataSource?.tableView(table, numberOfRowsInSection: 1), 1)
        XCTAssertEqual(table.dataSource?.tableView(table, numberOfRowsInSection: 2), 2)
        root.closeBookmarksLibrary()
    }

    func testBookmarksSelectBookmarksBatchDeletesFolderAndBookmark() throws {
        let fixture = try makeRegularRoot()
        let root = fixture.root
        let bookmarkStore = try XCTUnwrap(root.bookmarkStore)

        let folder = try bookmarkStore.createFolder(title: "Work")
        let keepBookmark = try XCTUnwrap(bookmarkStore.add(
            title: "Keep Me",
            url: XCTUnwrap(URL(string: "https://keep.example.com")),
            sortOrder: 0
        ))
        let deleteBookmark = try XCTUnwrap(bookmarkStore.add(
            title: "Delete Me",
            url: XCTUnwrap(URL(string: "https://delete.example.com")),
            sortOrder: 1
        ))

        root.openBookmarksLibrary(tab: .bookmarks)
        let library = root.bookmarksLibraryView
        let browser = try XCTUnwrap(library.bookmarksBrowserView)
        let table = browser.tableView

        library.enterBookmarksSelectionMode()
        XCTAssertTrue(library.isBookmarksInSelectionMode)
        XCTAssertFalse(library.isOptionsMenuVisible)
        XCTAssertTrue(library.isInlineDeleteVisible)
        XCTAssertFalse(library.isInlineDeleteEnabled)
        XCTAssertEqual(library.closeButtonAccessibilityLabel, "Done")

        // Pinned Favorites row ignores taps during selection mode.
        table.delegate?.tableView?(table, didSelectRowAt: IndexPath(row: 0, section: 0))
        XCTAssertFalse(browser.isViewingFavorites)
        XCTAssertFalse(library.isInlineDeleteEnabled)

        // Select the folder and the second bookmark.
        table.delegate?.tableView?(table, didSelectRowAt: IndexPath(row: 0, section: 1))
        table.delegate?.tableView?(table, didSelectRowAt: IndexPath(row: 1, section: 2))
        XCTAssertEqual(browser.selectedFolderIDs, [folder.id])
        XCTAssertEqual(browser.selectedBookmarkIDs, [deleteBookmark.id])
        XCTAssertTrue(library.isInlineDeleteEnabled)

        library.performInlineDelete()
        XCTAssertTrue(bookmarkStore.fetchFolders(parentId: nil).isEmpty)
        let remainingBookmarks = bookmarkStore.fetchBookmarks(folderId: nil)
        XCTAssertEqual(remainingBookmarks.map(\.id), [keepBookmark.id])
        XCTAssertFalse(library.isInlineDeleteEnabled)

        library.performDone()
        XCTAssertFalse(library.isBookmarksInSelectionMode)
        XCTAssertTrue(root.isLibraryVisible)
        XCTAssertTrue(library.isOptionsMenuVisible)
        root.closeBookmarksLibrary()
    }

    func testCompactHistoryAndBookmarkCellsLayOutWithoutZeroHeightContentConstraints() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let historyStore = HistoryStore(database: database)
        let bookmarkStore = BookmarkStore(database: database)
        try historyStore.record(visit: PageVisit(
            url: XCTUnwrap(URL(string: "https://news.google.com")),
            title: "Google News"
        ))
        try bookmarkStore.add(
            title: "Apple News",
            url: XCTUnwrap(URL(string: "https://apple.com"))
        )

        let frame = CGRect(x: 0, y: 0, width: 402, height: 800)
        let historyView = HistoryListView(historyStore: historyStore)
        historyView.frame = frame
        TestWindow.attach(historyView, frame: frame)
        historyView.tableView.layoutIfNeeded()

        let historyCell = try XCTUnwrap(
            historyView.tableView.cellForRow(at: IndexPath(row: 0, section: 0)) as? HistoryEntryCell
        )
        XCTAssertNil(historyCell.contentConfiguration)
        XCTAssertEqual(historyCell.textLabel?.text, "Google News")
        XCTAssertGreaterThanOrEqual(historyCell.bounds.height, 44)
        XCTAssertGreaterThanOrEqual(historyCell.contentView.bounds.height, 44)
        XCTAssertTrue(historyCell.contentView.constraints.isEmpty)

        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let bookmarksView = BookmarksBrowserView(bookmarkStore: bookmarkStore, defaults: defaults)
        bookmarksView.frame = frame
        TestWindow.attach(bookmarksView, frame: frame)
        bookmarksView.tableView.layoutIfNeeded()

        let bookmarkCell = try XCTUnwrap(
            bookmarksView.tableView.cellForRow(at: IndexPath(row: 0, section: 2)) as? BookmarkRowCell
        )
        XCTAssertNil(bookmarkCell.contentConfiguration)
        XCTAssertEqual(bookmarkCell.textLabel?.text, "Apple News")
        XCTAssertGreaterThanOrEqual(bookmarkCell.bounds.height, 44)
        XCTAssertGreaterThanOrEqual(bookmarkCell.contentView.bounds.height, 44)
        XCTAssertTrue(bookmarkCell.contentView.constraints.isEmpty)
    }

    func testSelectionIndicatorFramesInsideContentViewAndDetachesOnExit() throws {
        let fixture = try makeRegularRoot()
        let root = fixture.root
        let historyStore = try XCTUnwrap(root.historyStore)
        try historyStore.record(visit: PageVisit(
            url: XCTUnwrap(URL(string: "https://news.google.com")),
            title: "Google News"
        ))

        root.openBookmarksLibrary(tab: .history)
        root.view.layoutIfNeeded()
        let library = root.bookmarksLibraryView
        let historyView = try XCTUnwrap(library.historyListView)

        library.enterHistorySelectionMode()
        historyView.tableView.layoutIfNeeded()

        let firstRow = IndexPath(row: 0, section: 0)
        let selectedCell = try XCTUnwrap(historyView.tableView.cellForRow(at: firstRow) as? HistoryEntryCell)
        selectedCell.layoutIfNeeded()
        XCTAssertTrue(selectedCell.isShowingSelectionIndicator)
        let indicator = try XCTUnwrap(
            selectedCell.contentView.subviews.first {
                $0.accessibilityIdentifier == "LibrarySubtitleCell.SelectionIndicator"
            } as? UIImageView
        )
        XCTAssertFalse(indicator.isHidden)
        XCTAssertEqual(indicator.frame.size, CGSize(width: 22, height: 22))
        XCTAssertEqual(indicator.frame.minX, 16)
        XCTAssertGreaterThan(indicator.frame.minY, 0)

        library.performDone()
        historyView.tableView.layoutIfNeeded()
        let exitedCell = try XCTUnwrap(historyView.tableView.cellForRow(at: firstRow) as? HistoryEntryCell)
        XCTAssertFalse(exitedCell.isShowingSelectionIndicator)
        XCTAssertNil(
            exitedCell.contentView.subviews.first {
                $0.accessibilityIdentifier == "LibrarySubtitleCell.SelectionIndicator"
            }
        )
        root.closeBookmarksLibrary()
    }
}
