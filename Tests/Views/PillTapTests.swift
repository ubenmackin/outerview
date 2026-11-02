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
        XCTAssertNil(BrowserRootViewController.routePillTap(pill: .expanded, isEditing: true, rail: .visible))
        XCTAssertNil(BrowserRootViewController.routePillTap(pill: .minified, isEditing: true, rail: .visible))
        XCTAssertNil(BrowserRootViewController.routePillTap(pill: .editing, isEditing: true, rail: .visible))
        XCTAssertNil(BrowserRootViewController.routePillTap(pill: .expanded, isEditing: true, rail: .hidden))
        XCTAssertNil(BrowserRootViewController.routePillTap(pill: .minified, isEditing: true, rail: .hidden))
        XCTAssertNil(BrowserRootViewController.routePillTap(pill: .editing, isEditing: true, rail: .hidden))
    }

    func testRoutePillTapEditingPillIsIgnored() {
        XCTAssertNil(BrowserRootViewController.routePillTap(pill: .editing, isEditing: false, rail: .visible))
        XCTAssertNil(BrowserRootViewController.routePillTap(pill: .editing, isEditing: false, rail: .hidden))
    }

    func testRoutePillTapMinifiedRestoresChrome() {
        XCTAssertEqual(
            BrowserRootViewController.routePillTap(pill: .minified, isEditing: false, rail: .visible),
            .restoreChrome
        )
        XCTAssertEqual(
            BrowserRootViewController.routePillTap(pill: .minified, isEditing: false, rail: .hidden),
            .restoreChrome
        )
    }

    func testRoutePillTapExpandedBeginsEditing() {
        XCTAssertEqual(
            BrowserRootViewController.routePillTap(pill: .expanded, isEditing: false, rail: .visible),
            .beginEditing
        )
    }

    func testRoutePillTapHiddenExpandedRestoresChrome() {
        XCTAssertEqual(
            BrowserRootViewController.routePillTap(pill: .expanded, isEditing: false, rail: .hidden),
            .restoreChrome
        )
    }

    func testRoutePillTapHiddenNeverBeginsEditing() {
        let pills: [PillState] = [.expanded, .minified, .editing]
        for pill in pills {
            for isEditing in [true, false] {
                XCTAssertNotEqual(
                    BrowserRootViewController.routePillTap(pill: pill, isEditing: isEditing, rail: .hidden),
                    .beginEditing
                )
            }
        }
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
