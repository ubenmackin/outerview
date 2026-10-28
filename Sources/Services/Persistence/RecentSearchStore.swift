//
//  RecentSearchStore.swift
//  OuterView
//

import Foundation
import os
import SwiftData

/// Persists the user's recent search queries (capped at 20 items).
/// Duplicate searches move the existing query to the top with an updated timestamp.
@MainActor
final class RecentSearchStore {
    static let maxEntries = 20

    private let database: OuterViewDatabase

    init(database: OuterViewDatabase) {
        self.database = database
    }

    private var context: ModelContext {
        database.context
    }

    /// Records a search query. If the query already exists, updates its timestamp.
    /// Prunes to keep at most `maxEntries`.
    func record(query: String) throws {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let descriptor = FetchDescriptor<RecentSearch>(
            sortBy: [SortDescriptor(\.searchedAt, order: .reverse)]
        )
        let all = try context.fetch(descriptor)
        if let existing = all.first(where: { $0.query.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            existing.searchedAt = Date()
            existing.query = trimmed
        } else {
            context.insert(RecentSearch(query: trimmed, searchedAt: Date()))
        }
        try context.save()
        try pruneIfNeeded()
    }

    func fetchRecents(limit: Int = 20) -> [RecentSearch] {
        var descriptor = FetchDescriptor<RecentSearch>(
            sortBy: [SortDescriptor(\.searchedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        do {
            return try context.fetch(descriptor)
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                .error("fetchRecents searches failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func delete(id: UUID) throws {
        var descriptor = FetchDescriptor<RecentSearch>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let found = try context.fetch(descriptor).first {
            context.delete(found)
            try context.save()
        }
    }

    func clear() throws {
        let descriptor = FetchDescriptor<RecentSearch>()
        for entry in try context.fetch(descriptor) {
            context.delete(entry)
        }
        try context.save()
    }

    private func pruneIfNeeded() throws {
        let descriptor = FetchDescriptor<RecentSearch>(
            sortBy: [SortDescriptor(\.searchedAt, order: .reverse)]
        )
        let all = try context.fetch(descriptor)
        if all.count > Self.maxEntries {
            for excess in all.dropFirst(Self.maxEntries) {
                context.delete(excess)
            }
            try context.save()
        }
    }
}
