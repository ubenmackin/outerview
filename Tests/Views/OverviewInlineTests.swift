// TabOverview — Inline toolbar visibility and search filtering verification.

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class OverviewInlineTests: XCTestCase {
    private func makeItem(title: String, host: String = "example.com") -> TabOverviewItem {
        TabOverviewItem(
            title: title,
            host: host,
            url: URL(string: "https://\(host)/\(title.lowercased())"),
            isPrivate: false
        )
    }

    private func makeOverview(tabs: [TabOverviewItem]? = nil) -> TabOverviewViewController {
        let overview = TabOverviewViewController()
        let parent = UIViewController()
        let window = TestWindow.attach(parent)
        window.rootViewController = parent
        window.makeKeyAndVisible()
        parent.addChild(overview)
        parent.view.addSubview(overview.view)
        overview.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overview.view.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
            overview.view.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
            overview.view.topAnchor.constraint(equalTo: parent.view.topAnchor),
            overview.view.bottomAnchor.constraint(equalTo: parent.view.bottomAnchor)
        ])
        overview.didMove(toParent: parent)
        parent.view.layoutIfNeeded()
        overview.view.layoutIfNeeded()
        let items = tabs ?? [makeItem(title: "Apple"), makeItem(title: "Banana")]
        overview.configure(tabs: items, selectedID: items.first?.id, mode: .standard)
        overview.view.layoutIfNeeded()
        return overview
    }

    private func makeRegularRoot() throws -> (parent: UIViewController, root: BrowserRootViewController) {
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
        return (parent, root)
    }

    private func isPresentationSettled(_ overview: TabOverviewViewController) -> Bool {
        guard let presented = overview.presentedViewController else { return false }
        return !overview.isBeingPresented
            && !overview.isBeingDismissed
            && !presented.isBeingPresented
            && !presented.isBeingDismissed
            && overview.transitionCoordinator == nil
            && presented.transitionCoordinator == nil
    }

    private func isDismissalSettled(_ overview: TabOverviewViewController) -> Bool {
        overview.presentedViewController == nil
            && !overview.isBeingPresented
            && !overview.isBeingDismissed
            && overview.transitionCoordinator == nil
    }

    private func waitForPresented(_ overview: TabOverviewViewController, timeout: TimeInterval = 5.0) -> UIViewController? {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            // Require the presentation transition to finish so a follow-up
            // dismiss cannot land mid-animation and leave the next present as a no-op.
            if isPresentationSettled(overview) {
                return overview.presentedViewController
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        return isPresentationSettled(overview) ? overview.presentedViewController : nil
    }

    private func waitForDismissed(_ overview: TabOverviewViewController, timeout: TimeInterval = 5.0) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while Date() < deadline {
            if isDismissalSettled(overview) {
                return true
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        return isDismissalSettled(overview)
    }

    func testStaticsMatchRegularHeaderContract() {
        XCTAssertEqual(TopBarView.barHeight, 84)
        XCTAssertEqual(TabStripView.stripHeight, 44)
        XCTAssertEqual(TopBarView.remnantHeight, 48)
        XCTAssertEqual(BrowserRootViewController.regularRemnantHeight, TopBarView.remnantHeight)
        XCTAssertEqual(TopBarView.trailingStatusInset, 164)
        XCTAssertEqual(BrowserRootViewController.regularTrailingClearance, 164)
    }

    func testInlineBarVisibilityPerPlacement() {
        let overview = makeOverview()
        XCTAssertFalse(overview.showsInlineCommands)
        XCTAssertFalse(overview.isInlineBarVisible)
        XCTAssertFalse(overview.isInlineSearchVisible)
        XCTAssertFalse(overview.isInlineMenuVisible)
        XCTAssertFalse(overview.isInlineDoneVisible)
        overview.showsInlineCommands = true
        overview.view.layoutIfNeeded()
        XCTAssertTrue(overview.isInlineBarVisible)
        XCTAssertTrue(overview.isInlineSearchVisible)
        XCTAssertTrue(overview.isInlineMenuVisible)
        XCTAssertTrue(overview.isInlineDoneVisible)
        overview.showsInlineCommands = false
        overview.view.layoutIfNeeded()
        XCTAssertFalse(overview.isInlineBarVisible)
    }

    func testRootPropagatesPlacementToInlineFlag() throws {
        let fixture = try makeRegularRoot()
        let root = fixture.root
        root.applyStructuralLayout()
        XCTAssertEqual(root.chromePlacement, .regular)
        XCTAssertTrue(root.overviewController.showsInlineCommands)
        XCTAssertTrue(root.overviewController.isInlineBarVisible)
        XCTAssertTrue(root.railView.isHidden)
        root.traitOverrides.horizontalSizeClass = .compact
        fixture.parent.view.layoutIfNeeded()
        root.view.layoutIfNeeded()
        root.applyStructuralLayout()
        XCTAssertEqual(root.chromePlacement, .compact)
        XCTAssertFalse(root.overviewController.showsInlineCommands)
        XCTAssertFalse(root.overviewController.isInlineBarVisible)
        XCTAssertFalse(root.railView.isHidden)
    }

    func testMode3OverviewShowsTopToolbar() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let root = BrowserRootViewController(database: database)
        let phoneFrame = CGRect(x: 0, y: 0, width: 402, height: 874)
        TestWindow.attach(root, frame: phoneFrame)
        root.traitOverrides.horizontalSizeClass = .compact
        root.view.layoutIfNeeded()
        root.applyChromePlacement(for: .compact)
        root.setOverviewVisible(true)
        root.view.layoutIfNeeded()

        XCTAssertEqual(root.interfaceMode, .nonDuoPhone)
        XCTAssertTrue(root.overviewController.showsInlineCommands)
        XCTAssertTrue(root.overviewController.isInlineBarVisible)
        XCTAssertTrue(root.overviewController.isInlineSearchVisible)
        XCTAssertTrue(root.overviewController.isInlineMenuVisible)
        XCTAssertTrue(root.overviewController.isInlineDoneVisible)
        XCTAssertTrue(root.railView.isHidden)
    }

    func testCompactKeepsRailCompositionPath() {
        let overview = makeOverview()
        XCTAssertFalse(overview.showsInlineCommands)
        let items = overview.overviewChromeItems()
        XCTAssertEqual(items.prefix.count, 2)
        XCTAssertEqual(items.suffix.count, 2)
        XCTAssertEqual(items.prefix[0].accessibilityLabel, "Search")
        XCTAssertEqual(items.prefix[1].accessibilityLabel, "Overview Menu")
        XCTAssertEqual(items.suffix[0].accessibilityLabel, "New Tab")
        XCTAssertEqual(items.suffix[1].accessibilityLabel, "Done")
        overview.setFilterVisible(true)
        XCTAssertFalse(overview.isInlineBarVisible)
        overview.setFilterVisible(false)
    }

    func testSearchFilteringThroughInlineField() {
        let tabs = [makeItem(title: "Apple"), makeItem(title: "Banana"), makeItem(title: "Cherry")]
        let overview = makeOverview(tabs: tabs)
        overview.showsInlineCommands = true
        overview.view.layoutIfNeeded()
        XCTAssertEqual(overview.visibleItems.count, 3)
        overview.filterField.text = "appl"
        overview.filterField.sendActions(for: .editingChanged)
        XCTAssertEqual(overview.filterQuery, "appl")
        XCTAssertEqual(overview.visibleItems.map(\.title), ["Apple"])
        overview.filterField.text = ""
        overview.filterField.sendActions(for: .editingChanged)
        XCTAssertEqual(overview.visibleItems.count, 3)
    }

    func testMenuActionForwarding() {
        let overview = makeOverview()
        overview.showsInlineCommands = true
        overview.view.layoutIfNeeded()
        let actions = overview.overviewMenuActions(includesCloseAll: true)
        XCTAssertEqual(actions.map(\.title), ["Manage Tab Groups", "New Group…", "Close All Tabs"])
        let inlineMenu = overview.makeInlineOverviewMenu()
        let inlineTitles = inlineMenu.children.compactMap { ($0 as? UIAction)?.title }
        XCTAssertEqual(inlineTitles, ["Manage Tab Groups", "New Group…", "Close All Tabs"])
        XCTAssertNotNil(overview.inlineMenu)
        let buttonTitles = overview.inlineMenu?.children.compactMap { ($0 as? UIAction)?.title }
        XCTAssertEqual(buttonTitles, inlineTitles)
        let railMenu = overview.makeOverviewMenu(includesCloseAll: true)
        XCTAssertEqual(railMenu.children.count, 1)
        XCTAssertTrue(railMenu.children.first is UIDeferredMenuElement)
        overview.showGroupsSheet()
        XCTAssertTrue(waitForPresented(overview) is TabGroupsSheetController)
        overview.dismiss(animated: false)
        XCTAssertTrue(waitForDismissed(overview))
        overview.showCloseAllSheet()
        XCTAssertTrue(waitForPresented(overview) is UIAlertController)
        overview.dismiss(animated: false)
        XCTAssertTrue(waitForDismissed(overview))
        overview.promptNewGroupCreation(withTabIDs: [])
        XCTAssertTrue(waitForPresented(overview) is UIAlertController)
        overview.dismiss(animated: false)
        XCTAssertTrue(waitForDismissed(overview))
    }

    func testDoneFinishingThroughDelegate() {
        let overview = makeOverview()
        overview.showsInlineCommands = true
        overview.view.layoutIfNeeded()
        let delegate = OverviewInlineDelegate()
        overview.delegate = delegate
        XCTAssertEqual(delegate.finishCount, 0)
        overview.performInlineDone()
        XCTAssertEqual(delegate.finishCount, 1)
    }

    func testSelectedCardFrameReturnsConvertedFrameAndNilWhenMissing() {
        let item1 = makeItem(title: "First")
        let item2 = makeItem(title: "Second")
        let overview = makeOverview(tabs: [item1, item2])
        overview.view.bounds = CGRect(x: 0, y: 0, width: 400, height: 600)
        overview.view.layoutIfNeeded()

        let frame = overview.selectedCardFrame(in: overview.view)
        XCTAssertNotNil(frame)
        if let frame {
            XCTAssertGreaterThan(frame.width, 0)
            XCTAssertGreaterThan(frame.height, 0)
        }

        overview.setItems([item1, item2], selectedID: nil)
        XCTAssertNil(overview.selectedCardFrame(in: overview.view))

        overview.setItems([item1, item2], selectedID: UUID())
        XCTAssertNil(overview.selectedCardFrame(in: overview.view))
    }
}

@MainActor
private final class OverviewInlineDelegate: TabOverviewViewControllerDelegate {
    var finishCount = 0
    func tabOverviewDidFinish(_: TabOverviewViewController) {
        finishCount += 1
    }
}
