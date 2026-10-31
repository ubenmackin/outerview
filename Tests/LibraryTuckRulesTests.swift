//
//  LibraryTuckRulesTests.swift
//  OuterViewTests
//

@testable import OuterView
import XCTest

/// Decision matrix for the pure re-tuck predicate behind the library search
/// tuck: re-tuck only when the field is not first responder, no query filters
/// the list, and the table offset sits below the hide offset.
final class LibraryTuckRulesTests: XCTestCase {
    func testRetucksAtRestAndDuringPullDown() {
        XCTAssertTrue(LibrarySearchTuckController.shouldRetuck(
            isEditing: false,
            isFiltering: false,
            offsetY: 0,
            headerHeight: 64
        ))
        XCTAssertTrue(LibrarySearchTuckController.shouldRetuck(
            isEditing: false,
            isFiltering: false,
            offsetY: 20,
            headerHeight: 64
        ))
    }

    func testDoesNotRetuckWhileEditing() {
        XCTAssertFalse(LibrarySearchTuckController.shouldRetuck(
            isEditing: true,
            isFiltering: false,
            offsetY: 0,
            headerHeight: 64
        ))
    }

    func testDoesNotRetuckWhileFiltering() {
        XCTAssertFalse(LibrarySearchTuckController.shouldRetuck(
            isEditing: false,
            isFiltering: true,
            offsetY: 0,
            headerHeight: 64
        ))
    }

    func testDoesNotRetuckAtOrBeyondTheHideOffset() {
        XCTAssertFalse(LibrarySearchTuckController.shouldRetuck(
            isEditing: false,
            isFiltering: false,
            offsetY: 64,
            headerHeight: 64
        ))
        XCTAssertFalse(LibrarySearchTuckController.shouldRetuck(
            isEditing: false,
            isFiltering: false,
            offsetY: 120,
            headerHeight: 64
        ))
    }

    func testDefaultHeaderHeightIsTheTuckConstant() {
        XCTAssertEqual(LibrarySearchHeaderView.defaultHeight, 64)
        XCTAssertTrue(LibrarySearchTuckController.shouldRetuck(
            isEditing: false,
            isFiltering: false,
            offsetY: 63
        ))
        XCTAssertFalse(LibrarySearchTuckController.shouldRetuck(
            isEditing: false,
            isFiltering: false,
            offsetY: 64
        ))
    }

    func testRequiresCollapseNeverWhenBoundsIsZero() {
        XCTAssertFalse(LibrarySearchTuckController.requiresCollapse(
            contentHeight: 0,
            boundsHeight: 0
        ))
        XCTAssertFalse(LibrarySearchTuckController.requiresCollapse(
            contentHeight: 200,
            boundsHeight: 0
        ))
    }

    func testRequiresCollapseForShortLists() {
        XCTAssertTrue(LibrarySearchTuckController.requiresCollapse(
            contentHeight: 200,
            boundsHeight: 600
        ))
    }

    func testRequiresCollapseFalseForTallLists() {
        XCTAssertFalse(LibrarySearchTuckController.requiresCollapse(
            contentHeight: 700,
            boundsHeight: 600
        ))
    }

    func testRequiresCollapseBoundaryIsFalse() {
        XCTAssertFalse(LibrarySearchTuckController.requiresCollapse(
            contentHeight: 664,
            boundsHeight: 600
        ))
    }

    @MainActor
    func testReassertDoesNotForceLayoutWhenDetachedOrZeroBounds() {
        let tuck = LibrarySearchTuckController()
        let tableView = UITableView(frame: .zero)
        let header = LibrarySearchHeaderView(frame: .zero)
        // Table is detached and bounds.height == 0; reassert should safely no-op without attaching or laying out
        tuck.reassert(tableView: tableView, header: header, searchBar: header.searchBar, isFiltering: false)
        XCTAssertNil(tableView.tableHeaderView)
    }
}
