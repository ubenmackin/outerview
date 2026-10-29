//
//  TabOverviewReorderTests.swift
//  OuterViewTests
//

import Foundation
@testable import OuterView
import XCTest

final class TabOverviewReorderTests: XCTestCase {
    private func makeIDs(_ count: Int) -> [UUID] {
        (0 ..< count).map { _ in UUID() }
    }

    func testMoveIDFirstToLast() {
        let ids = makeIDs(4)
        let moved = TabOverviewViewController.moveID(ids, from: 0, to: 3)
        XCTAssertEqual(moved, [ids[1], ids[2], ids[3], ids[0]])
    }

    func testMoveIDLastToFirst() {
        let ids = makeIDs(4)
        let moved = TabOverviewViewController.moveID(ids, from: 3, to: 0)
        XCTAssertEqual(moved, [ids[3], ids[0], ids[1], ids[2]])
    }

    func testMoveIDSameIndexReturnsUnchanged() {
        let ids = makeIDs(4)
        XCTAssertEqual(TabOverviewViewController.moveID(ids, from: 1, to: 1), ids)
    }

    func testMoveIDClampsDestinationAndIgnoresOutOfRangeSource() {
        let ids = makeIDs(4)
        // Overshot destination clamps to the last slot.
        XCTAssertEqual(
            TabOverviewViewController.moveID(ids, from: 0, to: 99),
            [ids[1], ids[2], ids[3], ids[0]]
        )
        // Negative destination clamps to the first slot.
        XCTAssertEqual(
            TabOverviewViewController.moveID(ids, from: 3, to: -5),
            [ids[3], ids[0], ids[1], ids[2]]
        )
        // Out-of-range source leaves the order untouched.
        XCTAssertEqual(TabOverviewViewController.moveID(ids, from: 99, to: 0), ids)
        XCTAssertEqual(TabOverviewViewController.moveID(ids, from: -1, to: 2), ids)
    }

    func testSpliceStandardReorderPutsStandardFirst() {
        let s1 = UUID()
        let s2 = UUID()
        let p1 = UUID()
        let p2 = UUID()
        let current = [s1, p1, s2, p2]
        let privacy: [UUID: Bool] = [s1: false, s2: false, p1: true, p2: true]
        let spliced = TabOverviewViewController.spliceTabOrder(
            currentIDs: current,
            privacyByID: privacy,
            orderedIDs: [s2, s1],
            isPrivate: false
        )
        XCTAssertEqual(spliced, [s2, s1, p1, p2])
    }

    func testSplicePrivateReorderPutsPrivateFirst() {
        let s1 = UUID()
        let s2 = UUID()
        let p1 = UUID()
        let p2 = UUID()
        let current = [s1, p1, s2, p2]
        let privacy: [UUID: Bool] = [s1: false, s2: false, p1: true, p2: true]
        let spliced = TabOverviewViewController.spliceTabOrder(
            currentIDs: current,
            privacyByID: privacy,
            orderedIDs: [p2, p1],
            isPrivate: true
        )
        XCTAssertEqual(spliced, [p2, p1, s1, s2])
    }

    func testSpliceFiltersOppositeModeAndDropsUnknownIDs() {
        let s1 = UUID()
        let s2 = UUID()
        let s3 = UUID()
        let p1 = UUID()
        let unknown = UUID()
        let current = [s1, p1, s2, s3]
        let privacy: [UUID: Bool] = [s1: false, s2: false, s3: false, p1: true]
        let spliced = TabOverviewViewController.spliceTabOrder(
            currentIDs: current,
            privacyByID: privacy,
            orderedIDs: [p1, s2, s1, unknown],
            isPrivate: false
        )
        XCTAssertEqual(spliced, [s2, s1, p1, s3])
    }

    func testSpliceMissingSameModeIDsFallBackToUntouchedInStripOrder() {
        let s1 = UUID()
        let s2 = UUID()
        let s3 = UUID()
        let current = [s1, s2, s3]
        let privacy: [UUID: Bool] = [s1: false, s2: false, s3: false]
        let spliced = TabOverviewViewController.spliceTabOrder(
            currentIDs: current,
            privacyByID: privacy,
            orderedIDs: [s3, s1],
            isPrivate: false
        )
        XCTAssertEqual(spliced, [s3, s1, s2])
    }
}
