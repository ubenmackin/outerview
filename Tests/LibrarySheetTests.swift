//
//  LibrarySheetTests.swift
//  OuterViewTests
//

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class LibrarySheetTests: XCTestCase {
    private func makeCard(placement: ChromePlacement = .compact) -> OverlayCardView {
        let card = OverlayCardView()
        card.frame = CGRect(origin: .zero, size: TestWindow.defaultFrame.size)
        TestWindow.attach(card)
        card.frame = CGRect(origin: .zero, size: TestWindow.defaultFrame.size)
        card.applyPlacement(for: placement)
        card.layoutIfNeeded()
        return card
    }

    private func makeLibrary(tab: LibraryTab = .bookmarks, placement: ChromePlacement = .compact) throws -> BookmarksLibraryView {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let library = BookmarksLibraryView(defaults: defaults)
        TestWindow.attach(library)
        library.applyPlacement(for: placement)
        library.open(tab: tab)
        library.layoutIfNeeded()
        return library
    }

    private func makeRoot() throws -> BrowserRootViewController {
        let database = try OuterViewDatabase(inMemory: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let root = BrowserRootViewController(database: database, defaults: defaults)
        TestWindow.attach(root)
        return root
    }

    func testStaticsMatchContracts() {
        XCTAssertEqual(OverlayCardView.maxWidth, 560)
        XCTAssertEqual(OverlayCardView.cornerRadius, 16)
        XCTAssertEqual(OverlayCardView.dimAlpha, 0.2, accuracy: 0.001)
        XCTAssertEqual(OverlayCardView.contentPadding, 16)
        XCTAssertEqual(TopBarView.barHeight, 56)
        XCTAssertEqual(TabStripView.stripHeight, 44)
        XCTAssertEqual(TopBarView.remnantHeight, TopBarView.barHeight)
        XCTAssertEqual(TopBarView.trailingClearance, 96)
    }

    func testRegularCardContentPadded() {
        let card = makeCard(placement: .regular)
        let content = UIView()
        card.setContent(content)
        card.layoutIfNeeded()
        XCTAssertEqual(content.frame.minX, OverlayCardView.contentPadding, accuracy: 1.0)
        XCTAssertEqual(content.frame.minY, OverlayCardView.contentPadding, accuracy: 1.0)
        XCTAssertEqual(content.frame.width, card.cardView.bounds.width - 32, accuracy: 1.0)
        XCTAssertEqual(content.frame.height, card.cardView.bounds.height - 32, accuracy: 1.0)
    }

    func testCompactCardContentFullBleed() {
        let card = makeCard(placement: .compact)
        let content = UIView()
        card.setContent(content)
        card.layoutIfNeeded()
        XCTAssertEqual(content.frame, card.cardView.bounds)
    }

    func testDimHeavyBlurWithOverlay() {
        let card = makeCard(placement: .regular)
        XCTAssertNotNil(card.dimBlurView.effect)
        XCTAssertEqual(card.dimOverlayView.backgroundColor, UIColor.black.withAlphaComponent(OverlayCardView.dimAlpha))
        XCTAssertFalse(card.dimBlurView.isUserInteractionEnabled)
        XCTAssertFalse(card.dimOverlayView.isUserInteractionEnabled)
        XCTAssertFalse(card.dimView.isUserInteractionEnabled)
    }

    func testDimOnlyOnRegular() {
        let card = makeCard(placement: .compact)
        XCTAssertTrue(card.dimView.isHidden)
        card.applyPlacement(for: .regular)
        XCTAssertFalse(card.dimView.isHidden)
        card.applyPlacement(for: .compact)
        XCTAssertTrue(card.dimView.isHidden)
    }

    func testBookmarksTabShowsAddAndEditOnRegular() throws {
        let library = try makeLibrary(tab: .bookmarks, placement: .regular)
        XCTAssertTrue(library.isDoneVisible)
        XCTAssertTrue(library.isInlineAddVisible)
        XCTAssertTrue(library.isInlineEditVisible)
        XCTAssertFalse(library.isInlineClearVisible)
        XCTAssertFalse(library.isInlineMenuVisible)
        XCTAssertFalse(library.isInlineDeleteVisible)
        XCTAssertEqual(library.inlineEditAccessibilityLabel, "Edit Bookmarks")
    }

    func testHistoryTabShowsClearOnRegular() throws {
        let library = try makeLibrary(tab: .history, placement: .regular)
        XCTAssertTrue(library.isDoneVisible)
        XCTAssertFalse(library.isInlineAddVisible)
        XCTAssertFalse(library.isInlineEditVisible)
        XCTAssertTrue(library.isInlineClearVisible)
        XCTAssertFalse(library.isInlineMenuVisible)
        XCTAssertFalse(library.isInlineDeleteVisible)
    }

    func testReadingListTabShowsMenuOnRegular() throws {
        let root = try makeRoot()
        root.openBookmarksLibrary(tab: .readingList)
        root.bookmarksLibraryView.applyPlacement(for: .regular)
        let library = root.bookmarksLibraryView
        XCTAssertTrue(library.isDoneVisible)
        XCTAssertFalse(library.isInlineAddVisible)
        XCTAssertFalse(library.isInlineEditVisible)
        XCTAssertFalse(library.isInlineClearVisible)
        XCTAssertTrue(library.isInlineMenuVisible)
        XCTAssertFalse(library.isInlineDeleteVisible)
        XCTAssertNotNil(library.makeReadingListMenu())
        root.closeBookmarksLibrary()
    }

    func testFavoritesTabShowsOnlyDoneOnRegular() throws {
        let library = try makeLibrary(tab: .favorites, placement: .regular)
        XCTAssertTrue(library.isDoneVisible)
        XCTAssertFalse(library.isInlineAddVisible)
        XCTAssertFalse(library.isInlineEditVisible)
        XCTAssertFalse(library.isInlineClearVisible)
        XCTAssertFalse(library.isInlineMenuVisible)
        XCTAssertFalse(library.isInlineDeleteVisible)
    }

    func testCompactHidesAllInline() throws {
        for tab: LibraryTab in [.favorites, .bookmarks, .history, .readingList] {
            let library = try makeLibrary(tab: tab, placement: .compact)
            XCTAssertFalse(library.isDoneVisible)
            XCTAssertFalse(library.isInlineAddVisible)
            XCTAssertFalse(library.isInlineEditVisible)
            XCTAssertFalse(library.isInlineClearVisible)
            XCTAssertFalse(library.isInlineMenuVisible)
            XCTAssertFalse(library.isInlineDeleteVisible)
        }
    }

    func testInlineCallbacksFireThroughButtons() throws {
        let library = try makeLibrary(tab: .bookmarks, placement: .regular)
        var didAdd = false
        var didEdit = false
        var didClear = false
        var didDone = false
        library.onInlineAddFolder = { didAdd = true }
        library.onInlineToggleEdit = { didEdit = true }
        library.onInlineClearHistory = { didClear = true }
        library.onInlineDone = { didDone = true }
        library.onDone = { didDone = true }
        library.open(tab: .bookmarks)
        library.applyPlacement(for: .regular)
        library.performInlineAdd()
        XCTAssertTrue(didAdd)
        library.performInlineToggleEdit()
        XCTAssertTrue(didEdit)
        library.open(tab: .history)
        library.applyPlacement(for: .regular)
        library.performInlineClear()
        XCTAssertTrue(didClear)
        library.performInlineDone()
        XCTAssertTrue(didDone)
    }

    func testRootWiresInlineToRailHandlers() throws {
        let root = try makeRoot()
        root.openBookmarksLibrary(tab: .bookmarks)
        root.bookmarksLibraryView.applyPlacement(for: .regular)
        let library = root.bookmarksLibraryView
        XCTAssertNotNil(library.onInlineAddFolder)
        XCTAssertNotNil(library.onInlineToggleEdit)
        XCTAssertNotNil(library.onInlineClearHistory)
        XCTAssertNotNil(library.inlineMenu)
        XCTAssertNotNil(library.onInlineDone)
        XCTAssertFalse(library.isEditingBookmarks)
        library.performInlineToggleEdit()
        XCTAssertTrue(library.isEditingBookmarks)
        XCTAssertEqual(library.inlineEditAccessibilityLabel, "Done Editing")
        library.performInlineToggleEdit()
        XCTAssertFalse(library.isEditingBookmarks)
        library.performInlineDone()
        XCTAssertFalse(root.isLibraryVisible)
    }

    func testInlineEditTitleFollowsEditingState() throws {
        let library = try makeLibrary(tab: .bookmarks, placement: .regular)
        let database = try OuterViewDatabase(inMemory: true)
        library.configureStores(
            bookmarkStore: BookmarkStore(database: database),
            historyStore: HistoryStore(database: database),
            readingListStore: ReadingListStore(database: database)
        )
        library.applyPlacement(for: .regular)
        XCTAssertEqual(library.inlineEditAccessibilityLabel, "Edit Bookmarks")
        library.toggleBookmarksEdit()
        XCTAssertEqual(library.inlineEditAccessibilityLabel, "Done Editing")
        XCTAssertTrue(library.isInlineEditVisible)
        library.toggleBookmarksEdit()
        XCTAssertEqual(library.inlineEditAccessibilityLabel, "Edit Bookmarks")
    }

    func testClearEnabledReflectsHistoryPresence() throws {
        let root = try makeRoot()
        root.openBookmarksLibrary(tab: .history)
        root.bookmarksLibraryView.applyPlacement(for: .regular)
        XCTAssertFalse(root.bookmarksLibraryView.isInlineClearEnabled)
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        try root.historyStore?.record(visit: PageVisit(url: url, title: "Example"))
        root.bookmarksLibraryView.reload()
        XCTAssertTrue(root.bookmarksLibraryView.isInlineClearEnabled)
        root.closeBookmarksLibrary()
    }

    func testSelectionModeShowsDeleteAndDoneExits() throws {
        let root = try makeRoot()
        root.openBookmarksLibrary(tab: .readingList)
        root.bookmarksLibraryView.applyPlacement(for: .regular)
        let library = root.bookmarksLibraryView
        XCTAssertTrue(library.isInlineMenuVisible)
        XCTAssertFalse(library.isInlineDeleteVisible)
        library.enterReadingListSelectionMode()
        XCTAssertFalse(library.isInlineMenuVisible)
        XCTAssertTrue(library.isInlineDeleteVisible)
        XCTAssertTrue(library.isDoneVisible)
        library.performDone()
        XCTAssertFalse(library.isReadingListInSelectionMode)
        XCTAssertTrue(root.isLibraryVisible)
        XCTAssertTrue(library.isInlineMenuVisible)
        XCTAssertFalse(library.isInlineDeleteVisible)
        root.closeBookmarksLibrary()
    }
}
