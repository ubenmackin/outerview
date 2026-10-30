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
}
