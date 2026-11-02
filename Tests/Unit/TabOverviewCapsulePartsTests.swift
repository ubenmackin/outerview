//
//  TabOverviewCapsulePartsTests.swift
//  OuterViewTests
//

@testable import OuterView
import XCTest

final class TabOverviewCapsulePartsTests: XCTestCase {
    func testTabsCapsuleCountTitleUsesSingularForOne() {
        XCTAssertEqual(TabOverviewViewController.tabsCapsuleCountTitle(count: 1), "1 Tab")
    }

    func testTabsCapsuleCountTitlePluralizesOtherCounts() {
        XCTAssertEqual(TabOverviewViewController.tabsCapsuleCountTitle(count: 2), "2 Tabs")
    }

    func testOtherModeTitleNamesPrivateForStandard() {
        XCTAssertEqual(TabOverviewViewController.otherModeTitle(for: .standard), "Private")
    }

    func testOtherModeTitleNamesStandardForPrivate() {
        XCTAssertEqual(TabOverviewViewController.otherModeTitle(for: .privateMode), "Standard")
    }
}
