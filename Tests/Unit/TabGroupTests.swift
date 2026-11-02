//
//  TabGroupTests.swift
//  OuterViewTests
//

@testable import OuterView
import SwiftData
import XCTest

@MainActor
final class TabGroupTests: XCTestCase {
    private func makeDatabase() throws -> OuterViewDatabase {
        try OuterViewDatabase(inMemory: true)
    }

    private func url(_ path: String) -> URL {
        URL(string: "https://example.com/\(path)")!
    }

    private func tab(_ name: String, groupId: UUID? = nil) -> TabRecord {
        TabRecord(url: url(name.lowercased()), title: name, isPrivate: false, groupId: groupId)
    }

    private func item(_ name: String, groupId: UUID? = nil, isPrivate: Bool = false) -> TabOverviewItem {
        TabOverviewItem(title: name, host: "example.com", url: url(name.lowercased()), isPrivate: isPrivate, groupId: groupId)
    }

    func testCreateGroupClampsToMaxLength() throws {
        let store = try TabStore(database: makeDatabase())
        let group = try store.createGroup(name: String(repeating: "x", count: 40))
        XCTAssertEqual(group.name.count, TabGroup.maxNameLength)
        XCTAssertEqual(store.fetchGroups().map(\.id), [group.id])
    }

    func testCreateGroupRejectsEmptyName() throws {
        let store = try TabStore(database: makeDatabase())
        XCTAssertThrowsError(try store.createGroup(name: "")) { error in
            XCTAssertEqual(error as? TabStoreError, .invalidGroupName)
        }
        XCTAssertThrowsError(try store.createGroup(name: "   \n  ")) { error in
            XCTAssertEqual(error as? TabStoreError, .invalidGroupName)
        }
        XCTAssertTrue(store.fetchGroups().isEmpty)
    }

    func testFetchGroupsOrdersByCreation() throws {
        let database = try makeDatabase()
        let base = Date(timeIntervalSince1970: 1000)
        database.context.insert(TabGroup(name: "Second", createdAt: base.addingTimeInterval(10)))
        database.context.insert(TabGroup(name: "First", createdAt: base))
        database.context.insert(TabGroup(name: "Third", createdAt: base.addingTimeInterval(20)))
        try database.context.save()
        let store = TabStore(database: database)
        XCTAssertEqual(store.fetchGroups().map(\.name), ["First", "Second", "Third"])
    }

    func testRenameGroupClampsRejectsAndRequiresExisting() throws {
        let store = try TabStore(database: makeDatabase())
        let group = try store.createGroup(name: "Work")
        try store.renameGroup(id: group.id, name: "Personal")
        XCTAssertEqual(store.fetchGroups().first?.name, "Personal")
        try store.renameGroup(id: group.id, name: String(repeating: "y", count: 50))
        XCTAssertEqual(store.fetchGroups().first?.name.count, TabGroup.maxNameLength)
        XCTAssertThrowsError(try store.renameGroup(id: group.id, name: "  ")) { error in
            XCTAssertEqual(error as? TabStoreError, .invalidGroupName)
        }
        XCTAssertThrowsError(try store.renameGroup(id: UUID(), name: "Ghost")) { error in
            XCTAssertEqual(error as? TabStoreError, .groupNotFound)
        }
    }

    func testDeleteGroupOrphansMembersButKeepsTabsOpen() throws {
        let store = try TabStore(database: makeDatabase())
        let keep = try store.createGroup(name: "Keep")
        let drop = try store.createGroup(name: "Drop")
        let memberA = tab("A", groupId: drop.id)
        let memberB = tab("B", groupId: drop.id)
        let other = tab("C", groupId: keep.id)
        let plain = tab("D")
        try store.saveSession(tabs: [memberA, memberB, other, plain], selected: memberA.id)
        try store.deleteGroup(id: drop.id)
        XCTAssertEqual(store.fetchGroups().map(\.id), [keep.id])
        let (tabs, _) = store.loadSession()
        XCTAssertEqual(tabs.count, 4)
        let byID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        XCTAssertNil(byID[memberA.id]?.groupId)
        XCTAssertNil(byID[memberB.id]?.groupId)
        XCTAssertEqual(byID[other.id]?.groupId, keep.id)
        XCTAssertNil(byID[plain.id]?.groupId)
    }

    func testAssignTabValidatesGroupAndTab() throws {
        let store = try TabStore(database: makeDatabase())
        let group = try store.createGroup(name: "Work")
        let other = try store.createGroup(name: "Other")
        let record = tab("A")
        try store.saveSession(tabs: [record], selected: record.id)
        try store.assignTab(id: record.id, toGroup: group.id)
        XCTAssertEqual(store.loadSession().tabs.first?.groupId, group.id)
        try store.assignTab(id: record.id, toGroup: other.id)
        XCTAssertEqual(store.loadSession().tabs.first?.groupId, other.id)
        try store.assignTab(id: record.id, toGroup: nil)
        XCTAssertNil(store.loadSession().tabs.first?.groupId)
        XCTAssertThrowsError(try store.assignTab(id: record.id, toGroup: UUID())) { error in
            XCTAssertEqual(error as? TabStoreError, .groupNotFound)
        }
        XCTAssertThrowsError(try store.assignTab(id: UUID(), toGroup: group.id)) { error in
            XCTAssertEqual(error as? TabStoreError, .tabNotFound)
        }
    }

    func testSessionRestorePreservesMemberships() throws {
        let database = try makeDatabase()
        let store = TabStore(database: database)
        let group = try store.createGroup(name: "Work")
        let grouped = tab("A", groupId: group.id)
        let ungrouped = tab("B")
        try store.saveSession(tabs: [grouped, ungrouped], selected: grouped.id)
        let reloaded = TabStore(database: database)
        let (tabs, selected) = reloaded.loadSession()
        XCTAssertEqual(selected, grouped.id)
        let byID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        XCTAssertEqual(byID[grouped.id]?.groupId, group.id)
        XCTAssertNil(byID[ungrouped.id]?.groupId)
    }

    func testGroupCapsuleItemsCountsAndHidesEmpties() {
        let work = TabGroup(name: "Work")
        let empty = TabGroup(name: "Empty")
        let play = TabGroup(name: "Play")
        let tabs = [
            item("A", groupId: work.id),
            item("B", groupId: work.id),
            item("C", groupId: play.id),
            item("D")
        ]
        let capsule = TabOverviewViewController.groupCapsuleItems(groups: [work, empty, play], tabs: tabs)
        XCTAssertEqual(capsule.count, 3)
        XCTAssertNil(capsule[0].id)
        XCTAssertEqual(capsule[0].title, "All")
        XCTAssertEqual(capsule[0].count, 4)
        XCTAssertEqual(capsule[1].id, work.id)
        XCTAssertEqual(capsule[1].count, 2)
        XCTAssertEqual(capsule[2].id, play.id)
        XCTAssertEqual(capsule[2].count, 1)
    }

    func testVisibleTabsGroupFilterComposesWithModeAndQuery() {
        let group = TabGroup(name: "Work")
        let other = TabGroup(name: "Other")
        let tabs = [
            item("Apple", groupId: group.id),
            item("Apricot", groupId: other.id),
            item("Apple Pie"),
            item("Apple Private", groupId: group.id, isPrivate: true)
        ]
        let filtered = TabOverviewViewController.visibleTabs(tabs, mode: .standard, query: "", groupId: group.id)
        XCTAssertEqual(filtered.map(\.title), ["Apple"])
        let queried = TabOverviewViewController.visibleTabs(tabs, mode: .standard, query: "apricot", groupId: other.id)
        XCTAssertEqual(queried.map(\.title), ["Apricot"])
        let mismatched = TabOverviewViewController.visibleTabs(tabs, mode: .standard, query: "apple", groupId: other.id)
        XCTAssertTrue(mismatched.isEmpty)
        let unfiltered = TabOverviewViewController.visibleTabs(tabs, mode: .standard, query: "")
        XCTAssertEqual(unfiltered.count, 3)
        let privateFiltered = TabOverviewViewController.visibleTabs(tabs, mode: .privateMode, query: "", groupId: group.id)
        XCTAssertEqual(privateFiltered.map(\.title), ["Apple Private"])
    }

    func testMembersFiltersByGroup() {
        let group = TabGroup(name: "Work")
        let other = TabGroup(name: "Other")
        let tabs = [
            item("A", groupId: group.id),
            item("B", groupId: other.id),
            item("C")
        ]
        XCTAssertEqual(
            TabOverviewViewController.members(tabs: tabs, of: group.id).map(\.title),
            ["A"]
        )
        XCTAssertEqual(TabOverviewViewController.members(tabs: tabs, of: nil).count, 3)
    }
}
