//
//  PillTapTests.swift
//  OuterView
//

import CoreGraphics
@testable import OuterView
import UIKit
import XCTest

@MainActor
final class PillTapTests: XCTestCase {
    private func makeVerticalRoot() throws -> BrowserRootViewController {
        let database = try OuterViewDatabase(inMemory: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let root = BrowserRootViewController(database: database, defaults: defaults)
        TestWindow.attach(root)
        root.view.layoutIfNeeded()
        return root
    }

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

    func testVerticalPanIgnoredWhileEditing() throws {
        let root = try makeVerticalRoot()
        root.isEditingAddress = true
        root.handleVerticalPan(.began)
        XCTAssertFalse(root.isOverviewVisible)
        XCTAssertTrue(root.overviewView.isHidden)
        root.handleVerticalPan(.changed(translation: -300, velocity: -500))
        XCTAssertEqual(root.contentContainer.transform, .identity)
        XCTAssertTrue(root.overviewView.isHidden)
        root.handleVerticalPan(.changed(translation: -300, velocity: -1200))
        root.handleVerticalPan(.ended(translation: -300, velocity: -1200))
        XCTAssertFalse(root.isOverviewVisible)
        XCTAssertEqual(root.contentContainer.transform, .identity)
        XCTAssertTrue(root.overviewView.isHidden)
    }

    func testVerticalPanIgnoredWhileFindActive() throws {
        let root = try makeVerticalRoot()
        root.isFindActive = true
        root.handleVerticalPan(.began)
        XCTAssertFalse(root.isOverviewVisible)
        XCTAssertTrue(root.overviewView.isHidden)
        root.handleVerticalPan(.changed(translation: -300, velocity: -500))
        XCTAssertEqual(root.contentContainer.transform, .identity)
        XCTAssertTrue(root.overviewView.isHidden)
        root.handleVerticalPan(.changed(translation: -300, velocity: -1200))
        root.handleVerticalPan(.ended(translation: -300, velocity: -1200))
        XCTAssertFalse(root.isOverviewVisible)
        XCTAssertEqual(root.contentContainer.transform, .identity)
        XCTAssertTrue(root.overviewView.isHidden)
    }

    func testVerticalPanIgnoredWhileOverviewVisible() throws {
        let root = try makeVerticalRoot()
        root.isOverviewVisible = true
        root.handleVerticalPan(.began)
        XCTAssertTrue(root.overviewView.isHidden)
        XCTAssertEqual(root.contentContainer.transform, .identity)
        root.handleVerticalPan(.changed(translation: -300, velocity: -500))
        XCTAssertEqual(root.contentContainer.transform, .identity)
        root.handleVerticalPan(.changed(translation: -300, velocity: -1200))
        root.handleVerticalPan(.ended(translation: -300, velocity: -1200))
        XCTAssertEqual(root.contentContainer.transform, .identity)
        XCTAssertTrue(root.overviewView.isHidden)
    }

    func testDownwardTranslationNeverCommitsOverview() throws {
        XCTAssertFalse(AddressBarView.shouldCommitVertical(translationY: 100, height: 678, velocityY: -1000))
        XCTAssertFalse(AddressBarView.shouldCommitVertical(translationY: 0, height: 678, velocityY: -1000))
        XCTAssertFalse(AddressBarView.shouldCommitVertical(translationY: -100, height: 678, velocityY: 0))
        XCTAssertTrue(AddressBarView.shouldCommitVertical(translationY: -300, height: 678, velocityY: 0))
        let root = try makeVerticalRoot()
        root.handleVerticalPan(.began)
        XCTAssertFalse(root.overviewView.isHidden)
        root.handleVerticalPan(.changed(translation: 80, velocity: 300))
        XCTAssertEqual(root.contentContainer.transform, .identity)
        XCTAssertEqual(root.overviewView.alpha, 0)
        root.handleVerticalPan(.ended(translation: 80, velocity: 300))
        XCTAssertFalse(root.isOverviewVisible)
    }

    func testUpwardFlickBelowThresholdCommitsOverview() throws {
        let root = try makeVerticalRoot()
        root.handleVerticalPan(.began)
        let translation = -root.view.bounds.height * 0.10
        root.handleVerticalPan(.changed(translation: translation, velocity: -1200))
        root.handleVerticalPan(.ended(translation: translation, velocity: -1200))
        let deadline = Date(timeIntervalSinceNow: 1.0)
        while !root.isOverviewVisible, Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        XCTAssertTrue(root.isOverviewVisible)
        XCTAssertEqual(root.contentContainer.transform, .identity)
        XCTAssertFalse(root.contentContainer.clipsToBounds)
    }

    func testPillKeepsSinglePanRecognizerTapRequiresFail() throws {
        let root = try makeVerticalRoot()
        let recognizers = root.pillView.gestureRecognizers ?? []
        let pans = recognizers.compactMap { $0 as? UIPanGestureRecognizer }
        let taps = recognizers.compactMap { $0 as? UITapGestureRecognizer }
        XCTAssertEqual(pans.count, 1)
        XCTAssertEqual(taps.count, 1)
        XCTAssertTrue(pans.first?.cancelsTouchesInView ?? false)
    }
}
