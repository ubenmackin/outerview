// Chrome — Regular header layout and pill width verification.

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
/// both stacks plus strip hidden and the pill minified centered in its slot;
/// collapsed top inset equals TopBarView.remnantHeight; additionalSafeArea top
/// is zero in every placement and state; no remnant view exists anywhere.
@MainActor
final class RegularHeaderTests: XCTestCase {
    private func makeRegularRoot(tabCount: Int = 2) throws -> (parent: UIViewController, root: BrowserRootViewController) {
        let database = try OuterViewDatabase(inMemory: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let root = BrowserRootViewController(database: database, defaults: defaults)
        let parent = UIViewController()
        // Regular needs inner-display width; 466 pt outer leaves no slot for caps.
        TestWindow.attach(parent, frame: CGRect(x: 0, y: 0, width: 951, height: 669))
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

    private func hasRemnantProperty(_ root: BrowserRootViewController) -> Bool {
        Mirror(reflecting: root).children.contains { $0.label == "headerRemnantView" }
    }

    func testStaticsMatchRegularHeaderContract() {
        XCTAssertEqual(TopBarView.barHeight, 84)
        XCTAssertEqual(TabStripView.stripHeight, 44)
        XCTAssertEqual(TopBarView.remnantHeight, 48)
        XCTAssertEqual(BrowserRootViewController.regularRemnantHeight, TopBarView.remnantHeight)
        XCTAssertEqual(BrowserRootViewController.regularTrailingClearance, 84)
        XCTAssertEqual(TopBarView.horizontalInset, 28)
        XCTAssertEqual(TopBarView.trailingStatusInset, 84)
        XCTAssertEqual(TopBarView.clusterSpacing, 12)
        XCTAssertEqual(TopBarView.expandedPillMaxWidth, 380)
        XCTAssertEqual(AddressBarView.minifiedMaxWidth, 220)
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

    func testCollapsedTopInsetEqualsRemnant() {
        let collapsed = ChromeState(rail: .hidden, pill: .minified)
        XCTAssertEqual(
            BrowserRootViewController.topContentInset(for: .regular, state: collapsed, stripVisible: false),
            TopBarView.remnantHeight
        )
        XCTAssertEqual(
            BrowserRootViewController.topContentInset(for: .regular, state: collapsed, stripVisible: true),
            TopBarView.remnantHeight
        )
        XCTAssertEqual(
            BrowserRootViewController.additionalSafeAreaTopInset(for: .regular, state: collapsed),
            0
        )
        let expanded = ChromeState(rail: .visible, pill: .expanded)
        XCTAssertEqual(
            BrowserRootViewController.additionalSafeAreaTopInset(for: .regular, state: expanded),
            0
        )
    }

    func testAdditionalSafeAreaZeroEverywhere() {
        let states = [
            ChromeState(rail: .visible, pill: .expanded),
            ChromeState(rail: .hidden, pill: .minified),
            ChromeState(rail: .hidden, pill: .expanded),
            ChromeState(rail: .hidden, pill: .editing),
            ChromeState(rail: .visible, pill: .editing)
        ]
        for state in states {
            XCTAssertEqual(
                BrowserRootViewController.additionalSafeAreaTopInset(for: .regular, state: state),
                0
            )
            XCTAssertEqual(
                BrowserRootViewController.additionalSafeAreaTopInset(for: .compact, state: state),
                0
            )
        }
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
        XCTAssertEqual(forward.y, 300, accuracy: 0.001)
        XCTAssertEqual(forward.x, current.x, accuracy: 0.001)
        let back = BrowserRootViewController.compensatedOffset(current: forward, oldTop: 0, newTop: 100)
        XCTAssertEqual(back.x, current.x, accuracy: 0.001)
        XCTAssertEqual(back.y, current.y, accuracy: 0.001)
        let unchanged = BrowserRootViewController.compensatedOffset(current: current, oldTop: 84, newTop: 84)
        XCTAssertEqual(unchanged.x, current.x, accuracy: 0.001)
        XCTAssertEqual(unchanged.y, current.y, accuracy: 0.001)
        let restingCollapse = BrowserRootViewController.compensatedOffset(
            current: CGPoint(x: 0, y: -TopBarView.barHeight),
            oldTop: TopBarView.barHeight,
            newTop: TopBarView.remnantHeight
        )
        XCTAssertEqual(restingCollapse.y, -TopBarView.remnantHeight, accuracy: 0.001)
        let restingExpand = BrowserRootViewController.compensatedOffset(
            current: CGPoint(x: 0, y: -TopBarView.remnantHeight),
            oldTop: TopBarView.remnantHeight,
            newTop: TopBarView.barHeight
        )
        XCTAssertEqual(restingExpand.y, -TopBarView.barHeight, accuracy: 0.001)
        let restingExpandTwoTabs = BrowserRootViewController.compensatedOffset(
            current: CGPoint(x: 0, y: -TopBarView.remnantHeight),
            oldTop: TopBarView.remnantHeight,
            newTop: TopBarView.barHeight + TabStripView.stripHeight
        )
        XCTAssertEqual(restingExpandTwoTabs.y, -(TopBarView.barHeight + TabStripView.stripHeight), accuracy: 0.001)
    }

    func testPinningConstantsOnRegular() throws {
        let fixture = try makeRegularRoot()
        let root = fixture.root
        XCTAssertEqual(root.chromePlacement, .regular)
        let topBarTop = try XCTUnwrap(root.topBarTopConstraint)
        let topSecond = topBarTop.secondItem as? UIView
        XCTAssertTrue(topSecond === root.view)
        XCTAssertEqual(topBarTop.secondAttribute, .top)
        XCTAssertEqual(topBarTop.firstAttribute, .top)
        XCTAssertEqual(try XCTUnwrap(root.topBarTrailingConstraint).constant, 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(root.topBarLeadingConstraint).constant, 0, accuracy: 0.001)
    }

    func testAlwaysBlurBackground() {
        let bar = TopBarView()
        TestWindow.attach(bar)
        bar.applyHeaderBackground()
        XCTAssertEqual(bar.backgroundColor, .clear)
        XCTAssertFalse(bar.isOpaque)
        XCTAssertTrue(bar.isBlurVisible)
        let strip = TabStripView()
        TestWindow.attach(strip)
        strip.applyHeaderBackground()
        XCTAssertEqual(strip.backgroundColor, .clear)
        XCTAssertFalse(strip.isOpaque)
        XCTAssertTrue(strip.isBlurVisible)
    }

    func testBarFullWidthTrailing() throws {
        let fixture = try makeRegularRoot()
        let root = fixture.root
        XCTAssertEqual(try XCTUnwrap(root.topBarTrailingConstraint).constant, 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(root.topBarLeadingConstraint).constant, 0, accuracy: 0.001)
    }

    func testClusterInsetsAndSpacing() {
        XCTAssertEqual(TopBarView.horizontalInset, 28)
        XCTAssertEqual(TopBarView.trailingStatusInset, 84)
        XCTAssertEqual(TopBarView.clusterSpacing, 12)
        let bar = TopBarView()
        TestWindow.attach(bar)
        XCTAssertEqual(bar.leadingStack.spacing, 12)
        XCTAssertEqual(bar.trailingStack.spacing, 12)
    }

    func testPillCapsPerState() throws {
        let fixture = try makeRegularRoot(tabCount: 2)
        let root = fixture.root
        XCTAssertFalse(try XCTUnwrap(root.pillSlotLeadingConstraint).isActive)
        XCTAssertFalse(try XCTUnwrap(root.pillSlotTrailingConstraint).isActive)
        XCTAssertTrue(try XCTUnwrap(root.pillSlotCenterXConstraint).isActive)
        XCTAssertTrue(try XCTUnwrap(root.pillSlotWidthConstraint).isActive)
        let expandedSlotWidth = root.topBarView.pillSlotView.bounds.width
        let expandedExpected = BrowserRootViewController.regularPillTarget(
            slotWidth: expandedSlotWidth,
            isMinified: false,
            preferredMinifiedWidth: root.pillView.preferredMinifiedWidth()
        )
        XCTAssertEqual(TopBarView.expandedPillMaxWidth, 380)
        XCTAssertEqual(try XCTUnwrap(root.pillSlotWidthConstraint).constant, expandedExpected, accuracy: 0.5)
        scroll(root, delta: 30)
        root.view.layoutIfNeeded()
        root.view.layoutIfNeeded()
        root.view.layoutIfNeeded()
        XCTAssertFalse(try XCTUnwrap(root.pillSlotLeadingConstraint).isActive)
        XCTAssertFalse(try XCTUnwrap(root.pillSlotTrailingConstraint).isActive)
        XCTAssertTrue(try XCTUnwrap(root.pillSlotCenterXConstraint).isActive)
        XCTAssertTrue(try XCTUnwrap(root.pillSlotWidthConstraint).isActive)
        let slotWidth = root.topBarView.pillSlotView.bounds.width
        let minifiedExpected = BrowserRootViewController.regularPillTarget(
            slotWidth: slotWidth,
            isMinified: true,
            preferredMinifiedWidth: root.pillView.preferredMinifiedWidth()
        )
        XCTAssertEqual(AddressBarView.minifiedMaxWidth, 220)
        XCTAssertEqual(try XCTUnwrap(root.pillSlotWidthConstraint).constant, minifiedExpected, accuracy: 0.5)
    }

    func testExpandedHeaderTranslucentWithContentBelow() throws {
        let fixture = try makeRegularRoot(tabCount: 2)
        let root = fixture.root
        XCTAssertFalse(root.topBarView.isHidden)
        XCTAssertFalse(root.topBarView.leadingStack.isHidden)
        XCTAssertFalse(root.topBarView.trailingStack.isHidden)
        XCTAssertFalse(root.tabStripView.isHidden)
        XCTAssertEqual(root.topBarView.backgroundColor, .clear)
        XCTAssertFalse(root.topBarView.isOpaque)
        XCTAssertTrue(root.topBarView.isBlurVisible)
        XCTAssertFalse(hasRemnantProperty(root))
        XCTAssertEqual(root.additionalSafeAreaInsets.top, 0, accuracy: 0.001)
        XCTAssertFalse(try XCTUnwrap(root.pillSlotLeadingConstraint).isActive)
        XCTAssertFalse(try XCTUnwrap(root.pillSlotTrailingConstraint).isActive)
        XCTAssertTrue(try XCTUnwrap(root.pillSlotCenterXConstraint).isActive)
        XCTAssertTrue(try XCTUnwrap(root.pillSlotWidthConstraint).isActive)
        let slotWidth = root.topBarView.pillSlotView.bounds.width
        let expected = BrowserRootViewController.regularPillTarget(
            slotWidth: slotWidth,
            isMinified: false,
            preferredMinifiedWidth: root.pillView.preferredMinifiedWidth()
        )
        XCTAssertEqual(try XCTUnwrap(root.pillSlotWidthConstraint).constant, expected, accuracy: 0.5)
        XCTAssertTrue(root.startPageTopToStripConstraint?.isActive ?? false)
        XCTAssertFalse(root.startPageTopToBarConstraint?.isActive ?? true)
    }

    func testCollapsedKeepsMiniCapsuleCentered() throws {
        let fixture = try makeRegularRoot(tabCount: 2)
        let root = fixture.root
        XCTAssertFalse(root.topBarView.isCollapsed)
        XCTAssertEqual(root.topBarView.currentHeightConstant, TopBarView.barHeight)
        XCTAssertFalse(root.prefersStatusBarHidden)
        scroll(root, delta: 30)
        root.view.layoutIfNeeded()
        root.view.layoutIfNeeded()
        root.view.layoutIfNeeded()
        XCTAssertEqual(root.chromeController.state.rail, .hidden)
        XCTAssertEqual(root.chromeController.state.pill, .minified)
        XCTAssertFalse(root.topBarView.isHidden)
        XCTAssertTrue(root.topBarView.isCollapsed)
        XCTAssertEqual(root.topBarView.currentHeightConstant, TopBarView.remnantHeight)
        XCTAssertTrue(root.prefersStatusBarHidden)
        XCTAssertTrue(root.topBarView.leadingStack.isHidden)
        XCTAssertTrue(root.topBarView.trailingStack.isHidden)
        XCTAssertTrue(root.tabStripView.isHidden)
        XCTAssertEqual(root.topBarView.backgroundColor, .clear)
        XCTAssertFalse(root.topBarView.isOpaque)
        XCTAssertTrue(root.topBarView.isBlurVisible)
        XCTAssertFalse(hasRemnantProperty(root))
        XCTAssertEqual(root.additionalSafeAreaInsets.top, 0, accuracy: 0.001)
        XCTAssertFalse(try XCTUnwrap(root.pillSlotLeadingConstraint).isActive)
        XCTAssertFalse(try XCTUnwrap(root.pillSlotTrailingConstraint).isActive)
        XCTAssertTrue(try XCTUnwrap(root.pillSlotCenterXConstraint).isActive)
        XCTAssertTrue(try XCTUnwrap(root.pillSlotWidthConstraint).isActive)
        let slotWidth = root.topBarView.pillSlotView.bounds.width
        let expected = BrowserRootViewController.regularPillTarget(
            slotWidth: slotWidth,
            isMinified: true,
            preferredMinifiedWidth: root.pillView.preferredMinifiedWidth()
        )
        XCTAssertEqual(try XCTUnwrap(root.pillSlotWidthConstraint).constant, expected, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(root.pillHeightConstraint).constant, AddressBarView.minifiedHeight, accuracy: 0.001)
        XCTAssertTrue(root.startPageTopToBarConstraint?.isActive ?? false)
        XCTAssertFalse(root.startPageTopToStripConstraint?.isActive ?? true)
        scroll(root, delta: -40)
        root.view.layoutIfNeeded()
        root.view.layoutIfNeeded()
        root.view.layoutIfNeeded()
        XCTAssertEqual(root.chromeController.state.rail, .visible)
        XCTAssertFalse(root.topBarView.isHidden)
        XCTAssertFalse(root.topBarView.isCollapsed)
        XCTAssertEqual(root.topBarView.currentHeightConstant, TopBarView.barHeight)
        XCTAssertFalse(root.prefersStatusBarHidden)
        XCTAssertFalse(root.topBarView.leadingStack.isHidden)
        XCTAssertFalse(root.topBarView.trailingStack.isHidden)
        XCTAssertFalse(root.tabStripView.isHidden)
        XCTAssertEqual(root.topBarView.backgroundColor, .clear)
        XCTAssertFalse(root.topBarView.isOpaque)
        XCTAssertTrue(root.topBarView.isBlurVisible)
        XCTAssertFalse(try XCTUnwrap(root.pillSlotLeadingConstraint).isActive)
        XCTAssertFalse(try XCTUnwrap(root.pillSlotTrailingConstraint).isActive)
        XCTAssertTrue(try XCTUnwrap(root.pillSlotCenterXConstraint).isActive)
        XCTAssertTrue(try XCTUnwrap(root.pillSlotWidthConstraint).isActive)
        let restoredSlotWidth = root.topBarView.pillSlotView.bounds.width
        let restoredExpected = BrowserRootViewController.regularPillTarget(
            slotWidth: restoredSlotWidth,
            isMinified: false,
            preferredMinifiedWidth: root.pillView.preferredMinifiedWidth()
        )
        XCTAssertEqual(try XCTUnwrap(root.pillSlotWidthConstraint).constant, restoredExpected, accuracy: 0.5)
    }

    func testNoRemnantViewExists() throws {
        let fixture = try makeRegularRoot(tabCount: 2)
        let root = fixture.root
        XCTAssertFalse(hasRemnantProperty(root))
        scroll(root, delta: 30)
        root.view.layoutIfNeeded()
        XCTAssertFalse(hasRemnantProperty(root))
        let strayRemnants = root.view.subviews.filter { $0 is UIVisualEffectView && $0.superview === root.view }
        XCTAssertTrue(strayRemnants.isEmpty)
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
        XCTAssertFalse(hasRemnantProperty(root))
    }

    func testContentOffsetRestingTopPreservation() throws {
        let fixture = try makeRegularRoot(tabCount: 2)
        let root = fixture.root
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let tab1 = TabRecord(url: url, title: "Example 1", isPrivate: false)
        let tab2 = TabRecord(url: url, title: "Example 2", isPrivate: false)
        root.tabs = [tab1, tab2]
        root.tabPool.create(tab1)
        root.tabPool.create(tab2)
        root.selectedTabID = tab1.id
        root.displaySelectedTabForTest(id: tab1.id)
        root.applyChromeViews(animated: false)
        root.view.layoutIfNeeded()

        guard let page = root.peekActivePage() else {
            XCTFail("Missing active page")
            return
        }
        let webView = page.webView
        let expandedTop = TopBarView.barHeight + TabStripView.stripHeight
        XCTAssertEqual(webView.obscuredContentInsets.top, expandedTop)
        // Resting top is -expandedTop (-128)
        webView.scrollView.contentOffset = CGPoint(x: 0, y: -expandedTop)

        // Scroll down to collapse chrome (delta >= 24 minifies pill, which collapses regular header)
        scroll(root, delta: 25)
        XCTAssertEqual(root.chromeController.state.pill, .minified)
        let collapsedTop = TopBarView.remnantHeight
        XCTAssertEqual(webView.obscuredContentInsets.top, collapsedTop)
        XCTAssertEqual(webView.scrollView.contentOffset.y, -collapsedTop, accuracy: 0.001)

        // Scroll up to reveal chrome
        scroll(root, delta: -40)
        XCTAssertEqual(root.chromeController.state.rail, .visible)
        XCTAssertEqual(webView.obscuredContentInsets.top, expandedTop)
        XCTAssertEqual(webView.scrollView.contentOffset.y, -expandedTop, accuracy: 0.001)
    }
}
