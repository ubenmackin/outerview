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
}
