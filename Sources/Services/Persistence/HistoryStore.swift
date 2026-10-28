//
//  HistoryStore.swift
//  OuterView
//

import Foundation
import os
import SwiftData

/// A single page visit to record; `visitedAt` defaults to now and is pinned
/// explicitly by tests.
struct PageVisit: Sendable {
    let url: URL
    let title: String
    var visitedAt: Date

    init(url: URL, title: String, visitedAt: Date = Date()) {
        self.url = url
        self.title = title
        self.visitedAt = visitedAt
    }
}

/// Append-only visit log capped at `maxEntries` rows; pruning drops the
/// oldest visits. Newest-first fetches feed the start page and suggestions.
@MainActor
final class HistoryStore {
    static let maxEntries = 10000

    /// Retained so the container outlives any context derived from it; a
    /// temporary database would otherwise deallocate while the store is in use.
    private let database: OuterViewDatabase

    init(database: OuterViewDatabase) {
        self.database = database
    }

    private var context: ModelContext {
        database.context
    }

    /// Inserts one row per visit; repeated URLs are not deduped. The insert is
    /// saved before pruning so the cap check counts the new row deterministically.
    func record(visit: PageVisit) throws {
        // Rejected schemes never enter history, even if a snapshot bypassed
        // the web-view allowlist.
        guard URLNormalizer.isLoadable(visit.url) else { return }
        context.insert(
            HistoryEntry(
                id: UUID(),
                title: visit.title,
                url: visit.url,
                visitedAt: visit.visitedAt
            )
        )
        try context.save()
        try pruneIfNeeded()
    }

    func fetchRecents(limit: Int) -> [HistoryEntry] {
        var descriptor = FetchDescriptor<HistoryEntry>(
            sortBy: [SortDescriptor(\.visitedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        do {
            return try context.fetch(descriptor)
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                .error("fetchRecents failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Newest-first bounded read; the 200-row default feeds the suggestion
    /// engine's ranked inputs.
    func fetchAll(limit: Int = 200) -> [HistoryEntry] {
        var descriptor = FetchDescriptor<HistoryEntry>(
            sortBy: [SortDescriptor(\.visitedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        do {
            return try context.fetch(descriptor)
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                .error("fetchAll history failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func delete(id: UUID) throws {
        var descriptor = FetchDescriptor<HistoryEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let found = try context.fetch(descriptor).first {
            context.delete(found)
            try context.save()
        }
    }

    func clear() throws {
        // Bounded deletes can leave overflow rows when inserts bypass the
        // capped record path, so clear fetches without a limit.
        let descriptor = FetchDescriptor<HistoryEntry>()
        for entry in try context.fetch(descriptor) {
            context.delete(entry)
        }
        try context.save()
    }

    // MARK: - Private

    /// Deletes only the rows overflowing the cap: the oldest `excess` entries
    /// by `visitedAt`. Ties at the boundary are removed from the same oldest
    /// block, so the newest rows always survive.
    private func pruneIfNeeded() throws {
        let count = try context.fetchCount(FetchDescriptor<HistoryEntry>())
        guard count > Self.maxEntries else { return }
        var descriptor = FetchDescriptor<HistoryEntry>(
            sortBy: [SortDescriptor(\.visitedAt, order: .forward)]
        )
        descriptor.fetchLimit = count - Self.maxEntries
        for entry in try context.fetch(descriptor) {
            context.delete(entry)
        }
        try context.save()
    }
}
