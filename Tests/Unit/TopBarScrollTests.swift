//
//  TopBarScrollTests.swift
//  OuterViewTests
//

@testable import OuterView
import UIKit
import XCTest

/// Shared Contract HEADER-BAR: regular bar leading zero plus trailing zero to
/// the view edges; leading cluster inset 28; trailing cluster inset 164;
/// cluster spacing 12; regular header background always clear with blur shown
/// in every state; expanded pill centered with width min of 380 and slot
/// width; minified capsule centered with domain-hugging width capped at 220;
/// slot leading plus trailing inactive on regular in both states.
/// Shared Contract REGULAR-COLLAPSE: collapsed keeps topBarView visible with
/// both stacks plus strip hidden; expanded centered with min(380,slotWidth)
/// and collapsed centered with domain-hugging width capped at min(220,slotWidth);
/// collapsed top inset equals TopBarView.remnantHeight; additionalSafeArea top
/// is zero in every placement and state; no remnant view exists anywhere.
@MainActor
final class TopBarScrollTests: XCTestCase {
    private func makeRegularRoot(
        tabCount: Int = 2
    ) throws -> (parent: UIViewController, root: BrowserRootViewController) {
        let database = try OuterViewDatabase(inMemory: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let root = BrowserRootViewController(database: database, defaults: defaults)
        let parent = UIViewController()
        TestWindow.attach(parent)
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
        root.view.layoutIfNeeded()
        parent.view.layoutIfNeeded()
        var tabs: [TabRecord] = []
        for _ in 0 ..< tabCount {
            tabs.append(TabRecord(isPrivate: false))
        }
        root.tabs = tabs
        root.selectedTabID = tabs.first?.id
        root.applyChromePlacement(for: .regular)
        root.applyChromeViews(animated: false)
        root.view.layoutIfNeeded()
        return (parent, root)
    }

    private func scroll(_ root: BrowserRootViewController, delta: CGFloat) {
        let commands = root.chromeController.handle(.scroll(offsetDelta: delta))
        root.applyCommands(commands, animated: false)
    }

    func testSharedThresholdsStayAcrossPlacements() {
        XCTAssertEqual(ChromeStateController.hideThreshold, 8)
        XCTAssertEqual(ChromeStateController.minifyThreshold, 24)
        XCTAssertEqual(ChromeStateController.revealThreshold, 32)
    }

    func testRegularDownHidesToolbarThenMinifiesPill() throws {
        let fixture = try makeRegularRoot()
        let root = fixture.root
        XCTAssertEqual(root.chromePlacement, .regular)
        XCTAssertFalse(root.topBarView.isHidden)
        XCTAssertFalse(root.topBarView.leadingStack.isHidden)
        XCTAssertFalse(root.topBarView.trailingStack.isHidden)
        XCTAssertFalse(root.tabStripView.isHidden)
        XCTAssertFalse(root.pillView.isHidden)
        XCTAssertEqual(root.pillHeightConstraint.constant, AddressBarView.expandedHeight)
        XCTAssertTrue(root.railView.isHidden)
        XCTAssertEqual(root.topBarView.currentHeightConstant, TopBarView.barHeight)
        XCTAssertFalse(root.prefersStatusBarHidden)

        scroll(root, delta: 8)
        // With synchronized tab bar & address bar contract, while the full large address bar
        // is showing, the toolbar remains expanded and tab bar stays visible.
        XCTAssertFalse(root.topBarView.isHidden)
        XCTAssertEqual(root.topBarView.currentHeightConstant, TopBarView.barHeight)
        XCTAssertFalse(root.prefersStatusBarHidden)
        XCTAssertFalse(root.topBarView.leadingStack.isHidden)
        XCTAssertFalse(root.topBarView.trailingStack.isHidden)
        XCTAssertFalse(root.tabStripView.isHidden)
        XCTAssertFalse(root.pillView.isHidden)
        XCTAssertEqual(root.pillHeightConstraint.constant, AddressBarView.expandedHeight)
        XCTAssertFalse(root.pillSlotLeadingConstraint.isActive)
        XCTAssertFalse(root.pillSlotTrailingConstraint.isActive)
        XCTAssertTrue(root.pillSlotCenterXConstraint.isActive)
        XCTAssertTrue(root.pillSlotWidthConstraint.isActive)
        XCTAssertEqual(root.additionalSafeAreaInsets.top, 0, accuracy: 0.001)
        XCTAssertNil(root.railView.lastAppliedRail)
        XCTAssertEqual(root.railView.applyCount, 0)

        // At 24 pt total delta, the address pill minifies -> toolbar collapses and tab strip hides.
        scroll(root, delta: 16)
        XCTAssertFalse(root.topBarView.isHidden)
        XCTAssertEqual(root.topBarView.currentHeightConstant, TopBarView.remnantHeight)
        XCTAssertTrue(root.prefersStatusBarHidden)
        XCTAssertTrue(root.topBarView.leadingStack.isHidden)
        XCTAssertTrue(root.topBarView.trailingStack.isHidden)
        XCTAssertTrue(root.tabStripView.isHidden)
        XCTAssertFalse(root.pillView.isHidden)
        XCTAssertEqual(root.pillHeightConstraint.constant, AddressBarView.minifiedHeight)
        XCTAssertFalse(root.pillSlotLeadingConstraint.isActive)
        XCTAssertFalse(root.pillSlotTrailingConstraint.isActive)
        XCTAssertTrue(root.pillSlotCenterXConstraint.isActive)
        XCTAssertTrue(root.pillSlotWidthConstraint.isActive)
        XCTAssertEqual(root.additionalSafeAreaInsets.top, 0, accuracy: 0.001)
        XCTAssertNil(root.railView.lastAppliedRail)
        XCTAssertEqual(root.railView.applyCount, 0)
    }

    func testRegularUpRestoresBoth() throws {
        let fixture = try makeRegularRoot()
        let root = fixture.root
        XCTAssertEqual(root.chromePlacement, .regular)

        scroll(root, delta: 24)
        XCTAssertFalse(root.topBarView.isHidden)
        XCTAssertEqual(root.topBarView.currentHeightConstant, TopBarView.remnantHeight)
        XCTAssertTrue(root.prefersStatusBarHidden)
        XCTAssertTrue(root.topBarView.leadingStack.isHidden)
        XCTAssertTrue(root.topBarView.trailingStack.isHidden)
        XCTAssertTrue(root.tabStripView.isHidden)
        XCTAssertFalse(root.pillView.isHidden)
        XCTAssertEqual(root.pillHeightConstraint.constant, AddressBarView.minifiedHeight)
        XCTAssertFalse(root.pillSlotLeadingConstraint.isActive)
        XCTAssertFalse(root.pillSlotTrailingConstraint.isActive)
        XCTAssertTrue(root.pillSlotCenterXConstraint.isActive)
        XCTAssertTrue(root.pillSlotWidthConstraint.isActive)
        XCTAssertEqual(root.additionalSafeAreaInsets.top, 0, accuracy: 0.001)

        scroll(root, delta: -32)
        XCTAssertFalse(root.topBarView.isHidden)
        XCTAssertEqual(root.topBarView.currentHeightConstant, TopBarView.barHeight)
        XCTAssertFalse(root.prefersStatusBarHidden)
        XCTAssertFalse(root.topBarView.leadingStack.isHidden)
        XCTAssertFalse(root.topBarView.trailingStack.isHidden)
        XCTAssertFalse(root.tabStripView.isHidden)
        XCTAssertFalse(root.pillView.isHidden)
        XCTAssertEqual(root.pillHeightConstraint.constant, AddressBarView.expandedHeight)
        XCTAssertFalse(root.pillSlotLeadingConstraint.isActive)
        XCTAssertFalse(root.pillSlotTrailingConstraint.isActive)
        XCTAssertTrue(root.pillSlotCenterXConstraint.isActive)
        XCTAssertTrue(root.pillSlotWidthConstraint.isActive)
        XCTAssertEqual(root.additionalSafeAreaInsets.top, 0, accuracy: 0.001)
        XCTAssertNil(root.railView.lastAppliedRail)
        XCTAssertEqual(root.railView.applyCount, 0)
    }

    func testRegularEndToEndScrollHidesWithoutRailSprings() throws {
        let fixture = try makeRegularRoot()
        let root = fixture.root
        XCTAssertEqual(root.chromePlacement, .regular)

        root.handleScrollDelta(10)
        XCTAssertFalse(root.topBarView.isHidden)
        XCTAssertFalse(root.topBarView.leadingStack.isHidden)
        XCTAssertFalse(root.topBarView.trailingStack.isHidden)
        XCTAssertFalse(root.tabStripView.isHidden)
        XCTAssertEqual(root.railView.applyCount, 0)

        root.handleScrollDelta(20)
        XCTAssertFalse(root.topBarView.isHidden)
        XCTAssertTrue(root.topBarView.leadingStack.isHidden)
        XCTAssertTrue(root.topBarView.trailingStack.isHidden)
        XCTAssertTrue(root.tabStripView.isHidden)
        XCTAssertEqual(root.pillHeightConstraint.constant, AddressBarView.minifiedHeight)
        XCTAssertFalse(root.pillSlotLeadingConstraint.isActive)
        XCTAssertFalse(root.pillSlotTrailingConstraint.isActive)
        XCTAssertTrue(root.pillSlotCenterXConstraint.isActive)
        XCTAssertTrue(root.pillSlotWidthConstraint.isActive)
        XCTAssertEqual(root.railView.applyCount, 0)
    }

    func testRegularSecondUpPerformsNoAnimation() throws {
        let fixture = try makeRegularRoot()
        let root = fixture.root
        XCTAssertEqual(root.chromePlacement, .regular)

        scroll(root, delta: 24)
        scroll(root, delta: -32)
        XCTAssertFalse(root.topBarView.isHidden)
        XCTAssertFalse(root.topBarView.leadingStack.isHidden)
        XCTAssertFalse(root.topBarView.trailingStack.isHidden)
        XCTAssertFalse(root.tabStripView.isHidden)
        XCTAssertEqual(root.pillHeightConstraint.constant, AddressBarView.expandedHeight)
        XCTAssertNil(root.pillAnimator)

        root.handleScrollDelta(-10)
        XCTAssertFalse(root.topBarView.isHidden)
        XCTAssertFalse(root.topBarView.leadingStack.isHidden)
        XCTAssertFalse(root.topBarView.trailingStack.isHidden)
        XCTAssertFalse(root.tabStripView.isHidden)
        XCTAssertEqual(root.pillHeightConstraint.constant, AddressBarView.expandedHeight)
        XCTAssertNil(root.pillAnimator)
        XCTAssertEqual(root.railView.applyCount, 0)
        XCTAssertNil(root.railView.lastAppliedRail)
    }

    func testRegularEditingMapsToDropdownEditor() throws {
        let fixture = try makeRegularRoot()
        let root = fixture.root
        XCTAssertEqual(root.chromePlacement, .regular)

        let began = root.chromeController.handle(.editBegan)
        root.applyCommands(began, animated: false)
        XCTAssertFalse(root.topBarView.isHidden)
        XCTAssertTrue(root.tabStripView.isHidden)
        XCTAssertTrue(root.pillView.isHidden)
        XCTAssertFalse(root.editorView.isHidden)
        XCTAssertEqual(root.railView.applyCount, 0)

        let ended = root.chromeController.handle(.editEnded(submitted: false))
        root.applyCommands(ended, animated: false)
        XCTAssertFalse(root.topBarView.isHidden)
        XCTAssertFalse(root.tabStripView.isHidden)
        XCTAssertFalse(root.pillView.isHidden)
        XCTAssertTrue(root.editorView.isHidden)
    }

    func testCompactScrollStillUsesRailSprings() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let root = BrowserRootViewController(database: database, defaults: defaults)
        let parent = UIViewController()
        TestWindow.attach(parent)
        parent.addChild(root)
        root.traitOverrides.horizontalSizeClass = .compact
        parent.view.addSubview(root.view)
        root.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            root.view.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
            root.view.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
            root.view.topAnchor.constraint(equalTo: parent.view.topAnchor),
            root.view.bottomAnchor.constraint(equalTo: parent.view.bottomAnchor)
        ])
        root.didMove(toParent: parent)
        root.view.layoutIfNeeded()
        let tabs: [TabRecord] = [TabRecord(isPrivate: false), TabRecord(isPrivate: false)]
        root.tabs = tabs
        root.selectedTabID = tabs.first?.id
        root.applyChromePlacement(for: .compact)
        root.applyChromeViews(animated: false)
        XCTAssertEqual(root.chromePlacement, .compact)
        let baseCount = root.railView.applyCount

        let commands = root.chromeController.handle(.scroll(offsetDelta: 8))
        root.applyCommands(commands, animated: false)
        XCTAssertTrue(root.topBarView.isHidden)
        XCTAssertFalse(root.railView.isHidden)
        XCTAssertFalse(root.prefersStatusBarHidden)
        XCTAssertEqual(root.railView.applyCount, baseCount + 1)
        XCTAssertEqual(root.railView.lastAppliedRail, .hidden)
    }
}
