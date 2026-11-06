// Bookmarks — Display/sort/menu options for browser.

import os
import UIKit

enum BookmarksDisplayMode: String, Sendable {
    case compact
    case large
}

enum BookmarksSortMode: String, CaseIterable, Sendable {
    case none
    case name
    case website

    var displayName: String {
        switch self {
        case .none: "None"
        case .name: "Name"
        case .website: "Website"
        }
    }
}

enum BookmarkListEntry {
    case folder(BookmarkFolder)
    case bookmark(Bookmark)
}

extension BookmarksBrowserView {
    nonisolated static let displayModeDefaultsKey = "bookmarks.displayMode"
    nonisolated static let sortModeDefaultsKey = "bookmarks.sortMode"
    nonisolated static let showsFoldersOnTopDefaultsKey = "bookmarks.showsFoldersOnTop"

    nonisolated static func storedDisplayMode(defaults: UserDefaults = .standard) -> BookmarksDisplayMode {
        guard let raw = defaults.string(forKey: displayModeDefaultsKey),
              let mode = BookmarksDisplayMode(rawValue: raw)
        else {
            return .compact
        }
        return mode
    }

    nonisolated static func storedSortMode(defaults: UserDefaults = .standard) -> BookmarksSortMode {
        guard let raw = defaults.string(forKey: sortModeDefaultsKey),
              let mode = BookmarksSortMode(rawValue: raw)
        else {
            return .none
        }
        return mode
    }

    nonisolated static func storedShowsFoldersOnTop(defaults: UserDefaults = .standard) -> Bool {
        guard let value = defaults.object(forKey: showsFoldersOnTopDefaultsKey) as? Bool else {
            return true
        }
        return value
    }

    nonisolated static func persist(displayMode: BookmarksDisplayMode, defaults: UserDefaults = .standard) {
        defaults.set(displayMode.rawValue, forKey: displayModeDefaultsKey)
    }

    nonisolated static func persist(sortMode: BookmarksSortMode, defaults: UserDefaults = .standard) {
        defaults.set(sortMode.rawValue, forKey: sortModeDefaultsKey)
    }

    nonisolated static func persist(showsFoldersOnTop: Bool, defaults: UserDefaults = .standard) {
        defaults.set(showsFoldersOnTop, forKey: showsFoldersOnTopDefaultsKey)
    }

    static func bookmarkDisplayTitle(_ bookmark: Bookmark) -> String {
        bookmark.title.isEmpty ? HostFormatter.host(of: bookmark.url) : bookmark.title
    }

    static func sortedFolders(_ folders: [BookmarkFolder], by sortMode: BookmarksSortMode) -> [BookmarkFolder] {
        switch sortMode {
        case .none:
            folders
        case .name, .website:
            folders.sorted {
                let cmp = $0.title.localizedStandardCompare($1.title)
                if cmp != .orderedSame {
                    return cmp == .orderedAscending
                }
                return $0.sortOrder < $1.sortOrder
            }
        }
    }

    static func sortedBookmarks(_ bookmarks: [Bookmark], by sortMode: BookmarksSortMode) -> [Bookmark] {
        switch sortMode {
        case .none:
            bookmarks
        case .name:
            bookmarks.sorted {
                let lhsTitle = bookmarkDisplayTitle($0)
                let rhsTitle = bookmarkDisplayTitle($1)
                let cmp = lhsTitle.localizedStandardCompare(rhsTitle)
                if cmp != .orderedSame {
                    return cmp == .orderedAscending
                }
                return $0.url.absoluteString < $1.url.absoluteString
            }
        case .website:
            bookmarks.sorted {
                let lhsHost = HostFormatter.host(of: $0.url)
                let rhsHost = HostFormatter.host(of: $1.url)
                let hostCmp = lhsHost.localizedStandardCompare(rhsHost)
                if hostCmp != .orderedSame {
                    return hostCmp == .orderedAscending
                }
                return bookmarkDisplayTitle($0).localizedStandardCompare(bookmarkDisplayTitle($1)) == .orderedAscending
            }
        }
    }

    static func mergedEntries(
        folders: [BookmarkFolder],
        bookmarks: [Bookmark],
        sortMode: BookmarksSortMode
    ) -> [BookmarkListEntry] {
        let combined = folders.map(BookmarkListEntry.folder) + bookmarks.map(BookmarkListEntry.bookmark)
        switch sortMode {
        case .none:
            return combined.sorted { lhs, rhs in
                let lhsOrder = sortOrderValue(for: lhs)
                let rhsOrder = sortOrderValue(for: rhs)
                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }
                if case .folder = lhs, case .bookmark = rhs {
                    return true
                }
                return false
            }
        case .name:
            return combined.sorted { lhs, rhs in
                entryTitle(for: lhs).localizedStandardCompare(entryTitle(for: rhs)) == .orderedAscending
            }
        case .website:
            return combined.sorted { lhs, rhs in
                let cmp = entryWebsiteKey(for: lhs).localizedStandardCompare(entryWebsiteKey(for: rhs))
                if cmp != .orderedSame {
                    return cmp == .orderedAscending
                }
                return entryTitle(for: lhs).localizedStandardCompare(entryTitle(for: rhs)) == .orderedAscending
            }
        }
    }

    private static func sortOrderValue(for entry: BookmarkListEntry) -> Int {
        switch entry {
        case let .folder(folder): folder.sortOrder
        case let .bookmark(bookmark): bookmark.sortOrder
        }
    }

    private static func entryTitle(for entry: BookmarkListEntry) -> String {
        switch entry {
        case let .folder(folder): folder.title
        case let .bookmark(bookmark): bookmarkDisplayTitle(bookmark)
        }
    }

    private static func entryWebsiteKey(for entry: BookmarkListEntry) -> String {
        switch entry {
        case let .folder(folder): folder.title
        case let .bookmark(bookmark): HostFormatter.host(of: bookmark.url)
        }
    }

    // MARK: - Options Actions & Menu Builder

    func setDisplayMode(_ mode: BookmarksDisplayMode) {
        guard displayMode != mode else { return }
        displayMode = mode
        Self.persist(displayMode: mode, defaults: defaults)
        tableView.reloadData()
        reassertSearchTuck()
        onNavigationStateChanged?()
    }

    func setSortMode(_ mode: BookmarksSortMode) {
        guard sortMode != mode else { return }
        sortMode = mode
        Self.persist(sortMode: mode, defaults: defaults)
        reload()
    }

    func setShowsFoldersOnTop(_ enabled: Bool) {
        guard showsFoldersOnTop != enabled else { return }
        showsFoldersOnTop = enabled
        Self.persist(showsFoldersOnTop: enabled, defaults: defaults)
        reload()
    }

    func enterSelectionMode() {
        if tableView.isEditing {
            tableView.setEditing(false, animated: false)
        }
        isSelectionMode = true
        selectedBookmarkIDs.removeAll()
        selectedFolderIDs.removeAll()
        tableView.reloadData()
        reassertSearchTuck()
        onNavigationStateChanged?()
    }

    func exitSelectionMode() {
        guard isSelectionMode || !selectedBookmarkIDs.isEmpty || !selectedFolderIDs.isEmpty else { return }
        isSelectionMode = false
        selectedBookmarkIDs.removeAll()
        selectedFolderIDs.removeAll()
        tableView.reloadData()
        reassertSearchTuck()
        onNavigationStateChanged?()
    }

    func deleteSelectedItems() {
        guard hasSelectedItems else { return }
        do {
            if !selectedBookmarkIDs.isEmpty {
                try bookmarkStore.delete(ids: selectedBookmarkIDs)
            }
            for folderID in selectedFolderIDs {
                try bookmarkStore.deleteFolder(id: folderID)
            }
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                .error("delete selected bookmarks failed: \(error.localizedDescription, privacy: .public)")
        }
        selectedBookmarkIDs.removeAll()
        selectedFolderIDs.removeAll()
        reload()
        if !hasSelectableItems {
            isSelectionMode = false
        }
        onDidMutateBookmarks?()
        onNavigationStateChanged?()
    }

    struct MenuConfiguration {
        var displayMode: BookmarksDisplayMode
        var sortMode: BookmarksSortMode
        var showsFoldersOnTop: Bool
        var hasSelectableItems: Bool
        var canCreateFolder: Bool
        var isSearching: Bool = false
        var onSelectDisplayMode: (BookmarksDisplayMode) -> Void
        var onSelectSortMode: (BookmarksSortMode) -> Void
        var onToggleFoldersOnTop: () -> Void
        var onSelectBookmarks: () -> Void
        var onEditBookmarks: () -> Void
        var onNewFolder: () -> Void
    }

    static func buildOptionsMenu(_ config: MenuConfiguration) -> UIMenu {
        let largeAction = UIAction(
            title: "Large",
            image: UIImage(systemName: "rectangle.grid.1x2"),
            state: config.displayMode == .large ? .on : .off
        ) { _ in config.onSelectDisplayMode(.large) }

        let compactAction = UIAction(
            title: "Compact",
            image: UIImage(systemName: "list.bullet"),
            state: config.displayMode == .compact ? .on : .off
        ) { _ in config.onSelectDisplayMode(.compact) }

        let sortChildren = BookmarksSortMode.allCases.map { mode in
            UIAction(
                title: mode.displayName,
                state: config.sortMode == mode ? .on : .off
            ) { _ in config.onSelectSortMode(mode) }
        }
        let sortSubmenu = UIMenu(
            title: "Sort By",
            subtitle: config.sortMode.displayName,
            image: UIImage(systemName: "arrow.up.arrow.down"),
            children: sortChildren
        )

        let foldersOnTopAction = UIAction(
            title: "Show Folders on Top",
            image: UIImage(systemName: "folder"),
            attributes: config.isSearching ? [.disabled] : [],
            state: config.showsFoldersOnTop ? .on : .off
        ) { _ in config.onToggleFoldersOnTop() }

        let selectBookmarksAction = UIAction(
            title: "Select Bookmarks",
            image: UIImage(systemName: "checkmark.circle"),
            attributes: config.hasSelectableItems ? [] : [.disabled]
        ) { _ in config.onSelectBookmarks() }

        let editBookmarksAction = UIAction(
            title: "Edit Bookmarks",
            image: UIImage(systemName: "pencil")
        ) { _ in config.onEditBookmarks() }

        let newFolderAction = UIAction(
            title: "New Folder",
            image: UIImage(systemName: "folder.badge.plus"),
            attributes: config.canCreateFolder ? [] : [.disabled]
        ) { _ in config.onNewFolder() }

        let displaySection = UIMenu(title: "", options: .displayInline, children: [largeAction, compactAction])
        let organizationSection = UIMenu(title: "", options: .displayInline, children: [sortSubmenu, foldersOnTopAction])
        let actionsSection = UIMenu(
            title: "",
            options: .displayInline,
            children: [selectBookmarksAction, editBookmarksAction, newFolderAction]
        )
        return UIMenu(title: "", children: [displaySection, organizationSection, actionsSection])
    }
}
