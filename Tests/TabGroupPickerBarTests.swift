//
//  TabGroupPickerBarTests.swift
//  OuterViewTests
//

@testable import OuterView
import XCTest

final class TabGroupPickerBarTests: XCTestCase {
    private func capsule(_ id: UUID?, title: String, count: Int) -> GroupCapsuleItem {
        GroupCapsuleItem(id: id, title: title, count: count)
    }

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

    func testSelectionStandardWithNilGroupYieldsAllStandard() {
        XCTAssertEqual(
            TabGroupPickerBar.selection(isPrivate: false, selectedGroupID: nil, groups: []),
            PickerSelection.allStandard
        )
    }

    func testSelectionPrivateYieldsPrivate() {
        XCTAssertEqual(
            TabGroupPickerBar.selection(isPrivate: true, selectedGroupID: nil, groups: []),
            PickerSelection.private
        )
    }

    func testSelectionPrivateWinsOverGroupFilter() {
        let id = UUID()
        XCTAssertEqual(
            TabGroupPickerBar.selection(
                isPrivate: true,
                selectedGroupID: id,
                groups: [capsule(id, title: "Work", count: 3)]
            ),
            PickerSelection.private
        )
    }

    func testSelectionMatchingGroupYieldsGroup() {
        let id = UUID()
        XCTAssertEqual(
            TabGroupPickerBar.selection(
                isPrivate: false,
                selectedGroupID: id,
                groups: [capsule(id, title: "Work", count: 3)]
            ),
            PickerSelection.group(id)
        )
    }

    func testSelectionUnknownGroupYieldsAllStandard() {
        let known = UUID()
        let unknown = UUID()
        XCTAssertEqual(
            TabGroupPickerBar.selection(
                isPrivate: false,
                selectedGroupID: unknown,
                groups: [capsule(known, title: "Work", count: 3)]
            ),
            PickerSelection.allStandard
        )
    }

    func testCompactTitleUsesSingularForOneStandardTab() {
        let title = TabGroupPickerBar.compactTitle(for: state(standardCount: 1))
        let expected = "\(TabOverviewViewController.otherModeTitle(for: .standard)) · \(TabOverviewViewController.tabsCapsuleCountTitle(count: 1))"
        XCTAssertEqual(title, expected)
        XCTAssertEqual(TabOverviewViewController.tabsCapsuleCountTitle(count: 1), "1 Tab")
    }

    func testCompactTitleUsesPluralForManyStandardTabs() {
        let title = TabGroupPickerBar.compactTitle(for: state(standardCount: 4))
        let expected = "\(TabOverviewViewController.otherModeTitle(for: .standard)) · \(TabOverviewViewController.tabsCapsuleCountTitle(count: 4))"
        XCTAssertEqual(title, expected)
        XCTAssertEqual(TabOverviewViewController.tabsCapsuleCountTitle(count: 4), "4 Tabs")
    }

    func testCompactTitleInPrivateModeUsesPrivateCount() {
        let title = TabGroupPickerBar.compactTitle(for: state(isPrivate: true, privateCount: 2))
        let expected = "\(TabOverviewViewController.otherModeTitle(for: .privateMode)) · \(TabOverviewViewController.tabsCapsuleCountTitle(count: 2))"
        XCTAssertEqual(title, expected)
    }
}
