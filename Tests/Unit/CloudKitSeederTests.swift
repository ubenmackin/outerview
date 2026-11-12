// Tests — Simulator-only CloudKit schema seeder contracts.
#if targetEnvironment(simulator)
    @testable import OuterView
    import SwiftData
    import XCTest

    private final class SeederMockKeyValueStore: NSUbiquitousKeyValueStore {
        var storage: [String: Any] = [:]

        override func object(forKey key: String) -> Any? {
            storage[key]
        }

        override func set(_ value: Any?, forKey key: String) {
            if let value {
                storage[key] = value
            } else {
                storage.removeValue(forKey: key)
            }
        }

        override func removeObject(forKey key: String) {
            storage.removeValue(forKey: key)
        }

        override func synchronize() -> Bool {
            true
        }
    }

    @MainActor
    final class CloudKitSeederTests: XCTestCase {
        private func makeDatabase() throws -> OuterViewDatabase {
            try OuterViewDatabase(inMemory: true)
        }

        private func makeDefaults() throws -> UserDefaults {
            let name = "CloudKitSeederTests.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
            defaults.removePersistentDomain(forName: name)
            addTeardownBlock {
                defaults.removePersistentDomain(forName: name)
            }
            return defaults
        }

        private func makeStore(defaults: UserDefaults, kvs: NSUbiquitousKeyValueStore) -> SyncedSettingsStore {
            SyncedSettingsStore(defaults: defaults, keyValueStore: kvs, notificationCenter: NotificationCenter())
        }

        private func snapshotRow(in database: OuterViewDatabase) throws -> TabSession? {
            try database.context.fetch(FetchDescriptor<TabSession>()).first
        }

        private func transientKeys() -> [String] {
            [
                LibraryTabBar.libraryTabDefaultsKey,
                TabOverviewViewController.overviewModeDefaultsKey,
                TabOverviewViewController.overviewGroupDefaultsKey,
                BookmarksBrowserView.displayModeDefaultsKey,
                BookmarksBrowserView.sortModeDefaultsKey,
                BookmarksBrowserView.showsFoldersOnTopDefaultsKey,
                ReadingListView.displayModeDefaultsKey,
                ReadingListView.filterModeDefaultsKey
            ]
        }

        private func seedProductionRows(database: OuterViewDatabase) throws {
            let bookmarks = BookmarkStore(database: database)
            let history = HistoryStore(database: database)
            let tabs = TabStore(database: database)
            let recents = RecentSearchStore(database: database)
            let reading = ReadingListStore(database: database)
            let folder = try bookmarks.createFolder(title: "Production Folder")
            try bookmarks.add(
                title: "Production Bookmark",
                url: URL(string: "https://example.com/production-bookmark")!,
                folderId: folder.id
            )
            try history.record(visit: PageVisit(
                url: URL(string: "https://example.com/production-history")!,
                title: "Production History",
                visitedAt: Date(timeIntervalSince1970: 100)
            ))
            try recents.record(query: "production query")
            _ = try reading.add(
                title: "Production Reading",
                url: URL(string: "https://example.com/production-reading")!,
                previewText: "Production preview"
            )
            let group = try tabs.createGroup(name: "Production Group")
            let tab = TabRecord(
                url: URL(string: "https://example.com/production-tab")!,
                title: "Production Tab",
                isPrivate: false,
                groupId: group.id
            )
            try tabs.saveSession(tabs: [tab], selected: tab.id)
        }

        func testSeedReportsExactPerTypeCounts() throws {
            let database = try makeDatabase()
            let defaults = try makeDefaults()
            let report = try CloudKitSchemaSeeder.seed(
                database: database,
                defaults: defaults,
                keyValueStore: .default
            )
            XCTAssertEqual(report.bookmarkFolders, 2)
            XCTAssertEqual(report.bookmarks, 3)
            XCTAssertEqual(report.historyEntries, 2)
            XCTAssertEqual(report.recentSearches, 2)
            XCTAssertEqual(report.readingListItems, 2)
            XCTAssertEqual(report.tabGroups, 1)
            XCTAssertEqual(report.tabs, 2)

            XCTAssertEqual(BookmarkStore(database: database).fetchAllFolders().count, 2)
            XCTAssertEqual(BookmarkStore(database: database).fetchAll().count, 3)
            XCTAssertEqual(HistoryStore(database: database).fetchAll(limit: HistoryStore.maxEntries).count, 2)
            XCTAssertEqual(RecentSearchStore(database: database).fetchRecents().count, 2)
            XCTAssertEqual(ReadingListStore(database: database).fetchAll().count, 2)
            XCTAssertEqual(TabStore(database: database).fetchGroups().count, 1)
            XCTAssertEqual(TabStore(database: database).loadSession().tabs.count, 2)
        }

        func testEverySeededRowCarriesSentinelWithZeroProductionOverlap() throws {
            let database = try makeDatabase()
            let defaults = try makeDefaults()
            let kvs = SeederMockKeyValueStore()
            try seedProductionRows(database: database)
            let prefix = CloudKitSchemaSeeder.sentinelTitlePrefix
            let host = CloudKitSchemaSeeder.sentinelHost
            _ = try CloudKitSchemaSeeder.seed(database: database, defaults: defaults, keyValueStore: kvs)

            let folders = BookmarkStore(database: database).fetchAllFolders()
            XCTAssertEqual(folders.filter { $0.title.hasPrefix(prefix) }.count, 2)
            XCTAssertTrue(folders.contains { !$0.title.hasPrefix(prefix) })

            let bookmarks = BookmarkStore(database: database).fetchAll()
            XCTAssertEqual(bookmarks.filter { $0.title.hasPrefix(prefix) }.count, 3)
            for seeded in bookmarks where seeded.title.hasPrefix(prefix) {
                XCTAssertEqual(seeded.url.host, host)
            }
            XCTAssertTrue(bookmarks.contains {
                !$0.title.hasPrefix(prefix) && $0.url.host != host
            })

            let history = HistoryStore(database: database).fetchAll(limit: HistoryStore.maxEntries)
            XCTAssertEqual(history.filter { $0.title.hasPrefix(prefix) }.count, 2)
            for seeded in history where seeded.title.hasPrefix(prefix) {
                XCTAssertEqual(seeded.url.host, host)
            }
            XCTAssertTrue(history.contains {
                !$0.title.hasPrefix(prefix) && $0.url.host != host
            })

            let recents = RecentSearchStore(database: database).fetchRecents()
            XCTAssertEqual(recents.filter { $0.query.hasPrefix(prefix) }.count, 2)
            XCTAssertTrue(recents.contains { !$0.query.hasPrefix(prefix) })

            let reading = ReadingListStore(database: database).fetchAll()
            XCTAssertEqual(reading.filter { $0.title.hasPrefix(prefix) }.count, 2)
            for seeded in reading where seeded.title.hasPrefix(prefix) {
                XCTAssertEqual(seeded.url.host, host)
            }
            XCTAssertTrue(reading.contains {
                !$0.title.hasPrefix(prefix) && $0.url.host != host
            })

            let groups = TabStore(database: database).fetchGroups()
            XCTAssertEqual(groups.filter { $0.name.hasPrefix(prefix) }.count, 1)
            XCTAssertTrue(groups.contains { !$0.name.hasPrefix(prefix) })

            let (tabs, _) = TabStore(database: database).loadSession()
            let seededTabs = tabs.filter {
                ($0.title?.hasPrefix(prefix) ?? false) || $0.url?.host == host
            }
            XCTAssertFalse(seededTabs.isEmpty)
            XCTAssertTrue(tabs.contains {
                !($0.title?.hasPrefix(prefix) ?? false) && $0.url?.host != host
            })
            // Bare parent carries no title or URL; lineage through parentTabID marks it seeded.
            let populated = try XCTUnwrap(seededTabs.first {
                $0.title?.hasPrefix(prefix) ?? false
            })
            let parent = try XCTUnwrap(tabs.first { $0.id == populated.parentTabID })
            XCTAssertNil(parent.url)
            XCTAssertFalse(tabs.contains { $0.isPrivate })
        }

        func testSeededRowsCarryExhaustiveFieldPopulation() throws {
            let database = try makeDatabase()
            let defaults = try makeDefaults()
            let kvs = SeederMockKeyValueStore()
            _ = try CloudKitSchemaSeeder.seed(database: database, defaults: defaults, keyValueStore: kvs)
            let prefix = CloudKitSchemaSeeder.sentinelTitlePrefix

            let folders = BookmarkStore(database: database).fetchAllFolders()
            let nested = try XCTUnwrap(folders.first { $0.parentId != nil })
            XCTAssertTrue(nested.title.hasPrefix(prefix))
            try XCTAssertNotNil(BookmarkStore(database: database).fetchFolder(id: XCTUnwrap(nested.parentId)))

            let bookmarks = BookmarkStore(database: database).fetchAll()
            let housed = try XCTUnwrap(bookmarks.first { $0.folderId != nil })
            XCTAssertTrue(housed.title.hasPrefix(prefix))
            try XCTAssertNotNil(BookmarkStore(database: database).fetchFolder(id: XCTUnwrap(housed.folderId)))

            let (tabs, selected) = TabStore(database: database).loadSession()
            let populated = try XCTUnwrap(tabs.first {
                $0.url != nil && ($0.title?.hasPrefix(prefix) ?? false)
            })
            XCTAssertNotNil(populated.url)
            XCTAssertNotNil(populated.title)
            XCTAssertNotNil(populated.groupId)
            XCTAssertNotNil(populated.parentTabID)
            XCTAssertNotNil(TabStore(database: database).fetchGroups().first { $0.id == populated.groupId })
            XCTAssertNotNil(tabs.first { $0.id == populated.parentTabID })
            XCTAssertNotNil(selected)
            XCTAssertEqual(selected, populated.id)

            let snapshot = try XCTUnwrap(snapshotRow(in: database))
            XCTAssertFalse(snapshot.tabIdsEncoded.isEmpty)

            let reading = ReadingListStore(database: database).fetchAll()
            XCTAssertTrue(reading.contains { $0.title.hasPrefix(prefix) && $0.previewText != nil })
        }

        func testSeederWritesAllEightSyncedKeysAndZeroTransientKeys() throws {
            let database = try makeDatabase()
            let defaults = try makeDefaults()
            let kvs = SeederMockKeyValueStore()
            let report = try CloudKitSchemaSeeder.seed(database: database, defaults: defaults, keyValueStore: kvs)

            XCTAssertTrue(report.syncEnabled)
            XCTAssertEqual(report.kvsKeysMirrored, 8)
            XCTAssertEqual(SyncedSettingsStore.syncedKeys.count, 8)
            for key in SyncedSettingsStore.syncedKeys {
                XCTAssertNotNil(defaults.object(forKey: key), "Missing local write for \(key)")
                XCTAssertNotNil(kvs.storage[key], "Missing KVS mirror for \(key)")
            }
            for key in transientKeys() {
                XCTAssertNil(defaults.object(forKey: key), "Transient key leaked to defaults: \(key)")
                XCTAssertNil(kvs.storage[key], "Transient key leaked to KVS: \(key)")
            }
            XCTAssertNil(kvs.storage[SyncedSettingsStore.iCloudSyncEnabledKey])
        }

        func testSeederKeepsPrivateHostsOutOfPersistence() throws {
            let database = try makeDatabase()
            let defaults = try makeDefaults()
            let kvs = SeederMockKeyValueStore()
            _ = try CloudKitSchemaSeeder.seed(database: database, defaults: defaults, keyValueStore: kvs)
            let host = CloudKitSchemaSeeder.sentinelHost

            let synced = makeStore(defaults: defaults, kvs: kvs)
            let standard = WebsiteSettingsStore(defaults: defaults, syncedStore: synced)
            XCTAssertFalse(standard.settings(forHost: host, isPrivate: false).isDefault)
            XCTAssertTrue(standard.settings(forHost: host, isPrivate: true).isDefault)

            XCTAssertEqual(SiteZoomStore(defaults: defaults, syncedStore: synced).zoom(forHost: host), 1.5, accuracy: 0.001)
            let (loaded, _) = TabStore(database: database).loadSession()
            XCTAssertFalse(loaded.contains { $0.isPrivate })
            XCTAssertNotNil(defaults.object(forKey: WebsiteSettingsStore.storeKey))
            XCTAssertNotNil(defaults.object(forKey: SiteZoomStore.storeKey))
        }

        func testSeedWithSyncDisabledReportsZeroMirror() throws {
            let database = try makeDatabase()
            let defaults = try makeDefaults()
            let kvs = SeederMockKeyValueStore()
            defaults.set(false, forKey: SyncedSettingsStore.iCloudSyncEnabledKey)
            let report = try CloudKitSchemaSeeder.seed(database: database, defaults: defaults, keyValueStore: kvs)

            XCTAssertFalse(report.syncEnabled)
            XCTAssertEqual(report.kvsKeysMirrored, 0)
            XCTAssertEqual(report.bookmarkFolders, 2)
            XCTAssertEqual(report.bookmarks, 3)
            XCTAssertEqual(report.historyEntries, 2)
            XCTAssertEqual(report.recentSearches, 2)
            XCTAssertEqual(report.readingListItems, 2)
            XCTAssertEqual(report.tabGroups, 1)
            XCTAssertEqual(report.tabs, 2)
            XCTAssertTrue(kvs.storage.isEmpty)
            for key in SyncedSettingsStore.syncedKeys {
                XCTAssertNotNil(defaults.object(forKey: key), "Local write missing while toggle off: \(key)")
            }
        }

        func testClearSeededRemovesAllSentinelRowsAndSecondClearReportsZero() throws {
            let database = try makeDatabase()
            let defaults = try makeDefaults()
            let kvs = SeederMockKeyValueStore()
            _ = try CloudKitSchemaSeeder.seed(database: database, defaults: defaults, keyValueStore: kvs)
            let prefix = CloudKitSchemaSeeder.sentinelTitlePrefix
            let host = CloudKitSchemaSeeder.sentinelHost

            let first = try CloudKitSchemaSeeder.clearSeeded(database: database, defaults: defaults, keyValueStore: kvs)
            XCTAssertEqual(first.bookmarkFolders, 0)
            XCTAssertEqual(first.bookmarks, 0)
            XCTAssertEqual(first.historyEntries, 0)
            XCTAssertEqual(first.recentSearches, 0)
            XCTAssertEqual(first.readingListItems, 0)
            XCTAssertEqual(first.tabGroups, 0)
            XCTAssertEqual(first.tabs, 0)

            XCTAssertTrue(BookmarkStore(database: database).fetchAllFolders().filter { $0.title.hasPrefix(prefix) }.isEmpty)
            XCTAssertTrue(BookmarkStore(database: database).fetchAll().filter { $0.title.hasPrefix(prefix) }.isEmpty)
            XCTAssertTrue(HistoryStore(database: database).fetchAll(limit: HistoryStore.maxEntries).filter { $0.title.hasPrefix(prefix) }.isEmpty)
            XCTAssertTrue(RecentSearchStore(database: database).fetchRecents().filter { $0.query.hasPrefix(prefix) }.isEmpty)
            XCTAssertTrue(ReadingListStore(database: database).fetchAll().filter { $0.title.hasPrefix(prefix) }.isEmpty)
            XCTAssertTrue(TabStore(database: database).fetchGroups().filter { $0.name.hasPrefix(prefix) }.isEmpty)
            let (remaining, _) = TabStore(database: database).loadSession()
            XCTAssertTrue(remaining.filter {
                ($0.title?.hasPrefix(prefix) ?? false) || $0.url?.host == host
            }.isEmpty)
            XCTAssertNotNil(try snapshotRow(in: database))

            let second = try CloudKitSchemaSeeder.clearSeeded(database: database, defaults: defaults, keyValueStore: kvs)
            XCTAssertEqual(second.bookmarkFolders, 0)
            XCTAssertEqual(second.bookmarks, 0)
            XCTAssertEqual(second.historyEntries, 0)
            XCTAssertEqual(second.recentSearches, 0)
            XCTAssertEqual(second.readingListItems, 0)
            XCTAssertEqual(second.tabGroups, 0)
            XCTAssertEqual(second.tabs, 0)
        }

        func testNonSentinelRowsSurviveClearSeeded() throws {
            let database = try makeDatabase()
            let defaults = try makeDefaults()
            let kvs = SeederMockKeyValueStore()
            try seedProductionRows(database: database)
            _ = try CloudKitSchemaSeeder.seed(database: database, defaults: defaults, keyValueStore: kvs)
            _ = try CloudKitSchemaSeeder.clearSeeded(database: database, defaults: defaults, keyValueStore: kvs)

            XCTAssertEqual(BookmarkStore(database: database).fetchAllFolders().count, 1)
            XCTAssertEqual(BookmarkStore(database: database).fetchAll().count, 1)
            XCTAssertEqual(BookmarkStore(database: database).fetchAll().first?.title, "Production Bookmark")
            XCTAssertEqual(HistoryStore(database: database).fetchAll(limit: HistoryStore.maxEntries).count, 1)
            XCTAssertEqual(RecentSearchStore(database: database).fetchRecents().count, 1)
            XCTAssertEqual(ReadingListStore(database: database).fetchAll().count, 1)
            XCTAssertEqual(TabStore(database: database).fetchGroups().count, 1)
            let (tabs, selected) = TabStore(database: database).loadSession()
            XCTAssertEqual(tabs.count, 1)
            XCTAssertEqual(tabs.first?.title, "Production Tab")
            XCTAssertEqual(selected, tabs.first?.id)
        }

        func testSeedingTwiceThenClearingLeavesZeroSentinelRows() throws {
            let database = try makeDatabase()
            let defaults = try makeDefaults()
            let kvs = SeederMockKeyValueStore()
            let prefix = CloudKitSchemaSeeder.sentinelTitlePrefix
            let host = CloudKitSchemaSeeder.sentinelHost
            _ = try CloudKitSchemaSeeder.seed(database: database, defaults: defaults, keyValueStore: kvs)
            let second = try CloudKitSchemaSeeder.seed(database: database, defaults: defaults, keyValueStore: kvs)
            XCTAssertEqual(second.bookmarkFolders, 2)
            XCTAssertEqual(second.bookmarks, 3)
            XCTAssertEqual(second.historyEntries, 2)
            XCTAssertEqual(second.recentSearches, 2)
            XCTAssertEqual(second.readingListItems, 2)
            XCTAssertEqual(second.tabGroups, 1)
            XCTAssertEqual(second.tabs, 2)

            _ = try CloudKitSchemaSeeder.clearSeeded(database: database, defaults: defaults, keyValueStore: kvs)
            XCTAssertTrue(BookmarkStore(database: database).fetchAllFolders().filter { $0.title.hasPrefix(prefix) }.isEmpty)
            XCTAssertTrue(BookmarkStore(database: database).fetchAll().filter { $0.title.hasPrefix(prefix) }.isEmpty)
            XCTAssertTrue(HistoryStore(database: database).fetchAll(limit: HistoryStore.maxEntries).filter { $0.title.hasPrefix(prefix) }.isEmpty)
            XCTAssertTrue(RecentSearchStore(database: database).fetchRecents().filter { $0.query.hasPrefix(prefix) }.isEmpty)
            XCTAssertTrue(ReadingListStore(database: database).fetchAll().filter { $0.title.hasPrefix(prefix) }.isEmpty)
            XCTAssertTrue(TabStore(database: database).fetchGroups().filter { $0.name.hasPrefix(prefix) }.isEmpty)
            let (remaining, _) = TabStore(database: database).loadSession()
            XCTAssertTrue(remaining.filter {
                ($0.title?.hasPrefix(prefix) ?? false) || $0.url?.host == host
            }.isEmpty)
        }
    }
#endif
