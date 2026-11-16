// Persistence — StoreReconciler one-shot cross-store bootstrap copy tests.

@testable import OuterView
import SwiftData
import XCTest

@MainActor
final class StoreReconcilerTests: XCTestCase {
    // MARK: - Fixtures

    // Every store-touching phase runs inside StoreFixtures.quiesced so its
    // SQLite connection closes first: a live writer connection during
    // reconcile's container open logs disk-I/O errors even on success.

    /// Temp-file store isolated per test: no Application Support path is
    /// touched, and SQLite journal siblings are removed with the store.
    private func makeStoreURL() -> URL {
        let url = StoreFixtures.tempStoreURL()
        addTeardownBlock { [url] in
            StoreFixtures.removeStoreArtifacts(at: url)
        }
        return url
    }

    /// Isolated defaults suite so reconcile markers never land in .standard.
    private func makeDefaults() throws -> UserDefaults {
        let name = "StoreReconcilerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        addTeardownBlock {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
        }
        return defaults
    }

    private struct ReconcileFixture {
        let destination: ModelContainer
        let sourceConfiguration: ModelConfiguration
        let defaults: UserDefaults
    }

    private func makeFixture() throws -> ReconcileFixture {
        let destinationURL = makeStoreURL()
        let destination = try ModelContainer(
            for: Schema(OuterViewDatabase.syncedModelTypes),
            configurations: [ModelConfiguration(url: destinationURL)]
        )
        let sourceConfiguration = ModelConfiguration(url: makeStoreURL())
        return try ReconcileFixture(
            destination: destination,
            sourceConfiguration: sourceConfiguration,
            defaults: makeDefaults()
        )
    }

    private func makeSourceContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(OuterViewDatabase.syncedModelTypes),
            configurations: [configuration]
        )
    }

    private func makeContext(for container: ModelContainer) -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    // MARK: - Seeding

    private struct SeededRoster {
        let bookmark: Bookmark
        let folder: BookmarkFolder
        let history: HistoryEntry
        let recentSearch: RecentSearch
        let readingListItem: ReadingListItem
        let tabRecord: TabRecord
        let tabGroup: TabGroup
        let tabSession: TabSession
    }

    /// Ids shared across roster builds so an expectation roster survives
    /// quiesced seeding whose models must not outlive their store connection.
    private struct RosterIDs {
        let bookmark = UUID()
        let folder = UUID()
        let folderParent = UUID()
        let history = UUID()
        let recentSearch = UUID()
        let readingListItem = UUID()
        let tabRecord = UUID()
        let tabGroup = UUID()
        let tabSession = UUID()
        let tabA = UUID()
        let tabB = UUID()
    }

    /// Builds the full roster detached from any context; folder and group ids
    /// cross-reference the rows so the optional UUID fields carry distinct
    /// non-nil values.
    private func makeRoster(ids: RosterIDs = RosterIDs()) -> SeededRoster {
        let bookmark = Bookmark(
            id: ids.bookmark,
            title: "Roster Bookmark",
            url: URL(string: "https://example.com/roster-bookmark")!,
            addedAt: Date(timeIntervalSince1970: 1_000_000),
            isFavorite: true,
            folderId: ids.folder,
            sortOrder: 3
        )
        let folder = BookmarkFolder(
            id: ids.folder,
            title: "Roster Folder",
            parentId: ids.folderParent,
            createdAt: Date(timeIntervalSince1970: 2_000_000),
            sortOrder: 2,
            isFavorite: true
        )
        let history = HistoryEntry(
            id: ids.history,
            title: "Roster History",
            url: URL(string: "https://example.com/roster-history")!,
            visitedAt: Date(timeIntervalSince1970: 3_000_000)
        )
        let recentSearch = RecentSearch(
            id: ids.recentSearch,
            query: "roster query",
            searchedAt: Date(timeIntervalSince1970: 4_000_000)
        )
        let readingListItem = ReadingListItem(
            id: ids.readingListItem,
            title: "Roster Article",
            url: URL(string: "https://example.com/roster-article")!,
            addedAt: Date(timeIntervalSince1970: 5_000_000),
            isRead: true,
            sortIndex: 7,
            previewText: "Roster preview"
        )
        let tabRecord = TabRecord(
            id: ids.tabRecord,
            url: URL(string: "https://example.com/roster-tab")!,
            title: "Roster Tab",
            isPrivate: false,
            createdAt: Date(timeIntervalSince1970: 6_000_000),
            lastActiveAt: Date(timeIntervalSince1970: 6_500_000),
            groupId: ids.tabGroup,
            parentTabID: ids.tabA
        )
        let tabGroup = TabGroup(id: ids.tabGroup, name: "Roster Group", createdAt: Date(timeIntervalSince1970: 7_000_000))
        let tabSession = TabSession(
            id: ids.tabSession,
            tabIds: [ids.tabA, ids.tabB],
            selectedTabId: ids.tabB,
            tabIdsEncoded: "\(ids.tabA.uuidString),\(ids.tabB.uuidString)"
        )

        return SeededRoster(
            bookmark: bookmark,
            folder: folder,
            history: history,
            recentSearch: recentSearch,
            readingListItem: readingListItem,
            tabRecord: tabRecord,
            tabGroup: tabGroup,
            tabSession: tabSession
        )
    }

    /// Inserts the whole roster and saves once.
    private func insert(_ roster: SeededRoster, in context: ModelContext) throws {
        context.insert(roster.bookmark)
        context.insert(roster.folder)
        context.insert(roster.history)
        context.insert(roster.recentSearch)
        context.insert(roster.readingListItem)
        context.insert(roster.tabRecord)
        context.insert(roster.tabGroup)
        context.insert(roster.tabSession)
        try context.save()
    }

    // MARK: - Field comparators

    private func assertBookmark(_ expected: Bookmark, equals actual: Bookmark, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.id, expected.id, "Bookmark.id", file: file, line: line)
        XCTAssertEqual(actual.title, expected.title, "Bookmark.title", file: file, line: line)
        XCTAssertEqual(actual.url, expected.url, "Bookmark.url", file: file, line: line)
        XCTAssertEqual(actual.addedAt, expected.addedAt, "Bookmark.addedAt", file: file, line: line)
        XCTAssertEqual(actual.isFavorite, expected.isFavorite, "Bookmark.isFavorite", file: file, line: line)
        XCTAssertEqual(actual.folderId, expected.folderId, "Bookmark.folderId", file: file, line: line)
        XCTAssertEqual(actual.sortOrder, expected.sortOrder, "Bookmark.sortOrder", file: file, line: line)
    }

    private func assertBookmarkFolder(_ expected: BookmarkFolder, equals actual: BookmarkFolder, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.id, expected.id, "BookmarkFolder.id", file: file, line: line)
        XCTAssertEqual(actual.title, expected.title, "BookmarkFolder.title", file: file, line: line)
        XCTAssertEqual(actual.parentId, expected.parentId, "BookmarkFolder.parentId", file: file, line: line)
        XCTAssertEqual(actual.createdAt, expected.createdAt, "BookmarkFolder.createdAt", file: file, line: line)
        XCTAssertEqual(actual.sortOrder, expected.sortOrder, "BookmarkFolder.sortOrder", file: file, line: line)
        XCTAssertEqual(actual.isFavorite, expected.isFavorite, "BookmarkFolder.isFavorite", file: file, line: line)
    }

    private func assertHistoryEntry(_ expected: HistoryEntry, equals actual: HistoryEntry, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.id, expected.id, "HistoryEntry.id", file: file, line: line)
        XCTAssertEqual(actual.title, expected.title, "HistoryEntry.title", file: file, line: line)
        XCTAssertEqual(actual.url, expected.url, "HistoryEntry.url", file: file, line: line)
        XCTAssertEqual(actual.visitedAt, expected.visitedAt, "HistoryEntry.visitedAt", file: file, line: line)
    }

    private func assertRecentSearch(_ expected: RecentSearch, equals actual: RecentSearch, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.id, expected.id, "RecentSearch.id", file: file, line: line)
        XCTAssertEqual(actual.query, expected.query, "RecentSearch.query", file: file, line: line)
        XCTAssertEqual(actual.searchedAt, expected.searchedAt, "RecentSearch.searchedAt", file: file, line: line)
    }

    private func assertReadingListItem(_ expected: ReadingListItem, equals actual: ReadingListItem, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.id, expected.id, "ReadingListItem.id", file: file, line: line)
        XCTAssertEqual(actual.title, expected.title, "ReadingListItem.title", file: file, line: line)
        XCTAssertEqual(actual.url, expected.url, "ReadingListItem.url", file: file, line: line)
        XCTAssertEqual(actual.addedAt, expected.addedAt, "ReadingListItem.addedAt", file: file, line: line)
        XCTAssertEqual(actual.isRead, expected.isRead, "ReadingListItem.isRead", file: file, line: line)
        XCTAssertEqual(actual.sortIndex, expected.sortIndex, "ReadingListItem.sortIndex", file: file, line: line)
        XCTAssertEqual(actual.previewText, expected.previewText, "ReadingListItem.previewText", file: file, line: line)
    }

    private func assertTabRecord(_ expected: TabRecord, equals actual: TabRecord, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.id, expected.id, "TabRecord.id", file: file, line: line)
        XCTAssertEqual(actual.url, expected.url, "TabRecord.url", file: file, line: line)
        XCTAssertEqual(actual.title, expected.title, "TabRecord.title", file: file, line: line)
        XCTAssertEqual(actual.isPrivate, expected.isPrivate, "TabRecord.isPrivate", file: file, line: line)
        XCTAssertEqual(actual.createdAt, expected.createdAt, "TabRecord.createdAt", file: file, line: line)
        XCTAssertEqual(actual.lastActiveAt, expected.lastActiveAt, "TabRecord.lastActiveAt", file: file, line: line)
        XCTAssertEqual(actual.groupId, expected.groupId, "TabRecord.groupId", file: file, line: line)
        XCTAssertEqual(actual.parentTabID, expected.parentTabID, "TabRecord.parentTabID", file: file, line: line)
    }

    private func assertTabGroup(_ expected: TabGroup, equals actual: TabGroup, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.id, expected.id, "TabGroup.id", file: file, line: line)
        XCTAssertEqual(actual.name, expected.name, "TabGroup.name", file: file, line: line)
        XCTAssertEqual(actual.createdAt, expected.createdAt, "TabGroup.createdAt", file: file, line: line)
    }

    private func assertTabSession(_ expected: TabSession, equals actual: TabSession, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.id, expected.id, "TabSession.id", file: file, line: line)
        XCTAssertEqual(actual.tabIds, expected.tabIds, "TabSession.tabIds", file: file, line: line)
        XCTAssertEqual(actual.selectedTabId, expected.selectedTabId, "TabSession.selectedTabId", file: file, line: line)
        XCTAssertEqual(actual.tabIdsEncoded, expected.tabIdsEncoded, "TabSession.tabIdsEncoded", file: file, line: line)
    }

    // MARK: - Roster comparators

    /// Asserts the destination holds exactly the source's rows, field-for-field,
    /// one row per roster type.
    private func assertRosterCopied(source: ModelContext, destination: ModelContext, file: StaticString = #filePath, line: UInt = #line) throws {
        let sourceBookmarks = try source.fetch(FetchDescriptor<Bookmark>())
        let destinationBookmarks = try destination.fetch(FetchDescriptor<Bookmark>())
        XCTAssertEqual(sourceBookmarks.count, 1, "Bookmark source rows", file: file, line: line)
        XCTAssertEqual(destinationBookmarks.count, 1, "Bookmark destination rows", file: file, line: line)
        if let expected = sourceBookmarks.first, let actual = destinationBookmarks.first {
            assertBookmark(expected, equals: actual, file: file, line: line)
        }

        let sourceFolders = try source.fetch(FetchDescriptor<BookmarkFolder>())
        let destinationFolders = try destination.fetch(FetchDescriptor<BookmarkFolder>())
        XCTAssertEqual(sourceFolders.count, 1, "BookmarkFolder source rows", file: file, line: line)
        XCTAssertEqual(destinationFolders.count, 1, "BookmarkFolder destination rows", file: file, line: line)
        if let expected = sourceFolders.first, let actual = destinationFolders.first {
            assertBookmarkFolder(expected, equals: actual, file: file, line: line)
        }

        let sourceHistory = try source.fetch(FetchDescriptor<HistoryEntry>())
        let destinationHistory = try destination.fetch(FetchDescriptor<HistoryEntry>())
        XCTAssertEqual(sourceHistory.count, 1, "HistoryEntry source rows", file: file, line: line)
        XCTAssertEqual(destinationHistory.count, 1, "HistoryEntry destination rows", file: file, line: line)
        if let expected = sourceHistory.first, let actual = destinationHistory.first {
            assertHistoryEntry(expected, equals: actual, file: file, line: line)
        }

        let sourceSearches = try source.fetch(FetchDescriptor<RecentSearch>())
        let destinationSearches = try destination.fetch(FetchDescriptor<RecentSearch>())
        XCTAssertEqual(sourceSearches.count, 1, "RecentSearch source rows", file: file, line: line)
        XCTAssertEqual(destinationSearches.count, 1, "RecentSearch destination rows", file: file, line: line)
        if let expected = sourceSearches.first, let actual = destinationSearches.first {
            assertRecentSearch(expected, equals: actual, file: file, line: line)
        }

        let sourceReadingList = try source.fetch(FetchDescriptor<ReadingListItem>())
        let destinationReadingList = try destination.fetch(FetchDescriptor<ReadingListItem>())
        XCTAssertEqual(sourceReadingList.count, 1, "ReadingListItem source rows", file: file, line: line)
        XCTAssertEqual(destinationReadingList.count, 1, "ReadingListItem destination rows", file: file, line: line)
        if let expected = sourceReadingList.first, let actual = destinationReadingList.first {
            assertReadingListItem(expected, equals: actual, file: file, line: line)
        }

        let sourceTabs = try source.fetch(FetchDescriptor<TabRecord>())
        let destinationTabs = try destination.fetch(FetchDescriptor<TabRecord>())
        XCTAssertEqual(sourceTabs.count, 1, "TabRecord source rows", file: file, line: line)
        XCTAssertEqual(destinationTabs.count, 1, "TabRecord destination rows", file: file, line: line)
        if let expected = sourceTabs.first, let actual = destinationTabs.first {
            assertTabRecord(expected, equals: actual, file: file, line: line)
        }

        let sourceGroups = try source.fetch(FetchDescriptor<TabGroup>())
        let destinationGroups = try destination.fetch(FetchDescriptor<TabGroup>())
        XCTAssertEqual(sourceGroups.count, 1, "TabGroup source rows", file: file, line: line)
        XCTAssertEqual(destinationGroups.count, 1, "TabGroup destination rows", file: file, line: line)
        if let expected = sourceGroups.first, let actual = destinationGroups.first {
            assertTabGroup(expected, equals: actual, file: file, line: line)
        }

        let sourceSessions = try source.fetch(FetchDescriptor<TabSession>())
        let destinationSessions = try destination.fetch(FetchDescriptor<TabSession>())
        XCTAssertEqual(sourceSessions.count, 1, "TabSession source rows", file: file, line: line)
        XCTAssertEqual(destinationSessions.count, 1, "TabSession destination rows", file: file, line: line)
        if let expected = sourceSessions.first, let actual = destinationSessions.first {
            assertTabSession(expected, equals: actual, file: file, line: line)
        }
    }

    /// Asserts a context still holds exactly the seeded rows, field-for-field.
    private func assertRosterUntouched(_ seeded: SeededRoster, in context: ModelContext, file: StaticString = #filePath, line: UInt = #line) throws {
        let bookmarks = try context.fetch(FetchDescriptor<Bookmark>())
        XCTAssertEqual(bookmarks.count, 1, "Bookmark rows", file: file, line: line)
        if let actual = bookmarks.first {
            assertBookmark(seeded.bookmark, equals: actual, file: file, line: line)
        }

        let folders = try context.fetch(FetchDescriptor<BookmarkFolder>())
        XCTAssertEqual(folders.count, 1, "BookmarkFolder rows", file: file, line: line)
        if let actual = folders.first {
            assertBookmarkFolder(seeded.folder, equals: actual, file: file, line: line)
        }

        let history = try context.fetch(FetchDescriptor<HistoryEntry>())
        XCTAssertEqual(history.count, 1, "HistoryEntry rows", file: file, line: line)
        if let actual = history.first {
            assertHistoryEntry(seeded.history, equals: actual, file: file, line: line)
        }

        let searches = try context.fetch(FetchDescriptor<RecentSearch>())
        XCTAssertEqual(searches.count, 1, "RecentSearch rows", file: file, line: line)
        if let actual = searches.first {
            assertRecentSearch(seeded.recentSearch, equals: actual, file: file, line: line)
        }

        let readingList = try context.fetch(FetchDescriptor<ReadingListItem>())
        XCTAssertEqual(readingList.count, 1, "ReadingListItem rows", file: file, line: line)
        if let actual = readingList.first {
            assertReadingListItem(seeded.readingListItem, equals: actual, file: file, line: line)
        }

        let tabs = try context.fetch(FetchDescriptor<TabRecord>())
        XCTAssertEqual(tabs.count, 1, "TabRecord rows", file: file, line: line)
        if let actual = tabs.first {
            assertTabRecord(seeded.tabRecord, equals: actual, file: file, line: line)
        }

        let groups = try context.fetch(FetchDescriptor<TabGroup>())
        XCTAssertEqual(groups.count, 1, "TabGroup rows", file: file, line: line)
        if let actual = groups.first {
            assertTabGroup(seeded.tabGroup, equals: actual, file: file, line: line)
        }

        let sessions = try context.fetch(FetchDescriptor<TabSession>())
        XCTAssertEqual(sessions.count, 1, "TabSession rows", file: file, line: line)
        if let actual = sessions.first {
            assertTabSession(seeded.tabSession, equals: actual, file: file, line: line)
        }
    }

    // MARK: - Copy direction

    func testCloudToLocalCopiesAllRosterTypesFieldForField() throws {
        let fixture = try makeFixture()
        try StoreFixtures.quiesced {
            let source = try makeSourceContainer(configuration: fixture.sourceConfiguration)
            try insert(makeRoster(), in: makeContext(for: source))
        }

        try StoreFixtures.quiesced {
            try StoreReconciler.reconcile(
                direction: .cloudToLocal,
                models: OuterViewDatabase.syncedModelTypes,
                destination: fixture.destination,
                sourceConfiguration: fixture.sourceConfiguration,
                defaults: fixture.defaults
            )
        }

        try StoreFixtures.quiesced {
            let reopened = try makeSourceContainer(configuration: fixture.sourceConfiguration)
            try assertRosterCopied(source: makeContext(for: reopened), destination: makeContext(for: fixture.destination))
        }
        XCTAssertTrue(fixture.defaults.bool(forKey: StoreReconciler.cloudToLocalMarkerKey))
        XCTAssertFalse(fixture.defaults.bool(forKey: StoreReconciler.localToCloudMarkerKey))
    }

    func testLocalToCloudCopiesAllRosterTypesFieldForField() throws {
        let fixture = try makeFixture()
        try StoreFixtures.quiesced {
            let source = try makeSourceContainer(configuration: fixture.sourceConfiguration)
            try insert(makeRoster(), in: makeContext(for: source))
        }

        try StoreFixtures.quiesced {
            try StoreReconciler.reconcile(
                direction: .localToCloud,
                models: OuterViewDatabase.syncedModelTypes,
                destination: fixture.destination,
                sourceConfiguration: fixture.sourceConfiguration,
                defaults: fixture.defaults
            )
        }

        try StoreFixtures.quiesced {
            let reopened = try makeSourceContainer(configuration: fixture.sourceConfiguration)
            try assertRosterCopied(source: makeContext(for: reopened), destination: makeContext(for: fixture.destination))
        }
        XCTAssertTrue(fixture.defaults.bool(forKey: StoreReconciler.localToCloudMarkerKey))
        XCTAssertFalse(fixture.defaults.bool(forKey: StoreReconciler.cloudToLocalMarkerKey))
    }

    // MARK: - Dedup, marker, plus recovery semantics

    func testInsertMissingDedupSkipsExistingIDAndCopiesRemainingRows() throws {
        let fixture = try makeFixture()
        let destinationContext = makeContext(for: fixture.destination)
        let keptID = UUID()
        let kept = try Bookmark(
            id: keptID,
            title: "Destination Title",
            url: XCTUnwrap(URL(string: "https://example.com/destination-kept")),
            addedAt: Date(timeIntervalSince1970: 111),
            isFavorite: true,
            folderId: UUID(),
            sortOrder: 9
        )
        destinationContext.insert(kept)
        try destinationContext.save()

        try StoreFixtures.quiesced {
            let source = try makeSourceContainer(configuration: fixture.sourceConfiguration)
            let sourceContext = makeContext(for: source)
            try sourceContext.insert(Bookmark(
                id: keptID,
                title: "Source Title",
                url: XCTUnwrap(URL(string: "https://example.com/source-collide")),
                addedAt: Date(timeIntervalSince1970: 222),
                isFavorite: false,
                folderId: UUID(),
                sortOrder: 4
            ))
            try sourceContext.insert(Bookmark(
                id: UUID(),
                title: "Fresh One",
                url: XCTUnwrap(URL(string: "https://example.com/fresh-one")),
                addedAt: Date(timeIntervalSince1970: 333)
            ))
            try sourceContext.insert(Bookmark(
                id: UUID(),
                title: "Fresh Two",
                url: XCTUnwrap(URL(string: "https://example.com/fresh-two")),
                addedAt: Date(timeIntervalSince1970: 444)
            ))
            try sourceContext.save()
        }

        try StoreFixtures.quiesced {
            try StoreReconciler.reconcile(
                direction: .cloudToLocal,
                models: OuterViewDatabase.syncedModelTypes,
                destination: fixture.destination,
                sourceConfiguration: fixture.sourceConfiguration,
                defaults: fixture.defaults
            )
        }

        let rows = try makeContext(for: fixture.destination).fetch(FetchDescriptor<Bookmark>())
        XCTAssertEqual(rows.count, 3)
        let unchanged = try XCTUnwrap(rows.first { $0.id == keptID })
        assertBookmark(kept, equals: unchanged)
        XCTAssertEqual(rows.filter { $0.id != keptID }.map(\.title).sorted(), ["Fresh One", "Fresh Two"])
        XCTAssertTrue(fixture.defaults.bool(forKey: StoreReconciler.cloudToLocalMarkerKey))
    }

    func testCompletedMarkerShortCircuitsSecondPass() throws {
        let fixture = try makeFixture()
        try StoreFixtures.quiesced {
            let source = try makeSourceContainer(configuration: fixture.sourceConfiguration)
            let sourceContext = makeContext(for: source)
            try sourceContext.insert(Bookmark(
                id: UUID(),
                title: "First Pass",
                url: XCTUnwrap(URL(string: "https://example.com/first-pass")),
                addedAt: Date(timeIntervalSince1970: 100)
            ))
            try sourceContext.save()
        }

        try StoreFixtures.quiesced {
            try StoreReconciler.reconcile(
                direction: .cloudToLocal,
                models: OuterViewDatabase.syncedModelTypes,
                destination: fixture.destination,
                sourceConfiguration: fixture.sourceConfiguration,
                defaults: fixture.defaults
            )
        }

        try StoreFixtures.quiesced {
            let source = try makeSourceContainer(configuration: fixture.sourceConfiguration)
            let sourceContext = makeContext(for: source)
            try sourceContext.insert(Bookmark(
                id: UUID(),
                title: "Second Pass",
                url: XCTUnwrap(URL(string: "https://example.com/second-pass")),
                addedAt: Date(timeIntervalSince1970: 200)
            ))
            try sourceContext.save()
        }

        try StoreFixtures.quiesced {
            try StoreReconciler.reconcile(
                direction: .cloudToLocal,
                models: OuterViewDatabase.syncedModelTypes,
                destination: fixture.destination,
                sourceConfiguration: fixture.sourceConfiguration,
                defaults: fixture.defaults
            )
        }

        let titles = try makeContext(for: fixture.destination).fetch(FetchDescriptor<Bookmark>()).map(\.title)
        XCTAssertEqual(titles, ["First Pass"])
        XCTAssertTrue(fixture.defaults.bool(forKey: StoreReconciler.cloudToLocalMarkerKey))
    }

    func testBothStoresEmptyLeavesMarkerUnsetAndRetriesLater() throws {
        let fixture = try makeFixture()

        try StoreFixtures.quiesced {
            try StoreReconciler.reconcile(
                direction: .cloudToLocal,
                models: OuterViewDatabase.syncedModelTypes,
                destination: fixture.destination,
                sourceConfiguration: fixture.sourceConfiguration,
                defaults: fixture.defaults
            )
        }
        XCTAssertFalse(fixture.defaults.bool(forKey: StoreReconciler.cloudToLocalMarkerKey))

        try StoreFixtures.quiesced {
            let source = try makeSourceContainer(configuration: fixture.sourceConfiguration)
            let sourceContext = makeContext(for: source)
            try sourceContext.insert(Bookmark(
                id: UUID(),
                title: "Retry Row",
                url: XCTUnwrap(URL(string: "https://example.com/retry")),
                addedAt: Date(timeIntervalSince1970: 500)
            ))
            try sourceContext.save()
        }

        try StoreFixtures.quiesced {
            try StoreReconciler.reconcile(
                direction: .cloudToLocal,
                models: OuterViewDatabase.syncedModelTypes,
                destination: fixture.destination,
                sourceConfiguration: fixture.sourceConfiguration,
                defaults: fixture.defaults
            )
        }

        let titles = try makeContext(for: fixture.destination).fetch(FetchDescriptor<Bookmark>()).map(\.title)
        XCTAssertEqual(titles, ["Retry Row"])
        XCTAssertTrue(fixture.defaults.bool(forKey: StoreReconciler.cloudToLocalMarkerKey))
    }

    func testPassLeavesSourceStoreUntouched() throws {
        let fixture = try makeFixture()
        let ids = RosterIDs()
        let seeded = makeRoster(ids: ids)

        try StoreFixtures.quiesced {
            let source = try makeSourceContainer(configuration: fixture.sourceConfiguration)
            try insert(makeRoster(ids: ids), in: makeContext(for: source))
        }

        try StoreFixtures.quiesced {
            try StoreReconciler.reconcile(
                direction: .cloudToLocal,
                models: OuterViewDatabase.syncedModelTypes,
                destination: fixture.destination,
                sourceConfiguration: fixture.sourceConfiguration,
                defaults: fixture.defaults
            )
        }

        try StoreFixtures.quiesced {
            let reopened = try makeSourceContainer(configuration: fixture.sourceConfiguration)
            try assertRosterUntouched(seeded, in: makeContext(for: reopened))
        }
        XCTAssertTrue(fixture.defaults.bool(forKey: StoreReconciler.cloudToLocalMarkerKey))
    }

    func testUnmarkedPassAfterPartialCopyCompletesWithoutDuplicates() throws {
        let fixture = try makeFixture()
        // Simulated crashed partial pass: A and B already landed in the
        // destination, C arrived after the crash, and no marker was ever set.
        let destinationContext = makeContext(for: fixture.destination)
        let survivorA = try Bookmark(
            id: UUID(),
            title: "Survivor A",
            url: XCTUnwrap(URL(string: "https://example.com/survivor-a")),
            addedAt: Date(timeIntervalSince1970: 100),
            isFavorite: true,
            folderId: UUID(),
            sortOrder: 1
        )
        let survivorB = try Bookmark(
            id: UUID(),
            title: "Survivor B",
            url: XCTUnwrap(URL(string: "https://example.com/survivor-b")),
            addedAt: Date(timeIntervalSince1970: 200),
            isFavorite: false,
            folderId: nil,
            sortOrder: 2
        )
        destinationContext.insert(survivorA)
        destinationContext.insert(survivorB)
        try destinationContext.save()

        try StoreFixtures.quiesced {
            let source = try makeSourceContainer(configuration: fixture.sourceConfiguration)
            let sourceContext = makeContext(for: source)
            sourceContext.insert(Bookmark(
                id: survivorA.id,
                title: survivorA.title,
                url: survivorA.url,
                addedAt: survivorA.addedAt,
                isFavorite: survivorA.isFavorite,
                folderId: survivorA.folderId,
                sortOrder: survivorA.sortOrder
            ))
            sourceContext.insert(Bookmark(
                id: survivorB.id,
                title: survivorB.title,
                url: survivorB.url,
                addedAt: survivorB.addedAt,
                isFavorite: survivorB.isFavorite,
                folderId: survivorB.folderId,
                sortOrder: survivorB.sortOrder
            ))
            try sourceContext.insert(Bookmark(
                id: UUID(),
                title: "Arrived After Crash",
                url: XCTUnwrap(URL(string: "https://example.com/after-crash")),
                addedAt: Date(timeIntervalSince1970: 300)
            ))
            try sourceContext.save()
        }

        try StoreFixtures.quiesced {
            try StoreReconciler.reconcile(
                direction: .cloudToLocal,
                models: OuterViewDatabase.syncedModelTypes,
                destination: fixture.destination,
                sourceConfiguration: fixture.sourceConfiguration,
                defaults: fixture.defaults
            )
        }

        let rows = try makeContext(for: fixture.destination).fetch(FetchDescriptor<Bookmark>())
        XCTAssertEqual(rows.count, 3)
        let copiedA = try XCTUnwrap(rows.first { $0.id == survivorA.id })
        assertBookmark(survivorA, equals: copiedA)
        let copiedB = try XCTUnwrap(rows.first { $0.id == survivorB.id })
        assertBookmark(survivorB, equals: copiedB)
        XCTAssertEqual(rows.filter { $0.title == "Arrived After Crash" }.count, 1)
        XCTAssertTrue(fixture.defaults.bool(forKey: StoreReconciler.cloudToLocalMarkerKey))
    }

    func testPopulatedDestinationWithEmptySourceSetsMarkerWithoutChanges() throws {
        let fixture = try makeFixture()
        let destinationContext = makeContext(for: fixture.destination)
        let preexisting = try Bookmark(
            id: UUID(),
            title: "Preexisting",
            url: XCTUnwrap(URL(string: "https://example.com/preexisting")),
            addedAt: Date(timeIntervalSince1970: 900)
        )
        destinationContext.insert(preexisting)
        try destinationContext.save()

        try StoreFixtures.quiesced {
            try StoreReconciler.reconcile(
                direction: .cloudToLocal,
                models: OuterViewDatabase.syncedModelTypes,
                destination: fixture.destination,
                sourceConfiguration: fixture.sourceConfiguration,
                defaults: fixture.defaults
            )
        }

        let rows = try makeContext(for: fixture.destination).fetch(FetchDescriptor<Bookmark>())
        XCTAssertEqual(rows.count, 1)
        try assertBookmark(preexisting, equals: XCTUnwrap(rows.first))
        XCTAssertTrue(fixture.defaults.bool(forKey: StoreReconciler.cloudToLocalMarkerKey))
    }
}
