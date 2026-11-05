// Bookmarks — Native regular Library page sheet and compact parity tests.

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

    private func makeRegularRoot() throws -> (parent: UIViewController, root: BrowserRootViewController) {
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
        return (parent, root)
    }

    func testStaticsMatchContracts() {
        XCTAssertEqual(OverlayCardView.maxWidth, 560)
        XCTAssertEqual(OverlayCardView.cornerRadius, 16)
        XCTAssertEqual(OverlayCardView.dimAlpha, 0.2, accuracy: 0.001)
        XCTAssertEqual(OverlayCardView.contentPadding, 16)
        XCTAssertEqual(LibrarySheetViewController.preferredSheetCornerRadius, 32)
        XCTAssertEqual(TopBarView.barHeight, 84)
        XCTAssertEqual(TabStripView.stripHeight, 44)
        XCTAssertEqual(TopBarView.remnantHeight, 48)
        XCTAssertEqual(TopBarView.trailingStatusInset, 164)
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

    func testRegularHeaderUsesToolbarGlassWithZeroVisibleTitles() throws {
        for tab: LibraryTab in [.favorites, .bookmarks, .history, .readingList] {
            let library = try makeLibrary(tab: tab, placement: .regular)
            XCTAssertTrue(library.isDoneVisible)
            XCTAssertFalse(library.hasAnyVisibleButtonTitle)
            XCTAssertEqual(library.displayedSectionTitle, tab.title)
        }
    }

    func testBookmarksTabShowsToolbarOptionsAndDoneOnRegular() throws {
        let library = try makeLibrary(tab: .bookmarks, placement: .regular)
        XCTAssertTrue(library.isDoneVisible)
        XCTAssertTrue(library.isOptionsMenuVisible)
        XCTAssertFalse(library.isInlineAddVisible)
        XCTAssertFalse(library.isInlineDeleteVisible)
        XCTAssertFalse(library.hasAnyVisibleButtonTitle)

        let sections = library.currentOptionsMenu?.children.compactMap { $0 as? UIMenu } ?? []
        XCTAssertEqual(sections.count, 3)

        let displayTitles = sections[0].children.compactMap { ($0 as? UIAction)?.title }
        XCTAssertEqual(displayTitles, ["Large", "Compact"])
        let compactAction = try XCTUnwrap(sections[0].children.last as? UIAction)
        XCTAssertEqual(compactAction.state, .on)

        let sortSubmenu = try XCTUnwrap(sections[1].children.first as? UIMenu)
        XCTAssertEqual(sortSubmenu.title, "Sort By")
        XCTAssertEqual(sortSubmenu.subtitle, "None")
        XCTAssertEqual(sortSubmenu.children.compactMap { ($0 as? UIAction)?.title }, ["None", "Name", "Website"])
        let foldersOnTop = try XCTUnwrap(sections[1].children.last as? UIAction)
        XCTAssertEqual(foldersOnTop.title, "Show Folders on Top")
        XCTAssertEqual(foldersOnTop.state, .on)

        let actionTitles = sections[2].children.compactMap { ($0 as? UIAction)?.title }
        XCTAssertEqual(actionTitles, ["Select Bookmarks", "Edit Bookmarks", "New Folder"])
    }

    func testHistoryTabShowsToolbarOptionsMenuOnRegular() throws {
        let library = try makeLibrary(tab: .history, placement: .regular)
        XCTAssertTrue(library.isDoneVisible)
        XCTAssertTrue(library.isOptionsMenuVisible)
        XCTAssertFalse(library.isInlineAddVisible)
        XCTAssertFalse(library.isInlineDeleteVisible)
        let actionTitles = library.currentOptionsMenu?.children.compactMap { ($0 as? UIAction)?.title } ?? []
        XCTAssertEqual(actionTitles, ["Select Websites", "Clear History…"])
    }

    func testReadingListTabShowsToolbarOptionsMenuOnRegular() throws {
        let root = try makeRoot()
        root.openBookmarksLibrary(tab: .readingList)
        root.bookmarksLibraryView.applyPlacement(for: .regular)
        let library = root.bookmarksLibraryView
        XCTAssertTrue(library.isDoneVisible)
        XCTAssertTrue(library.isOptionsMenuVisible)
        XCTAssertFalse(library.isInlineAddVisible)
        XCTAssertFalse(library.isInlineDeleteVisible)
        XCTAssertNotNil(library.makeReadingListMenu())
        root.closeBookmarksLibrary()
    }

    func testFavoritesTabShowsOnlyToolbarDoneOnRegular() throws {
        let library = try makeLibrary(tab: .favorites, placement: .regular)
        XCTAssertTrue(library.isDoneVisible)
        XCTAssertFalse(library.isOptionsMenuVisible)
        XCTAssertFalse(library.isInlineAddVisible)
        XCTAssertFalse(library.isInlineDeleteVisible)
    }

    func testCompactHidesAllRegularHeaderControls() throws {
        for tab: LibraryTab in [.favorites, .bookmarks, .history, .readingList] {
            let library = try makeLibrary(tab: tab, placement: .compact)
            XCTAssertFalse(library.isDoneVisible)
            XCTAssertFalse(library.isOptionsMenuVisible)
            XCTAssertFalse(library.isInlineAddVisible)
            XCTAssertFalse(library.isInlineDeleteVisible)
            XCTAssertFalse(library.isFolderBackVisible)
        }
    }

    func testInlineCallbacksFireThroughHelpersAndMenuActions() throws {
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

    func testBookmarksEditModeSwitchesHeaderToAddFolderAndAccentDoneCheck() throws {
        let fixture = try makeRegularRoot()
        let root = fixture.root
        root.openBookmarksLibrary(tab: .bookmarks)
        let library = root.bookmarksLibraryView
        XCTAssertFalse(library.isEditingBookmarks)
        XCTAssertTrue(library.isOptionsMenuVisible)
        XCTAssertFalse(library.isInlineAddVisible)
        XCTAssertEqual(library.closeButtonAccessibilityLabel, "Done")

        library.performInlineToggleEdit()
        XCTAssertTrue(library.isEditingBookmarks)
        XCTAssertFalse(library.isOptionsMenuVisible)
        XCTAssertTrue(library.isInlineAddVisible)
        XCTAssertEqual(library.closeButtonAccessibilityLabel, "Done Editing")
        XCTAssertFalse(library.hasAnyVisibleButtonTitle)

        // Tapping the accent check exits edit mode while keeping the Library sheet open.
        library.performDone()
        XCTAssertFalse(library.isEditingBookmarks)
        XCTAssertTrue(root.isLibraryVisible)
        XCTAssertEqual(library.closeButtonAccessibilityLabel, "Done")

        // Tapping close (`✕`) now dismisses the Library sheet.
        library.performDone()
        XCTAssertFalse(root.isLibraryVisible)
        XCTAssertNil(root.librarySheetController)
    }

    func testClearHistoryMenuActionReflectsHistoryPresence() throws {
        let fixture = try makeRegularRoot()
        let root = fixture.root
        root.openBookmarksLibrary(tab: .history)
        let library = root.bookmarksLibraryView

        let emptyActions = library.currentOptionsMenu?.children.compactMap { $0 as? UIAction } ?? []
        XCTAssertEqual(emptyActions.map(\.title), ["Select Websites", "Clear History…"])
        XCTAssertTrue(emptyActions[0].attributes.contains(.disabled))
        XCTAssertTrue(emptyActions[1].attributes.contains(.disabled))
        XCTAssertTrue(emptyActions[1].attributes.contains(.destructive))

        let url = try XCTUnwrap(URL(string: "https://example.com"))
        try root.historyStore?.record(visit: PageVisit(url: url, title: "Example"))
        library.reload()

        let populatedActions = library.currentOptionsMenu?.children.compactMap { $0 as? UIAction } ?? []
        XCTAssertEqual(populatedActions.map(\.title), ["Select Websites", "Clear History…"])
        XCTAssertFalse(populatedActions[0].attributes.contains(.disabled))
        XCTAssertFalse(populatedActions[1].attributes.contains(.disabled))
        root.closeBookmarksLibrary()
    }

    func testSelectionModeShowsToolbarDeleteAndDoneExitsSelectionFirst() throws {
        let fixture = try makeRegularRoot()
        let root = fixture.root
        root.openBookmarksLibrary(tab: .readingList)
        let library = root.bookmarksLibraryView
        XCTAssertTrue(library.isOptionsMenuVisible)
        XCTAssertFalse(library.isInlineDeleteVisible)

        library.enterReadingListSelectionMode()
        XCTAssertFalse(library.isOptionsMenuVisible)
        XCTAssertTrue(library.isInlineDeleteVisible)
        XCTAssertTrue(library.isDoneVisible)
        XCTAssertFalse(library.hasAnyVisibleButtonTitle)

        library.performDone()
        XCTAssertFalse(library.isReadingListInSelectionMode)
        XCTAssertTrue(root.isLibraryVisible)
        XCTAssertTrue(library.isOptionsMenuVisible)
        XCTAssertFalse(library.isInlineDeleteVisible)
        root.closeBookmarksLibrary()
    }

    func testRegularOpenLibraryPresentsNativePageSheetAndKeepsTopBarIntact() throws {
        let fixture = try makeRegularRoot()
        let root = fixture.root

        root.openBookmarksLibrary(tab: .bookmarks)
        root.view.layoutIfNeeded()

        XCTAssertTrue(root.isLibraryVisible)
        XCTAssertTrue(root.libraryOverlay.isHidden)
        let sheet = try XCTUnwrap(root.librarySheetController)
        XCTAssertEqual(sheet.modalPresentationStyle, .pageSheet)
        XCTAssertTrue(root.presentedViewController === sheet)
        XCTAssertTrue(root.bookmarksLibraryView.superview === sheet.view)

        // TopBarView stays visible with browsing controls and address pill underneath the native sheet scrim.
        XCTAssertFalse(root.topBarView.isHidden)
        XCTAssertFalse(root.topBarView.isCollapsed)
        XCTAssertFalse(root.topBarView.leadingStack.isHidden)
        XCTAssertFalse(root.topBarView.trailingStack.isHidden)
        XCTAssertFalse(root.pillView.isHidden)
        XCTAssertFalse(root.prefersStatusBarHidden)
        let trailingLabels = root.topBarView.trailingStack.arrangedSubviews.compactMap(\.accessibilityLabel)
        XCTAssertFalse(trailingLabels.contains("Done"))

        // Swiping down / tapping outside triggers presentationControllerDidDismiss and cleans up state.
        if let presentationController = sheet.presentationController {
            sheet.dismiss(animated: false)
            sheet.presentationControllerDidDismiss(presentationController)
        } else {
            root.handleLibrarySheetSystemDismiss()
        }
        XCTAssertFalse(root.isLibraryVisible)
        XCTAssertNil(root.librarySheetController)
    }
}
