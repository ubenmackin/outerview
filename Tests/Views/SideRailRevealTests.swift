//
//  SideRailRevealTests.swift
//  OuterView
//

@testable import OuterView
import XCTest

@MainActor
final class SideRailRevealTests: XCTestCase {
    private func stacks(in rail: SideRailView) -> [UIStackView] {
        rail.subviews.compactMap { $0 as? UIStackView }
    }

    func testRedundantVisibleAppliesOnce() {
        let rail = SideRailView(frame: TestWindow.defaultFrame)
        TestWindow.attach(rail)
        XCTAssertNil(rail.lastAppliedRail)
        XCTAssertEqual(rail.applyCount, 0)

        rail.setRailState(.visible, pill: .expanded, animated: false)
        XCTAssertEqual(rail.lastAppliedRail, .visible)
        XCTAssertEqual(rail.applyCount, 1)
        let shown = stacks(in: rail)
        XCTAssertEqual(shown.count, 2)
        for stack in shown {
            XCTAssertEqual(stack.alpha, 1)
            XCTAssertEqual(stack.transform, .identity)
        }

        rail.setRailState(.visible, pill: .expanded, animated: false)
        XCTAssertEqual(rail.lastAppliedRail, .visible)
        XCTAssertEqual(rail.applyCount, 1)
        for stack in stacks(in: rail) {
            XCTAssertEqual(stack.alpha, 1)
            XCTAssertEqual(stack.transform, .identity)
        }
    }

    func testHiddenVisibleHiddenIncrementsApplyCount() {
        let rail = SideRailView(frame: TestWindow.defaultFrame)
        TestWindow.attach(rail)

        rail.setRailState(.hidden, pill: .expanded, animated: false)
        XCTAssertEqual(rail.lastAppliedRail, .hidden)
        XCTAssertEqual(rail.applyCount, 1)

        rail.setRailState(.visible, pill: .expanded, animated: false)
        XCTAssertEqual(rail.lastAppliedRail, .visible)
        XCTAssertEqual(rail.applyCount, 2)

        rail.setRailState(.hidden, pill: .expanded, animated: false)
        XCTAssertEqual(rail.lastAppliedRail, .hidden)
        XCTAssertEqual(rail.applyCount, 3)
        for stack in stacks(in: rail) {
            XCTAssertEqual(stack.alpha, 0)
        }

        rail.setRailState(.hidden, pill: .expanded, animated: false)
        XCTAssertEqual(rail.applyCount, 3)
    }

    func testShrinkingStacksFromTwoItemsToOnePreservesButtonHitTargets() {
        let rail = SideRailView(frame: TestWindow.defaultFrame)
        TestWindow.attach(rail)

        func assertStackDimensions(prefixCount: Int, suffixCount: Int, line: UInt = #line) {
            let railStacks = stacks(in: rail)
            XCTAssertEqual(railStacks.count, 2, line: line)
            XCTAssertEqual(
                railStacks[0].bounds.size,
                CGSize(width: SideRailView.columnWidth, height: SideRailView.expectedStackHeight(itemCount: prefixCount)),
                line: line
            )
            XCTAssertEqual(
                railStacks[1].bounds.size,
                CGSize(width: SideRailView.columnWidth, height: SideRailView.expectedStackHeight(itemCount: suffixCount)),
                line: line
            )
            for button in rail.buttons {
                XCTAssertEqual(
                    button.bounds.size,
                    CGSize(width: SystemToolbarMapper.hitTarget, height: SystemToolbarMapper.hitTarget),
                    line: line
                )
                XCTAssertFalse(button.hasAmbiguousLayout, line: line)
                let activeHeights = button.constraints.filter {
                    $0.isActive && $0.firstAttribute == .height && $0.constant == SystemToolbarMapper.hitTarget
                }
                XCTAssertEqual(activeHeights.count, 1, line: line)
            }
        }

        // Start with 2-item stacks (96 pt tall) then shrink to 1 item (44 pt), both visible and hidden.
        rail.setItems(prefix: [.addFolder {}, .edit {}], suffix: [.newTab {}, .tabs {}])
        rail.layoutIfNeeded()
        assertStackDimensions(prefixCount: 2, suffixCount: 2)

        rail.setItems(prefix: [.back {}], suffix: [.tabs {}])
        assertStackDimensions(prefixCount: 1, suffixCount: 1)
        rail.layoutIfNeeded()
        assertStackDimensions(prefixCount: 1, suffixCount: 1)

        rail.setItems(prefix: [.addFolder {}, .edit {}], suffix: [.newTab {}, .tabs {}])
        rail.setRailState(.hidden, pill: .expanded, animated: false)
        rail.layoutIfNeeded()

        rail.setItems(prefix: [.back {}], suffix: [])
        assertStackDimensions(prefixCount: 1, suffixCount: 0)
        rail.layoutIfNeeded()
        assertStackDimensions(prefixCount: 1, suffixCount: 0)
    }
}
