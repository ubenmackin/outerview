//
//  BookmarkStore.swift
//  OuterView
//

import Foundation
import os
import SwiftData

/// Shared cap for bookmark imports and store fetch limits, so a full import
/// stays fully visible to the dedupe scan on a repeated import.
enum BookmarkLimits: Sendable {
    static let maxEntries = 5000
}

/// Defines where a bookmark resides: pinned in Favorites, top-level Bookmarks, or inside a folder.
enum BookmarkLocation: Hashable, Equatable, Sendable {
    case favorites
    case root
    case folder(UUID)
}

enum BookmarkStoreError: Error, LocalizedError, Equatable {
    case cyclicFolderHierarchy
    case folderNotFound
    case bookmarkNotFound

    var errorDescription: String? {
        switch self {
        case .cyclicFolderHierarchy:
            "A folder cannot be moved inside itself or one of its subfolders."
        case .folderNotFound:
            "The requested bookmark folder could not be found."
        case .bookmarkNotFound:
            "The requested bookmark could not be found."
        }
    }
}

/// CRUD over persisted bookmarks. Mutations surface save failures as thrown
/// errors; fetches degrade to an empty array instead of throwing.
@MainActor
final class BookmarkStore {
    /// Retained so the container outlives any context derived from it; a
    /// temporary database would otherwise deallocate while the store is in use.
    private let database: OuterViewDatabase

    init(database: OuterViewDatabase) {
        self.database = database
    }

    private var context: ModelContext {
        database.context
    }

    /// Inserts a new row as-is; callers dedupe when URL uniqueness matters.
    @discardableResult
    func add(
        title: String,
        url: URL,
        isFavorite: Bool = false,
        addedDate: Date? = nil,
        folderId: UUID? = nil,
        sortOrder: Int = 0
    ) throws -> Bookmark? {
        // Rejected schemes never enter bookmarks or favorites.
        guard URLNormalizer.isLoadable(url) else { return nil }
        let bookmark = Bookmark(
            id: UUID(),
            title: title,
            url: url,
            addedAt: addedDate ?? Date(),
            isFavorite: isFavorite,
            folderId: folderId,
            sortOrder: sortOrder
        )
        context.insert(bookmark)
        try context.save()
        return bookmark
    }

    // MARK: - Folders

    @discardableResult
    func createFolder(title: String, parentId: UUID? = nil) throws -> BookmarkFolder {
        let existing = fetchFolders(parentId: parentId)
        let nextOrder = (existing.map(\.sortOrder).max() ?? -1) + 1
        let folder = BookmarkFolder(
            id: UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            parentId: parentId,
            createdAt: Date(),
            sortOrder: nextOrder
        )
        context.insert(folder)
        try context.save()
        return folder
    }

    func fetchFolder(id: UUID) -> BookmarkFolder? {
        var descriptor = FetchDescriptor<BookmarkFolder>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        do {
            return try context.fetch(descriptor).first
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                .error("fetchFolder failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func fetchFolders(parentId: UUID? = nil) -> [BookmarkFolder] {
        var descriptor = FetchDescriptor<BookmarkFolder>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward), SortDescriptor(\.title, order: .forward)]
        )
        descriptor.fetchLimit = BookmarkLimits.maxEntries
        do {
            let all = try context.fetch(descriptor)
            return all.filter { $0.parentId == parentId }
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                .error("fetchFolders failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func fetchBookmarks(folderId: UUID? = nil) -> [Bookmark] {
        var descriptor = FetchDescriptor<Bookmark>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward), SortDescriptor(\.addedAt, order: .forward)]
        )
        descriptor.fetchLimit = BookmarkLimits.maxEntries
        do {
            let all = try context.fetch(descriptor)
            return all.filter {
                if folderId == nil {
                    $0.folderId == nil && !$0.isFavorite
                } else {
                    $0.folderId == folderId
                }
            }
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                .error("fetchBookmarks in folder failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func renameFolder(id: UUID, newTitle: String) throws {
        if let folder = fetchFolder(id: id) {
            folder.title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            try context.save()
        }
    }

    func updateFolder(id: UUID, title: String, parentId: UUID?) throws {
        guard let folder = fetchFolder(id: id) else {
            throw BookmarkStoreError.folderNotFound
        }
        if let parentId {
            guard fetchFolder(id: parentId) != nil else {
                throw BookmarkStoreError.folderNotFound
            }
            if parentId == id || isFolder(parentId, descendantOf: id) {
                throw BookmarkStoreError.cyclicFolderHierarchy
            }
        }
        folder.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        folder.parentId = parentId
        try context.save()
    }

    private func isFolder(_ candidateId: UUID, descendantOf ancestorId: UUID) -> Bool {
        var current: UUID? = candidateId
        var visited = Set<UUID>()
        while let currentId = current {
            if currentId == ancestorId {
                return true
            }
            if visited.contains(currentId) {
                return true
            }
            visited.insert(currentId)
            current = fetchFolder(id: currentId)?.parentId
        }
        return false
    }

    /// Recursively deletes the folder, child subfolders, and all contained bookmarks.
    func deleteFolder(id: UUID) throws {
        guard let folder = fetchFolder(id: id) else { return }

        // Find and delete subfolders recursively
        let subfolders = fetchFolders(parentId: id)
        for sub in subfolders {
            try deleteFolder(id: sub.id)
        }

        // Delete contained bookmarks
        let bookmarks = fetchBookmarks(folderId: id)
        for storedBookmark in bookmarks {
            context.delete(storedBookmark)
        }

        context.delete(folder)
        try context.save()
    }

    func moveBookmark(id: UUID, toFolderId: UUID?) throws {
        if let found = try bookmark(id: id) {
            found.folderId = toFolderId
            try context.save()
        }
    }

    func updateBookmark(id: UUID, title: String, url: URL, location: BookmarkLocation) throws {
        guard URLNormalizer.isLoadable(url) else { return }
        guard let found = try bookmark(id: id) else {
            throw BookmarkStoreError.bookmarkNotFound
        }
        found.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        found.url = url
        switch location {
        case .favorites:
            found.isFavorite = true
            found.folderId = nil
        case .root:
            found.isFavorite = false
            found.folderId = nil
        case let .folder(folderId):
            guard fetchFolder(id: folderId) != nil else {
                throw BookmarkStoreError.folderNotFound
            }
            found.isFavorite = false
            found.folderId = folderId
        }
        try context.save()
    }

    func reorderBookmarks(_ ids: [UUID]) throws {
        for (index, id) in ids.enumerated() {
            if let found = try bookmark(id: id) {
                found.sortOrder = index
            }
        }
        try context.save()
    }

    func reorderFolders(_ ids: [UUID]) throws {
        for (index, id) in ids.enumerated() {
            if let folder = fetchFolder(id: id) {
                folder.sortOrder = index
            }
        }
        try context.save()
    }

    func fetchFavorites() -> [Bookmark] {
        var descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.isFavorite },
            sortBy: [SortDescriptor(\.sortOrder, order: .forward), SortDescriptor(\.addedAt, order: .forward)]
        )
        descriptor.fetchLimit = BookmarkLimits.maxEntries
        do {
            return try context.fetch(descriptor)
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                .error("fetchFavorites failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func fetchAll() -> [Bookmark] {
        var descriptor = FetchDescriptor<Bookmark>(
            sortBy: [SortDescriptor(\.addedAt, order: .forward)]
        )
        descriptor.fetchLimit = BookmarkLimits.maxEntries
        do {
            return try context.fetch(descriptor)
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                .error("fetchAll bookmarks failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func delete(id: UUID) throws {
        if let found = try bookmark(id: id) {
            context.delete(found)
            try context.save()
        }
    }

    /// Ensures `url` is favorited without creating a duplicate: an existing
    /// row keeps its identity (earliest wins) and is promoted in place; only a
    /// missing URL inserts a new favorite.
    func upsertFavorite(url: URL, title: String) throws {
        guard URLNormalizer.isLoadable(url) else { return }
        if let existing = try earliestBookmark(at: url) {
            existing.title = title
            existing.isFavorite = true
            existing.folderId = nil
            try context.save()
            return
        }
        try add(title: title, url: url, isFavorite: true)
    }

    func removeFavorite(url: URL) throws {
        if let existing = try earliestBookmark(at: url) {
            existing.isFavorite = false
            try context.save()
        }
    }

    func isFavorite(url: URL) -> Bool {
        do {
            return try earliestBookmark(at: url)?.isFavorite == true
        } catch {
            return false
        }
    }

    func bookmark(for url: URL) -> Bookmark? {
        do {
            return try earliestBookmark(at: url)
        } catch {
            return nil
        }
    }

    // MARK: - Private

    private func bookmark(id: UUID) throws -> Bookmark? {
        var descriptor = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func earliestBookmark(at url: URL) throws -> Bookmark? {
        // URL equality has no stable predicate translation, so the oldest-first
        // scan filters in memory instead of in the query.
        var descriptor = FetchDescriptor<Bookmark>(
            sortBy: [SortDescriptor(\.addedAt, order: .forward)]
        )
        descriptor.fetchLimit = BookmarkLimits.maxEntries
        return try context.fetch(descriptor).first { $0.url == url }
    }
}
