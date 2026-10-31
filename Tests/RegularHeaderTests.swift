//
//  RegularHeaderTests.swift
//  OuterViewTests
//

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class RegularHeaderTests: XCTestCase {
    private func makeRegularRoot(tabCount: Int = 2) throws -> (parent: UIViewController, root: BrowserRootViewController) {
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
        root.applyContentInsets()
        root.view.layoutIfNeeded()
        return (parent, root)
    }

    private func scroll(_ root: BrowserRootViewController, delta: CGFloat) {
        let commands = root.chromeController.handle(.scroll(offsetDelta: delta))
        root.applyCommands(commands, animated: false)
    }

    func testStaticsMatchRegularHeaderContract() {
        XCTAssertEqual(TopBarView.barHeight, 56)
        XCTAssertEqual(TabStripView.stripHeight, 44)
        XCTAssertEqual(TopBarView.remnantHeight, TopBarView.barHeight)
        XCTAssertEqual(BrowserRootViewController.regularRemnantHeight, TopBarView.barHeight)
        XCTAssertEqual(TopBarView.trailingClearance, 96)
        XCTAssertEqual(BrowserRootViewController.regularTrailingClearance, 96)
    }

    func testExpandedTopInsetEqualsToolbarPlusVisibleStrip() {
        let expanded = ChromeState(rail: .visible, pill: .expanded)
        XCTAssertEqual(
            BrowserRootViewController.topContentInset(for: .regular, state: expanded, stripVisible: true),
            TopBarView.barHeight + TabStripView.stripHeight
        )
        XCTAssertEqual(
            BrowserRootViewController.topContentInset(for: .regular, state: expanded, stripVisible: false),
            TopBarView.barHeight
        )
    }

    func testCollapsedTopInsetZeroWithRemnant() {
        let collapsed = ChromeState(rail: .hidden, pill: .expanded)
        XCTAssertEqual(
            BrowserRootViewController.topContentInset(for: .regular, state: collapsed, stripVisible: false),
            0
        )
        XCTAssertEqual(
            BrowserRootViewController.topContentInset(for: .regular, state: collapsed, stripVisible: true),
            0
        )
        XCTAssertEqual(
            BrowserRootViewController.additionalSafeAreaTopInset(for: .regular, state: collapsed),
            TopBarView.barHeight
        )
        let expanded = ChromeState(rail: .visible, pill: .expanded)
        XCTAssertEqual(
            BrowserRootViewController.additionalSafeAreaTopInset(for: .regular, state: expanded),
            0
        )
    }

    func testEditingKeepsExpandedInsets() {
        let editingHiddenRail = ChromeState(rail: .hidden, pill: .editing)
        XCTAssertEqual(
            BrowserRootViewController.topContentInset(for: .regular, state: editingHiddenRail, stripVisible: false),
            TopBarView.barHeight
        )
        XCTAssertEqual(
            BrowserRootViewController.topContentInset(for: .regular, state: editingHiddenRail, stripVisible: true),
            TopBarView.barHeight + TabStripView.stripHeight
        )
        XCTAssertEqual(
            BrowserRootViewController.additionalSafeAreaTopInset(for: .regular, state: editingHiddenRail),
            0
        )
    }

    func testCompactTopZeroWithNoAdditionalInsets() {
        let expanded = ChromeState(rail: .visible, pill: .expanded)
        let collapsed = ChromeState(rail: .hidden, pill: .expanded)
        let editing = ChromeState(rail: .hidden, pill: .editing)
        for state in [expanded, collapsed, editing] {
            XCTAssertEqual(
                BrowserRootViewController.topContentInset(for: .compact, state: state, stripVisible: true),
                0
            )
            XCTAssertEqual(
                BrowserRootViewController.topContentInset(for: .compact, state: state, stripVisible: false),
                0
            )
            XCTAssertEqual(
                BrowserRootViewController.additionalSafeAreaTopInset(for: .compact, state: state),
                0
            )
        }
    }

    func testCompensatedOffsetRoundTrips() {
        let current = CGPoint(x: 0, y: 200)
        let forward = BrowserRootViewController.compensatedOffset(current: current, oldTop: 100, newTop: 0)
        XCTAssertEqual(forward.y, 100, accuracy: 0.001)
        XCTAssertEqual(forward.x, current.x, accuracy: 0.001)
        let back = BrowserRootViewController.compensatedOffset(current: forward, oldTop: 0, newTop: 100)
        XCTAssertEqual(back.x, current.x, accuracy: 0.001)
        XCTAssertEqual(back.y, current.y, accuracy: 0.001)
        let unchanged = BrowserRootViewController.compensatedOffset(current: current, oldTop: 56, newTop: 56)
        XCTAssertEqual(unchanged.x, current.x, accuracy: 0.001)
        XCTAssertEqual(unchanged.y, current.y, accuracy: 0.001)
    }

    func testPinningConstantsOnRegular() throws {
        let fixture = try makeRegularRoot()
        let root = fixture.root
        XCTAssertEqual(root.chromePlacement, .regular)
        let topSecond = root.topBarTopConstraint.secondItem as? UIView
        XCTAssertTrue(topSecond === root.view)
        XCTAssertEqual(root.topBarTopConstraint.secondAttribute, .top)
        XCTAssertEqual(root.topBarTopConstraint.firstAttribute, .top)
        XCTAssertEqual(root.topBarTrailingConstraint.constant, -96, accuracy: 0.001)
    }

    func testBackgroundStates() {
        let bar = TopBarView()
        TestWindow.attach(bar)
        bar.applyHeaderBackground(isCollapsed: false)
        XCTAssertEqual(bar.backgroundColor, .systemBackground)
        XCTAssertTrue(bar.isOpaque)
        XCTAssertFalse(bar.isBlurVisible)
        bar.applyHeaderBackground(isCollapsed: true)
        XCTAssertEqual(bar.backgroundColor, .clear)
        XCTAssertFalse(bar.isOpaque)
        XCTAssertTrue(bar.isBlurVisible)

        let strip = TabStripView()
        TestWindow.attach(strip)
        strip.applyHeaderBackground(isCollapsed: false)
        XCTAssertEqual(strip.backgroundColor, .systemBackground)
        XCTAssertTrue(strip.isOpaque)
        XCTAssertFalse(strip.isBlurVisible)
        strip.applyHeaderBackground(isCollapsed: true)
        XCTAssertEqual(strip.backgroundColor, .clear)
        XCTAssertFalse(strip.isOpaque)
        XCTAssertTrue(strip.isBlurVisible)
    }

    func testExpandedHeaderOpaqueWithContentBelow() throws {
        let fixture = try makeRegularRoot(tabCount: 2)
        let root = fixture.root
        XCTAssertFalse(root.topBarView.isHidden)
        XCTAssertFalse(root.tabStripView.isHidden)
        XCTAssertEqual(root.topBarView.backgroundColor, .systemBackground)
        XCTAssertTrue(root.topBarView.isOpaque)
        XCTAssertFalse(root.topBarView.isBlurVisible)
        XCTAssertTrue(root.headerRemnantView?.isHidden ?? true)
        XCTAssertEqual(root.additionalSafeAreaInsets.top, 0, accuracy: 0.001)
        XCTAssertTrue(root.startPageTopToStripConstraint?.isActive ?? false)
        XCTAssertFalse(root.startPageTopToBarConstraint?.isActive ?? true)
    }

    func testCollapsedRemnantTranslucentWithContentBehind() throws {
        let fixture = try makeRegularRoot(tabCount: 2)
        let root = fixture.root
        scroll(root, delta: 8)
        XCTAssertEqual(root.chromeController.state.rail, .hidden)
        XCTAssertTrue(root.topBarView.isHidden)
        XCTAssertTrue(root.tabStripView.isHidden)
        XCTAssertEqual(root.topBarView.backgroundColor, .clear)
        XCTAssertFalse(root.topBarView.isOpaque)
        XCTAssertTrue(root.topBarView.isBlurVisible)
        XCTAssertFalse(root.headerRemnantView?.isHidden ?? true)
        XCTAssertEqual(root.additionalSafeAreaInsets.top, TopBarView.barHeight, accuracy: 0.001)
        XCTAssertEqual(root.additionalSafeAreaInsets.top, BrowserRootViewController.regularRemnantHeight, accuracy: 0.001)
        XCTAssertTrue(root.startPageTopToBarConstraint?.isActive ?? false)
        XCTAssertFalse(root.startPageTopToStripConstraint?.isActive ?? true)
    }

    func testStartPageTopFollowsStripOrBar() throws {
        let fixture = try makeRegularRoot(tabCount: 2)
        let root = fixture.root
        root.updateStartPageTop()
        XCTAssertTrue(root.startPageTopToStripConstraint?.isActive ?? false)
        let began = root.chromeController.handle(.editBegan)
        root.applyCommands(began, animated: false)
        root.updateStartPageTop()
        XCTAssertTrue(root.tabStripView.isHidden)
        XCTAssertTrue(root.startPageTopToBarConstraint?.isActive ?? false)
    }

    func testCompactClearsAdditionalInsets() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let root = BrowserRootViewController(database: database, defaults: defaults)
        TestWindow.attach(root)
        root.applyChromePlacement(for: .compact)
        root.applyChromeViews(animated: false)
        root.applyContentInsets()
        XCTAssertEqual(root.additionalSafeAreaInsets.top, 0, accuracy: 0.001)
        XCTAssertEqual(
            BrowserRootViewController.topContentInset(
                for: .compact,
                state: root.chromeController.state,
                stripVisible: false
            ),
            0
        )
        XCTAssertTrue(root.headerRemnantView?.isHidden ?? true)
    }
}
