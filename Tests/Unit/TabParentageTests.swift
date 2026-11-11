// Persistence — TabStore round-trip tests for TabRecord.parentTabID link lineage.

@testable import OuterView
import XCTest

@MainActor
final class TabParentageTests: XCTestCase {
    private func makeDatabase() throws -> OuterViewDatabase {
        try OuterViewDatabase(inMemory: true)
    }

    private func url(_ path: String) -> URL {
        URL(string: "https://example.com/\(path)")!
    }

    private func tab(_ name: String, parentTabID: UUID? = nil) -> TabRecord {
        TabRecord(url: url(name.lowercased()), title: name, isPrivate: false, parentTabID: parentTabID)
    }

    func testSaveLoadSessionRoundTripsParentage() throws {
        let store = try TabStore(database: makeDatabase())
        let parent = tab("Parent")
        let child = tab("Child", parentTabID: parent.id)
        try store.saveSession(tabs: [parent, child], selected: child.id)
        let (tabs, selected) = store.loadSession()
        XCTAssertEqual(selected, child.id)
        let byID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        XCTAssertEqual(byID[child.id]?.parentTabID, parent.id)
        XCTAssertNil(byID[parent.id]?.parentTabID)
    }

    func testUpsertTabPreservesParentage() throws {
        let store = try TabStore(database: makeDatabase())
        let parent = tab("Parent")
        let child = tab("Child", parentTabID: parent.id)
        try store.upsertTab(child)
        XCTAssertEqual(store.loadSession().tabs.first?.parentTabID, parent.id)
        // A second upsert of the same id exercises the row-update branch.
        let edited = TabRecord(
            id: child.id,
            url: url("child-two"),
            title: "Child Two",
            isPrivate: false,
            parentTabID: parent.id
        )
        try store.upsertTab(edited)
        let (tabs, _) = store.loadSession()
        XCTAssertEqual(tabs.first?.title, "Child Two")
        XCTAssertEqual(tabs.first?.parentTabID, parent.id)
    }

    func testReorderAndSelectPreserveParentage() throws {
        let store = try TabStore(database: makeDatabase())
        let parent = tab("Parent")
        let child = tab("Child", parentTabID: parent.id)
        try store.saveSession(tabs: [parent, child], selected: parent.id)
        try store.reorder(tabs: [child, parent])
        try store.select(id: child.id)
        let (tabs, selected) = store.loadSession()
        XCTAssertEqual(tabs.map(\.id), [child.id, parent.id])
        XCTAssertEqual(selected, child.id)
        let byID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        XCTAssertEqual(byID[child.id]?.parentTabID, parent.id)
    }

    func testDanglingParentIDPersists() throws {
        let store = try TabStore(database: makeDatabase())
        let parent = tab("Parent")
        let child = tab("Child", parentTabID: parent.id)
        try store.saveSession(tabs: [parent, child], selected: child.id)
        // Closing the parent never scrubs the child's lineage; inertness is
        // resolved at use time against the live tab list.
        try store.deleteTab(id: parent.id)
        let (tabs, _) = store.loadSession()
        XCTAssertEqual(tabs.map(\.id), [child.id])
        XCTAssertEqual(tabs.first?.parentTabID, parent.id)
    }

    func testDefaultTabRecordHasNilParentTabID() {
        XCTAssertNil(TabRecord(isPrivate: false).parentTabID)
    }
}
