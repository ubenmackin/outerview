// RootView — Interactive horizontal pill-switch target, commit, and axis-lock math.

import CoreGraphics
@testable import OuterView
import XCTest

final class PillSwipeInteractionTests: XCTestCase {
    func testPillTargetLeftAdvances() {
        XCTAssertEqual(BrowserRootViewController.pillTargetIndex(currentIndex: 0, count: 3, direction: .left), 1)
        XCTAssertEqual(BrowserRootViewController.pillTargetIndex(currentIndex: 1, count: 3, direction: .left), 2)
    }

    func testPillTargetRightRetreats() {
        XCTAssertEqual(BrowserRootViewController.pillTargetIndex(currentIndex: 2, count: 3, direction: .right), 1)
        XCTAssertEqual(BrowserRootViewController.pillTargetIndex(currentIndex: 1, count: 3, direction: .right), 0)
    }

    func testPillTargetLeftOnLastNilForOverflow() {
        XCTAssertNil(BrowserRootViewController.pillTargetIndex(currentIndex: 2, count: 3, direction: .left))
        XCTAssertNil(BrowserRootViewController.pillTargetIndex(currentIndex: 0, count: 1, direction: .left))
    }

    func testPillTargetRightOnFirstNilForClamp() {
        XCTAssertNil(BrowserRootViewController.pillTargetIndex(currentIndex: 0, count: 3, direction: .right))
        XCTAssertNil(BrowserRootViewController.pillTargetIndex(currentIndex: 0, count: 1, direction: .right))
    }

    func testShouldCommitHorizontalBoundaries() {
        let width: CGFloat = 300
        XCTAssertFalse(AddressBarView.shouldCommitHorizontal(translationX: width * 0.39, width: width))
        XCTAssertTrue(AddressBarView.shouldCommitHorizontal(translationX: width * 0.40, width: width))
        XCTAssertFalse(AddressBarView.shouldCommitHorizontal(translationX: -width * 0.39, width: width))
        XCTAssertTrue(AddressBarView.shouldCommitHorizontal(translationX: -width * 0.40, width: width))
        XCTAssertFalse(AddressBarView.shouldCommitHorizontal(translationX: 0, width: width))
    }

    func testShouldCommitVerticalBoundaries() {
        let height: CGFloat = 500
        XCTAssertFalse(AddressBarView.shouldCommitVertical(translationY: -height * 0.29, height: height))
        XCTAssertTrue(AddressBarView.shouldCommitVertical(translationY: -height * 0.30, height: height))
        XCTAssertFalse(AddressBarView.shouldCommitVertical(translationY: 0, height: height))
        XCTAssertFalse(AddressBarView.shouldCommitVertical(translationY: height * 0.30, height: height))
        XCTAssertFalse(AddressBarView.shouldCommitVertical(translationY: height, height: height))
    }

    func testLockedAxis() {
        XCTAssertEqual(AddressBarView.lockedAxis(tx: 10, ty: 5), .horizontal)
        XCTAssertEqual(AddressBarView.lockedAxis(tx: 5, ty: 10), .vertical)
        XCTAssertEqual(AddressBarView.lockedAxis(tx: 10, ty: 10), .horizontal)
        XCTAssertEqual(AddressBarView.lockedAxis(tx: 0, ty: 0), .horizontal)
        XCTAssertEqual(AddressBarView.lockedAxis(tx: -3, ty: 2), .horizontal)
        XCTAssertEqual(AddressBarView.lockedAxis(tx: 2, ty: -8), .vertical)
    }

    func testAxisLockThresholdAndElasticFactor() {
        XCTAssertEqual(AddressBarView.axisLockThreshold, 8)
        XCTAssertEqual(AddressBarView.elasticFactor, 0.35)
    }

    func testCommitGuardsRejectDegenerateMetrics() {
        XCTAssertFalse(AddressBarView.shouldCommitHorizontal(translationX: 0, width: 0))
        XCTAssertFalse(AddressBarView.shouldCommitHorizontal(translationX: 100, width: 0))
        XCTAssertFalse(AddressBarView.shouldCommitHorizontal(translationX: 100, width: -300))
        XCTAssertFalse(AddressBarView.shouldCommitVertical(translationY: 0, height: 0))
        XCTAssertFalse(AddressBarView.shouldCommitVertical(translationY: -100, height: 0))
        XCTAssertFalse(AddressBarView.shouldCommitVertical(translationY: -100, height: -500))
    }

    func testSettleDurationClamps() {
        XCTAssertEqual(AddressBarView.settleDuration(remaining: 0, velocity: 0), 0.12, accuracy: 0.001)
        XCTAssertEqual(AddressBarView.settleDuration(remaining: 1000, velocity: 100), 0.30, accuracy: 0.001)
        XCTAssertEqual(AddressBarView.settleDuration(remaining: 100, velocity: 500), 0.20, accuracy: 0.001)
    }
}
