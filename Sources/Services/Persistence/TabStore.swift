//
//  TabStore.swift
//  OuterView
//

import Foundation
import os
import SwiftData

/// Persists the tab strip for relaunch restore. Private tabs are filtered out
/// at every write path; a low-level DEBUG assertion trips if one ever slips
/// past the filter into the persistence write itself.
@MainActor
final class TabStore {
    private enum Limits {
        static let records = 5000
    }

    /// Fixed key for the single strip snapshot row.
    private static let sessionRowID = UUID(uuid: (0xA0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))

    /// Retained so the container outlives any context derived from it; a
    /// temporary database would otherwise deallocate while the store is in use.
    private let database: OuterViewDatabase

    init(database: OuterViewDatabase) {
        self.database = database
    }

    private var context: ModelContext {
        database.context
    }

    /// Persists a tab's current state. An existing row keeps its identity and
    /// `createdAt`; a new row is created when the id is unknown. Private tabs
    /// are dropped.
    func upsertTab(_ tab: TabRecord) throws {
        guard !tab.isPrivate else { return }
        try insertOrUpdate(tab)
        try ensureSnapshotContains(tab.id)
        try context.save()
    }

    /// Deletes the row and removes the tab from the snapshot, clearing the
    /// selection when it pointed at the deleted tab.
    func deleteTab(id: UUID) throws {
        if let record = try self.record(id: id) {
            context.delete(record)
        }
        if let snapshot = try snapshotRow() {
            snapshot.tabIds = snapshot.tabIds.filter { $0 != id }
            if snapshot.selectedTabId == id {
                snapshot.selectedTabId = nil
            }
        }
        try context.save()
    }

    /// Rewrites the strip order, keeping the current selection.
    func reorder(tabs: [TabRecord]) throws {
        let ids = tabs.filter { !$0.isPrivate }.map(\.id)
        try writeSnapshot(tabIds: ids, selectedTabId: snapshotRow()?.selectedTabId)
    }

    /// Updates the selection without touching the strip order.
    func select(id: UUID) throws {
        try writeSnapshot(
            tabIds: snapshotRow()?.tabIds ?? [],
            selectedTabId: id
        )
    }

    /// Saves the whole strip: private tabs are dropped deterministically,
    /// every remaining tab is persisted, and the snapshot stores the exact
    /// order plus the selection.
    func saveSession(tabs: [TabRecord], selected: UUID?) throws {
        let persistable = tabs.filter { !$0.isPrivate }
        for tab in persistable {
            try insertOrUpdate(tab)
        }
        try writeSnapshot(tabIds: persistable.map(\.id), selectedTabId: selected)
    }

    /// Restores the strip in saved order. Ids without a persisted row and a
    /// selection that no longer resolves are dropped.
    func loadSession() -> (tabs: [TabRecord], selected: UUID?) {
        let snapshot: TabSession?
        do {
            snapshot = try snapshotRow()
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                .error("loadSession failed: \(error.localizedDescription, privacy: .public)")
            return ([], nil)
        }
        guard let snapshot else { return ([], nil) }
        var byID: [UUID: TabRecord] = [:]
        for record in allRecords() {
            byID[record.id] = record
        }
        var didScrub = false
        let tabs = snapshot.tabIds.compactMap { byID[$0] }.map { record -> TabRecord in
            // Rows written before the scheme allowlist may still hold a
            // rejected URL; scrub them so restore never reloads it.
            if let url = record.url, !URLNormalizer.isLoadable(url) {
                record.url = nil
                record.title = nil
                didScrub = true
            }
            return record
        }
        if didScrub {
            do {
                try context.save()
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                    .error("loadSession scrub save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        let selected = snapshot.selectedTabId.flatMap { selectedID in
            tabs.first { $0.id == selectedID }?.id
        }
        return (tabs, selected)
    }

    // MARK: - Private

    private func insertOrUpdate(_ tab: TabRecord) throws {
        assert(!tab.isPrivate, "Private tab reached the persistence write path")
        // Rejected schemes persist as an empty tab so a poisoned URL can
        // never reload across launches.
        let sanitizedURL: URL? = tab.url.flatMap { URLNormalizer.isLoadable($0) ? $0 : nil }
        let sanitizedTitle: String? = sanitizedURL == nil ? nil : tab.title
        if let existing = try record(id: tab.id) {
            existing.url = sanitizedURL
            existing.title = sanitizedTitle
            existing.lastActiveAt = tab.lastActiveAt
            existing.groupId = tab.groupId
        } else {
            context.insert(
                TabRecord(
                    id: tab.id,
                    url: sanitizedURL,
                    title: sanitizedTitle,
                    isPrivate: false,
                    createdAt: tab.createdAt,
                    lastActiveAt: tab.lastActiveAt,
                    groupId: tab.groupId
                )
            )
        }
    }

    private func ensureSnapshotContains(_ id: UUID) throws {
        if let snapshot = try snapshotRow() {
            guard !snapshot.tabIds.contains(id) else { return }
            snapshot.tabIds += [id]
            return
        }
        context.insert(TabSession(id: Self.sessionRowID, tabIds: [id], selectedTabId: nil))
    }

    private func writeSnapshot(tabIds: [UUID], selectedTabId: UUID?) throws {
        let snapshot: TabSession
        if let existing = try snapshotRow() {
            snapshot = existing
        } else {
            snapshot = TabSession(id: Self.sessionRowID, tabIds: [], selectedTabId: nil)
            context.insert(snapshot)
        }
        snapshot.tabIds = tabIds
        // Private or missing selections never persist: only an id present in
        // the filtered strip survives the write.
        snapshot.selectedTabId = selectedTabId.flatMap { tabIds.contains($0) ? $0 : nil }
        try context.save()
    }

    private func record(id: UUID) throws -> TabRecord? {
        var descriptor = FetchDescriptor<TabRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func snapshotRow() throws -> TabSession? {
        let rowID = Self.sessionRowID
        var descriptor = FetchDescriptor<TabSession>(predicate: #Predicate { $0.id == rowID })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func allRecords() -> [TabRecord] {
        var descriptor = FetchDescriptor<TabRecord>()
        descriptor.fetchLimit = Limits.records
        do {
            return try context.fetch(descriptor)
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                .error("allRecords failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
