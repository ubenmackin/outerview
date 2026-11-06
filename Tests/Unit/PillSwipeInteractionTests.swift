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
        XCTAssertFalse(AddressBarView.shouldCommitHorizontal(translationX: width * 0.39, width: width, velocityX: 0, direction: .right))
        XCTAssertTrue(AddressBarView.shouldCommitHorizontal(translationX: width * 0.40, width: width, velocityX: 0, direction: .right))
        XCTAssertFalse(AddressBarView.shouldCommitHorizontal(translationX: -width * 0.39, width: width, velocityX: 0, direction: .left))
        XCTAssertTrue(AddressBarView.shouldCommitHorizontal(translationX: -width * 0.40, width: width, velocityX: 0, direction: .left))
        XCTAssertFalse(AddressBarView.shouldCommitHorizontal(translationX: 0, width: width, velocityX: 0, direction: .right))
    }

    func testShouldCommitHorizontalFling() {
        let width: CGFloat = 300
        XCTAssertTrue(AddressBarView.shouldCommitHorizontal(translationX: width * 0.10, width: width, velocityX: 800, direction: .right))
        XCTAssertTrue(AddressBarView.shouldCommitHorizontal(translationX: -width * 0.10, width: width, velocityX: -800, direction: .left))
        XCTAssertFalse(AddressBarView.shouldCommitHorizontal(translationX: width * 0.10, width: width, velocityX: 799, direction: .right))
        XCTAssertFalse(AddressBarView.shouldCommitHorizontal(translationX: -width * 0.10, width: width, velocityX: -799, direction: .left))
        XCTAssertFalse(AddressBarView.shouldCommitHorizontal(translationX: width * 0.10, width: width, velocityX: -900, direction: .right))
        XCTAssertFalse(AddressBarView.shouldCommitHorizontal(translationX: -width * 0.10, width: width, velocityX: 900, direction: .left))
        XCTAssertFalse(AddressBarView.shouldCommitHorizontal(translationX: 10, width: 0, velocityX: 800, direction: .right))
        XCTAssertFalse(AddressBarView.shouldCommitHorizontal(translationX: 10, width: 0, velocityX: -800, direction: .left))
    }

    func testOverviewDragHelpers() {
        XCTAssertEqual(AddressBarView.overviewDragScale(progress: 0), 1, accuracy: 0.001)
        XCTAssertEqual(AddressBarView.overviewDragScale(progress: 1), 0.70, accuracy: 0.001)
        XCTAssertEqual(AddressBarView.overviewDragScale(progress: 0.3), 0.91, accuracy: 0.001)
        let anchorY: CGFloat = 600
        let centerY: CGFloat = 400
        let scale: CGFloat = 0.85
        let translation: CGFloat = -100
        let offset = AddressBarView.overviewDragOffset(
            translation: translation,
            scale: scale,
            anchorY: anchorY,
            centerY: centerY
        )
        // Verify offset ensures 1:1 finger tracking:
        // centerY + scale * (anchorY - centerY) + offset == anchorY + translation
        let resultingAnchor = centerY + scale * (anchorY - centerY) + offset
        XCTAssertEqual(resultingAnchor, anchorY + translation, accuracy: 0.001)
        XCTAssertEqual(AddressBarView.overviewDragRadius(progress: 1), 24, accuracy: 0.001)
        XCTAssertEqual(AddressBarView.overviewDragRadius(progress: 0), 0, accuracy: 0.001)
    }

    func testShouldCommitVerticalBoundaries() {
        let height: CGFloat = 500
        XCTAssertFalse(AddressBarView.shouldCommitVertical(translationY: -height * 0.29, height: height, velocityY: 0))
        XCTAssertTrue(AddressBarView.shouldCommitVertical(translationY: -height * 0.30, height: height, velocityY: 0))
        XCTAssertFalse(AddressBarView.shouldCommitVertical(translationY: 0, height: height, velocityY: 0))
        XCTAssertFalse(AddressBarView.shouldCommitVertical(translationY: height * 0.30, height: height, velocityY: 0))
        XCTAssertFalse(AddressBarView.shouldCommitVertical(translationY: height, height: height, velocityY: 0))
    }

    func testShouldCommitVerticalFlick() {
        let height: CGFloat = 500
        XCTAssertTrue(AddressBarView.shouldCommitVertical(translationY: -100, height: height, velocityY: -800))
        XCTAssertFalse(AddressBarView.shouldCommitVertical(translationY: -100, height: height, velocityY: -799))
        XCTAssertFalse(AddressBarView.shouldCommitVertical(translationY: -100, height: height, velocityY: 0))
        XCTAssertTrue(AddressBarView.shouldCommitVertical(translationY: -height * 0.60, height: height, velocityY: 900))
        XCTAssertFalse(AddressBarView.shouldCommitVertical(translationY: 100, height: height, velocityY: -1000))
        XCTAssertFalse(AddressBarView.shouldCommitVertical(translationY: 0, height: height, velocityY: -800))
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

    func testFlingVelocityConstants() {
        XCTAssertEqual(AddressBarView.horizontalFlingVelocity, 800)
        XCTAssertEqual(AddressBarView.verticalFlingVelocity, 800)
    }

    func testCommitGuardsRejectDegenerateMetrics() {
        XCTAssertFalse(AddressBarView.shouldCommitHorizontal(translationX: 0, width: 0, velocityX: 0, direction: .right))
        XCTAssertFalse(AddressBarView.shouldCommitHorizontal(translationX: 100, width: 0, velocityX: 800, direction: .right))
        XCTAssertFalse(AddressBarView.shouldCommitHorizontal(translationX: 100, width: -300, velocityX: 800, direction: .right))
        XCTAssertFalse(AddressBarView.shouldCommitVertical(translationY: 0, height: 0, velocityY: -800))
        XCTAssertFalse(AddressBarView.shouldCommitVertical(translationY: -100, height: 0, velocityY: -800))
        XCTAssertFalse(AddressBarView.shouldCommitVertical(translationY: -100, height: -500, velocityY: -800))
        XCTAssertFalse(AddressBarView.shouldCommitVertical(translationY: -100, height: 500, velocityY: 800))
    }

    func testSettleDurationClamps() {
        XCTAssertEqual(AddressBarView.settleDuration(remaining: 0, velocity: 0), 0.12, accuracy: 0.001)
        XCTAssertEqual(AddressBarView.settleDuration(remaining: 1000, velocity: 100), 0.30, accuracy: 0.001)
        XCTAssertEqual(AddressBarView.settleDuration(remaining: 100, velocity: 500), 0.20, accuracy: 0.001)
    }
}
