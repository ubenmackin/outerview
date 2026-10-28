//
//  StartPageViewModel.swift
//  OuterView
//

import Foundation
import Observation
import UIKit

/// Content source for the no-URL start page. Favorites come from bookmark
/// rows flagged as favorites; recents are the newest history rows.
@MainActor
@Observable
final class StartPageViewModel {
    static let recentsLimit = 8

    private let bookmarkStore: BookmarkStore
    private let historyStore: HistoryStore

    var favorites: [Bookmark] = []
    var recents: [HistoryEntry] = []
    var activePageURL: URL?
    var activePageTitle: String?

    var isFavoritesEmpty: Bool {
        favorites.isEmpty
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

    func reload() {
        favorites = Self.sortedFavorites(bookmarkStore.fetchFavorites())
        recents = Self.sortedRecents(historyStore.fetchRecents(limit: Self.recentsLimit))
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
        try bookmarkStore.upsertFavorite(url: url, title: title)
        reload()
    }

    static func sortedFavorites(_ bookmarks: [Bookmark]) -> [Bookmark] {
        bookmarks.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.addedAt > $1.addedAt
        }
    }

    static func sortedRecents(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        entries.sorted { $0.visitedAt > $1.visitedAt }
    }

    static func isFavoritesEmpty(_ favorites: [Bookmark]) -> Bool {
        favorites.isEmpty
    }

    static func isRecentsEmpty(_ recents: [HistoryEntry]) -> Bool {
        recents.isEmpty
    }

    static func columnCount(for traits: UITraitCollection) -> Int {
        // Regular width affords the dense grid; compact and unspecified
        // fall back to the base grid.
        traits.horizontalSizeClass == .regular ? 6 : 4
    }
}
