//
//  PillTapTests.swift
//  OuterView
//

import CoreGraphics
@testable import OuterView
import XCTest

@MainActor
final class PillTapTests: XCTestCase {
    func testRoutePillTapWhileEditingIsIgnored() {
        XCTAssertNil(BrowserRootViewController.routePillTap(pill: .expanded, isEditing: true))
        XCTAssertNil(BrowserRootViewController.routePillTap(pill: .minified, isEditing: true))
        XCTAssertNil(BrowserRootViewController.routePillTap(pill: .editing, isEditing: true))
    }

    func testRoutePillTapEditingPillIsIgnored() {
        XCTAssertNil(BrowserRootViewController.routePillTap(pill: .editing, isEditing: false))
    }

    func testRoutePillTapMinifiedRestoresChrome() {
        XCTAssertEqual(
            BrowserRootViewController.routePillTap(pill: .minified, isEditing: false),
            .restoreChrome
        )
    }

    func testRoutePillTapExpandedBeginsEditing() {
        XCTAssertEqual(
            BrowserRootViewController.routePillTap(pill: .expanded, isEditing: false),
            .beginEditing
        )
    }

    func testBrowsingResumedFromMinifiedRestoresChrome() {
        var controller = ChromeStateController()
        _ = controller.handle(.scroll(offsetDelta: 30))
        XCTAssertEqual(controller.state.pill, .minified)
        _ = controller.handle(.browsingResumed)
        XCTAssertEqual(controller.state.pill, .expanded)
        XCTAssertEqual(controller.state.rail, .visible)
    }
}
