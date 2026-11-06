// Chrome — Geometry plus rail to toolbar mapping verification.
import CoreGraphics
@testable import OuterView
import UIKit
import XCTest

final class ChromeGeometryTests: XCTestCase {
    func testRailColumnOriginCalculation() {
        // iPhone Duo outer display bounds width is 466 pt.
        // Rail column width is 44 pt (matching hitTarget).
        // Button centers align with the hardware Control Center icon at 47 pt from trailing edge:
        // boundsMaxX - 47 - (44 / 2) = 466 - 47 - 22 = 397.
        let originXWithSafeArea = SideRailView.columnOriginX(boundsMaxX: 466, safeAreaRight: 84)
        XCTAssertEqual(originXWithSafeArea, 397)

        let originXFallback = SideRailView.columnOriginX(boundsMaxX: 466, safeAreaRight: 0)
        XCTAssertEqual(originXFallback, 397)
    }

    @MainActor
    func testRailHiddenShowsNoQuickMenuViews() {
        let rail = SideRailView(frame: CGRect(x: 0, y: 0, width: 466, height: 678))
        rail.setItems(prefix: [RailAction.back {}], suffix: [RailAction.tabs {}])
        rail.setRailState(.hidden, pill: .expanded, animated: false)
        let stacks = rail.subviews.compactMap { $0 as? UIStackView }
        XCTAssertEqual(stacks.count, 2)
        for stack in stacks {
            XCTAssertEqual(stack.alpha, 0)
        }
        // No replacement affordance when collapsed; only stacks remain.
        XCTAssertTrue(rail.subviews.allSatisfy { $0 is UIStackView })
    }

    @MainActor
    func testSetRailStateTogglesStacksOnly() {
        let rail = SideRailView(frame: CGRect(x: 0, y: 0, width: 466, height: 678))
        rail.setItems(prefix: [RailAction.back {}], suffix: [RailAction.tabs {}])
        let subviewCount = rail.subviews.count
        rail.setRailState(.hidden, pill: .expanded, animated: false)
        rail.setRailState(.visible, pill: .expanded, animated: false)
        // Toggling visibility fades stacks without adding views.
        XCTAssertEqual(rail.subviews.count, subviewCount)
        for stack in rail.subviews.compactMap({ $0 as? UIStackView }) {
            XCTAssertEqual(stack.alpha, 1)
        }
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
        // System mapping keeps disabled items visible; UIKit dims them.
        let disabledItem = SystemToolbarMapper.makeItem(for: disabledBack)
        XCTAssertFalse(disabledItem.isEnabled)
        XCTAssertEqual(disabledItem.accessibilityLabel, "Back")
        let disabledButton = SystemToolbarMapper.makeButton(for: disabledBack)
        XCTAssertFalse(disabledButton.isEnabled)
        XCTAssertEqual(disabledButton.alpha, 0.35, accuracy: 0.01)
    }

    @MainActor
    func testSystemToolbarButtonMetrics() {
        let action = RailAction.done {}
        let button = SystemToolbarMapper.makeButton(for: action)
        let width = button.constraints.first { $0.firstAttribute == .width }
        let height = button.constraints.first { $0.firstAttribute == .height }
        XCTAssertEqual(width?.constant, SystemToolbarMapper.hitTarget)
        XCTAssertEqual(height?.constant, SystemToolbarMapper.hitTarget)
        XCTAssertEqual(button.configuration?.baseBackgroundColor, .systemBlue)
        XCTAssertEqual(button.configuration?.baseForegroundColor, .white)
        let item = SystemToolbarMapper.makeItem(for: action)
        XCTAssertEqual(item.accessibilityLabel, "Done")
        XCTAssertEqual(item.tintColor, .systemBlue)
        XCTAssertTrue(item.isEnabled)
    }

    @MainActor
    func testSystemToolbarItemsPreserveOrder() {
        let items = SystemToolbarMapper.makeToolbarItems(
            prefix: [.back(handler: {}), .bookmarks(handler: {})],
            suffix: [.newTab(handler: {}), .tabs(handler: {})]
        )
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items.map(\.accessibilityLabel), ["Back", "Bookmarks", "New Tab", "Tabs"])
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
        let doneItem = SystemToolbarMapper.makeItem(for: done)
        XCTAssertEqual(doneItem.tintColor, .systemBlue)
        XCTAssertEqual(doneItem.accessibilityLabel, "Done")
        let doneButton = SystemToolbarMapper.makeButton(for: done)
        XCTAssertEqual(doneButton.configuration?.baseBackgroundColor, .systemBlue)
        XCTAssertEqual(doneButton.configuration?.baseForegroundColor, .white)
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
