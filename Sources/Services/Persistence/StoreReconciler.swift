// Persistence — one-shot cross-store bootstrap copies.

import Foundation
import SwiftData

/// A model that can rebuild itself field-for-field, `id` included, for
/// insert-missing-by-id copying between stores.
protocol StoreReconcileCopyable: PersistentModel {
    func reconcileCopy() -> Self
}

extension Bookmark: StoreReconcileCopyable {
    func reconcileCopy() -> Bookmark {
        Bookmark(
            id: id,
            title: title,
            url: url,
            addedAt: addedAt,
            isFavorite: isFavorite,
            folderId: folderId,
            sortOrder: sortOrder
        )
    }
}

extension BookmarkFolder: StoreReconcileCopyable {
    func reconcileCopy() -> BookmarkFolder {
        BookmarkFolder(
            id: id,
            title: title,
            parentId: parentId,
            createdAt: createdAt,
            sortOrder: sortOrder,
            isFavorite: isFavorite
        )
    }
}

extension HistoryEntry: StoreReconcileCopyable {
    func reconcileCopy() -> HistoryEntry {
        HistoryEntry(id: id, title: title, url: url, visitedAt: visitedAt)
    }
}

extension RecentSearch: StoreReconcileCopyable {
    func reconcileCopy() -> RecentSearch {
        RecentSearch(id: id, query: query, searchedAt: searchedAt)
    }
}

extension ReadingListItem: StoreReconcileCopyable {
    func reconcileCopy() -> ReadingListItem {
        ReadingListItem(
            id: id,
            title: title,
            url: url,
            addedAt: addedAt,
            isRead: isRead,
            sortIndex: sortIndex,
            previewText: previewText
        )
    }
}

extension TabRecord: StoreReconcileCopyable {
    func reconcileCopy() -> TabRecord {
        // isPrivate copies as stored; persisted rows are always non-private
        // because TabStore never writes private tabs to disk.
        TabRecord(
            id: id,
            url: url,
            title: title,
            isPrivate: isPrivate,
            createdAt: createdAt,
            lastActiveAt: lastActiveAt,
            groupId: groupId,
            parentTabID: parentTabID
        )
    }
}

extension TabGroup: StoreReconcileCopyable {
    func reconcileCopy() -> TabGroup {
        TabGroup(id: id, name: name, createdAt: createdAt)
    }
}

extension TabSession: StoreReconcileCopyable {
    func reconcileCopy() -> TabSession {
        TabSession(
            id: id,
            tabIds: tabIds,
            selectedTabId: selectedTabId,
            tabIdsEncoded: tabIdsEncoded
        )
    }
}

/// One-shot bootstrap copy per direction between the cloud-managed default
/// store and the local fallback file: insert-missing-by-id, marker set only
/// when a store held roster rows, errors thrown to the scheduler for logging.
@MainActor
enum StoreReconciler {
    enum Direction {
        case cloudToLocal
        case localToCloud
    }

    nonisolated static let cloudToLocalMarkerKey = "com.volcrypt.OuterView.reconcile.cloudToLocal.done"
    nonisolated static let localToCloudMarkerKey = "com.volcrypt.OuterView.reconcile.localToCloud.done"

    static func reconcile(
        direction: Direction,
        models: [any PersistentModel.Type],
        destination: ModelContainer,
        sourceConfiguration: ModelConfiguration,
        defaults: UserDefaults = .standard
    ) throws {
        let markerKey = markerKey(for: direction)
        // A completed pass short-circuits before any container work.
        guard !defaults.bool(forKey: markerKey) else { return }

        let source = try ModelContainer(for: Schema(models), configurations: sourceConfiguration)
        let sourceContext = ModelContext(source)
        let destinationContext = ModelContext(destination)
        // Manual contexts must not autosave into the stores' deterministic
        // save-then-read sequences on the shared main context.
        sourceContext.autosaveEnabled = false
        destinationContext.autosaveEnabled = false

        let counts = try rosterRowCount(models: models, source: sourceContext, destination: destinationContext)
        // Both stores empty: no copy is possible, and the marker stays unset
        // so a populated launch retries.
        guard counts.source > 0 || counts.destination > 0 else { return }

        try reconcileModels(models: models, source: sourceContext, destination: destinationContext)
        // Whole-roster batching keeps the destination to exactly one save per pass.
        try destinationContext.save()
        defaults.set(true, forKey: markerKey)
    }

    private static func markerKey(for direction: Direction) -> String {
        switch direction {
        case .cloudToLocal: cloudToLocalMarkerKey
        case .localToCloud: localToCloudMarkerKey
        }
    }

    /// Per-type dispatch entry: the single mechanism both the row-count step
    /// plus the copy step consult for every roster model.
    private struct RosterWorker {
        let count: @MainActor (ModelContext, ModelContext) throws -> (source: Int, destination: Int)
        let copyMissing: @MainActor (ModelContext, ModelContext) throws -> Void
    }

    /// Roster-driven dispatch table. A roster metatype without an entry is a
    /// programmer error: the pass fails loudly instead of silently skipping
    /// the type while still marking itself done.
    private static let rosterWorkers: [ObjectIdentifier: RosterWorker] = [
        ObjectIdentifier(Bookmark.self): RosterWorker(
            count: { try (source: rowCount(of: Bookmark.self, in: $0), destination: rowCount(of: Bookmark.self, in: $1)) },
            copyMissing: { try copyMissing(of: Bookmark.self, source: $0, destination: $1) }
        ),
        ObjectIdentifier(BookmarkFolder.self): RosterWorker(
            count: { try (source: rowCount(of: BookmarkFolder.self, in: $0), destination: rowCount(of: BookmarkFolder.self, in: $1)) },
            copyMissing: { try copyMissing(of: BookmarkFolder.self, source: $0, destination: $1) }
        ),
        ObjectIdentifier(HistoryEntry.self): RosterWorker(
            count: { try (source: rowCount(of: HistoryEntry.self, in: $0), destination: rowCount(of: HistoryEntry.self, in: $1)) },
            copyMissing: { try copyMissing(of: HistoryEntry.self, source: $0, destination: $1) }
        ),
        ObjectIdentifier(RecentSearch.self): RosterWorker(
            count: { try (source: rowCount(of: RecentSearch.self, in: $0), destination: rowCount(of: RecentSearch.self, in: $1)) },
            copyMissing: { try copyMissing(of: RecentSearch.self, source: $0, destination: $1) }
        ),
        ObjectIdentifier(ReadingListItem.self): RosterWorker(
            count: { try (source: rowCount(of: ReadingListItem.self, in: $0), destination: rowCount(of: ReadingListItem.self, in: $1)) },
            copyMissing: { try copyMissing(of: ReadingListItem.self, source: $0, destination: $1) }
        ),
        ObjectIdentifier(TabRecord.self): RosterWorker(
            count: { try (source: rowCount(of: TabRecord.self, in: $0), destination: rowCount(of: TabRecord.self, in: $1)) },
            copyMissing: { try copyMissing(of: TabRecord.self, source: $0, destination: $1) }
        ),
        ObjectIdentifier(TabGroup.self): RosterWorker(
            count: { try (source: rowCount(of: TabGroup.self, in: $0), destination: rowCount(of: TabGroup.self, in: $1)) },
            copyMissing: { try copyMissing(of: TabGroup.self, source: $0, destination: $1) }
        ),
        ObjectIdentifier(TabSession.self): RosterWorker(
            count: { try (source: rowCount(of: TabSession.self, in: $0), destination: rowCount(of: TabSession.self, in: $1)) },
            copyMissing: { try copyMissing(of: TabSession.self, source: $0, destination: $1) }
        )
    ]

    /// Thrown when the roster names a model with no dispatch table entry.
    enum ReconcileError: Error {
        case unhandledModelType(String)
    }

    private static func worker(for type: any PersistentModel.Type) throws -> RosterWorker {
        guard let worker = rosterWorkers[ObjectIdentifier(type)] else {
            throw ReconcileError.unhandledModelType(String(describing: type))
        }
        return worker
    }

    private static func rosterRowCount(
        models: [any PersistentModel.Type],
        source: ModelContext,
        destination: ModelContext
    ) throws -> (source: Int, destination: Int) {
        var sourceTotal = 0
        var destinationTotal = 0
        for type in models {
            let counts = try worker(for: type).count(source, destination)
            sourceTotal += counts.source
            destinationTotal += counts.destination
        }
        return (sourceTotal, destinationTotal)
    }

    private static func rowCount<T: PersistentModel>(of _: T.Type, in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    private static func reconcileModels(
        models: [any PersistentModel.Type],
        source: ModelContext,
        destination: ModelContext
    ) throws {
        for type in models {
            try worker(for: type).copyMissing(source, destination)
        }
    }

    private static func copyMissing<T: PersistentModel & StoreReconcileCopyable>(
        of _: T.Type,
        source: ModelContext,
        destination: ModelContext
    ) throws where T.ID == UUID {
        let sourceRows: [T] = try source.fetch(FetchDescriptor<T>())
        // Nothing to match when the source type holds no rows; skip the destination id fetch.
        guard !sourceRows.isEmpty else { return }
        let destinationIds = try Set<UUID>(
            destination.fetch(FetchDescriptor<T>()).map(\.id)
        )
        for row in sourceRows where !destinationIds.contains(row.id) {
            destination.insert(row.reconcileCopy())
        }
    }
}
