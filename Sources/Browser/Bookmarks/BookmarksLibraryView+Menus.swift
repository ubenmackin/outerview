//
//  BookmarksLibraryView+Menus.swift
//  OuterView
//

import UIKit

extension BookmarksLibraryView {
    // MARK: - Bookmarks Display & Organization Preferences

    var bookmarksDisplayMode: BookmarksDisplayMode {
        bookmarksBrowserView?.displayMode ?? BookmarksBrowserView.storedDisplayMode(defaults: defaults)
    }

    var bookmarksSortMode: BookmarksSortMode {
        bookmarksBrowserView?.sortMode ?? BookmarksBrowserView.storedSortMode(defaults: defaults)
    }

    var bookmarksShowsFoldersOnTop: Bool {
        bookmarksBrowserView?.showsFoldersOnTop ?? BookmarksBrowserView.storedShowsFoldersOnTop(defaults: defaults)
    }

    func setBookmarksDisplayMode(_ mode: BookmarksDisplayMode) {
        if let bookmarksBrowserView {
            bookmarksBrowserView.setDisplayMode(mode)
        } else {
            BookmarksBrowserView.persist(displayMode: mode, defaults: defaults)
        }
        updateInlineCommands()
    }

    func setBookmarksSortMode(_ mode: BookmarksSortMode) {
        if let bookmarksBrowserView {
            bookmarksBrowserView.setSortMode(mode)
        } else {
            BookmarksBrowserView.persist(sortMode: mode, defaults: defaults)
        }
        updateInlineCommands()
    }

    func setBookmarksShowsFoldersOnTop(_ enabled: Bool) {
        if let bookmarksBrowserView {
            bookmarksBrowserView.setShowsFoldersOnTop(enabled)
        } else {
            BookmarksBrowserView.persist(showsFoldersOnTop: enabled, defaults: defaults)
        }
        updateInlineCommands()
    }

    // MARK: - Multi-Tab Selection Helpers

    var isBookmarksInSelectionMode: Bool {
        bookmarksBrowserView?.isSelectionMode ?? false
    }

    var canDeleteBookmarksSelection: Bool {
        bookmarksBrowserView?.hasSelectedItems ?? false
    }

    var isHistoryInSelectionMode: Bool {
        historyListView?.isSelectionMode ?? false
    }

    var canDeleteHistorySelection: Bool {
        historyListView?.hasSelectedEntries ?? false
    }

    var isActiveTabInSelectionMode: Bool {
        switch activeTab {
        case .bookmarks:
            isBookmarksInSelectionMode
        case .history:
            isHistoryInSelectionMode
        case .readingList:
            isReadingListInSelectionMode
        case .favorites:
            false
        }
    }

    var canDeleteActiveTabSelection: Bool {
        switch activeTab {
        case .bookmarks:
            canDeleteBookmarksSelection
        case .history:
            canDeleteHistorySelection
        case .readingList:
            canDeleteReadingListSelection
        case .favorites:
            false
        }
    }

    func enterBookmarksSelectionMode() {
        bookmarksBrowserView?.enterSelectionMode()
        updateInlineCommands()
    }

    func exitBookmarksSelectionMode() {
        bookmarksBrowserView?.exitSelectionMode()
        updateInlineCommands()
    }

    func deleteBookmarksSelectedItems() {
        bookmarksBrowserView?.deleteSelectedItems()
        updateInlineCommands()
    }

    func enterHistorySelectionMode() {
        historyListView?.enterSelectionMode()
        updateInlineCommands()
    }

    func exitHistorySelectionMode() {
        historyListView?.exitSelectionMode()
        updateInlineCommands()
    }

    func deleteHistorySelectedItems() {
        historyListView?.deleteSelectedEntries()
        updateInlineCommands()
    }

    func exitActiveTabSelectionMode() {
        switch activeTab {
        case .bookmarks:
            exitBookmarksSelectionMode()
        case .history:
            exitHistorySelectionMode()
        case .readingList:
            exitReadingListSelectionMode()
        case .favorites:
            break
        }
    }

    func resetRegularSelectionModes() {
        bookmarksBrowserView?.exitSelectionMode()
        historyListView?.exitSelectionMode()
        updateInlineCommands()
    }

    func deleteSelectedItemsForActiveTab() {
        switch activeTab {
        case .bookmarks:
            deleteBookmarksSelectedItems()
        case .history:
            deleteHistorySelectedItems()
        case .readingList:
            deleteReadingListSelectedItems()
        case .favorites:
            break
        }
    }

    // MARK: - Safari Options Menus

    func makeBookmarksOptionsMenu() -> UIMenu {
        let config = BookmarksBrowserView.MenuConfiguration(
            displayMode: bookmarksDisplayMode,
            sortMode: bookmarksSortMode,
            showsFoldersOnTop: bookmarksShowsFoldersOnTop,
            isViewingFavorites: bookmarksBrowserView?.isViewingFavorites ?? false,
            hasSelectableItems: bookmarksBrowserView?.hasSelectableItems ?? false,
            canCreateFolder: bookmarksBrowserView?.canCreateFolder ?? true,
            onSelectDisplayMode: { [weak self] mode in
                self?.setBookmarksDisplayMode(mode)
            },
            onSelectSortMode: { [weak self] mode in
                self?.setBookmarksSortMode(mode)
            },
            onToggleFoldersOnTop: { [weak self] in
                guard let self else { return }
                self.setBookmarksShowsFoldersOnTop(!self.bookmarksShowsFoldersOnTop)
            },
            onSelectBookmarks: { [weak self] in
                self?.enterBookmarksSelectionMode()
            },
            onEditBookmarks: { [weak self] in
                self?.triggerInlineToggleEdit()
            },
            onNewFolder: { [weak self] in
                self?.triggerInlineAdd()
            }
        )
        return BookmarksBrowserView.buildOptionsMenu(config)
    }

    func makeHistoryOptionsMenu(canClear: Bool) -> UIMenu {
        let selectWebsites = UIAction(
            title: "Select Websites",
            image: UIImage(systemName: "checkmark.circle"),
            attributes: canClear ? [] : [.disabled]
        ) { [weak self] _ in
            self?.enterHistorySelectionMode()
        }
        let clearImage = UIImage(systemName: "clock.badge.xmark") ?? UIImage(systemName: "trash")
        let clearHistory = UIAction(
            title: "Clear History…",
            image: clearImage,
            attributes: canClear ? [.destructive] : [.destructive, .disabled]
        ) { [weak self] _ in
            self?.triggerInlineClear()
        }
        return UIMenu(title: "", children: [selectWebsites, clearHistory])
    }

    // MARK: - Inline Command Triggers

    func triggerInlineAdd() {
        if let callback = onInlineAddFolder {
            callback()
        } else {
            promptNewFolder()
        }
    }

    func triggerInlineToggleEdit() {
        if let callback = onInlineToggleEdit {
            callback()
        } else {
            toggleBookmarksEdit()
        }
    }

    func triggerInlineClear() {
        if let callback = onInlineClearHistory {
            callback()
        } else {
            promptClearHistory()
        }
    }

    func triggerInlineDelete() {
        if let callback = onInlineDelete {
            callback()
        } else {
            deleteSelectedItemsForActiveTab()
        }
    }

    func handlePrimaryCloseOrDone() {
        let commands = LibraryTabCommands.make(
            for: activeTab,
            isEditingBookmarks: isEditingBookmarks,
            canClearHistory: canClearHistory,
            isInSelection: isActiveTabInSelectionMode,
            canDeleteSelection: canDeleteActiveTabSelection,
            hasReadingListMenu: inlineMenu != nil || makeReadingListMenu() != nil
        )
        if commands.isEditingBookmarks {
            triggerInlineToggleEdit()
            return
        }
        if commands.doneExitsSelection {
            exitActiveTabSelectionMode()
            return
        }
        if let inlineDone = onInlineDone {
            inlineDone()
        } else {
            onDone?()
        }
    }
}
