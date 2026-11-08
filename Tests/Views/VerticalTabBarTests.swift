// TabOverview — Vertical tab bar tests for portrait tablet/foldable mode.

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class VerticalTabBarTests: XCTestCase {
    func testVerticalTabBarRendersTabsAndSelection() {
        let bar = VerticalTabBarView(frame: CGRect(x: 0, y: 0, width: 52, height: 400))
        let idA = UUID()
        let idB = UUID()
        let itemA = TabOverviewItem(id: idA, title: "Apple", host: "apple.com", url: URL(string: "https://apple.com"), isPrivate: false)
        let itemB = TabOverviewItem(id: idB, title: "Google", host: "google.com", url: URL(string: "https://google.com"), isPrivate: false)

        bar.render(tabs: [itemA, itemB], selectedID: idA)

        XCTAssertEqual(bar.displayedTabs.count, 2)
        XCTAssertEqual(bar.displayedSelectedID, idA)
    }

    func testVerticalTabBarSelectionCallback() {
        let bar = VerticalTabBarView(frame: CGRect(x: 0, y: 0, width: 52, height: 400))
        let idA = UUID()
        let itemA = TabOverviewItem(id: idA, title: "Apple", host: "apple.com", url: URL(string: "https://apple.com"), isPrivate: false)

        var selectedTab: UUID?
        bar.onSelectTab = { id in
            selectedTab = id
        }

        bar.render(tabs: [itemA], selectedID: idA)

        guard let tabView = bar.itemViews[idA] else {
            XCTFail("Tab item view for Apple not found")
            return
        }

        tabView.handleTap()
        XCTAssertEqual(selectedTab, idA)
    }

    func testVerticalTabBarNewTabCallback() {
        let bar = VerticalTabBarView(frame: CGRect(x: 0, y: 0, width: 52, height: 400))
        bar.showsNewTabButton = true
        var newTabTapped = false
        bar.onNewTab = {
            newTabTapped = true
        }
        bar.render(tabs: [], selectedID: nil)

        // Find new tab button
        let buttons = bar.subviews.flatMap(\.subviews).flatMap(\.subviews).compactMap { $0 as? UIButton }
        guard let newButton = buttons.first(where: { $0.accessibilityLabel == "New Tab" }) else {
            XCTFail("New tab button not found")
            return
        }

        newButton.sendActions(for: .touchUpInside)
        XCTAssertTrue(newTabTapped)
    }

    func testVerticalTabBarBottomUpOrdering() {
        let bar = VerticalTabBarView(frame: CGRect(x: 0, y: 0, width: 52, height: 400))
        let idA = UUID()
        let idB = UUID()
        let itemA = TabOverviewItem(id: idA, title: "FirstTab", host: "first.com", url: URL(string: "https://first.com"), isPrivate: false)
        let itemB = TabOverviewItem(id: idB, title: "SecondTab", host: "second.com", url: URL(string: "https://second.com"), isPrivate: false)

        bar.render(tabs: [itemA, itemB], selectedID: idA)

        let scroll = bar.subviews.compactMap { $0 as? UIScrollView }.first
        let stack = scroll?.subviews.compactMap { $0 as? UIStackView }.first
        let itemViews = stack?.arrangedSubviews.compactMap { $0 as? VerticalTabItemView } ?? []
        XCTAssertEqual(itemViews.count, 2)
        XCTAssertEqual(itemViews.first?.accessibilityLabel, "SecondTab, second.com")
        XCTAssertEqual(itemViews.last?.accessibilityLabel, "FirstTab, first.com")
    }

    func testVerticalTabBarShowsNewTabToggle() {
        let bar = VerticalTabBarView(frame: CGRect(x: 0, y: 0, width: 52, height: 400))
        bar.showsNewTabButton = false
        bar.render(tabs: [], selectedID: nil)

        let buttonsFalse = bar.subviews.flatMap(\.subviews).flatMap(\.subviews).compactMap { $0 as? UIButton }
        XCTAssertFalse(buttonsFalse.contains(where: { $0.accessibilityLabel == "New Tab" }))

        bar.showsNewTabButton = true
        let buttonsTrue = bar.subviews.flatMap(\.subviews).flatMap(\.subviews).compactMap { $0 as? UIButton }
        XCTAssertTrue(buttonsTrue.contains(where: { $0.accessibilityLabel == "New Tab" }))
    }

    func testRootViewControllerPositionConstraintToggle() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let root = BrowserRootViewController(database: database, defaults: defaults)
        let frame = CGRect(x: 0, y: 0, width: 669, height: 951)
        TestWindow.attach(root, frame: frame)
        root.view.frame = frame

        // Defaults to right side (trailing constraint active)
        root.updateVerticalTabBarPosition()
        XCTAssertTrue(root.verticalTabBarTrailingConstraint?.isActive == true)
        XCTAssertFalse(root.verticalTabBarLeadingConstraint?.isActive == true)

        // Switch to left side
        defaults.set("left", forKey: SettingsViewModel.portraitTabBarPositionDefaultsKey)
        root.updateVerticalTabBarPosition()
        XCTAssertTrue(root.verticalTabBarLeadingConstraint?.isActive == true)
        XCTAssertFalse(root.verticalTabBarTrailingConstraint?.isActive == true)

        // Switch back to right
        defaults.set("right", forKey: SettingsViewModel.portraitTabBarPositionDefaultsKey)
        root.updateVerticalTabBarPosition()
        XCTAssertTrue(root.verticalTabBarTrailingConstraint?.isActive == true)
        XCTAssertFalse(root.verticalTabBarLeadingConstraint?.isActive == true)
    }
}
