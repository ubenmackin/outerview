//
//  TabStripTests.swift
//  OuterViewTests
//

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class TabStripTests: XCTestCase {
    private func makeItem(title: String, isPrivate: Bool = false) -> TabOverviewItem {
        TabOverviewItem(
            id: UUID(),
            title: title,
            host: "example.com",
            url: URL(string: "https://example.com/\(title)"),
            isPrivate: isPrivate
        )
    }

    private func makeRoot() throws -> BrowserRootViewController {
        let database = try OuterViewDatabase(inMemory: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let root = BrowserRootViewController(database: database, defaults: defaults)
        TestWindow.attach(root)
        return root
    }

    private func allSubviews<T>(of view: UIView) -> [T] {
        var found: [T] = []
        for sub in view.subviews {
            if let match = sub as? T {
                found.append(match)
            }
            found.append(contentsOf: allSubviews(of: sub))
        }
        return found
    }

    func testStripFixedGeometry() {
        XCTAssertEqual(TabStripView.stripHeight, 44)
        XCTAssertEqual(TabStripView.horizontalInset, 28)
        XCTAssertEqual(TabStripView.trackHeight, 32)
        XCTAssertEqual(TabStripView.cellHeight, 32)
        XCTAssertEqual(TabStripView.minCellWidth, 140)
        XCTAssertEqual(TabStripView.cellWidth, 140)
        let strip = TabStripView()
        TestWindow.attach(strip)
        XCTAssertEqual(strip.intrinsicContentSize.height, 44)
        let layout = strip.collectionView.collectionViewLayout as? UICollectionViewFlowLayout
        XCTAssertNotNil(layout)
        XCTAssertEqual(layout?.scrollDirection, .horizontal)
        XCTAssertEqual(strip.newTabButton.accessibilityLabel, "New Tab")
        XCTAssertTrue(strip.newTabButton.isHidden)
    }

    func testTabWidthEqualDistributionAcrossAvailableWidth() {
        // 2 tabs with width 895: index 0 gets 447, index 1 gets 448 (sum = 895)
        let width0 = TabStripView.tabWidth(at: 0, count: 2, availableWidth: 895)
        let width1 = TabStripView.tabWidth(at: 1, count: 2, availableWidth: 895)
        XCTAssertEqual(width0, 447)
        XCTAssertEqual(width1, 448)
        XCTAssertEqual(width0 + width1, 895)

        // 3 tabs with width 900: each gets 300
        let w30 = TabStripView.tabWidth(at: 0, count: 3, availableWidth: 900)
        let w31 = TabStripView.tabWidth(at: 1, count: 3, availableWidth: 900)
        let w32 = TabStripView.tabWidth(at: 2, count: 3, availableWidth: 900)
        XCTAssertEqual(w30, 300)
        XCTAssertEqual(w31, 300)
        XCTAssertEqual(w32, 300)

        // 8 tabs with width 895: 895 / 8 = 111.875 < 140 minCellWidth -> clamped to 140 each
        let w8 = TabStripView.tabWidth(at: 0, count: 8, availableWidth: 895)
        XCTAssertEqual(w8, 140)
    }

    func testStripCellShowsFaviconTitleAndClose() {
        let strip = TabStripView()
        TestWindow.attach(strip)
        let item = makeItem(title: "Example")
        strip.render(tabs: [item, makeItem(title: "Second")], selectedID: item.id)
        let cell = strip.collectionView.dataSource?.collectionView(
            strip.collectionView,
            cellForItemAt: IndexPath(item: 0, section: 0)
        ) as? TabStripCell
        XCTAssertNotNil(cell)
        guard let cell else { return }
        let images: [UIImageView] = allSubviews(of: cell)
        XCTAssertFalse(images.isEmpty)
        let labels: [UILabel] = allSubviews(of: cell)
        XCTAssertTrue(labels.contains { $0.text == "Example" })
        let buttons: [UIButton] = allSubviews(of: cell)
        XCTAssertTrue(buttons.contains { $0.accessibilityLabel == "Close Tab" })
        XCTAssertTrue(cell.isCloseButtonVisible)
    }

    func testActiveTabShowsCloseAndInactiveHidesClose() {
        let strip = TabStripView()
        TestWindow.attach(strip)
        let first = makeItem(title: "Active")
        let second = makeItem(title: "Inactive")
        strip.render(tabs: [first, second], selectedID: first.id)

        let activeCell = strip.collectionView.dataSource?.collectionView(
            strip.collectionView,
            cellForItemAt: IndexPath(item: 0, section: 0)
        ) as? TabStripCell
        let inactiveCell = strip.collectionView.dataSource?.collectionView(
            strip.collectionView,
            cellForItemAt: IndexPath(item: 1, section: 0)
        ) as? TabStripCell

        XCTAssertNotNil(activeCell)
        XCTAssertNotNil(inactiveCell)
        XCTAssertTrue(activeCell?.isCloseButtonVisible ?? false)
        XCTAssertFalse(inactiveCell?.isCloseButtonVisible ?? true)
        XCTAssertTrue(activeCell?.accessibilityTraits.contains(.selected) ?? false)
        XCTAssertFalse(inactiveCell?.accessibilityTraits.contains(.selected) ?? true)
    }

    func testBelowTwoHiddenRule() throws {
        let root = try makeRoot()
        let first = TabRecord(isPrivate: false)
        let second = TabRecord(isPrivate: false)
        root.tabs = [first]
        root.selectedTabID = first.id
        root.applyChromePlacement(for: .regular)
        XCTAssertTrue(root.tabStripView.isHidden)

        root.tabs = [first, second]
        root.selectedTabID = first.id
        root.applyChromePlacement(for: .regular)
        XCTAssertFalse(root.tabStripView.isHidden)
        XCTAssertEqual(root.tabStripView.displayedTabs.count, 2)
    }

    func testSingleTabHidesStrip() throws {
        let root = try makeRoot()
        let only = TabRecord(isPrivate: false)
        root.tabs = [only]
        root.selectedTabID = only.id
        root.applyChromePlacement(for: .regular)
        root.updateTabStrip()
        XCTAssertTrue(root.tabStripView.isHidden)
    }

    func testTwoTabsShowStrip() throws {
        let root = try makeRoot()
        let first = TabRecord(isPrivate: false)
        let second = TabRecord(isPrivate: false)
        root.tabs = [first, second]
        root.selectedTabID = first.id
        root.applyChromePlacement(for: .regular)
        root.updateTabStrip()
        XCTAssertFalse(root.tabStripView.isHidden)
    }

    func testSelectDelegationSwitchesTab() throws {
        let root = try makeRoot()
        let first = TabRecord(isPrivate: false)
        let second = TabRecord(isPrivate: false)
        root.tabs = [first, second]
        root.selectedTabID = first.id
        root.applyChromePlacement(for: .regular)
        XCTAssertEqual(root.selectedTabID, first.id)
        root.tabStripView.onSelectTab?(second.id)
        XCTAssertEqual(root.selectedTabID, second.id)
    }

    func testCloseDelegationRemovesTabAndUpdatesSelection() throws {
        let root = try makeRoot()
        let first = TabRecord(isPrivate: false)
        let second = TabRecord(isPrivate: false)
        root.tabs = [first, second]
        root.selectedTabID = first.id
        root.applyChromePlacement(for: .regular)
        XCTAssertFalse(root.tabStripView.isHidden)
        root.tabStripView.onCloseTab?(first.id)
        XCTAssertEqual(root.tabs.count, 1)
        XCTAssertEqual(root.tabs.first?.id, second.id)
        XCTAssertEqual(root.selectedTabID, second.id)
        XCTAssertTrue(root.tabStripView.isHidden)
    }

    func testNewDelegationCreatesTab() throws {
        let root = try makeRoot()
        let first = TabRecord(isPrivate: false)
        let second = TabRecord(isPrivate: false)
        root.tabs = [first, second]
        root.selectedTabID = first.id
        root.applyChromePlacement(for: .regular)
        let before = root.tabs.count
        root.tabStripView.onNewTab?()
        XCTAssertEqual(root.tabs.count, before + 1)
    }

    func testSelectedStateRendering() {
        let strip = TabStripView()
        TestWindow.attach(strip)
        let first = makeItem(title: "First")
        let second = makeItem(title: "Second")
        strip.render(tabs: [first, second], selectedID: second.id)
        XCTAssertEqual(strip.displayedSelectedID, second.id)
        let selected = strip.collectionView.dataSource?.collectionView(
            strip.collectionView,
            cellForItemAt: IndexPath(item: 1, section: 0)
        ) as? TabStripCell
        let unselected = strip.collectionView.dataSource?.collectionView(
            strip.collectionView,
            cellForItemAt: IndexPath(item: 0, section: 0)
        ) as? TabStripCell
        XCTAssertNotNil(selected)
        XCTAssertNotNil(unselected)
        XCTAssertTrue(selected?.accessibilityTraits.contains(.selected) ?? false)
        XCTAssertFalse(unselected?.accessibilityTraits.contains(.selected) ?? true)
    }

    func testCompactPlacementHidesStrip() throws {
        let root = try makeRoot()
        let first = TabRecord(isPrivate: false)
        let second = TabRecord(isPrivate: false)
        root.tabs = [first, second]
        root.selectedTabID = first.id
        root.applyChromePlacement(for: .regular)
        XCTAssertFalse(root.tabStripView.isHidden)
        root.applyChromePlacement(for: .compact)
        root.updateTabStrip()
        XCTAssertTrue(root.tabStripView.isHidden)
        XCTAssertTrue(root.topBarView.isHidden)
        XCTAssertFalse(root.railView.isHidden)
    }

    func testStripStaysHiddenOnOuterDisplay() throws {
        let root = try makeRoot()
        let first = TabRecord(isPrivate: false)
        let second = TabRecord(isPrivate: false)
        root.tabs = [first, second]
        root.selectedTabID = first.id
        root.applyChromePlacement(for: .compact)
        root.updateTabStrip()
        XCTAssertTrue(root.tabStripView.isHidden)
    }

    func testStripShowsOnlyActiveModeInOrder() throws {
        let root = try makeRoot()
        let standardFirst = TabRecord(isPrivate: false)
        let privateOnly = TabRecord(isPrivate: true)
        let standardSecond = TabRecord(isPrivate: false)
        root.tabs = [standardFirst, privateOnly, standardSecond]
        root.selectedTabID = standardFirst.id
        root.setOverviewMode(.standard)
        root.applyChromePlacement(for: .regular)
        root.updateTabStrip()
        XCTAssertFalse(root.tabStripView.isHidden)
        XCTAssertEqual(root.tabStripView.displayedTabs.map(\.id), [standardFirst.id, standardSecond.id])
    }
}
