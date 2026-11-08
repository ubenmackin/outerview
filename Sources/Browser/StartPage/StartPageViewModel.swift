// StartPage — Content source for favorites plus recents.

import Foundation
import Observation
import UIKit

enum FavoriteItem: Equatable, Identifiable {
    case bookmark(Bookmark)
    case folder(BookmarkFolder)

    var id: UUID {
        switch self {
        case let .bookmark(bookmark): bookmark.id
        case let .folder(folder): folder.id
        }
    }

    var title: String {
        switch self {
        case let .bookmark(bookmark): bookmark.title
        case let .folder(folder): folder.title
        }
    }

    var sortOrder: Int {
        switch self {
        case let .bookmark(bookmark): bookmark.sortOrder
        case let .folder(folder): folder.sortOrder
        }
    }

    var addedAt: Date {
        switch self {
        case let .bookmark(bookmark): bookmark.addedAt
        case let .folder(folder): folder.createdAt
        }
    }
}

/// Content source for the no-URL start page. Favorites come from bookmark
/// rows flagged as favorites; recents are the newest history rows.
@MainActor
@Observable
final class StartPageViewModel {
    nonisolated static let recentsLimit = 8

    private let bookmarkStore: BookmarkStore
    private let historyStore: HistoryStore

    var favoriteItems: [FavoriteItem] = []
    var favorites: [Bookmark] = []
    var recents: [HistoryEntry] = []
    var activePageURL: URL?
    var activePageTitle: String?

    var currentFolder: BookmarkFolder?
    var folderStack: [BookmarkFolder] = []

    var isAtRoot: Bool {
        folderStack.isEmpty
    }

    var currentTitle: String {
        currentFolder?.title ?? "Favorites"
    }

    var isFavoritesEmpty: Bool {
        favoriteItems.isEmpty
    }

    var isRecentsEmpty: Bool {
        recents.isEmpty
    }

    var canAddCurrentPage: Bool {
        activePageURL.map(URLNormalizer.isLoadable) ?? false
    }

    init(bookmarkStore: BookmarkStore, historyStore: HistoryStore) {
        self.bookmarkStore = bookmarkStore
        self.historyStore = historyStore
        reload()
    }

    func openFolder(_ folder: BookmarkFolder) {
        folderStack.append(folder)
        currentFolder = folder
        reload()
    }

    func popFolder() {
        guard !folderStack.isEmpty else { return }
        folderStack.removeLast()
        currentFolder = folderStack.last
        reload()
    }

    func previewBookmarks(for folder: BookmarkFolder) -> [Bookmark] {
        bookmarkStore.fetchPreviewBookmarks(forFolderId: folder.id, limit: 4)
    }

    func loadableURLs(in folder: BookmarkFolder) -> [URL] {
        let allBookmarks = bookmarkStore.fetchAllBookmarks(inFolderId: folder.id)
        return Array(allBookmarks.map(\.url).filter { URLNormalizer.isLoadable($0) }.prefix(TabPool.livePageLimit))
    }

    func deleteItem(id: UUID) throws {
        // Folder and bookmark ids share one space; direct lookup avoids
        // misrouting when the visible items are stale or filtered.
        if bookmarkStore.fetchFolder(id: id) != nil {
            try bookmarkStore.deleteFolder(id: id)
        } else {
            try bookmarkStore.delete(id: id)
        }
        reload()
    }

    func reload() {
        if let currentFolder {
            let bookmarks = bookmarkStore.fetchBookmarks(folderId: currentFolder.id)
            let folders = bookmarkStore.fetchFolders(parentId: currentFolder.id)
            let items = folders.map(FavoriteItem.folder) + bookmarks.map(FavoriteItem.bookmark)
            favoriteItems = Self.sortedFavoriteItems(items)
            favorites = favoriteItems.compactMap {
                if case let .bookmark(bookmark) = $0 {
                    return bookmark
                }
                return nil
            }
        } else {
            let bookmarks = bookmarkStore.fetchFavorites(rootOnly: true)
            let folders = bookmarkStore.fetchFolders(parentId: nil, isFavorite: true)
            let items = folders.map(FavoriteItem.folder) + bookmarks.map(FavoriteItem.bookmark)
            favoriteItems = Self.sortedFavoriteItems(items)
            favorites = favoriteItems.compactMap {
                if case let .bookmark(bookmark) = $0 {
                    return bookmark
                }
                return nil
            }
        }
        // Fetch beyond the display cap so unique rows hidden behind a
        // duplicated head still surface after dedupe.
        recents = Self.sortedRecents(historyStore.fetchAll(limit: 200))
    }

    func updateActivePage(url: URL?, title: String?) {
        // Rejected schemes never become favoritable; they surface as nil so
        // the add tile stays disabled.
        guard let url, URLNormalizer.isLoadable(url) else {
            activePageURL = nil
            activePageTitle = nil
            return
        }
        activePageURL = url
        activePageTitle = title
    }

    func updateActivePage(_ snapshot: WebPageSnapshot) {
        updateActivePage(url: snapshot.url, title: snapshot.title)
    }

    func addCurrentPage() throws {
        guard let url = activePageURL, URLNormalizer.isLoadable(url) else { return }
        let title = HostFormatter.displayTitle(url: url, title: activePageTitle)
        if let currentFolder {
            try bookmarkStore.add(title: title, url: url, isFavorite: currentFolder.isFavorite, folderId: currentFolder.id)
        } else {
            try bookmarkStore.upsertFavorite(url: url, title: title)
        }
        reload()
    }

    func applyOrderedFavorites(_ ordered: [UUID]) -> Bool {
        let byID = Dictionary(uniqueKeysWithValues: favoriteItems.map { ($0.id, $0) })
        var rebuilt: [FavoriteItem] = []
        rebuilt.reserveCapacity(ordered.count)
        for id in ordered {
            guard let item = byID[id] else { return false }
            rebuilt.append(item)
        }
        favoriteItems = rebuilt
        favorites = favoriteItems.compactMap {
            if case let .bookmark(bookmark) = $0 {
                return bookmark
            }
            return nil
        }
        return true
    }

    func persistReorderedFavorites(_ ordered: [UUID]) throws {
        for (index, id) in ordered.enumerated() {
            if let item = favoriteItems.first(where: { $0.id == id }) {
                switch item {
                case let .bookmark(bookmark):
                    bookmark.sortOrder = index
                case let .folder(folder):
                    folder.sortOrder = index
                }
            }
        }
        // Shared indices are already assigned above; an empty reorder only
        // flushes the context without per-type reindexing.
        try bookmarkStore.reorderBookmarks([])
    }

    static func sortedFavorites(_ bookmarks: [Bookmark]) -> [Bookmark] {
        bookmarks.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.addedAt < $1.addedAt
        }
    }

    static func sortedFavoriteItems(_ items: [FavoriteItem]) -> [FavoriteItem] {
        items.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.addedAt < $1.addedAt
        }
    }

    static func sortedRecents(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        // Host dedupe: the first (newest) visit keeps the row; www. folds
        // onto the bare host while other subdomains stay distinct.
        var seen = Set<String>()
        var unique: [HistoryEntry] = []
        unique.reserveCapacity(entries.count)
        for entry in entries.sorted(by: { $0.visitedAt > $1.visitedAt }) {
            let key = HostFormatter.normalizedHost(HostFormatter.host(of: entry.url))
            guard seen.insert(key).inserted else { continue }
            unique.append(entry)
        }
        return Array(unique.prefix(Self.recentsLimit))
    }

    nonisolated static func isFavoritesEmpty(_ favorites: [Bookmark]) -> Bool {
        favorites.isEmpty
    }

    nonisolated static func isFavoriteItemsEmpty(_ items: [FavoriteItem]) -> Bool {
        items.isEmpty
    }

    nonisolated static func isRecentsEmpty(_ recents: [HistoryEntry]) -> Bool {
        recents.isEmpty
    }

    static func columnCount(for traits: UITraitCollection) -> Int {
        // Regular width affords the dense grid; compact and unspecified
        // fall back to the base grid.
        traits.horizontalSizeClass == .regular ? 6 : 4
    }
}
