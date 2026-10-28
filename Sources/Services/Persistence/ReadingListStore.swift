//
//  ReadingListStore.swift
//  OuterView
//

import Foundation
import os
import SwiftData

/// Persists pages saved for later (capped at 2000 items). Re-saving a URL
/// keeps the earliest row and refreshes only an empty stored title.
@MainActor
final class ReadingListStore {
    static let maxEntries = 2000

    /// Retained so the container outlives any context derived from it; a
    /// temporary database would otherwise deallocate while the store is in use.
    private let database: OuterViewDatabase

    init(database: OuterViewDatabase) {
        self.database = database
    }

    private var context: ModelContext {
        database.context
    }

    /// Saves a page for later. An already-saved URL keeps its earliest row
    /// (the stored title is refreshed only when it is empty); an unknown URL
    /// inserts a new row, then the cap prunes oldest-first.
    @discardableResult
    func add(title: String, url: URL, previewText: String? = nil) throws -> ReadingListItem? {
        if let existing = try earliestItem(at: url) {
            var changed = false
            if existing.title.isEmpty {
                // Direct mutation bypasses the model's init clamp, so clamp here.
                existing.title = String(title.prefix(ReadingListItem.maxTitleLength))
                changed = true
            }
            if let previewText, !previewText.isEmpty, existing.previewText == nil || existing.previewText?.isEmpty == true {
                existing.previewText = String(previewText.prefix(ReadingListItem.maxPreviewLength))
                changed = true
            }
            if changed {
                try context.save()
            }
            return existing
        }
        let item = ReadingListItem(title: title, url: url, previewText: previewText)
        context.insert(item)
        try context.save()
        try pruneIfNeeded()
        return item
    }

    /// Bounded newest-first read; the cap bounds the retained rows, so the
    /// fetch limit mirrors it.
    func fetchAll() -> [ReadingListItem] {
        var descriptor = FetchDescriptor<ReadingListItem>(
            sortBy: [SortDescriptor(\.addedAt, order: .reverse)]
        )
        descriptor.fetchLimit = Self.maxEntries
        do {
            return try context.fetch(descriptor)
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                .error("fetchAll reading list failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func setRead(id: UUID, isRead: Bool) throws {
        guard let found = try item(id: id) else { return }
        found.isRead = isRead
        try context.save()
    }

    func delete(id: UUID) throws {
        guard let found = try item(id: id) else { return }
        context.delete(found)
        try context.save()
    }

    func delete(ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        for id in ids {
            if let found = try item(id: id) {
                context.delete(found)
            }
        }
        try context.save()
    }

    /// Assigns `sortIndex` 0…n-1 in `ids` order; unknown ids are skipped and
    /// rows not listed keep their current index.
    func reorder(ids: [UUID]) throws {
        var position = 0
        for id in ids {
            if let found = try item(id: id) {
                found.sortIndex = position
                position += 1
            }
        }
        try context.save()
    }

    func clear() throws {
        // Bounded deletes can leave overflow rows when inserts bypass the
        // capped add path, so clear fetches without a limit.
        let descriptor = FetchDescriptor<ReadingListItem>()
        for entry in try context.fetch(descriptor) {
            context.delete(entry)
        }
        try context.save()
    }

    func count() -> Int {
        do {
            return try context.fetchCount(FetchDescriptor<ReadingListItem>())
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                .error("count reading list failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }

    // MARK: - Private

    private func item(id: UUID) throws -> ReadingListItem? {
        var descriptor = FetchDescriptor<ReadingListItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func earliestItem(at url: URL) throws -> ReadingListItem? {
        // URL equality has no stable predicate translation, so the oldest-first
        // scan filters in memory instead of in the query.
        var descriptor = FetchDescriptor<ReadingListItem>(
            sortBy: [SortDescriptor(\.addedAt, order: .forward)]
        )
        descriptor.fetchLimit = Self.maxEntries
        return try context.fetch(descriptor).first { $0.url == url }
    }

    /// Deletes only the rows overflowing the cap: the oldest `excess` entries
    /// by `addedAt`. The row just added carries the latest timestamp, so it is
    /// never among the pruned block.
    private func pruneIfNeeded() throws {
        let count = try context.fetchCount(FetchDescriptor<ReadingListItem>())
        guard count > Self.maxEntries else { return }
        var descriptor = FetchDescriptor<ReadingListItem>(
            sortBy: [SortDescriptor(\.addedAt, order: .forward)]
        )
        descriptor.fetchLimit = count - Self.maxEntries
        for entry in try context.fetch(descriptor) {
            context.delete(entry)
        }
        try context.save()
    }
}
