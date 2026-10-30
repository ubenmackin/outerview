//
//  SheetCardTests.swift
//  OuterViewTests
//

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class SheetCardTests: XCTestCase {
    func testConstants() {
        XCTAssertEqual(SheetCardOverlayView.cornerRadius, 16)
        XCTAssertEqual(SheetCardOverlayView.outerMargin, 8)
        XCTAssertEqual(SheetCardOverlayView.grabberTopReserve, 24)
        XCTAssertEqual(SheetCardOverlayView.dimAlpha, 0.4, accuracy: 0.001)
    }

    func testCardFrameOuterGeometry() {
        let bounds = CGRect(x: 0, y: 0, width: 466, height: 678)
        let safeArea = UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84)
        let frame = SheetCardOverlayView.cardFrame(bounds: bounds, safeArea: safeArea)
        XCTAssertEqual(frame, CGRect(x: 8, y: 8, width: 366, height: 628))
    }

    func testCardAvoidsRailColumn() {
        let bounds = CGRect(x: 0, y: 0, width: 466, height: 678)
        let safeArea = UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84)
        let frame = SheetCardOverlayView.cardFrame(bounds: bounds, safeArea: safeArea)
        XCTAssertEqual(frame.maxX, 374)
        let railX = SideRailView.columnOriginX(boundsMaxX: 466, safeAreaRight: 84)
        XCTAssertEqual(railX, 394)
        XCTAssertGreaterThan(railX, frame.maxX)
    }

    func testGrabberPresence() {
        let overlay = SheetCardOverlayView(frame: TestWindow.defaultFrame)
        TestWindow.attach(overlay)
        overlay.layoutIfNeeded()
        XCTAssertFalse(overlay.grabberView.isHidden)
        XCTAssertEqual(overlay.grabberView.frame.width, 36, accuracy: 0.5)
        XCTAssertEqual(overlay.grabberView.frame.height, 5, accuracy: 0.5)
        XCTAssertEqual(
            overlay.grabberView.frame.midX,
            overlay.cardView.bounds.midX,
            accuracy: 0.5
        )
        XCTAssertEqual(
            overlay.grabberView.frame.minY,
            (SheetCardOverlayView.grabberTopReserve - 5) / 2,
            accuracy: 0.5
        )
        XCTAssertLessThanOrEqual(
            overlay.grabberView.frame.maxY,
            SheetCardOverlayView.grabberTopReserve
        )
        XCTAssertEqual(overlay.cardView.layer.cornerRadius, SheetCardOverlayView.cornerRadius)
        XCTAssertEqual(overlay.dimView.alpha, SheetCardOverlayView.dimAlpha, accuracy: 0.001)
    }

    func testRailColumnAndDimPassthrough() {
        let overlay = SheetCardOverlayView(frame: TestWindow.defaultFrame)
        TestWindow.attach(overlay)
        overlay.layoutIfNeeded()
        let card = overlay.cardView.frame
        XCTAssertTrue(overlay.point(inside: CGPoint(x: card.midX, y: card.midY), with: nil))
        XCTAssertFalse(overlay.point(inside: CGPoint(x: 4, y: 4), with: nil))
        let outer = SheetCardOverlayView.cardFrame(
            bounds: CGRect(x: 0, y: 0, width: 466, height: 678),
            safeArea: UIEdgeInsets(top: 0, left: 0, bottom: 34, right: 84)
        )
        XCTAssertFalse(outer.contains(CGPoint(x: 430, y: 300)))
        XCTAssertFalse(outer.contains(CGPoint(x: 4, y: 4)))
        XCTAssertTrue(outer.contains(CGPoint(x: outer.midX, y: outer.midY)))
    }

    func testDimNeverDismisses() {
        let overlay = SheetCardOverlayView(frame: TestWindow.defaultFrame)
        XCTAssertTrue(overlay.dimView.gestureRecognizers?.isEmpty ?? true)
        XCTAssertFalse(overlay.dimView.isUserInteractionEnabled)
        XCTAssertTrue(overlay.gestureRecognizers?.isEmpty ?? true)
    }

    func testSetContentPinsWithTopInset() {
        let overlay = SheetCardOverlayView(frame: TestWindow.defaultFrame)
        let content = UIView()
        overlay.setContent(content)
        TestWindow.attach(overlay)
        overlay.layoutIfNeeded()
        XCTAssertTrue(content.superview === overlay.cardView)
        XCTAssertEqual(content.frame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(content.frame.minY, SheetCardOverlayView.grabberTopReserve, accuracy: 0.5)
        XCTAssertEqual(content.frame.width, overlay.cardView.bounds.width, accuracy: 0.5)
        XCTAssertEqual(
            content.frame.height,
            overlay.cardView.bounds.height - SheetCardOverlayView.grabberTopReserve,
            accuracy: 0.5
        )
        XCTAssertTrue(overlay.cardView.subviews.last === overlay.grabberView)
    }

    func testRotationReframesCard() {
        let overlay = SheetCardOverlayView(frame: CGRect(x: 0, y: 0, width: 466, height: 678))
        TestWindow.attach(overlay)
        overlay.layoutIfNeeded()
        let first = overlay.cardView.frame
        XCTAssertEqual(
            first,
            SheetCardOverlayView.cardFrame(bounds: overlay.bounds, safeArea: overlay.safeAreaInsets)
        )
        overlay.frame = CGRect(x: 0, y: 0, width: 951, height: 669)
        overlay.layoutIfNeeded()
        let second = overlay.cardView.frame
        XCTAssertEqual(
            second,
            SheetCardOverlayView.cardFrame(bounds: overlay.bounds, safeArea: overlay.safeAreaInsets)
        )
        XCTAssertNotEqual(first, second)
    }

    func testLibraryOverlayIntegration() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let root = BrowserRootViewController(database: database)
        TestWindow.attach(root)
        XCTAssertTrue(root.libraryOverlay.superview === root.view)
        XCTAssertTrue(root.libraryOverlay.isHidden)
        XCTAssertTrue(root.bookmarksLibraryView.superview === root.libraryOverlay.cardView)
        root.openBookmarksLibrary(tab: .bookmarks)
        XCTAssertFalse(root.libraryOverlay.isHidden)
        XCTAssertTrue(root.isLibraryVisible)
        XCTAssertEqual(root.currentRailMode, .library(.bookmarks))
        let overlayIndex = root.view.subviews.firstIndex(of: root.libraryOverlay) ?? -1
        let railIndex = root.view.subviews.firstIndex(of: root.railView) ?? -1
        XCTAssertGreaterThan(railIndex, overlayIndex)
        root.bookmarksLibraryView.onDone?()
        XCTAssertTrue(root.libraryOverlay.isHidden)
        XCTAssertFalse(root.isLibraryVisible)
        root.openBookmarksLibrary(tab: .history)
        XCTAssertFalse(root.libraryOverlay.isHidden)
        root.closeBookmarksLibrary()
        XCTAssertTrue(root.libraryOverlay.isHidden)
    }
}
