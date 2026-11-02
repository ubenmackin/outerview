//
//  ChromeGeometryTests.swift
//  OuterViewTests
//

import CoreGraphics
@testable import OuterView
import XCTest

final class ChromeGeometryTests: XCTestCase {
    func testRailColumnOriginCalculation() {
        // iPhone Duo outer display bounds width is 466 pt.
        // Reserved system column is 84 pt.
        // Rail column width is 60 pt.
        // Rail column should be centered within the 84 pt system column:
        // boundsMaxX - (84 / 2) - (60 / 2) = 466 - 42 - 30 = 394.
        let originXWithSafeArea = SideRailView.columnOriginX(boundsMaxX: 466, safeAreaRight: 84)
        XCTAssertEqual(originXWithSafeArea, 394)

        // When safeAreaRight is 0, it falls back to SideRailView.safeColumnWidth (84 pt).
        let originXFallback = SideRailView.columnOriginX(boundsMaxX: 466, safeAreaRight: 0)
        XCTAssertEqual(originXFallback, 394)
    }

    func testMenuButtonFrameCalculation() {
        let frame = SideRailView.menuButtonFrame(
            bounds: CGRect(x: 0, y: 0, width: 466, height: 678),
            safeAreaBottom: 34,
            safeAreaRight: 84
        )
        XCTAssertEqual(frame, CGRect(x: 402, y: 600, width: 44, height: 44))
    }

    func testAddressBarWidthForBounds() {
        // AddressBarView max width is 220 pt.
        // For a 466 pt screen, min(220, 466 - 32) = 220.
        XCTAssertEqual(AddressBarView.widthForBounds(466), 220)

        // For very narrow bounds, it should respect margins.
        XCTAssertEqual(AddressBarView.widthForBounds(200), 168)
    }

    func testPillBottomOffsetCalculation() {
        let systemBottom: CGFloat = 34
        // Expanded: systemBottom (34) + expandedPillBottomGap (4) = 38
        XCTAssertEqual(
            BrowserRootViewController.pillBottomOffset(for: .expanded, systemBottomInset: systemBottom),
            38
        )

        // Minified: systemBottom (34) - minifiedPillSink (14) = 20, which is >= minifiedPillMinimumBottom (8)
        XCTAssertEqual(
            BrowserRootViewController.pillBottomOffset(for: .minified, systemBottomInset: systemBottom),
            20
        )

        // Minified with 0 bottom inset should clamp to minifiedPillMinimumBottom (8)
        XCTAssertEqual(
            BrowserRootViewController.pillBottomOffset(for: .minified, systemBottomInset: 0),
            8
        )
    }

    func testContentBottomInsetCalculation() {
        let systemBottom: CGFloat = 34
        // pillBottomOffset(.expanded) (38) + expandedHeight (44) + contentBottomGap (8) = 90
        XCTAssertEqual(
            BrowserRootViewController.contentBottomInset(systemBottomInset: systemBottom),
            90
        )
    }

    func testScrollProxyUserDriven() {
        XCTAssertTrue(ChromeScrollProxy.isUserDriven(isDragging: true, isDecelerating: false))
        XCTAssertTrue(ChromeScrollProxy.isUserDriven(isDragging: false, isDecelerating: true))
        XCTAssertTrue(ChromeScrollProxy.isUserDriven(isDragging: true, isDecelerating: true))
        XCTAssertFalse(ChromeScrollProxy.isUserDriven(isDragging: false, isDecelerating: false))
    }

    @MainActor
    func testRailActionButtonEnablement() {
        let disabledBack = RailAction.back(isEnabled: false) {}
        XCTAssertFalse(disabledBack.isEnabled)

        let enabledBack = RailAction.back(isEnabled: true) {}
        XCTAssertTrue(enabledBack.isEnabled)

        let button = RailButton(action: disabledBack)
        XCTAssertFalse(button.isEnabled)
        XCTAssertEqual(button.alpha, 0.35, accuracy: 0.01)
    }

    @MainActor
    func testRailButtonConstraintPriority() {
        let action = RailAction.done {}
        let button = RailButton(action: action)
        let widthConstraint = button.constraints.first { $0.firstAttribute == .width }
        let heightConstraint = button.constraints.first { $0.firstAttribute == .height }
        XCTAssertEqual(widthConstraint?.constant, SideRailView.buttonDiameter)
        XCTAssertEqual(widthConstraint?.priority, UILayoutPriority(999))
        XCTAssertEqual(heightConstraint?.constant, SideRailView.buttonDiameter)
        XCTAssertEqual(heightConstraint?.priority, UILayoutPriority(999))
    }

    @MainActor
    func testSideRailViewLayoutSubviewsDoesNotCrashOnZeroOrStandardBounds() {
        let rail = SideRailView(frame: .zero)
        rail.setItems(
            prefix: [RailAction.back {}, RailAction.newTab {}],
            suffix: [RailAction.search {}, RailAction.tabs {}]
        )
        // Should not crash or throw unsatisfiable constraints on zero bounds
        rail.layoutIfNeeded()

        rail.frame = CGRect(x: 0, y: 0, width: 466, height: 678)
        rail.layoutIfNeeded()
    }

    @MainActor
    func testLibraryRailActions() {
        let addFolder = RailAction.addFolder {}
        XCTAssertEqual(addFolder.systemImageName, "folder.badge.plus")
        XCTAssertEqual(addFolder.accessibilityLabel, "New Folder")
        XCTAssertFalse(addFolder.isProminent)

        let edit = RailAction.edit(isEditing: false) {}
        XCTAssertEqual(edit.systemImageName, "pencil")
        XCTAssertEqual(edit.accessibilityLabel, "Edit Bookmarks")

        let editDone = RailAction.edit(isEditing: true) {}
        XCTAssertEqual(editDone.systemImageName, "checkmark")
        XCTAssertEqual(editDone.accessibilityLabel, "Done Editing")

        let clear = RailAction.clear(isEnabled: true) {}
        XCTAssertEqual(clear.systemImageName, "trash")
        XCTAssertTrue(clear.isEnabled)

        let clearDisabled = RailAction.clear(isEnabled: false) {}
        XCTAssertFalse(clearDisabled.isEnabled)

        let cancel = RailAction.cancel {}
        XCTAssertFalse(cancel.isProminent)
        XCTAssertEqual(cancel.systemImageName, "xmark")
        XCTAssertEqual(cancel.accessibilityLabel, "Cancel")

        let done = RailAction.done {}
        XCTAssertTrue(done.isProminent)
        XCTAssertEqual(done.systemImageName, "checkmark")
        let doneButton = RailButton(action: done)
        XCTAssertEqual(doneButton.backgroundColor, .systemBlue)
        XCTAssertEqual(doneButton.tintColor, .white)
    }

    @MainActor
    func testRailModes() {
        XCTAssertEqual(BrowserRootViewController.RailMode.browsing, .browsing)
        XCTAssertEqual(BrowserRootViewController.RailMode.startPage, .startPage)
        XCTAssertEqual(BrowserRootViewController.RailMode.library(.bookmarks), .library(.bookmarks))
        XCTAssertEqual(BrowserRootViewController.RailMode.bookmarkEditor, .bookmarkEditor)
        XCTAssertNotEqual(BrowserRootViewController.RailMode.browsing, .startPage)
        XCTAssertNotEqual(BrowserRootViewController.RailMode.startPage, .bookmarkEditor)
    }

    @MainActor
    func testStartPageAndBookmarkEditorRailFlow() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let rootVC = BrowserRootViewController(database: database)
        TestWindow.attach(rootVC)

        // 1. Initial mode should be browsing
        XCTAssertEqual(rootVC.currentRailMode, .browsing)

        // 2. Begin editing address transitions to .startPage mode with Done button in button well
        rootVC.beginEditing()
        XCTAssertTrue(rootVC.isEditingAddress)
        XCTAssertFalse(rootVC.editorView.isHidden)
        XCTAssertEqual(rootVC.currentRailMode, .startPage)

        // 3. Dismissing start page/editing restores browsing mode
        rootVC.dismissStartPageOrEditing()
        XCTAssertFalse(rootVC.isEditingAddress)
        XCTAssertEqual(rootVC.currentRailMode, .browsing)

        // 4. Opening bookmark editor transitions to .bookmarkEditor mode with Cancel & Save
        try rootVC.presentBookmarkEditor(for: .addBookmark(title: "Test", url: XCTUnwrap(URL(string: "https://example.com"))))
        XCTAssertTrue(rootVC.isBookmarkEditorVisible)
        XCTAssertEqual(rootVC.currentRailMode, .bookmarkEditor)

        // 5. Dismissing bookmark editor restores browsing mode
        rootVC.dismissBookmarkEditor()
        XCTAssertFalse(rootVC.isBookmarkEditorVisible)
        XCTAssertEqual(rootVC.currentRailMode, .browsing)
    }

    @MainActor
    func testOpenStartPageFromMenu() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let rootVC = BrowserRootViewController(database: database)
        TestWindow.attach(rootVC)

        rootVC.openStartPageFromMenu()
        XCTAssertEqual(rootVC.currentRailMode, .startPage)

        // Tapping into address bar while on start page preserves start page and activates editor
        rootVC.beginEditing()
        XCTAssertTrue(rootVC.isEditingAddress)
        XCTAssertFalse(rootVC.editorView.isHidden)
        XCTAssertEqual(rootVC.currentRailMode, .startPage)

        rootVC.dismissStartPageOrEditing()
        XCTAssertFalse(rootVC.isEditingAddress)
    }

    @MainActor
    func testPageMenuInlinePaletteConfiguration() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let rootVC = BrowserRootViewController(database: database)
        TestWindow.attach(rootVC)

        let menu = rootVC.makePageMenu()
        guard let palette = menu.children.first as? UIMenu else {
            XCTFail("First menu item should be palette UIMenu")
            return
        }
        XCTAssertTrue(palette.options.contains(.displayInline))
        XCTAssertTrue(palette.options.contains(.displayAsPalette))
    }

    func testFindBarFrameEqualsExpandedPillFrame() {
        let bounds = CGRect(x: 0, y: 0, width: 466, height: 678)
        let systemBottom: CGFloat = 34
        let safeRight: CGFloat = 84
        XCTAssertEqual(FindInPageView.barHeight, AddressBarView.heightForState(.expanded))
        let findFrame = FindInPageView.barFrame(
            for: bounds,
            safeAreaRight: safeRight,
            systemBottomInset: systemBottom
        )
        let pillBottom = BrowserRootViewController.pillBottomOffset(for: .expanded, systemBottomInset: systemBottom)
        let pillHeight = AddressBarView.heightForState(.expanded)
        let expected = CGRect(
            x: 16,
            y: bounds.height - pillBottom - pillHeight,
            width: bounds.width - safeRight - 32,
            height: pillHeight
        )
        XCTAssertEqual(findFrame, expected)
    }

    @MainActor
    func testFindCounterText() {
        XCTAssertEqual(FindInPageView.counterText(total: 0, index: 0), "No Results")
        XCTAssertEqual(FindInPageView.counterText(total: 1, index: 1), "1 match")
        XCTAssertEqual(FindInPageView.counterText(total: 5, index: 2), "2/5")
    }

    @MainActor
    func testFindBarOverlayLifecycle() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let rootVC = BrowserRootViewController(database: database)
        TestWindow.attach(rootVC)

        XCTAssertFalse(rootVC.isFindActive)

        rootVC.beginFind()
        XCTAssertTrue(rootVC.isFindActive)
        XCTAssertTrue(rootVC.pillView.isHidden)
        XCTAssertFalse(rootVC.findView.isHidden)

        rootVC.handleScrollDelta(60)
        XCTAssertFalse(rootVC.findView.isHidden)
        XCTAssertTrue(rootVC.pillView.isHidden)

        rootVC.endFind()
        XCTAssertFalse(rootVC.isFindActive)
        XCTAssertTrue(rootVC.findView.isHidden)
        XCTAssertFalse(rootVC.pillView.isHidden)
    }

    @MainActor
    func testSwitchingTabsEndsFind() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let rootVC = BrowserRootViewController(database: database)
        TestWindow.attach(rootVC)

        rootVC.beginFind()
        XCTAssertTrue(rootVC.isFindActive)

        rootVC.createNewTab()
        XCTAssertFalse(rootVC.isFindActive)
        XCTAssertTrue(rootVC.findView.isHidden)
    }
}
