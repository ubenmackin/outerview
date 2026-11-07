// Persistence — Bookmark/folder CRUD plus favorites flags.

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
    case invalidTitle

    var errorDescription: String? {
        switch self {
        case .cyclicFolderHierarchy:
            "A folder cannot be moved inside itself or one of its subfolders."
        case .folderNotFound:
            "The requested bookmark folder could not be found."
        case .bookmarkNotFound:
            "The requested bookmark could not be found."
        case .invalidTitle:
            "The title cannot be empty."
        }
    }
}

/// CRUD over persisted bookmarks. Mutations surface save failures as thrown
/// errors; fetches degrade to an empty array instead of throwing.
@MainActor
final class BookmarkStore {
    /// Retained so the container outlives any context derived from it; a
    /// temporary database would otherwise deallocate while the store is in use.
    let database: OuterViewDatabase

    init(database: OuterViewDatabase) {
        self.database = database
    }

    private var context: ModelContext {
        database.context
    }

    /// Inserts a new row with folder inheritance as truth; callers dedupe when URL uniqueness matters.
    @discardableResult
    func add(
        title: String,
        url: URL,
        isFavorite: Bool = false,
        addedDate: Date? = nil,
        folderId: UUID? = nil,
        sortOrder: Int? = nil
    ) throws -> Bookmark? {
        // Rejected schemes never enter bookmarks or favorites.
        guard URLNormalizer.isLoadable(url) else { return nil }
        // Folder inheritance is the single truth for the flag.
        var resolvedIsFavorite = isFavorite
        if let folderId {
            guard let folder = fetchFolder(id: folderId) else {
                throw BookmarkStoreError.folderNotFound
            }
            resolvedIsFavorite = folder.isFavorite
        }
        let effectiveSortOrder: Int
        if let sortOrder {
            effectiveSortOrder = sortOrder
        } else {
            let bookmarkSiblings = folderId == nil && resolvedIsFavorite
                ? fetchFavorites(rootOnly: true)
                : fetchBookmarks(folderId: folderId)
            // Shared sequence spans both types so manual rows never collide with imported orders.
            let folderSiblings = folderId == nil
                ? fetchFolders(parentId: nil, isFavorite: resolvedIsFavorite)
                : fetchFolders(parentId: folderId)
            effectiveSortOrder = max(bookmarkSiblings.map(\.sortOrder).max() ?? -1, folderSiblings.map(\.sortOrder).max() ?? -1) + 1
        }
        let bookmark = Bookmark(
            id: UUID(),
            title: title,
            url: url,
            addedAt: addedDate ?? Date(),
            isFavorite: resolvedIsFavorite,
            folderId: folderId,
            sortOrder: effectiveSortOrder
        )
        context.insert(bookmark)
        try context.save()
        return bookmark
    }

    // MARK: - Folders

    @discardableResult
    func createFolder(
        title: String,
        parentId: UUID? = nil,
        isFavorite: Bool = false,
        sortOrder: Int? = nil
    ) throws -> BookmarkFolder {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Empty titles stay rejected so untitled rows never persist.
        guard !trimmed.isEmpty else {
            throw BookmarkStoreError.invalidTitle
        }
        // Missing parents fail closed instead of orphaning the folder.
        if let parentId, fetchFolder(id: parentId) == nil {
            throw BookmarkStoreError.folderNotFound
        }
        var effectiveIsFavorite = isFavorite
        if let parentId, let parent = fetchFolder(id: parentId) {
            effectiveIsFavorite = parent.isFavorite
        }
        let siblings = fetchFolders(parentId: parentId, isFavorite: parentId == nil ? effectiveIsFavorite : nil)
        // Shared sequence spans both types so manual folders never collide with imported bookmarks.
        let bookmarkSiblings = parentId == nil && effectiveIsFavorite
            ? fetchFavorites(rootOnly: true)
            : fetchBookmarks(folderId: parentId)
        let effectiveSortOrder = sortOrder ?? (max(siblings.map(\.sortOrder).max() ?? -1, bookmarkSiblings.map(\.sortOrder).max() ?? -1) + 1)
        let folder = BookmarkFolder(
            id: UUID(),
            title: trimmed,
            parentId: parentId,
            createdAt: Date(),
            sortOrder: effectiveSortOrder,
            isFavorite: effectiveIsFavorite
        )
        context.insert(folder)
        try context.save()
        return folder
    }

    func fetchPreviewBookmarks(forFolderId folderId: UUID, limit: Int = 4) -> [Bookmark] {
        var descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.folderId == folderId },
            sortBy: [SortDescriptor(\.sortOrder, order: .forward), SortDescriptor(\.addedAt, order: .forward)]
        )
        descriptor.fetchLimit = limit
        do {
            return try context.fetch(descriptor)
        } catch {
            return []
        }
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

    func fetchFolders(parentId: UUID? = nil, isFavorite: Bool? = nil) -> [BookmarkFolder] {
        var descriptor = FetchDescriptor<BookmarkFolder>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward), SortDescriptor(\.title, order: .forward)]
        )
        descriptor.fetchLimit = BookmarkLimits.maxEntries
        do {
            let all = try context.fetch(descriptor)
            return all.filter { folder in
                guard folder.parentId == parentId else { return false }
                // Root listing filters by flag; nested listing ignores it.
                if parentId == nil, let isFavorite {
                    return folder.isFavorite == isFavorite
                }
                return true
            }
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                .error("fetchFolders failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func fetchAllFolders() -> [BookmarkFolder] {
        var descriptor = FetchDescriptor<BookmarkFolder>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward), SortDescriptor(\.title, order: .forward)]
        )
        descriptor.fetchLimit = BookmarkLimits.maxEntries
        do {
            return try context.fetch(descriptor)
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                .error("fetchAllFolders failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func fetchAllBookmarks(inFolderId folderId: UUID) -> [Bookmark] {
        var visited = Set<UUID>()
        return fetchAllBookmarks(inFolderId: folderId, visited: &visited)
    }

    private func fetchAllBookmarks(inFolderId folderId: UUID, visited: inout Set<UUID>) -> [Bookmark] {
        // Visited guard keeps cyclic legacy data from recursing forever.
        guard visited.insert(folderId).inserted else { return [] }
        var results = fetchBookmarks(folderId: folderId)
        if results.count >= BookmarkLimits.maxEntries {
            return Array(results.prefix(BookmarkLimits.maxEntries))
        }
        let subfolders = fetchFolders(parentId: folderId)
        for sub in subfolders {
            guard results.count < BookmarkLimits.maxEntries else { break }
            let nested = fetchAllBookmarks(inFolderId: sub.id, visited: &visited)
            results.append(contentsOf: nested.prefix(BookmarkLimits.maxEntries - results.count))
        }
        return results
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
        guard let folder = fetchFolder(id: id) else {
            throw BookmarkStoreError.folderNotFound
        }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        // Empty titles stay rejected so untitled rows never persist.
        guard !trimmed.isEmpty else {
            throw BookmarkStoreError.invalidTitle
        }
        folder.title = trimmed
        try context.save()
    }

    func updateFolder(id: UUID, title: String, parentId: UUID?, isFavorite: Bool? = nil) throws {
        guard let folder = fetchFolder(id: id) else {
            throw BookmarkStoreError.folderNotFound
        }
        var effectiveIsFavorite = isFavorite ?? folder.isFavorite
        if let parentId {
            guard let parent = fetchFolder(id: parentId) else {
                throw BookmarkStoreError.folderNotFound
            }
            if parentId == id || isFolder(parentId, descendantOf: id) {
                throw BookmarkStoreError.cyclicFolderHierarchy
            }
            effectiveIsFavorite = parent.isFavorite
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Empty titles stay rejected so untitled rows never persist.
        guard !trimmedTitle.isEmpty else {
            throw BookmarkStoreError.invalidTitle
        }
        folder.title = trimmedTitle
        let favoriteChanged = (folder.isFavorite != effectiveIsFavorite)
        // New parent or root favorite flip needs a fresh tail order
        // so the row never collides with the destination siblings.
        if folder.parentId != parentId || (parentId == nil && favoriteChanged) {
            let siblings = fetchFolders(parentId: parentId, isFavorite: parentId == nil ? effectiveIsFavorite : nil)
            folder.sortOrder = (siblings.map(\.sortOrder).max() ?? -1) + 1
        }
        folder.parentId = parentId
        folder.isFavorite = effectiveIsFavorite
        if favoriteChanged {
            propagateFavorite(effectiveIsFavorite, toFolderId: id)
        }
        try context.save()
    }

    private func propagateFavorite(_ isFavorite: Bool, toFolderId folderId: UUID, visited: Set<UUID> = []) {
        // Visited guard keeps cyclic legacy data from recursing forever.
        var visited = visited
        guard visited.insert(folderId).inserted else { return }
        let childBookmarks = fetchBookmarks(folderId: folderId)
        for bm in childBookmarks {
            bm.isFavorite = isFavorite
        }
        let subfolders = fetchFolders(parentId: folderId)
        for sub in subfolders {
            sub.isFavorite = isFavorite
            propagateFavorite(isFavorite, toFolderId: sub.id, visited: visited)
        }
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
        var visited = Set<UUID>()
        try deleteFolder(id: id, visited: &visited)
    }

    private func deleteFolder(id: UUID, visited: inout Set<UUID>) throws {
        // Visited guard keeps cyclic legacy data from recursing forever.
        guard visited.insert(id).inserted, let folder = fetchFolder(id: id) else { return }

        // Find and delete subfolders recursively
        let subfolders = fetchFolders(parentId: id)
        for sub in subfolders {
            try deleteFolder(id: sub.id, visited: &visited)
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
        guard let found = try bookmark(id: id) else {
            throw BookmarkStoreError.bookmarkNotFound
        }
        if let toFolderId {
            guard let folder = fetchFolder(id: toFolderId) else {
                throw BookmarkStoreError.folderNotFound
            }
            found.folderId = toFolderId
            found.isFavorite = folder.isFavorite
        } else {
            found.folderId = nil
            found.isFavorite = false
        }
        try context.save()
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
            guard let folder = fetchFolder(id: folderId) else {
                throw BookmarkStoreError.folderNotFound
            }
            found.isFavorite = folder.isFavorite
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

    func fetchFavorites(rootOnly: Bool = false) -> [Bookmark] {
        var descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.isFavorite },
            sortBy: [SortDescriptor(\.sortOrder, order: .forward), SortDescriptor(\.addedAt, order: .forward)]
        )
        descriptor.fetchLimit = BookmarkLimits.maxEntries
        do {
            let all = try context.fetch(descriptor)
            if rootOnly {
                return all.filter { $0.folderId == nil }
            }
            return all
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

    func delete(ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        for id in ids {
            if let found = try bookmark(id: id) {
                context.delete(found)
            }
        }
        try context.save()
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
            // Clearing the folder keeps a non-fav row out of a fav hierarchy.
            existing.folderId = nil
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
