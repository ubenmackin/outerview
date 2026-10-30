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

    @MainActor
    func testPillLayoutAtRest() {
        let bar = TabGroupPickerBar()
        bar.render(state: state(isPrivate: false, standardCount: 2))
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 466, height: 678))
        parent.addSubview(bar)
        bar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bar.centerXAnchor.constraint(equalTo: parent.centerXAnchor),
            bar.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -16),
            bar.leadingAnchor.constraint(greaterThanOrEqualTo: parent.leadingAnchor, constant: 16),
            bar.trailingAnchor.constraint(lessThanOrEqualTo: parent.trailingAnchor, constant: -16),
            bar.heightAnchor.constraint(equalToConstant: 44)
        ])
        parent.layoutIfNeeded()

        XCTAssertEqual(bar.activeIndex, 1)
        XCTAssertGreaterThan(bar.slidingPillView.frame.width, 40)
        XCTAssertEqual(bar.slidingPillView.frame.minY, 4, accuracy: 1)
        let initialPillMinX = bar.slidingPillView.frame.minX
        XCTAssertGreaterThan(initialPillMinX, 50)

        // Simulate release / scrub end: render is called again with the active state
        bar.render(state: state(isPrivate: false, standardCount: 2))
        parent.layoutIfNeeded()

        // Pill must maintain its centered alignment over button 1 rather than jumping back to top-left
        XCTAssertEqual(bar.activeIndex, 1)
        XCTAssertEqual(bar.slidingPillView.frame.minX, initialPillMinX, accuracy: 1)
        XCTAssertEqual(bar.slidingPillView.frame.minY, 4, accuracy: 1)
    }
}
