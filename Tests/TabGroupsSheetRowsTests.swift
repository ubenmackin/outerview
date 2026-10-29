//
//  TabGroupsSheetRowsTests.swift
//  OuterViewTests
//

@testable import OuterView
import XCTest

final class TabGroupsSheetRowsTests: XCTestCase {
    private typealias Row = TabGroupsSheetController.Row

    private func state(
        isPrivate: Bool = false,
        selectedGroupID: UUID? = nil,
        standardCount: Int = 2,
        privateCount: Int = 1,
        groups: [GroupCapsuleItem] = []
    ) -> TabGroupsSheetState {
        TabGroupsSheetState(
            isPrivate: isPrivate,
            selectedGroupID: selectedGroupID,
            standardCount: standardCount,
            privateCount: privateCount,
            groups: groups
        )
    }

    private func capsule(_ id: UUID?, title: String, count: Int) -> GroupCapsuleItem {
        GroupCapsuleItem(id: id, title: title, count: count)
    }

    private func groupRows(in rows: [Row]) -> [Row] {
        rows.compactMap { row -> Row? in
            if case .group = row {
                return row
            }
            return nil
        }
    }

    private func containsCreateWithTabs(_ rows: [Row]) -> Bool {
        rows.contains { row in
            if case .createWithTabs = row {
                return true
            }
            return false
        }
    }

    func testRowsWithOneGroupPutAllAndPrivateFirst() {
        let id = UUID()
        let rows = TabGroupsSheetController.rows(
            for: state(groups: [capsule(id, title: "Work", count: 3)])
        )
        XCTAssertEqual(rows.first, Row.allSelected(active: true))
        XCTAssertEqual(rows.dropFirst().first, Row.privateRow(active: false))
        XCTAssertEqual(groupRows(in: rows), [Row.group(id, "Work", 3, active: false)])
        XCTAssertTrue(containsCreateWithTabs(rows))
        XCTAssertTrue(rows.contains(Row.createEmpty))
    }

    func testSingleNonEmptyGroupYieldsExactlyOneGroupRow() {
        let id = UUID()
        let rows = TabGroupsSheetController.rows(
            for: state(groups: [capsule(id, title: "Work", count: 3)])
        )
        let expected: [Row] = [
            .allSelected(active: true),
            .privateRow(active: false),
            .group(id, "Work", 3, active: false),
            .createEmpty,
            .createWithTabs(count: 2)
        ]
        XCTAssertEqual(rows, expected)
    }

    func testZeroStandardTabsOmitCreateWithTabs() {
        let rows = TabGroupsSheetController.rows(for: state(standardCount: 0))
        XCTAssertFalse(containsCreateWithTabs(rows))
        XCTAssertEqual(rows.last, Row.createEmpty)
        XCTAssertTrue(rows.contains(Row.allSelected(active: true)))
    }

    func testTwoStandardTabsIncludeCreateWithTabs() {
        let rows = TabGroupsSheetController.rows(for: state(standardCount: 2))
        XCTAssertEqual(rows.last, Row.createWithTabs(count: 2))
    }

    func testActiveFlagsMapFromPrivacy() {
        let id = UUID()
        let rows = TabGroupsSheetController.rows(
            for: state(isPrivate: true, groups: [capsule(id, title: "Work", count: 3)])
        )
        let expected: [Row] = [
            .allSelected(active: false),
            .privateRow(active: true),
            .group(id, "Work", 3, active: false),
            .createEmpty,
            .createWithTabs(count: 2)
        ]
        XCTAssertEqual(rows, expected)
    }

    func testActiveFlagsMapFromGroupFilter() {
        let id = UUID()
        let rows = TabGroupsSheetController.rows(
            for: state(selectedGroupID: id, groups: [capsule(id, title: "Work", count: 3)])
        )
        let expected: [Row] = [
            .allSelected(active: false),
            .privateRow(active: false),
            .group(id, "Work", 3, active: true),
            .createEmpty,
            .createWithTabs(count: 2)
        ]
        XCTAssertEqual(rows, expected)
    }

    func testOnlySelectedGroupIsActiveWithMultipleGroups() {
        let first = UUID()
        let second = UUID()
        let rows = TabGroupsSheetController.rows(
            for: state(selectedGroupID: first, groups: [
                capsule(first, title: "Work", count: 3),
                capsule(second, title: "Personal", count: 1)
            ])
        )
        XCTAssertEqual(rows.first, Row.allSelected(active: false))
        XCTAssertEqual(
            groupRows(in: rows),
            [
                Row.group(first, "Work", 3, active: true),
                Row.group(second, "Personal", 1, active: false)
            ]
        )
    }

    func testSyntheticAllCapsuleItemIsNotDuplicated() {
        let id = UUID()
        let rows = TabGroupsSheetController.rows(
            for: state(groups: [
                capsule(nil, title: "All", count: 4),
                capsule(id, title: "Work", count: 1)
            ])
        )
        XCTAssertEqual(groupRows(in: rows), [Row.group(id, "Work", 1, active: false)])
        XCTAssertTrue(rows.contains(Row.allSelected(active: true)))
    }

    func testStateIsEquatableAcrossSnapshots() {
        let id = UUID()
        XCTAssertEqual(
            state(groups: [capsule(id, title: "Work", count: 1)]),
            state(groups: [capsule(id, title: "Work", count: 1)])
        )
        XCTAssertNotEqual(
            state(groups: [capsule(id, title: "Work", count: 1)]),
            state(groups: [capsule(id, title: "Work", count: 2)])
        )
    }
}
