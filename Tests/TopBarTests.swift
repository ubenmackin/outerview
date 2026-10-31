//
//  TopBarTests.swift
//  OuterViewTests
//

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class TopBarTests: XCTestCase {
    private func railLabels(in root: BrowserRootViewController) -> [String] {
        let stacks = root.railView.subviews.compactMap { $0 as? UIStackView }
        return stacks.flatMap(\.arrangedSubviews).compactMap(\.accessibilityLabel)
    }

    private func toolbarLabels(in root: BrowserRootViewController) -> [String] {
        let stacks = [root.topBarView.leadingStack, root.topBarView.trailingStack]
        return stacks.flatMap(\.arrangedSubviews).compactMap(\.accessibilityLabel)
    }

    func testPlacementResolution() {
        XCTAssertEqual(BrowserRootViewController.placement(for: .compact), .compact)
        XCTAssertEqual(BrowserRootViewController.placement(for: .regular), .regular)
        XCTAssertEqual(BrowserRootViewController.placement(for: .unspecified), .compact)
        XCTAssertEqual(ChromePlacement.compact, ChromePlacement.compact)
        XCTAssertNotEqual(ChromePlacement.compact, ChromePlacement.regular)
    }

    func testTopBarFixedHeightAndClusters() {
        XCTAssertEqual(TopBarView.barHeight, 56)
        let bar = TopBarView()
        TestWindow.attach(bar)
        XCTAssertEqual(bar.leadingStack.axis, .horizontal)
        XCTAssertEqual(bar.trailingStack.axis, .horizontal)
        XCTAssertTrue(bar.pillSlotView.superview === bar)
        let heights = bar.constraints.filter {
            $0.firstAttribute == .height && $0.firstItem as? UIView === bar
        }
        XCTAssertTrue(heights.contains { $0.constant == 56 && $0.isActive })
    }

    func testToolbarBuildsRailButtonsHorizontally() {
        let bar = TopBarView()
        TestWindow.attach(bar)
        bar.setItems(
            prefix: [.back(handler: {}), .bookmarks(handler: {})],
            suffix: [.newTab(handler: {}), .tabs(handler: {})]
        )
        XCTAssertEqual(bar.leadingStack.arrangedSubviews.count, 2)
        XCTAssertEqual(bar.trailingStack.arrangedSubviews.count, 2)
        for view in bar.leadingStack.arrangedSubviews + bar.trailingStack.arrangedSubviews {
            XCTAssertTrue(view is RailButton)
        }
        bar.setItems(prefix: [], suffix: [.done(handler: {})])
        XCTAssertEqual(bar.leadingStack.arrangedSubviews.count, 0)
        XCTAssertEqual(bar.trailingStack.arrangedSubviews.count, 1)
    }

    func testPillSlotParentingPerPlacement() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let root = BrowserRootViewController(database: database)
        TestWindow.attach(root)

        root.applyChromePlacement(for: .compact)
        XCTAssertTrue(root.pillView.superview === root.view)
        XCTAssertTrue(root.topBarView.isHidden)
        XCTAssertFalse(root.railView.isHidden)
        XCTAssertTrue(root.pillBottomConstraint.isActive)
        XCTAssertFalse(root.pillSlotLeadingConstraint.isActive)

        root.applyChromePlacement(for: .regular)
        XCTAssertTrue(root.pillView.superview === root.topBarView.pillSlotView)
        XCTAssertFalse(root.topBarView.isHidden)
        XCTAssertTrue(root.railView.isHidden)
        XCTAssertTrue(root.pillSlotLeadingConstraint.isActive)
        XCTAssertFalse(root.pillBottomConstraint.isActive)

        root.applyChromePlacement(for: .compact)
        XCTAssertTrue(root.pillView.superview === root.view)
        XCTAssertTrue(root.topBarView.isHidden)
        XCTAssertFalse(root.railView.isHidden)
    }

    func testToolbarMirrorsRailItems() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let root = BrowserRootViewController(database: database)
        TestWindow.attach(root)

        root.updateRailItems()
        XCTAssertEqual(railLabels(in: root).sorted(), toolbarLabels(in: root).sorted())
        XCTAssertEqual(railLabels(in: root).count, 4)

        root.applyChromePlacement(for: .regular)
        root.updateRailItems()
        XCTAssertEqual(railLabels(in: root).sorted(), toolbarLabels(in: root).sorted())
        XCTAssertFalse(root.topBarView.isHidden)
    }

    func testRailHiddenOnRegular() throws {
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
        root.applyStructuralLayout()
        XCTAssertTrue(root.railView.isHidden)
        XCTAssertFalse(root.topBarView.isHidden)

        root.traitOverrides.horizontalSizeClass = .compact
        root.view.layoutIfNeeded()
        parent.view.layoutIfNeeded()
        root.applyStructuralLayout()
        XCTAssertFalse(root.railView.isHidden)
        XCTAssertTrue(root.topBarView.isHidden)
    }
}
