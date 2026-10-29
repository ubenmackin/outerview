//
//  TabCardFlickTests.swift
//  OuterViewTests
//

import CoreGraphics
@testable import OuterView
import XCTest

final class TabCardFlickTests: XCTestCase {
    func testShouldBeginCardFlickRequiresFastDominantVerticalMotion() {
        // Fast, purely vertical motion claims the touch for dismissal.
        XCTAssertTrue(TabCardCell.shouldBeginCardFlick(velocity: CGPoint(x: 0, y: 1200)))

        // Horizontal-dominant motion belongs to the grid's scroll pan.
        XCTAssertFalse(TabCardCell.shouldBeginCardFlick(velocity: CGPoint(x: 900, y: 1000)))

        // Below the velocity gate even vertical motion starts no flick.
        XCTAssertFalse(TabCardCell.shouldBeginCardFlick(velocity: CGPoint(x: 0, y: 800)))
    }

    func testShouldDismissFlickAcceptsDistanceOrVelocity() {
        // 100 pt of travel clears the 96 pt distance leg with no velocity.
        XCTAssertTrue(TabCardCell.shouldDismissFlick(translationY: 100, velocityY: 0))

        // A short 20 pt drag with a 1500 pt/s exit clears the velocity leg.
        XCTAssertTrue(TabCardCell.shouldDismissFlick(translationY: 20, velocityY: 1500))

        // Neither leg met: the card springs back instead.
        XCTAssertFalse(TabCardCell.shouldDismissFlick(translationY: 40, velocityY: 300))
    }
}
