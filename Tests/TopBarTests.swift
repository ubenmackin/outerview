//
//  TopBarTests.swift
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
        XCTAssertEqual(TopBarView.barHeight, 84)
        XCTAssertEqual(TopBarView.remnantHeight, 48)
        XCTAssertEqual(TopBarView.horizontalInset, 28)
        XCTAssertEqual(TopBarView.trailingStatusInset, 164)
        XCTAssertEqual(TopBarView.clusterSpacing, 12)
        XCTAssertEqual(TopBarView.expandedPillMaxWidth, 380)
        let bar = TopBarView()
        TestWindow.attach(bar)
        XCTAssertEqual(bar.leadingStack.axis, .horizontal)
        XCTAssertEqual(bar.trailingStack.axis, .horizontal)
        XCTAssertEqual(bar.leadingStack.spacing, 12)
        XCTAssertEqual(bar.trailingStack.spacing, 12)
        XCTAssertTrue(bar.pillSlotView.superview === bar)
        let heights = bar.constraints.filter {
            $0.firstAttribute == .height && $0.firstItem as? UIView === bar
        }
        XCTAssertTrue(heights.contains { $0.constant == 84 && $0.isActive })
        let leadingInset = bar.constraints.first {
            $0.firstItem as? UIStackView === bar.leadingStack
                && $0.firstAttribute == .leading
        }
        XCTAssertEqual(leadingInset?.constant, 28)
        let trailingInset = bar.constraints.first {
            $0.firstItem as? UIStackView === bar.trailingStack
                && $0.firstAttribute == .trailing
        }
        XCTAssertEqual(trailingInset?.constant, -164)
        bar.setCollapsed(true)
        XCTAssertTrue(bar.isCollapsed)
        XCTAssertEqual(bar.currentHeightConstant, 48)
        bar.setCollapsed(false)
        XCTAssertFalse(bar.isCollapsed)
        XCTAssertEqual(bar.currentHeightConstant, 84)
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
        XCTAssertFalse(root.pillSlotLeadingConstraint.isActive)
        XCTAssertFalse(root.pillSlotTrailingConstraint.isActive)
        XCTAssertTrue(root.pillSlotCenterXConstraint.isActive)
        XCTAssertTrue(root.pillSlotWidthConstraint.isActive)
        XCTAssertTrue(root.pillSlotMinLeadingConstraint.isActive)
        XCTAssertTrue(root.pillSlotMaxTrailingConstraint.isActive)
        XCTAssertFalse(root.pillBottomConstraint.isActive)

        root.applyChromePlacement(for: .compact)
        XCTAssertTrue(root.pillView.superview === root.view)
        XCTAssertTrue(root.topBarView.isHidden)
        XCTAssertFalse(root.railView.isHidden)
        XCTAssertFalse(root.pillSlotMinLeadingConstraint.isActive)
        XCTAssertFalse(root.pillSlotMaxTrailingConstraint.isActive)
    }

    func testBarSpansFullWidthOnRegular() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let root = BrowserRootViewController(database: database, defaults: defaults)
        TestWindow.attach(root)
        root.applyChromePlacement(for: .regular)
        root.updateTopBarPinning(for: .regular)
        XCTAssertEqual(root.topBarLeadingConstraint.constant, 0, accuracy: 0.001)
        XCTAssertEqual(root.topBarTrailingConstraint.constant, 0, accuracy: 0.001)
        root.applyChromePlacement(for: .compact)
        root.updateTopBarPinning(for: .compact)
        XCTAssertEqual(root.topBarTrailingConstraint.constant, 0, accuracy: 0.001)
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

    func testPillCapsPerState() throws {
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
        for _ in 0 ..< 2 {
            tabs.append(TabRecord(isPrivate: false))
        }
        root.tabs = tabs
        root.selectedTabID = tabs.first?.id
        root.applyChromePlacement(for: .regular)
        root.applyChromeViews(animated: false)
        root.view.layoutIfNeeded()
        root.view.layoutIfNeeded()
        XCTAssertFalse(root.pillSlotLeadingConstraint.isActive)
        XCTAssertFalse(root.pillSlotTrailingConstraint.isActive)
        XCTAssertTrue(root.pillSlotCenterXConstraint.isActive)
        XCTAssertTrue(root.pillSlotWidthConstraint.isActive)
        let expandedSlotWidth = root.topBarView.pillSlotView.bounds.width
        let expandedExpected = expandedSlotWidth > 0
            ? min(TopBarView.expandedPillMaxWidth, expandedSlotWidth)
            : TopBarView.expandedPillMaxWidth
        XCTAssertEqual(root.pillSlotWidthConstraint.constant, expandedExpected, accuracy: 0.5)
        let minified = root.chromeController.handle(.scroll(offsetDelta: 30))
        root.applyCommands(minified, animated: false)
        root.view.layoutIfNeeded()
        root.view.layoutIfNeeded()
        XCTAssertFalse(root.pillSlotLeadingConstraint.isActive)
        XCTAssertFalse(root.pillSlotTrailingConstraint.isActive)
        XCTAssertTrue(root.pillSlotCenterXConstraint.isActive)
        XCTAssertTrue(root.pillSlotWidthConstraint.isActive)
        let slotWidth = root.topBarView.pillSlotView.bounds.width
        let minifiedExpected = slotWidth > 0
            ? min(AddressBarView.minifiedMaxWidth, slotWidth)
            : AddressBarView.minifiedMaxWidth
        XCTAssertEqual(root.pillSlotWidthConstraint.constant, minifiedExpected, accuracy: 0.5)
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

    func testMinifiedCapsuleHugsLoadedDomainOnRegular() throws {
        let duoInnerFrame = CGRect(x: 0, y: 0, width: 951, height: 678)
        let database = try OuterViewDatabase(inMemory: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let root = BrowserRootViewController(database: database, defaults: defaults)
        let parent = UIViewController()
        TestWindow.attach(parent, frame: duoInnerFrame)
        parent.view.frame = duoInnerFrame
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
        root.view.layoutIfNeeded()
        root.applyChromePlacement(for: .regular)
        root.applyChromeViews(animated: false)
        root.view.layoutIfNeeded()

        XCTAssertEqual(root.pillView.preferredMinifiedWidth(), AddressBarView.minifiedMaxWidth)
        let expandedCenterInBar = root.topBarView.pillSlotView.convert(root.pillView.center, to: root.topBarView)
        XCTAssertEqual(expandedCenterInBar.x, root.topBarView.bounds.midX, accuracy: 1.0)

        let appleURL = try XCTUnwrap(URL(string: "https://www.apple.com"))
        root.pillView.configure(url: appleURL, isSecure: true, isLoading: false)
        let minified = root.chromeController.handle(.scroll(offsetDelta: 30))
        root.applyCommands(minified, animated: false)
        root.view.layoutIfNeeded()

        let preferredWidth = root.pillView.preferredMinifiedWidth()
        XCTAssertGreaterThanOrEqual(preferredWidth, TopBarView.minifiedPillMinWidth)
        XCTAssertLessThan(preferredWidth, AddressBarView.minifiedMaxWidth)
        XCTAssertEqual(root.pillSlotWidthConstraint.constant, preferredWidth, accuracy: 0.5)
        let minifiedCenterInBar = root.topBarView.pillSlotView.convert(root.pillView.center, to: root.topBarView)
        XCTAssertEqual(minifiedCenterInBar.x, root.topBarView.bounds.midX, accuracy: 1.0)
    }
}
