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
        repairCorruptedTitles()
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

    /// Repairs the newest row for `url` once the page title arrives; title-only
    /// ticks must not duplicate the commit-time row.
    func refreshTitle(url: URL, title: String) throws {
        var descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { $0.url == url },
            sortBy: [SortDescriptor(\.visitedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        if let match = try context.fetch(descriptor).first, match.title != title {
            match.title = title
            try context.save()
            return
        }

        // Fallback: match by normalized equivalent URL if URL differs by trailing slash or redirects
        let recents = fetchRecents(limit: 10)
        if let fallbackMatch = recents.first(where: {
            Self.isEquivalentNavigationURL($0.url, url)
        }), fallbackMatch.title != title {
            fallbackMatch.title = title
            try context.save()
        }
    }

    private static func isEquivalentNavigationURL(_ firstURL: URL, _ secondURL: URL) -> Bool {
        let hostA = HostFormatter.normalizedHost(HostFormatter.host(of: firstURL))
        let hostB = HostFormatter.normalizedHost(HostFormatter.host(of: secondURL))
        guard !hostA.isEmpty, hostA == hostB else { return false }
        let pathA = firstURL.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let pathB = secondURL.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard pathA == pathB else { return false }
        return firstURL.query() == secondURL.query()
    }

    /// Scans history entries to heal any entries corrupted by prior stale-title bugs
    /// (e.g. non-search websites carrying a Google Search query title).
    func repairCorruptedTitles() {
        let entries = fetchAll(limit: 500)
        var didModify = false
        for entry in entries {
            let host = HostFormatter.normalizedHost(HostFormatter.host(of: entry.url))
            let isSearchHost = host.contains("google.") || host.contains("bing.") || host.contains("duckduckgo.") || host.contains("yahoo.") || host.contains("ecosia.")
            if !isSearchHost {
                let lowerTitle = entry.title.lowercased()
                if lowerTitle.contains("google search") || lowerTitle.contains(" - bing") || lowerTitle.contains("duckduckgo search") {
                    entry.title = HostFormatter.displayTitle(url: entry.url, title: nil)
                    didModify = true
                }
            }
        }
        if didModify {
            do {
                try context.save()
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                    .error("repairCorruptedTitles failed: \(error.localizedDescription, privacy: .public)")
            }
        }
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

    func delete(ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        for id in ids {
            var descriptor = FetchDescriptor<HistoryEntry>(predicate: #Predicate { $0.id == id })
            descriptor.fetchLimit = 1
            if let found = try context.fetch(descriptor).first {
                context.delete(found)
            }
        }
        try context.save()
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
