//
//  ReadingListDisplayPrefsTests.swift
//  OuterViewTests
//

@testable import OuterView
import XCTest

final class ReadingListDisplayPrefsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ReadingListDisplayPrefsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDisplayModeRoundTrip() {
        XCTAssertEqual(ReadingListView.storedDisplayMode(defaults: defaults), .compact)
        ReadingListView.persist(displayMode: .large, defaults: defaults)
        XCTAssertEqual(ReadingListView.storedDisplayMode(defaults: defaults), .large)
        ReadingListView.persist(displayMode: .compact, defaults: defaults)
        XCTAssertEqual(ReadingListView.storedDisplayMode(defaults: defaults), .compact)
    }

    func testFilterModeRoundTrip() {
        XCTAssertEqual(ReadingListView.storedFilterMode(defaults: defaults), .all)
        ReadingListView.persist(filterMode: .unreadOnly, defaults: defaults)
        XCTAssertEqual(ReadingListView.storedFilterMode(defaults: defaults), .unreadOnly)
        ReadingListView.persist(filterMode: .all, defaults: defaults)
        XCTAssertEqual(ReadingListView.storedFilterMode(defaults: defaults), .all)
    }

    func testCombinedPersistRoundTrip() {
        ReadingListView.persist(displayMode: .large, defaults: defaults)
        ReadingListView.persist(filterMode: .unreadOnly, defaults: defaults)
        XCTAssertEqual(ReadingListView.storedDisplayMode(defaults: defaults), .large)
        XCTAssertEqual(ReadingListView.storedFilterMode(defaults: defaults), .unreadOnly)
        ReadingListView.persist(displayMode: .compact, defaults: defaults)
        ReadingListView.persist(filterMode: .all, defaults: defaults)
        XCTAssertEqual(ReadingListView.storedDisplayMode(defaults: defaults), .compact)
        XCTAssertEqual(ReadingListView.storedFilterMode(defaults: defaults), .all)
    }

    func testUnknownValuesFallBackToDefaults() {
        defaults.set("bogus-value", forKey: ReadingListView.displayModeDefaultsKey)
        defaults.set("bogus-value", forKey: ReadingListView.filterModeDefaultsKey)
        XCTAssertEqual(ReadingListView.storedDisplayMode(defaults: defaults), .compact)
        XCTAssertEqual(ReadingListView.storedFilterMode(defaults: defaults), .all)
    }
}
