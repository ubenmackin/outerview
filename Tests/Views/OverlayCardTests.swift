//
//  OverlayCardTests.swift
//  OuterViewTests
//

@testable import OuterView
import UIKit
import XCTest

@MainActor
final class OverlayCardTests: XCTestCase {
    private func makeCard(
        placement: ChromePlacement = .compact,
        frame: CGRect = TestWindow.defaultFrame
    ) -> OverlayCardView {
        let card = OverlayCardView()
        card.frame = CGRect(origin: .zero, size: frame.size)
        TestWindow.attach(card, frame: frame)
        card.frame = CGRect(origin: .zero, size: frame.size)
        card.applyPlacement(for: placement)
        card.layoutIfNeeded()
        return card
    }

    func testStaticsMatchContract() {
        XCTAssertEqual(OverlayCardView.maxWidth, 560)
        XCTAssertEqual(OverlayCardView.cornerRadius, 16)
        XCTAssertEqual(OverlayCardView.dimAlpha, 0.2, accuracy: 0.001)
        XCTAssertEqual(OverlayCardView.contentPadding, 16)
    }

    func testCompactFillsScreenWithNoDimAndNoRadius() {
        let card = makeCard(placement: .compact)
        XCTAssertEqual(card.chromePlacement, .compact)
        XCTAssertTrue(card.dimView.isHidden)
        XCTAssertEqual(card.cardView.layer.cornerRadius, 0)
        XCTAssertTrue(card.compactConstraints.allSatisfy(\.isActive))
        XCTAssertFalse(card.regularConstraints.contains(where: \.isActive))
        card.layoutIfNeeded()
        XCTAssertEqual(card.cardView.frame, card.bounds)
    }

    func testRegularCentersCardWithDim() {
        let card = makeCard(placement: .regular)
        XCTAssertEqual(card.chromePlacement, .regular)
        XCTAssertFalse(card.dimView.isHidden)
        XCTAssertEqual(card.cardView.layer.cornerRadius, OverlayCardView.cornerRadius)
        XCTAssertTrue(card.regularConstraints.allSatisfy(\.isActive))
        XCTAssertFalse(card.compactConstraints.contains(where: \.isActive))
        card.layoutIfNeeded()
        XCTAssertEqual(card.cardView.frame.midX, card.bounds.midX, accuracy: 1.0)
        XCTAssertEqual(card.cardView.frame.midY, card.bounds.midY, accuracy: 1.0)
        XCTAssertLessThanOrEqual(card.cardView.frame.width, OverlayCardView.maxWidth + 1.0)
        XCTAssertTrue(card.cardView.frame.width < card.bounds.width)
    }

    func testMaxWidthCapOnWideDisplay() {
        let wide = CGRect(x: 0, y: 0, width: 951, height: 669)
        let card = makeCard(placement: .regular, frame: wide)
        card.layoutIfNeeded()
        XCTAssertEqual(card.cardView.frame.width, OverlayCardView.maxWidth, accuracy: 1.0)
        XCTAssertEqual(card.cardView.frame.midX, card.bounds.midX, accuracy: 1.0)
    }

    func testDimPresenceOnlyOnRegular() {
        let card = makeCard(placement: .compact)
        XCTAssertTrue(card.dimView.isHidden)
        card.applyPlacement(for: .regular)
        card.layoutIfNeeded()
        XCTAssertFalse(card.dimView.isHidden)
        card.applyPlacement(for: .compact)
        XCTAssertTrue(card.dimView.isHidden)
    }

    func testSetContentPinsFullBleedInsideCard() {
        let card = makeCard(placement: .compact)
        let content = UIView()
        card.setContent(content)
        XCTAssertTrue(content.superview === card.cardView)
        card.layoutIfNeeded()
        XCTAssertEqual(content.frame, card.cardView.bounds)
        card.applyPlacement(for: .regular)
        card.layoutIfNeeded()
        XCTAssertTrue(content.superview === card.cardView)
        XCTAssertEqual(content.frame.minX, OverlayCardView.contentPadding, accuracy: 1.0)
        XCTAssertEqual(content.frame.minY, OverlayCardView.contentPadding, accuracy: 1.0)
        XCTAssertEqual(content.frame.width, card.cardView.bounds.width - 32, accuracy: 1.0)
        XCTAssertEqual(content.frame.height, card.cardView.bounds.height - 32, accuracy: 1.0)
    }

    func testLibraryDoneVisibilityPerPlacement() {
        let library = BookmarksLibraryView()
        TestWindow.attach(library)
        library.applyPlacement(for: .compact)
        XCTAssertEqual(library.chromePlacement, .compact)
        XCTAssertFalse(library.isDoneVisible)
        library.applyPlacement(for: .regular)
        XCTAssertEqual(library.chromePlacement, .regular)
        XCTAssertTrue(library.isDoneVisible)
        library.applyPlacement(for: .compact)
        XCTAssertFalse(library.isDoneVisible)
    }

    func testLibraryDoneCallsOnDone() {
        let library = BookmarksLibraryView()
        TestWindow.attach(library)
        library.applyPlacement(for: .regular)
        var didCall = false
        library.onDone = { didCall = true }
        library.performDone()
        XCTAssertTrue(didCall)
    }

    func testCompactLibraryRendersAsToday() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let root = BrowserRootViewController(database: database)
        TestWindow.attach(root)
        root.openBookmarksLibrary(tab: .bookmarks)
        XCTAssertTrue(root.bookmarksLibraryView.superview === root.view)
        XCTAssertEqual(root.bookmarksLibraryView.frame, root.view.bounds)
        XCTAssertTrue(root.libraryOverlay.isHidden)
        XCTAssertFalse(root.bookmarksLibraryView.isDoneVisible)
        root.closeBookmarksLibrary()
        XCTAssertTrue(root.bookmarksLibraryView.isHidden)
    }

    func testFoldKeepsOldChromeUntilReopened() throws {
        let database = try OuterViewDatabase(inMemory: true)
        let root = BrowserRootViewController(database: database)
        TestWindow.attach(root)
        root.openBookmarksLibrary(tab: .bookmarks)
        XCTAssertTrue(root.bookmarksLibraryView.superview === root.view)
        root.applyChromePlacement(for: .regular)
        XCTAssertTrue(root.bookmarksLibraryView.superview === root.view)
        XCTAssertTrue(root.libraryOverlay.isHidden)
        XCTAssertFalse(root.bookmarksLibraryView.isDoneVisible)
        root.closeBookmarksLibrary()
    }
}
