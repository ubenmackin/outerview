//
//  TabGroupBatchTests.swift
//  OuterViewTests
//

@testable import OuterView
import SwiftData
import XCTest

@MainActor
final class TabGroupBatchTests: XCTestCase {
    // MARK: - Helpers

    private func makeDatabase() throws -> OuterViewDatabase {
        try OuterViewDatabase(inMemory: true)
    }

    private func url(_ path: String) -> URL {
        URL(string: "https://example.com/\(path)")!
    }

    private func tab(_ name: String) -> TabRecord {
        TabRecord(url: url(name.lowercased()), title: name, isPrivate: false)
    }

    /// Mirrors the owner-side batch creation shape: one `createGroup` call,
    /// then per-tab assignment restricted to non-private listed records
    /// (private tabs are skipped by the owner, never assigned).
    private func assignListed(
        _ listed: [UUID],
        toGroup group: TabGroup,
        strip: [TabRecord],
        using store: TabStore
    ) throws {
        for record in strip where listed.contains(record.id) && !record.isPrivate {
            record.groupId = group.id
            try store.assignTab(id: record.id, toGroup: group.id)
        }
    }

    // MARK: - Batch creation

    func testBatchCreationAssignsExactlyTheListedStandardTabs() throws {
        let database = try makeDatabase()
        let store = TabStore(database: database)
        let alpha = tab("Alpha")
        let beta = tab("Beta")
        let hidden = TabRecord(url: url("hidden"), title: "Hidden", isPrivate: true)
        let strip = [alpha, beta, hidden]
        try store.saveSession(tabs: strip, selected: alpha.id)

        let group = try store.createGroup(name: "Weekend")
        try assignListed(
            [alpha.id, beta.id, hidden.id],
            toGroup: group,
            strip: strip,
            using: store
        )
        try store.saveSession(tabs: strip, selected: alpha.id)

        // Private record stays unassigned in memory and never reaches disk.
        XCTAssertNil(hidden.groupId)
        XCTAssertEqual(store.fetchGroups().map(\.id), [group.id])
        let persisted = try database.context.fetch(FetchDescriptor<TabRecord>())
        XCTAssertEqual(Set(persisted.map(\.id)), Set([alpha.id, beta.id]))
        XCTAssertEqual(
            Set(persisted.filter { $0.groupId == group.id }.map(\.id)),
            Set([alpha.id, beta.id])
        )
        XCTAssertTrue(persisted.allSatisfy { $0.groupId == group.id })
    }

    func testEmptyListCreatesAGroupWithNoMembers() throws {
        let database = try makeDatabase()
        let store = TabStore(database: database)
        let solo = tab("Solo")
        try store.saveSession(tabs: [solo], selected: solo.id)

        let group = try store.createGroup(name: "Someday")
        try assignListed([], toGroup: group, strip: [solo], using: store)
        try store.saveSession(tabs: [solo], selected: solo.id)

        XCTAssertEqual(store.fetchGroups().map(\.id), [group.id])
        let persisted = try database.context.fetch(FetchDescriptor<TabRecord>())
        XCTAssertEqual(persisted.map(\.id), [solo.id])
        XCTAssertNil(persisted.first?.groupId)
    }

    func testBatchCreationToleratesListedIdsMissingFromTheStrip() throws {
        let database = try makeDatabase()
        let store = TabStore(database: database)
        let alpha = tab("Alpha")
        let strip = [alpha]
        try store.saveSession(tabs: strip, selected: alpha.id)

        let group = try store.createGroup(name: "Work")
        try assignListed([alpha.id, UUID()], toGroup: group, strip: strip, using: store)
        try store.saveSession(tabs: strip, selected: alpha.id)

        let persisted = try database.context.fetch(FetchDescriptor<TabRecord>())
        XCTAssertEqual(persisted.map(\.groupId), [group.id])
        XCTAssertEqual(store.fetchGroups().map(\.id), [group.id])
    }
}
