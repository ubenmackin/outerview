//
//  TabCardFlickTests.swift
//  OuterViewTests
//

import CoreGraphics
@testable import OuterView
import XCTest

final class TabCardFlickTests: XCTestCase {
    private var duoCardWidth: CGFloat {
        let outerWidth: CGFloat = 466
        let available = outerWidth - 2 * TabOverviewViewController.horizontalInset
        let columns = CGFloat(TabOverviewViewController.columnCount(forWidth: available))
        return (available - (columns - 1) * TabOverviewViewController.cellSpacing) / columns
    }

    func testHorizontalSwipeGating() {
        // Horizontal-dominant movement begins the swipe
        XCTAssertTrue(TabCardCell.shouldBeginSwipe(isImmediate: true, velocity: CGPoint(x: 100, y: 10)))
        XCTAssertTrue(TabCardCell.shouldBeginSwipe(isImmediate: true, velocity: CGPoint(x: -300, y: 50)))

        // Purely vertical or vertical-dominant movement does NOT begin swipe (stays with grid scroll)
        XCTAssertFalse(TabCardCell.shouldBeginSwipe(isImmediate: true, velocity: CGPoint(x: 0, y: 500)))
        XCTAssertFalse(TabCardCell.shouldBeginSwipe(isImmediate: true, velocity: CGPoint(x: 100, y: 300)))
        XCTAssertFalse(TabCardCell.shouldBeginSwipe(isImmediate: true, velocity: CGPoint(x: 200, y: 200)))
    }

    func testSwipeBeginGating() {
        // Immediate horizontal swipe begins immediately
        XCTAssertTrue(TabCardCell.shouldBeginSwipe(
            isImmediate: true,
            velocity: CGPoint(x: 200, y: 20)
        ))
        XCTAssertTrue(TabCardCell.shouldBeginSwipe(
            isImmediate: true,
            velocity: CGPoint(x: -300, y: 30)
        ))

        // Stationary touch (e.g. long press hold, isImmediate == false) must NOT begin swipe
        XCTAssertFalse(TabCardCell.shouldBeginSwipe(
            isImmediate: false,
            velocity: CGPoint(x: 200, y: 0)
        ))
        XCTAssertFalse(TabCardCell.shouldBeginSwipe(
            isImmediate: false,
            velocity: CGPoint(x: 500, y: 50)
        ))

        // Vertical dominant drag does not begin horizontal swipe
        XCTAssertFalse(TabCardCell.shouldBeginSwipe(
            isImmediate: true,
            velocity: CGPoint(x: 50, y: 400)
        ))
    }

    func testSlowDragPastThresholdDismisses() {
        let cardWidth = duoCardWidth
        let threshold = max(TabCardCell.swipeDismissDistance, cardWidth * 0.60)
        // Far drag past the distance threshold dismisses at rest
        XCTAssertTrue(TabCardCell.shouldDismissSwipe(translationX: threshold + 10, velocityX: 0, cardWidth: cardWidth))
        XCTAssertTrue(TabCardCell.shouldDismissSwipe(translationX: -(threshold + 10), velocityX: -10, cardWidth: cardWidth))

        // Under-threshold drags spring back
        XCTAssertFalse(TabCardCell.shouldDismissSwipe(translationX: 80, velocityX: 50, cardWidth: cardWidth))
        XCTAssertFalse(TabCardCell.shouldDismissSwipe(translationX: -80, velocityX: -50, cardWidth: cardWidth))
        XCTAssertFalse(TabCardCell.shouldDismissSwipe(translationX: 40, velocityX: 50, cardWidth: cardWidth))
    }

    func testFastFlickRequiresNoticeableTravel() {
        let cardWidth = duoCardWidth
        // Noticeable travel (>= 50 pt) with high velocity (>= 800 pt/s) dismisses
        XCTAssertTrue(TabCardCell.shouldDismissSwipe(translationX: 55, velocityX: 850, cardWidth: cardWidth))
        XCTAssertTrue(TabCardCell.shouldDismissSwipe(translationX: -55, velocityX: -850, cardWidth: cardWidth))

        // Short drags (< 50 pt) do NOT dismiss even with fast flick (high tolerance)
        XCTAssertFalse(TabCardCell.shouldDismissSwipe(translationX: 20, velocityX: 1000, cardWidth: cardWidth))
        XCTAssertFalse(TabCardCell.shouldDismissSwipe(translationX: 0, velocityX: 1200, cardWidth: cardWidth))
    }
}
