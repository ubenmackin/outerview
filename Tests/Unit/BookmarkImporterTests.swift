// Import — Importer routing plus dedupe tests.

@testable import OuterView
import XCTest

@MainActor
final class BookmarkImporterTests: XCTestCase {
    private func makeStore() throws -> BookmarkStore {
        let database = try OuterViewDatabase(inMemory: true)
        return BookmarkStore(database: database)
    }

    func testImportAgainstEmptyStoreMatchesFixtureCounts() async throws {
        let store = try makeStore()
        let summary = try await BookmarkImporter().importFromData(ImportFixtures.safariExport(), bookmarkStore: store)
        XCTAssertEqual(summary, ImportSummary(added: 5, skippedDuplicates: 1, skippedInvalid: 1, truncated: 0))
    }

    func testBarFolderEntriesBecomeFavorites() async throws {
        let store = try makeStore()
        _ = try await BookmarkImporter().importFromData(ImportFixtures.safariExport(), bookmarkStore: store)
        let stored = store.fetchAll()
        XCTAssertEqual(stored.count, 5)
        XCTAssertEqual(Set(stored.filter(\.isFavorite).map(\.title)), ["News & Notes"])
        let article = try XCTUnwrap(stored.first { $0.title == "Long Article" })
        XCTAssertFalse(article.isFavorite)
    }

    func testImportCreatesFoldersAndNestsBookmarks() async throws {
        let store = try makeStore()
        _ = try await BookmarkImporter().importFromData(ImportFixtures.safariExport(), bookmarkStore: store)

        let rootFolders = store.fetchFolders(parentId: nil, isFavorite: false)
        XCTAssertEqual(rootFolders.map(\.title), ["Reading"])
        let readingFolder = try XCTUnwrap(rootFolders.first)

        let readingBookmarks = store.fetchBookmarks(folderId: readingFolder.id)
        XCTAssertEqual(Set(readingBookmarks.map(\.title)), ["Long Article", "Nested Docs"])

        let subfolders = store.fetchFolders(parentId: readingFolder.id)
        XCTAssertEqual(subfolders.map(\.title), ["Inner"])
        let innerFolder = try XCTUnwrap(subfolders.first)

        let innerBookmarks = store.fetchBookmarks(folderId: innerFolder.id)
        XCTAssertEqual(innerBookmarks.map(\.title), ["Deep Page"])

        // Favorites Bar is recognized as Favorites container, so no regular folder is created
        let favFolders = store.fetchFolders(parentId: nil, isFavorite: true)
        XCTAssertTrue(favFolders.isEmpty)
        let favBookmarks = store.fetchFavorites()
        XCTAssertEqual(favBookmarks.map(\.title), ["News & Notes"])
    }

    func testRepeatedImportDeduplicatesAgainstStore() async throws {
        let store = try makeStore()
        let importer = BookmarkImporter()
        _ = try await importer.importFromData(ImportFixtures.safariExport(), bookmarkStore: store)
        let second = try await importer.importFromData(ImportFixtures.safariExport(), bookmarkStore: store)
        XCTAssertEqual(second.added, 0)
        XCTAssertEqual(second.skippedDuplicates, 6)
        XCTAssertEqual(second.skippedInvalid, 1)
        XCTAssertEqual(second.truncated, 0)
        XCTAssertEqual(store.fetchAll().count, 5)
    }

    func testEmptyDataYieldsZeroSummaryWithoutAdding() async throws {
        let store = try makeStore()
        let summary = await BookmarkImporter().importFromData(Data(), bookmarkStore: store)
        XCTAssertEqual(summary, ImportSummary(added: 0, skippedDuplicates: 0, skippedInvalid: 0, truncated: 0))
        XCTAssertTrue(store.fetchAll().isEmpty)
    }

    func testOversizeDataYieldsZeroSummaryWithoutAdding() async throws {
        let store = try makeStore()
        let payload = Data(repeating: 0x20, count: 10 * 1024 * 1024 + 1)
        let summary = await BookmarkImporter().importFromData(payload, bookmarkStore: store)
        XCTAssertEqual(summary.added, 0)
        XCTAssertEqual(summary.truncated, 0)
        XCTAssertTrue(store.fetchAll().isEmpty)
    }

    func testFavoriteFolderDetection() {
        XCTAssertTrue(BookmarkImporter.isFavorite(folderPath: ["Bookmarks Bar"]))
        XCTAssertTrue(BookmarkImporter.isFavorite(folderPath: ["BookmarksBar"]))
        XCTAssertTrue(BookmarkImporter.isFavorite(folderPath: ["Favorites"]))
        XCTAssertTrue(BookmarkImporter.isFavorite(folderPath: ["Bookmarks Menu", "Toolbar"]))
        XCTAssertFalse(BookmarkImporter.isFavorite(folderPath: []))
        XCTAssertFalse(BookmarkImporter.isFavorite(folderPath: ["Reading"]))
        XCTAssertFalse(BookmarkImporter.isFavorite(folderPath: ["Reading", "Inner"]))
    }

    func testSameURLInDifferentContainersImportsBoth() async throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <HTML><META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>Bookmarks</TITLE><H1>Bookmarks</H1>
        <DL><p>
            <DT><H3>FolderA</H3>
            <DL><p>
                <DT><A HREF="https://example.com/page">Page</A>
            </DL><p>
            <DT><A HREF="https://example.com/page">Page</A>
        </DL><p>
        </HTML>
        """
        let store = try makeStore()
        let summary = await BookmarkImporter().importFromData(Data(html.utf8), bookmarkStore: store)
        XCTAssertEqual(summary.added, 2)
        XCTAssertEqual(summary.skippedDuplicates, 0)
        let all = store.fetchAll()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.filter { $0.folderId != nil }.count, 1)
        XCTAssertEqual(all.filter { $0.folderId == nil }.count, 1)
    }

    func testUserSafariBookmarksImportsAllExpectedCountsAndOrder() async throws {
        let store = try makeStore()
        let data = try ImportFixtures.userSafariExport()
        let summary = await BookmarkImporter().importFromData(data, bookmarkStore: store)

        // All valid bookmarks from file are added
        XCTAssertGreaterThan(summary.added, 60)
        XCTAssertEqual(summary.skippedInvalid, 0)

        // Root favorite folders: "Open All" and "Pools"
        let favFolders = store.fetchFolders(parentId: nil, isFavorite: true)
        XCTAssertEqual(Set(favFolders.map(\.title)), ["Open All", "Pools"])

        let openAll = try XCTUnwrap(favFolders.first { $0.title == "Open All" })
        let openAllBookmarks = store.fetchBookmarks(folderId: openAll.id)
        XCTAssertEqual(openAllBookmarks.map(\.title), ["Google News", "AppleInsider", "Slashdot", "Ars Technica"])

        let pools = try XCTUnwrap(favFolders.first { $0.title == "Pools" })
        let poolsBookmarks = store.fetchBookmarks(folderId: pools.id)
        XCTAssertEqual(poolsBookmarks.count, 6)
        XCTAssertEqual(poolsBookmarks[0].title, "Ethereum Account")

        // Root favorite bookmarks
        let rootFavBookmarks = store.fetchFavorites(rootOnly: true)
        XCTAssertEqual(rootFavBookmarks.count, 13)
        XCTAssertEqual(rootFavBookmarks.first?.title, "Google News")
        XCTAssertEqual(rootFavBookmarks.last?.title, "Xbox")

        // StartPageViewModel combined favorites has 15 items in forward order
        let historyStore = HistoryStore(database: store.database)
        let vm = StartPageViewModel(bookmarkStore: store, historyStore: historyStore)
        XCTAssertEqual(vm.favoriteItems.count, 15)
        XCTAssertEqual(vm.favoriteItems.first?.title, "Open All")
        XCTAssertEqual(vm.favoriteItems.last?.title, "Xbox")

        // Root bookmarks outside folders (including Plex/Web, rTorrent, MDM)
        let rootBookmarks = store.fetchBookmarks(folderId: nil)
        XCTAssertTrue(rootBookmarks.contains { $0.title == "Plex/Web" })
        XCTAssertTrue(rootBookmarks.contains { $0.title == "rTorrent" })
        XCTAssertTrue(rootBookmarks.contains { $0.title == "MDM" })
        XCTAssertEqual(rootBookmarks.count, 17)
    }

    func testFolderDrillDownOnStartPageViewModel() async throws {
        let store = try makeStore()
        let data = try ImportFixtures.userSafariExport()
        _ = await BookmarkImporter().importFromData(data, bookmarkStore: store)

        let historyStore = HistoryStore(database: store.database)
        let vm = StartPageViewModel(bookmarkStore: store, historyStore: historyStore)
        XCTAssertTrue(vm.isAtRoot)
        XCTAssertEqual(vm.currentTitle, "Favorites")
        XCTAssertEqual(vm.favoriteItems.count, 15)

        // Find "Open All" folder
        guard case let .folder(openAllFolder)? = vm.favoriteItems.first(where: { $0.title == "Open All" }) else {
            XCTFail("Open All folder item not found")
            return
        }

        vm.openFolder(openAllFolder)
        XCTAssertFalse(vm.isAtRoot)
        XCTAssertEqual(vm.currentTitle, "Open All")
        XCTAssertEqual(vm.favoriteItems.count, 4)
        XCTAssertEqual(vm.favoriteItems.map(\.title), ["Google News", "AppleInsider", "Slashdot", "Ars Technica"])

        vm.popFolder()
        XCTAssertTrue(vm.isAtRoot)
        XCTAssertEqual(vm.currentTitle, "Favorites")
        XCTAssertEqual(vm.favoriteItems.count, 15)
    }
}
