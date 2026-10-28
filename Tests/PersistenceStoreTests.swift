//
//  PersistenceStoreTests.swift
//  OuterView
//

@testable import OuterView
import SwiftData
import XCTest

@MainActor
final class PersistenceStoreTests: XCTestCase {
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

    // MARK: - Bookmarks

    func testBookmarkCreateFetchUpdateDelete() throws {
        let database = try makeDatabase()
        let store = BookmarkStore(database: database)
        let addedAt = Date(timeIntervalSince1970: 100)

        try store.add(title: "Doc", url: url("doc"), addedDate: addedAt)
        let bookmarks = store.fetchAll()
        XCTAssertEqual(bookmarks.count, 1)
        let firstBookmark = try XCTUnwrap(bookmarks.first)
        XCTAssertEqual(firstBookmark.title, "Doc")
        XCTAssertEqual(firstBookmark.url, url("doc"))
        XCTAssertEqual(firstBookmark.addedAt, addedAt)
        XCTAssertFalse(firstBookmark.isFavorite)

        try store.upsertFavorite(url: url("doc"), title: "Doc Renamed")
        let favorites = store.fetchFavorites()
        XCTAssertEqual(favorites.count, 1)
        let firstFavorite = try XCTUnwrap(favorites.first)
        XCTAssertTrue(firstFavorite.isFavorite)
        XCTAssertEqual(firstFavorite.addedAt, addedAt)
        XCTAssertEqual(firstFavorite.title, "Doc Renamed")

        try store.delete(id: firstFavorite.id)
        XCTAssertTrue(store.fetchAll().isEmpty)
        XCTAssertTrue(store.fetchFavorites().isEmpty)
    }

    func testUpsertFavoriteDedupesByURLKeepingEarliest() throws {
        let database = try makeDatabase()
        let store = BookmarkStore(database: database)
        let addedAt = Date(timeIntervalSince1970: 100)

        try store.add(title: "First", url: url("same"), addedDate: addedAt)
        try store.upsertFavorite(url: url("same"), title: "Second")

        XCTAssertEqual(store.fetchAll().count, 1)
        let favorite = try XCTUnwrap(store.fetchFavorites().first)
        XCTAssertEqual(favorite.addedAt, addedAt)
        XCTAssertEqual(favorite.title, "Second")
        XCTAssertTrue(favorite.isFavorite)
    }

    func testUpsertFavoriteInsertsWhenURLIsUnknown() throws {
        let database = try makeDatabase()
        let store = BookmarkStore(database: database)

        try store.upsertFavorite(url: url("fresh"), title: "Fresh")

        XCTAssertEqual(store.fetchAll().count, 1)
        XCTAssertEqual(store.fetchFavorites().map(\.title), ["Fresh"])
    }

    func testFetchAllIsSortedOldestFirst() throws {
        let database = try makeDatabase()
        let store = BookmarkStore(database: database)

        try store.add(title: "Old", url: url("old"), addedDate: Date(timeIntervalSince1970: 1))
        try store.add(title: "New", url: url("new"), addedDate: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(store.fetchAll().map(\.title), ["Old", "New"])
    }

    // MARK: - History

    func testHistoryRecordsRowPerVisitNewestFirst() throws {
        let database = try makeDatabase()
        let store = HistoryStore(database: database)

        try store.record(visit: PageVisit(url: url("a"), title: "A", visitedAt: Date(timeIntervalSince1970: 1)))
        try store.record(visit: PageVisit(url: url("b"), title: "B", visitedAt: Date(timeIntervalSince1970: 2)))
        try store.record(visit: PageVisit(url: url("a"), title: "A again", visitedAt: Date(timeIntervalSince1970: 3)))

        XCTAssertEqual(store.fetchAll().map(\.title), ["A again", "B", "A"])
        XCTAssertEqual(store.fetchRecents(limit: 2).map(\.title), ["A again", "B"])
    }

    func testHistoryCapPrunesOldest() throws {
        let database = try makeDatabase()
        let store = HistoryStore(database: database)
        let base = Date(timeIntervalSince1970: 0)
        for index in 0 ..< HistoryStore.maxEntries {
            database.context.insert(
                HistoryEntry(
                    title: "h\(index)",
                    url: url("h\(index)"),
                    visitedAt: base.addingTimeInterval(TimeInterval(index))
                )
            )
        }
        try database.context.save()

        let newest = PageVisit(
            url: url("newest"),
            title: "newest",
            visitedAt: base.addingTimeInterval(TimeInterval(HistoryStore.maxEntries))
        )
        try store.record(visit: newest)

        let all = store.fetchAll(limit: HistoryStore.maxEntries)
        XCTAssertEqual(all.count, HistoryStore.maxEntries)
        XCTAssertEqual(all.first?.url, newest.url)
        XCTAssertFalse(all.contains { $0.title == "h0" })
        XCTAssertTrue(all.contains { $0.title == "h1" })
    }

    func testHistoryClearRemovesAllRows() throws {
        let database = try makeDatabase()
        let store = HistoryStore(database: database)
        try store.record(visit: PageVisit(url: url("a"), title: "A"))
        try store.record(visit: PageVisit(url: url("b"), title: "B"))

        try store.clear()

        XCTAssertTrue(store.fetchAll().isEmpty)
    }

    // MARK: - Tab session

    func testSessionSaveLoadPreservesOrderAndSelection() throws {
        let database = try makeDatabase()
        let store = TabStore(database: database)
        let tabA = tab("A")
        let tabB = tab("B")
        let tabC = tab("C")

        try store.saveSession(tabs: [tabA, tabB, tabC], selected: tabB.id)

        let (tabs, selected) = store.loadSession()
        XCTAssertEqual(tabs.map(\.id), [tabA.id, tabB.id, tabC.id])
        XCTAssertEqual(selected, tabB.id)
        XCTAssertEqual(tabs[1].title, "B")
        XCTAssertEqual(tabs[1].url, url("b"))
    }

    func testLoadSessionWithoutSaveReturnsEmpty() throws {
        let database = try makeDatabase()
        let store = TabStore(database: database)

        let (tabs, selected) = store.loadSession()

        XCTAssertTrue(tabs.isEmpty)
        XCTAssertNil(selected)
    }

    func testUpsertTabUpdatesExistingRecordInPlace() throws {
        let database = try makeDatabase()
        let store = TabStore(database: database)
        let original = tab("A")
        try store.upsertTab(original)

        let edited = TabRecord(
            id: original.id,
            url: url("moved"),
            title: "A moved",
            isPrivate: false,
            createdAt: original.createdAt,
            lastActiveAt: original.lastActiveAt.addingTimeInterval(60)
        )
        try store.upsertTab(edited)

        let (tabs, selected) = store.loadSession()
        XCTAssertEqual(tabs.count, 1)
        let firstTab = try XCTUnwrap(tabs.first)
        XCTAssertEqual(firstTab.id, original.id)
        XCTAssertEqual(firstTab.title, "A moved")
        XCTAssertEqual(firstTab.url, url("moved"))
        XCTAssertNil(selected)
    }

    func testReorderKeepsSelectionAndDropsPrivateTabs() throws {
        let database = try makeDatabase()
        let store = TabStore(database: database)
        let tabA = tab("A")
        let tabB = tab("B")
        let tabC = tab("C")
        try store.saveSession(tabs: [tabA, tabB, tabC], selected: tabB.id)

        let privateTab = TabRecord(url: url("hidden"), title: "Hidden", isPrivate: true)
        try store.reorder(tabs: [privateTab, tabC, tabA, tabB])

        let (tabs, selected) = store.loadSession()
        XCTAssertEqual(tabs.map(\.id), [tabC.id, tabA.id, tabB.id])
        XCTAssertEqual(selected, tabB.id)
    }

    func testDeleteTabRemovesRowAndSelection() throws {
        let database = try makeDatabase()
        let store = TabStore(database: database)
        let tabA = tab("A")
        let tabB = tab("B")
        try store.saveSession(tabs: [tabA, tabB], selected: tabB.id)

        try store.deleteTab(id: tabB.id)

        let (tabs, selected) = store.loadSession()
        XCTAssertEqual(tabs.map(\.id), [tabA.id])
        XCTAssertNil(selected)
    }

    func testPrivateTabIsDroppedAtSavePathDeterministically() throws {
        let database = try makeDatabase()
        let store = TabStore(database: database)
        let normal = tab("A")
        let privateTab = TabRecord(url: url("hidden"), title: "Hidden", isPrivate: true)

        try store.saveSession(tabs: [privateTab, normal, privateTab], selected: normal.id)
        try store.upsertTab(privateTab)

        let (tabs, selected) = store.loadSession()
        XCTAssertEqual(tabs.map(\.id), [normal.id])
        XCTAssertEqual(selected, normal.id)

        var descriptor = FetchDescriptor<TabRecord>()
        descriptor.fetchLimit = 100
        let records = try database.context.fetch(descriptor)
        XCTAssertEqual(records.count, 1)
        let firstRecord = try XCTUnwrap(records.first)
        XCTAssertFalse(firstRecord.isPrivate)
        XCTAssertNotEqual(firstRecord.id, privateTab.id)
    }

    func testSelectionOnPrivateTabResolvesToNil() throws {
        let database = try makeDatabase()
        let store = TabStore(database: database)
        let normal = tab("A")
        let privateTab = TabRecord(url: url("hidden"), title: "Hidden", isPrivate: true)

        try store.saveSession(tabs: [normal], selected: privateTab.id)

        XCTAssertEqual(store.loadSession().selected, nil)
    }

    // MARK: - Tab groups

    func testTabGroupCreateFetchUpdateDeleteAndNameClamp() throws {
        let database = try makeDatabase()
        let context = database.context
        let group = TabGroup(name: String(repeating: "x", count: 40))
        context.insert(group)
        try context.save()

        let groupID = group.id
        var descriptor = FetchDescriptor<TabGroup>(predicate: #Predicate { $0.id == groupID })
        descriptor.fetchLimit = 1
        var fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        let firstFetched = try XCTUnwrap(fetched.first)
        XCTAssertEqual(firstFetched.name.count, TabGroup.maxNameLength)

        firstFetched.name = "Renamed"
        try context.save()
        fetched = try context.fetch(descriptor)
        let renamedFetched = try XCTUnwrap(fetched.first)
        XCTAssertEqual(renamedFetched.name, "Renamed")

        context.delete(renamedFetched)
        try context.save()
        descriptor.fetchLimit = 1
        XCTAssertEqual(try context.fetch(descriptor).count, 0)
    }

    // MARK: - Bookmark Folders

    func testBookmarkFoldersAndHierarchy() throws {
        let database = try makeDatabase()
        let store = BookmarkStore(database: database)

        let rootFolder = try store.createFolder(title: "Development")
        let subFolder = try store.createFolder(title: "Swift", parentId: rootFolder.id)

        XCTAssertEqual(store.fetchFolders(parentId: nil).count, 1)
        XCTAssertEqual(store.fetchFolders(parentId: rootFolder.id).count, 1)

        try store.add(title: "Swift.org", url: url("swift"), folderId: subFolder.id)
        try store.add(title: "Apple Dev", url: url("developer"), folderId: rootFolder.id)
        try store.add(title: "Root Bookmark", url: url("root"), folderId: nil)

        XCTAssertEqual(store.fetchBookmarks(folderId: subFolder.id).count, 1)
        XCTAssertEqual(store.fetchBookmarks(folderId: rootFolder.id).count, 1)
        XCTAssertEqual(store.fetchBookmarks(folderId: nil).count, 1)

        try store.renameFolder(id: rootFolder.id, newTitle: "Coding")
        XCTAssertEqual(store.fetchFolder(id: rootFolder.id)?.title, "Coding")

        // Cascading deletion of rootFolder should delete subFolder and bookmarks
        try store.deleteFolder(id: rootFolder.id)
        XCTAssertEqual(store.fetchFolders(parentId: nil).count, 0)
        XCTAssertEqual(store.fetchFolders(parentId: rootFolder.id).count, 0)
        XCTAssertEqual(store.fetchBookmarks(folderId: subFolder.id).count, 0)
        XCTAssertEqual(store.fetchBookmarks(folderId: rootFolder.id).count, 0)
        // Root bookmark remains
        XCTAssertEqual(store.fetchBookmarks(folderId: nil).count, 1)
    }

    // MARK: - Recent Searches

    func testRecentSearchStoreRecordingAndPruning() throws {
        let database = try makeDatabase()
        let store = RecentSearchStore(database: database)

        // Empty string ignored
        try store.record(query: "   ")
        XCTAssertTrue(store.fetchRecents().isEmpty)

        // Record queries
        try store.record(query: "swiftui")
        try store.record(query: "apple")
        let recents = store.fetchRecents()
        XCTAssertEqual(recents.count, 2)
        XCTAssertEqual(recents[0].query, "apple")
        XCTAssertEqual(recents[1].query, "swiftui")

        // Re-recording "swiftui" moves it to front
        try store.record(query: "swiftui")
        let updated = store.fetchRecents()
        XCTAssertEqual(updated.count, 2)
        XCTAssertEqual(updated[0].query, "swiftui")
        XCTAssertEqual(updated[1].query, "apple")

        // Cap at 20 entries
        for queryIndex in 1 ... 25 {
            try store.record(query: "query \(queryIndex)")
        }
        let capped = store.fetchRecents()
        XCTAssertEqual(capped.count, RecentSearchStore.maxEntries)
        XCTAssertEqual(capped.first?.query, "query 25")

        // Single delete
        let firstID = capped[0].id
        try store.delete(id: firstID)
        XCTAssertEqual(store.fetchRecents().count, RecentSearchStore.maxEntries - 1)

        // Clear all
        try store.clear()
        XCTAssertTrue(store.fetchRecents().isEmpty)
    }

    func testHistoryStoreDeleteSingleEntry() throws {
        let database = try makeDatabase()
        let store = HistoryStore(database: database)

        let visit1 = PageVisit(url: url("page1"), title: "Page 1")
        let visit2 = PageVisit(url: url("page2"), title: "Page 2")
        try store.record(visit: visit1)
        try store.record(visit: visit2)

        let entries = store.fetchAll()
        XCTAssertEqual(entries.count, 2)

        let target = entries[0]
        try store.delete(id: target.id)

        let remaining = store.fetchAll()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertNotEqual(remaining[0].id, target.id)
    }

    // MARK: - Bookmark Store Advanced Features

    func testRootFetchExcludesFavorites() throws {
        let database = try makeDatabase()
        let store = BookmarkStore(database: database)

        try store.add(title: "Root Bookmark", url: url("root"), isFavorite: false)
        try store.upsertFavorite(url: url("favorite"), title: "Favorite Item")

        let rootBookmarks = store.fetchBookmarks(folderId: nil)
        XCTAssertEqual(rootBookmarks.count, 1)
        XCTAssertEqual(rootBookmarks.first?.title, "Root Bookmark")

        let favorites = store.fetchFavorites()
        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(favorites.first?.title, "Favorite Item")
    }

    func testUpdateBookmarkMovesBetweenFavoritesAndFolders() throws {
        let database = try makeDatabase()
        let store = BookmarkStore(database: database)
        let folder = try store.createFolder(title: "Dev")

        let bookmark = try XCTUnwrap(store.add(title: "Item", url: url("item"), isFavorite: false))

        // Move to Favorites
        try store.updateBookmark(id: bookmark.id, title: "Item in Favs", url: url("item"), location: .favorites)
        XCTAssertTrue(store.fetchBookmarks(folderId: nil).isEmpty)
        let favs = store.fetchFavorites()
        XCTAssertEqual(favs.count, 1)
        XCTAssertEqual(favs.first?.title, "Item in Favs")

        // Move to Folder
        try store.updateBookmark(id: bookmark.id, title: "Item in Dev", url: url("item"), location: .folder(folder.id))
        XCTAssertTrue(store.fetchFavorites().isEmpty)
        let folderBookmarks = store.fetchBookmarks(folderId: folder.id)
        XCTAssertEqual(folderBookmarks.count, 1)
        XCTAssertEqual(folderBookmarks.first?.title, "Item in Dev")

        // Move to Root
        try store.updateBookmark(id: bookmark.id, title: "Item at Root", url: url("item"), location: .root)
        XCTAssertTrue(store.fetchBookmarks(folderId: folder.id).isEmpty)
        let rootBookmarks = store.fetchBookmarks(folderId: nil)
        XCTAssertEqual(rootBookmarks.count, 1)
        XCTAssertEqual(rootBookmarks.first?.title, "Item at Root")
    }

    func testUpdateFolderCycleDetection() throws {
        let database = try makeDatabase()
        let store = BookmarkStore(database: database)

        let rootA = try store.createFolder(title: "Root A")
        let subA1 = try store.createFolder(title: "Sub A1", parentId: rootA.id)
        let subA2 = try store.createFolder(title: "Sub A2", parentId: subA1.id)

        // Cannot move folder inside itself
        XCTAssertThrowsError(try store.updateFolder(id: rootA.id, title: "Root A", parentId: rootA.id)) { error in
            XCTAssertEqual(error as? BookmarkStoreError, .cyclicFolderHierarchy)
        }

        // Cannot move folder inside its direct descendant
        XCTAssertThrowsError(try store.updateFolder(id: rootA.id, title: "Root A", parentId: subA1.id)) { error in
            XCTAssertEqual(error as? BookmarkStoreError, .cyclicFolderHierarchy)
        }

        // Cannot move folder inside its deeper descendant
        XCTAssertThrowsError(try store.updateFolder(id: rootA.id, title: "Root A", parentId: subA2.id)) { error in
            XCTAssertEqual(error as? BookmarkStoreError, .cyclicFolderHierarchy)
        }

        // Can rename without changing parent
        try store.updateFolder(id: rootA.id, title: "Root A Renamed", parentId: nil)
        XCTAssertEqual(store.fetchFolder(id: rootA.id)?.title, "Root A Renamed")

        // Can move subA2 up to root
        try store.updateFolder(id: subA2.id, title: "Sub A2 at Root", parentId: nil)
        XCTAssertNil(store.fetchFolder(id: subA2.id)?.parentId)
    }

    func testReorderFolders() throws {
        let database = try makeDatabase()
        let store = BookmarkStore(database: database)

        let f1 = try store.createFolder(title: "Folder 1")
        let f2 = try store.createFolder(title: "Folder 2")
        let f3 = try store.createFolder(title: "Folder 3")

        XCTAssertEqual(store.fetchFolders(parentId: nil).map(\.id), [f1.id, f2.id, f3.id])

        // Reverse order
        try store.reorderFolders([f3.id, f2.id, f1.id])
        XCTAssertEqual(store.fetchFolders(parentId: nil).map(\.id), [f3.id, f2.id, f1.id])
    }

    func testUpsertFavoritePromotesExistingBookmark() throws {
        let database = try makeDatabase()
        let store = BookmarkStore(database: database)
        let folder = try store.createFolder(title: "Folder")

        try store.add(title: "Existing", url: url("promo"), folderId: folder.id)
        XCTAssertEqual(store.fetchBookmarks(folderId: folder.id).count, 1)

        try store.upsertFavorite(url: url("promo"), title: "Promoted to Fav")
        XCTAssertEqual(store.fetchFavorites().count, 1)
        XCTAssertEqual(store.fetchFavorites().first?.title, "Promoted to Fav")
        // No longer in folder
        XCTAssertEqual(store.fetchBookmarks(folderId: folder.id).count, 0)
    }
}
