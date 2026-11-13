// Persistence — Simulator-only CloudKit schema seeder.
#if targetEnvironment(simulator)
    import Foundation
    import SwiftData

    enum CloudKitSchemaSeeder {
        static let sentinelTitlePrefix = "[CloudKit Seed] "
        static let sentinelHost = "cloudkit-seed.example.com"

        struct SeedReport: Sendable, Equatable {
            let bookmarkFolders: Int
            let bookmarks: Int
            let historyEntries: Int
            let recentSearches: Int
            let readingListItems: Int
            let tabGroups: Int
            let tabs: Int
            let kvsKeysMirrored: Int
            let syncEnabled: Bool

            var summary: String {
                "CloudKit seed — folders:\(bookmarkFolders) bookmarks:\(bookmarks) "
                    + "history:\(historyEntries) searches:\(recentSearches) "
                    + "reading:\(readingListItems) groups:\(tabGroups) tabs:\(tabs) "
                    + "kvs:\(kvsKeysMirrored) sync:\(syncEnabled ? "on" : "off")"
            }
        }

        @MainActor
        static func seed(
            database: OuterViewDatabase,
            defaults: UserDefaults,
            keyValueStore: NSUbiquitousKeyValueStore
        ) throws -> SeedReport {
            let bookmarkStore = BookmarkStore(database: database)
            let historyStore = HistoryStore(database: database)
            let tabStore = TabStore(database: database)
            let recentStore = RecentSearchStore(database: database)
            let readingStore = ReadingListStore(database: database)
            let syncedStore = SyncedSettingsStore(defaults: defaults, keyValueStore: keyValueStore)
            let zoomStore = SiteZoomStore(defaults: defaults, syncedStore: syncedStore)
            let websiteStore = WebsiteSettingsStore(defaults: defaults, syncedStore: syncedStore)
            try purgeSentinelDatabaseRows(
                bookmarkStore: bookmarkStore,
                historyStore: historyStore,
                tabStore: tabStore,
                recentStore: recentStore,
                readingStore: readingStore
            )
            try seedBookmarkTrees(bookmarkStore)
            try seedHistoryRows(historyStore)
            try seedRecentQueries(recentStore)
            try seedReadingItems(readingStore)
            try seedTabSession(tabStore)
            writeSeedSettings(syncedStore: syncedStore, zoomStore: zoomStore, websiteStore: websiteStore)
            syncedStore.startSync()
            _ = syncedStore.synchronize()
            let syncEnabled = SyncedSettingsStore.isSyncEnabled(defaults: defaults)
            let kvsKeysMirrored = syncedStore.mirroredKeyCount()
            return SeedReport(
                bookmarkFolders: 2,
                bookmarks: 3,
                historyEntries: 2,
                recentSearches: 2,
                readingListItems: 2,
                tabGroups: 1,
                tabs: 2,
                kvsKeysMirrored: kvsKeysMirrored,
                syncEnabled: syncEnabled
            )
        }

        @MainActor
        static func clearSeeded(
            database: OuterViewDatabase,
            defaults: UserDefaults,
            keyValueStore: NSUbiquitousKeyValueStore
        ) throws -> SeedReport {
            let bookmarkStore = BookmarkStore(database: database)
            let historyStore = HistoryStore(database: database)
            let tabStore = TabStore(database: database)
            let recentStore = RecentSearchStore(database: database)
            let readingStore = ReadingListStore(database: database)
            let syncedStore = SyncedSettingsStore(defaults: defaults, keyValueStore: keyValueStore)
            let zoomStore = SiteZoomStore(defaults: defaults, syncedStore: syncedStore)
            let websiteStore = WebsiteSettingsStore(defaults: defaults, syncedStore: syncedStore)
            try purgeSentinelDatabaseRows(
                bookmarkStore: bookmarkStore,
                historyStore: historyStore,
                tabStore: tabStore,
                recentStore: recentStore,
                readingStore: readingStore
            )
            zoomStore.setZoom(1.0, forHost: sentinelHost)
            websiteStore.updateSettings(WebsiteSettings(), forHost: sentinelHost, isPrivate: false)
            let (remainingTabs, selected) = tabStore.loadSession()
            let preservedSelection: UUID? = if let selected, remainingTabs.contains(where: { $0.id == selected }) {
                selected
            } else {
                remainingTabs.first?.id
            }
            try tabStore.saveSession(tabs: remainingTabs, selected: preservedSelection)
            // deleteTab clears the selection when it removes the seeded pick, so
            // re-assert the preserved pick when the snapshot write leaves it empty.
            if let fallback = preservedSelection, tabStore.loadSession().selected == nil {
                try tabStore.select(id: fallback)
            }
            let syncEnabled = SyncedSettingsStore.isSyncEnabled(defaults: defaults)
            let kvsKeysMirrored = syncedStore.mirroredKeyCount()
            return SeedReport(
                bookmarkFolders: 0,
                bookmarks: 0,
                historyEntries: 0,
                recentSearches: 0,
                readingListItems: 0,
                tabGroups: 0,
                tabs: 0,
                kvsKeysMirrored: kvsKeysMirrored,
                syncEnabled: syncEnabled
            )
        }

        @MainActor
        private static func seedBookmarkTrees(_ bookmarkStore: BookmarkStore) throws {
            let inbox = try bookmarkStore.createFolder(
                title: "\(sentinelTitlePrefix)Inbox",
                parentId: nil,
                isFavorite: true,
                sortOrder: 0
            )
            // Production folders inherit the parent favorite flag, so the root
            // inbox stays favorite to keep the nested favorites child reachable
            // through the production write path alone.
            let favoritesChild = try bookmarkStore.createFolder(
                title: "\(sentinelTitlePrefix)Favorites",
                parentId: inbox.id,
                isFavorite: true,
                sortOrder: 1
            )
            let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
            _ = try bookmarkStore.add(
                title: "\(sentinelTitlePrefix)Favorite Bookmark",
                url: sentinelURL(path: "/bookmark-favorite"),
                isFavorite: true,
                addedDate: baseDate,
                folderId: favoritesChild.id,
                sortOrder: 0
            )
            _ = try bookmarkStore.add(
                title: "\(sentinelTitlePrefix)Root Bookmark",
                url: sentinelURL(path: "/bookmark-root"),
                isFavorite: false,
                addedDate: baseDate.addingTimeInterval(24 * 60 * 60),
                folderId: nil,
                sortOrder: 1
            )
            _ = try bookmarkStore.add(
                title: "\(sentinelTitlePrefix)Extra Bookmark",
                url: sentinelURL(path: "/bookmark-extra"),
                isFavorite: true,
                addedDate: baseDate.addingTimeInterval(2 * 24 * 60 * 60),
                folderId: nil,
                sortOrder: 2
            )
        }

        @MainActor
        private static func seedHistoryRows(_ historyStore: HistoryStore) throws {
            let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
            try historyStore.record(visit: PageVisit(
                url: sentinelURL(path: "/history-1"),
                title: "\(sentinelTitlePrefix)History One",
                visitedAt: baseDate
            ))
            try historyStore.record(visit: PageVisit(
                url: sentinelURL(path: "/history-2"),
                title: "\(sentinelTitlePrefix)History Two",
                visitedAt: baseDate.addingTimeInterval(60 * 60)
            ))
        }

        @MainActor
        private static func seedRecentQueries(_ recentStore: RecentSearchStore) throws {
            try recentStore.record(query: "\(sentinelTitlePrefix)outer view sync")
            try recentStore.record(query: "\(sentinelTitlePrefix)cloudkit schema")
        }

        @MainActor
        private static func seedReadingItems(_ readingStore: ReadingListStore) throws {
            _ = try readingStore.add(
                title: "\(sentinelTitlePrefix)Reading One",
                url: sentinelURL(path: "/reading-1"),
                previewText: "\(sentinelTitlePrefix)preview text for offline reading"
            )
            if let second = try readingStore.add(
                title: "\(sentinelTitlePrefix)Reading Two",
                url: sentinelURL(path: "/reading-2")
            ) {
                try readingStore.setRead(id: second.id, isRead: true)
            }
        }

        private static func sentinelURL(path: String) throws -> URL {
            var components = URLComponents()
            components.scheme = "https"
            components.host = sentinelHost
            components.path = path
            guard let url = components.url else {
                throw CocoaError(.fileNoSuchFile)
            }
            return url
        }

        @MainActor
        private static func seedTabSession(_ tabStore: TabStore) throws {
            let group = try tabStore.createGroup(name: "\(sentinelTitlePrefix)Group")
            let bareTab = TabRecord(isPrivate: false)
            let populatedTab = TabRecord(
                url: URL(string: "https://\(sentinelHost)/tab-main"),
                title: "\(sentinelTitlePrefix)Tab",
                isPrivate: false,
                groupId: group.id,
                parentTabID: bareTab.id
            )
            let (productionTabs, _) = tabStore.loadSession()
            try tabStore.saveSession(tabs: productionTabs + [bareTab, populatedTab], selected: populatedTab.id)
        }

        @MainActor
        private static func writeSeedSettings(
            syncedStore: SyncedSettingsStore,
            zoomStore: SiteZoomStore,
            websiteStore: WebsiteSettingsStore
        ) {
            let engineRaw = SearchEngine.allCases.first(where: { $0 != .google })?.rawValue
                ?? SearchEngine.duckduckgo.rawValue
            syncedStore.set(engineRaw, forKey: SettingsViewModel.searchEngineDefaultsKey)
            syncedStore.set(false, forKey: SettingsViewModel.requireBiometricsDefaultsKey)
            syncedStore.set(false, forKey: SettingsViewModel.blockTrackersDefaultsKey)
            syncedStore.set(
                PortraitTabBarPosition.left.rawValue,
                forKey: SettingsViewModel.portraitTabBarPositionDefaultsKey
            )
            syncedStore.set(ReaderTheme.sepia.rawValue, forKey: ReaderMode.themeDefaultsKey)
            syncedStore.set(24, forKey: ReaderMode.fontSizeDefaultsKey)
            zoomStore.setZoom(1.5, forHost: sentinelHost)
            websiteStore.updateSettings(
                WebsiteSettings(requestDesktopWebsite: true, useReaderAutomatically: true),
                forHost: sentinelHost,
                isPrivate: false
            )
        }

        @MainActor
        private static func purgeSentinelDatabaseRows(
            bookmarkStore: BookmarkStore,
            historyStore: HistoryStore,
            tabStore: TabStore,
            recentStore: RecentSearchStore,
            readingStore: ReadingListStore
        ) throws {
            let seededBookmarkIDs = Set(bookmarkStore.fetchAll().filter {
                $0.title.hasPrefix(sentinelTitlePrefix)
            }.map(\.id))
            try bookmarkStore.delete(ids: seededBookmarkIDs)
            let seededFolders = bookmarkStore.fetchAllFolders().filter {
                $0.title.hasPrefix(sentinelTitlePrefix)
            }
            for folder in seededFolders.sorted(by: { ($0.parentId != nil) && ($1.parentId == nil) }) {
                try bookmarkStore.deleteFolder(id: folder.id)
            }
            let seededHistoryIDs = Set(historyStore.fetchAll(limit: HistoryStore.maxEntries).filter {
                $0.title.hasPrefix(sentinelTitlePrefix)
            }.map(\.id))
            try historyStore.delete(ids: seededHistoryIDs)
            for entry in recentStore.fetchRecents(limit: RecentSearchStore.maxEntries).filter({
                $0.query.hasPrefix(sentinelTitlePrefix)
            }) {
                try recentStore.delete(id: entry.id)
            }
            let seededReadingIDs = Set(readingStore.fetchAll().filter {
                $0.title.hasPrefix(sentinelTitlePrefix)
            }.map(\.id))
            try readingStore.delete(ids: seededReadingIDs)
            let (sessionTabs, _) = tabStore.loadSession()
            let seededTabs = sessionTabs.filter { tab in
                if let title = tab.title, title.hasPrefix(sentinelTitlePrefix) {
                    return true
                }
                if let host = tab.url?.host?.lowercased(), host == sentinelHost.lowercased() {
                    return true
                }
                return false
            }
            var tabIDsToDelete = Set(seededTabs.map(\.id))
            for tab in seededTabs {
                guard let parent = tab.parentTabID, let parentTab = sessionTabs.first(where: { $0.id == parent }), parentTab.url == nil else { continue }
                tabIDsToDelete.insert(parent)
            }
            for id in tabIDsToDelete {
                try tabStore.deleteTab(id: id)
            }
            for group in tabStore.fetchGroups().filter({ $0.name.hasPrefix(sentinelTitlePrefix) }) {
                try tabStore.deleteGroup(id: group.id)
            }
        }
    }
#endif
