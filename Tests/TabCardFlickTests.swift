//
//  TabCardFlickTests.swift
//  OuterViewTests
//

import CoreGraphics
@testable import OuterView
import XCTest

final class TabCardFlickTests: XCTestCase {
    func testShouldBeginCardFlickRequiresFastDominantMotion() {
        // Fast, purely vertical motion claims the touch for dismissal.
        XCTAssertTrue(TabCardCell.shouldBeginCardFlick(velocity: CGPoint(x: 0, y: 1200)))

        // Horizontal-dominant motion belongs to the grid's scroll pan only
        // when slow; fast horizontal motion claims the touch.
        XCTAssertTrue(TabCardCell.shouldBeginCardFlick(velocity: CGPoint(x: 1200, y: 100)))

        // Steepness gate still applies to vertical claims.
        XCTAssertFalse(TabCardCell.shouldBeginCardFlick(velocity: CGPoint(x: 900, y: 1000)))

        // Below the velocity gate even vertical motion starts no flick.
        XCTAssertFalse(TabCardCell.shouldBeginCardFlick(velocity: CGPoint(x: 0, y: 800)))

        // Slow horizontal motion stays with the grid.
        XCTAssertFalse(TabCardCell.shouldBeginCardFlick(velocity: CGPoint(x: 300, y: 100)))
    }

    func testShouldClaimFlickLatchesOnceClaimed() {
        XCTAssertFalse(TabCardCell.shouldClaimFlick(
            velocity: CGPoint(x: 300, y: 100),
            alreadyClaimed: false
        ))
        XCTAssertTrue(TabCardCell.shouldClaimFlick(
            velocity: CGPoint(x: 300, y: 100),
            alreadyClaimed: true
        ))
        XCTAssertTrue(TabCardCell.shouldClaimFlick(
            velocity: CGPoint(x: 1200, y: 100),
            alreadyClaimed: false
        ))
    }

    func testShouldDismissFlickUsesDominantAxis() {
        // Vertical: 100 pt of travel clears the 96 pt distance leg.
        XCTAssertTrue(TabCardCell.shouldDismissFlick(
            translation: CGPoint(x: 0, y: 100),
            velocity: CGPoint(x: 0, y: 0)
        ))

        // Vertical: a short 20 pt drag with a 1500 pt/s exit clears the velocity leg.
        XCTAssertTrue(TabCardCell.shouldDismissFlick(
            translation: CGPoint(x: 0, y: 20),
            velocity: CGPoint(x: 0, y: 1500)
        ))

        // Horizontal: 100 pt of dominant travel dismisses.
        XCTAssertTrue(TabCardCell.shouldDismissFlick(
            translation: CGPoint(x: 100, y: 10),
            velocity: CGPoint(x: 0, y: 0)
        ))

        // Horizontal: zero travel with a 1500 pt/s fling dismisses.
        XCTAssertTrue(TabCardCell.shouldDismissFlick(
            translation: CGPoint(x: 0, y: 0),
            velocity: CGPoint(x: 1500, y: 100)
        ))

        // Neither leg met: the card springs back instead.
        XCTAssertFalse(TabCardCell.shouldDismissFlick(
            translation: CGPoint(x: 0, y: 40),
            velocity: CGPoint(x: 0, y: 300)
        ))
        XCTAssertFalse(TabCardCell.shouldDismissFlick(
            translation: CGPoint(x: 40, y: 10),
            velocity: CGPoint(x: 300, y: 50)
        ))
    }
}
