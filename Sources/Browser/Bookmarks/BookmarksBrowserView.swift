//
//  BookmarksBrowserView.swift
//  OuterView
//

import os
import SwiftUI
import UIKit

/// Subtitle-style cell so dequeued reuse keeps its detail label.
@MainActor
final class BookmarkRowCell: LibrarySubtitleCell {
    override init(style _: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .subtitle, reuseIdentifier: reuseIdentifier)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Safari-style hierarchical bookmark browser supporting pinned Favorites folder,
/// nested user folders, reordering clamped within section, context menus, and inline editing.
@MainActor
final class BookmarksBrowserView: UIView {
    var onOpenURL: ((URL) -> Void)?
    var onOpenInNewTab: ((URL) -> Void)?
    var onRequestEdit: ((BookmarkEditorTarget) -> Void)?
    var onNavigationStateChanged: (() -> Void)?
    var onDidMutateBookmarks: (() -> Void)?

    let bookmarkStore: BookmarkStore
    let defaults: UserDefaults
    private var folderStack: [BookmarkFolder] = []
    private(set) var isViewingFavorites: Bool = false
    private var currentFolders: [BookmarkFolder] = []
    private var currentBookmarks: [Bookmark] = []
    private var combinedEntries: [BookmarkListEntry] = []
    private var favoritesCount: Int = 0
    private var folderItemCounts: [UUID: Int] = [:]
    private var hidesInlineHeaderBar = false

    var displayMode: BookmarksDisplayMode = .compact
    var sortMode: BookmarksSortMode = .none
    var showsFoldersOnTop: Bool = true
    var isSelectionMode: Bool = false
    var selectedBookmarkIDs: Set<UUID> = []
    var selectedFolderIDs: Set<UUID> = []

    private let navBar = UIView()
    private var navBarTopConstraint: NSLayoutConstraint!
    private var navBarHeightConstraint: NSLayoutConstraint!
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let searchHeader = LibrarySearchHeaderView(
        frame: CGRect(x: 0, y: 0, width: 0, height: LibrarySearchHeaderView.defaultHeight)
    )
    private var searchQuery: String = ""
    private var searchResults: [Bookmark] = []
    private let searchTuck = LibrarySearchTuckController()

    var effectiveDisplayMode: BookmarksDisplayMode {
        hidesInlineHeaderBar ? displayMode : .large
    }

    var effectiveSortMode: BookmarksSortMode {
        hidesInlineHeaderBar ? sortMode : .none
    }

    var effectiveShowsFoldersOnTop: Bool {
        hidesInlineHeaderBar ? showsFoldersOnTop : true
    }

    var isEditingBookmarks: Bool {
        tableView.isEditing
    }

    var hasSelectedItems: Bool {
        !selectedBookmarkIDs.isEmpty || !selectedFolderIDs.isEmpty
    }

    var hasSelectableItems: Bool {
        if !searchQuery.isEmpty {
            return !searchResults.isEmpty
        }
        return !currentFolders.isEmpty || !currentBookmarks.isEmpty
    }

    var canCreateFolder: Bool {
        !isViewingFavorites && searchQuery.isEmpty
    }

    var isAtRoot: Bool {
        folderStack.isEmpty && !isViewingFavorites
    }

    var currentNavigationTitle: String {
        if isViewingFavorites {
            return "Favorites"
        }
        return folderStack.last?.title ?? "Bookmarks"
    }

    var backNavigationAccessibilityLabel: String {
        backButton.accessibilityLabel ?? "Back to Bookmarks"
    }

    func setHeaderBarHidden(_ hidden: Bool) {
        let changed = hidesInlineHeaderBar != hidden
        hidesInlineHeaderBar = hidden
        if !hidden, isSelectionMode {
            isSelectionMode = false
            selectedBookmarkIDs.removeAll()
            selectedFolderIDs.removeAll()
        }
        navBar.isHidden = hidden
        navBarTopConstraint.constant = hidden ? 0 : 4
        navBarHeightConstraint.constant = hidden ? 0 : 40
        if changed {
            reload()
        } else {
            tableView.reloadData()
        }
    }

    func popNavigation() {
        popFolder()
    }

    enum Section: Equatable {
        case searchResults
        case pinnedFavorites
        case folders
        case bookmarks
        case combinedItems
    }

    init(bookmarkStore: BookmarkStore, defaults: UserDefaults = .standard) {
        self.bookmarkStore = bookmarkStore
        self.defaults = defaults
        self.displayMode = Self.storedDisplayMode(defaults: defaults)
        self.sortMode = Self.storedSortMode(defaults: defaults)
        self.showsFoldersOnTop = Self.storedShowsFoldersOnTop(defaults: defaults)
        super.init(frame: .zero)
        setup()
        reload()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        favoritesCount = bookmarkStore.fetchFavorites().count
        let activeSort = effectiveSortMode

        if isViewingFavorites {
            currentFolders = []
            currentBookmarks = Self.sortedBookmarks(bookmarkStore.fetchFavorites(), by: activeSort)
            combinedEntries = []
            folderItemCounts = [:]
            backButton.isHidden = false
            backButton.setTitle(" Bookmarks", for: .normal)
            backButton.accessibilityLabel = "Back to Bookmarks"
            titleLabel.text = "Favorites"
        } else {
            let currentParentID = folderStack.last?.id
            let rawFolders = bookmarkStore.fetchFolders(parentId: currentParentID)
            let rawBookmarks = bookmarkStore.fetchBookmarks(folderId: currentParentID)
            var counts: [UUID: Int] = [:]
            for folder in rawFolders {
                counts[folder.id] = bookmarkStore.fetchFolders(parentId: folder.id).count
                    + bookmarkStore.fetchBookmarks(folderId: folder.id).count
            }
            folderItemCounts = counts
            currentFolders = Self.sortedFolders(rawFolders, by: activeSort)
            currentBookmarks = Self.sortedBookmarks(rawBookmarks, by: activeSort)
            combinedEntries = effectiveShowsFoldersOnTop
                ? []
                : Self.mergedEntries(folders: currentFolders, bookmarks: currentBookmarks, sortMode: activeSort)

            let isRoot = folderStack.isEmpty
            backButton.isHidden = isRoot
            if let parent = folderStack.dropLast().last {
                backButton.setTitle(" \(parent.title)", for: .normal)
                backButton.accessibilityLabel = "Back to \(parent.title)"
            } else {
                backButton.setTitle(" Bookmarks", for: .normal)
                backButton.accessibilityLabel = "Back to Bookmarks"
            }
            titleLabel.text = folderStack.last?.title ?? "Bookmarks"
        }

        if !searchQuery.isEmpty {
            let matches = bookmarkStore.fetchAll().filter {
                $0.title.localizedCaseInsensitiveContains(searchQuery) ||
                    $0.url.absoluteString.localizedCaseInsensitiveContains(searchQuery)
            }
            searchResults = Self.sortedBookmarks(matches, by: activeSort)
        }

        let validBookmarkIDs = Set((searchQuery.isEmpty ? currentBookmarks : searchResults).map(\.id))
        let validFolderIDs = Set(currentFolders.map(\.id))
        selectedBookmarkIDs.formIntersection(validBookmarkIDs)
        selectedFolderIDs.formIntersection(validFolderIDs)
        if !hasSelectableItems, isSelectionMode {
            isSelectionMode = false
        }

        tableView.reloadData()
        reassertSearchTuck()
        onNavigationStateChanged?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutSearchTuck()
    }

    func sectionType(for section: Int) -> Section {
        if !searchQuery.isEmpty {
            return .searchResults
        }
        if isViewingFavorites {
            return .bookmarks
        }
        if !effectiveShowsFoldersOnTop {
            if folderStack.isEmpty {
                return section == 0 ? .pinnedFavorites : .combinedItems
            }
            return .combinedItems
        }
        if folderStack.isEmpty {
            switch section {
            case 0: return .pinnedFavorites
            case 1: return .folders
            default: return .bookmarks
            }
        }
        return section == 0 ? .folders : .bookmarks
    }

    static func clampedMoveTarget(
        source: IndexPath,
        proposed: IndexPath,
        sectionTypeProvider: (Int) -> Section
    ) -> IndexPath {
        if sectionTypeProvider(source.section) == .pinnedFavorites {
            return source
        }
        if proposed.section != source.section {
            return source
        }
        return proposed
    }

    // MARK: - Private

    private func setup() {
        backgroundColor = .clear

        navBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(navBar)

        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.setImage(UIImage(systemName: "chevron.backward"), for: .normal)
        backButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        backButton.titleLabel?.adjustsFontForContentSizeCategory = true
        backButton.addAction(UIAction { [weak self] _ in self?.popFolder() }, for: .touchUpInside)
        navBar.addSubview(backButton)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        navBar.addSubview(titleLabel)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.alwaysBounceVertical = true
        tableView.register(BookmarkRowCell.self, forCellReuseIdentifier: "BookmarkRowCell")
        addSubview(tableView)

        searchTuck.wire(
            header: searchHeader,
            tableView: tableView,
            onQueryChanged: { [weak self] query in
                guard let self else { return }
                self.searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if self.searchQuery.isEmpty {
                    self.searchResults = []
                }
                self.reload()
            },
            onCleared: { [weak self] in
                guard let self else { return }
                self.searchQuery = ""
                self.searchResults = []
                self.reload()
            }
        )

        navBarTopConstraint = navBar.topAnchor.constraint(equalTo: topAnchor, constant: 4)
        navBarHeightConstraint = navBar.heightAnchor.constraint(equalToConstant: 40)

        NSLayoutConstraint.activate([
            navBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            navBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            navBarTopConstraint,
            navBarHeightConstraint,

            backButton.leadingAnchor.constraint(equalTo: navBar.leadingAnchor),
            backButton.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),

            titleLabel.centerXAnchor.constraint(equalTo: navBar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: navBar.centerYAnchor),

            tableView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tableView.topAnchor.constraint(equalTo: navBar.bottomAnchor),
            tableView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func popFolder() {
        isSelectionMode = false
        selectedBookmarkIDs.removeAll()
        selectedFolderIDs.removeAll()
        if isViewingFavorites {
            isViewingFavorites = false
            reload()
            return
        }
        guard !folderStack.isEmpty else { return }
        folderStack.removeLast()
        reload()
    }

    func toggleEditMode() {
        if isSelectionMode {
            isSelectionMode = false
            selectedBookmarkIDs.removeAll()
            selectedFolderIDs.removeAll()
        }
        let editing = !tableView.isEditing
        tableView.setEditing(editing, animated: true)
        tableView.reloadData()
        onNavigationStateChanged?()
    }

    func promptNewFolder() {
        guard !isViewingFavorites,
              let windowScene = window?.windowScene,
              let rootVC = windowScene.windows.first(where: \.isKeyWindow)?.rootViewController
        else {
            return
        }
        var presenter = rootVC
        while let next = presenter.presentedViewController {
            presenter = next
        }

        let alert = UIAlertController(title: "New Folder", message: "Enter a name for this folder.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Folder Name"
            field.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self, let name = alert?.textFields?.first?.text, !name.isEmpty else { return }
            let parentID = self.folderStack.last?.id
            do {
                try self.bookmarkStore.createFolder(title: name, parentId: parentID)
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                    .error("createFolder failed: \(error.localizedDescription, privacy: .public)")
            }
            self.reload()
        })
        presenter.present(alert, animated: true)
    }

    private static func roundedFavicon(for url: URL, size: CGFloat = 26, cornerRadius: CGFloat = 6) -> UIImage {
        let base = FaviconService.shared.cachedFaviconOrMonogram(for: url, size: size)
        let targetSize = CGSize(width: size, height: size)
        return UIGraphicsImageRenderer(size: targetSize).image { _ in
            let rect = CGRect(origin: .zero, size: targetSize)
            UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).addClip()
            base.draw(in: rect)
        }
    }

    private func entryAt(_ indexPath: IndexPath) -> BookmarkListEntry? {
        switch sectionType(for: indexPath.section) {
        case .pinnedFavorites:
            nil
        case .searchResults:
            indexPath.row < searchResults.count ? .bookmark(searchResults[indexPath.row]) : nil
        case .folders:
            indexPath.row < currentFolders.count ? .folder(currentFolders[indexPath.row]) : nil
        case .bookmarks:
            indexPath.row < currentBookmarks.count ? .bookmark(currentBookmarks[indexPath.row]) : nil
        case .combinedItems:
            indexPath.row < combinedEntries.count ? combinedEntries[indexPath.row] : nil
        }
    }

    func visibleBookmarkID(at indexPath: IndexPath) -> UUID? {
        guard case let .bookmark(bookmark) = entryAt(indexPath) else { return nil }
        return bookmark.id
    }

    func visibleFolderID(at indexPath: IndexPath) -> UUID? {
        guard case let .folder(folder) = entryAt(indexPath) else { return nil }
        return folder.id
    }

    private func configureRegularCell(_ cell: UITableViewCell, at indexPath: IndexPath) {
        let verticalPadding: CGFloat = effectiveDisplayMode == .large ? 12 : 9
        let type = sectionType(for: indexPath.section)
        if type == .pinnedFavorites {
            var content = UIListContentConfiguration.valueCell()
            content.directionalLayoutMargins = NSDirectionalEdgeInsets(
                top: verticalPadding, leading: 16, bottom: verticalPadding, trailing: 16
            )
            content.text = "Favorites"
            content.secondaryText = favoritesCount > 0 ? "\(favoritesCount)" : nil
            content.image = UIImage(systemName: "star.fill")
            content.imageProperties.tintColor = .systemYellow
            cell.contentConfiguration = content
            cell.backgroundColor = .secondarySystemGroupedBackground
            cell.accessoryType = isSelectionMode ? .none : .disclosureIndicator
            (cell as? LibrarySubtitleCell)?.configureSelectionIndicator(visible: false, isSelected: false)
            return
        }

        guard let entry = entryAt(indexPath) else { return }
        let leadingMargin: CGFloat = isSelectionMode ? LibrarySubtitleCell.selectionLeadingInset : 16
        switch entry {
        case let .folder(folder):
            let isSelected = isSelectionMode && selectedFolderIDs.contains(folder.id)
            var content = UIListContentConfiguration.valueCell()
            content.directionalLayoutMargins = NSDirectionalEdgeInsets(
                top: verticalPadding, leading: leadingMargin, bottom: verticalPadding, trailing: 16
            )
            content.text = folder.title
            let itemCount = folderItemCounts[folder.id] ?? 0
            content.secondaryText = itemCount > 0 ? "\(itemCount)" : nil
            content.image = UIImage(systemName: "folder.fill")
            content.imageProperties.tintColor = .systemYellow
            cell.contentConfiguration = content
            cell.backgroundColor = isSelected ? .tertiarySystemGroupedBackground : .secondarySystemGroupedBackground
            cell.accessoryType = isSelectionMode ? .none : .disclosureIndicator
            (cell as? LibrarySubtitleCell)?.configureSelectionIndicator(visible: isSelectionMode, isSelected: isSelected)

        case let .bookmark(bookmark):
            let isSelected = isSelectionMode && selectedBookmarkIDs.contains(bookmark.id)
            let isLarge = effectiveDisplayMode == .large
            var content = isLarge ? UIListContentConfiguration.subtitleCell() : UIListContentConfiguration.cell()
            content.directionalLayoutMargins = NSDirectionalEdgeInsets(
                top: verticalPadding, leading: leadingMargin, bottom: verticalPadding, trailing: 16
            )
            content.text = Self.bookmarkDisplayTitle(bookmark)
            content.textProperties.color = .label
            if isLarge {
                let bodyFont = UIFont.preferredFont(forTextStyle: .body)
                content.textProperties.font = UIFont.systemFont(ofSize: bodyFont.pointSize, weight: .semibold)
                content.textProperties.numberOfLines = 2
                content.textToSecondaryTextVerticalPadding = 3
                content.secondaryText = HostFormatter.host(of: bookmark.url)
                content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
                content.secondaryTextProperties.color = .secondaryLabel
                content.image = Self.roundedFavicon(for: bookmark.url, size: 36, cornerRadius: 8)
            } else {
                content.textProperties.font = .preferredFont(forTextStyle: .body)
                content.textProperties.numberOfLines = 1
                content.image = Self.roundedFavicon(for: bookmark.url, size: 22, cornerRadius: 5)
            }
            cell.contentConfiguration = content
            cell.backgroundColor = isSelected ? .tertiarySystemGroupedBackground : .secondarySystemGroupedBackground
            cell.accessoryType = .none
            (cell as? LibrarySubtitleCell)?.configureSelectionIndicator(visible: isSelectionMode, isSelected: isSelected)
        }
    }

    func presentEditor(for target: BookmarkEditorTarget) {
        onRequestEdit?(target)
    }
}

// MARK: - UITableViewDataSource, UITableViewDelegate

extension BookmarksBrowserView: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in _: UITableView) -> Int {
        if !searchQuery.isEmpty || isViewingFavorites {
            return 1
        }
        if !effectiveShowsFoldersOnTop {
            return folderStack.isEmpty ? 2 : 1
        }
        return folderStack.isEmpty ? 3 : 2
    }

    func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sectionType(for: section) {
        case .searchResults:
            searchResults.count
        case .pinnedFavorites:
            1
        case .folders:
            currentFolders.count
        case .bookmarks:
            currentBookmarks.count
        case .combinedItems:
            combinedEntries.count
        }
    }

    func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch sectionType(for: section) {
        case .searchResults:
            searchResults.isEmpty ? "No Results" : "Search Results"
        case .pinnedFavorites:
            nil
        case .folders:
            currentFolders.isEmpty ? nil : "Folders"
        case .bookmarks:
            currentBookmarks.isEmpty ? nil : "Bookmarks"
        case .combinedItems:
            combinedEntries.isEmpty ? nil : "Bookmarks"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BookmarkRowCell", for: indexPath)
        cell.backgroundColor = .secondarySystemGroupedBackground

        if hidesInlineHeaderBar {
            configureRegularCell(cell, at: indexPath)
            return cell
        }

        (cell as? LibrarySubtitleCell)?.configureSelectionIndicator(visible: false, isSelected: false)
        cell.contentConfiguration = nil
        switch sectionType(for: indexPath.section) {
        case .searchResults, .bookmarks, .combinedItems:
            guard case let .bookmark(bookmark) = entryAt(indexPath) else { return cell }
            cell.textLabel?.text = Self.bookmarkDisplayTitle(bookmark)
            cell.detailTextLabel?.text = HostFormatter.host(of: bookmark.url)
            cell.imageView?.image = UIImage(systemName: bookmark.isFavorite ? "star.fill" : "bookmark.fill")
            cell.imageView?.tintColor = bookmark.isFavorite ? .systemOrange : .systemBlue
            cell.accessoryType = .none

        case .pinnedFavorites:
            cell.textLabel?.text = "Favorites"
            cell.imageView?.image = UIImage(systemName: "star.fill")
            cell.imageView?.tintColor = .systemYellow
            cell.accessoryType = .disclosureIndicator
            cell.detailTextLabel?.text = nil

        case .folders:
            let folder = currentFolders[indexPath.row]
            cell.textLabel?.text = folder.title
            cell.imageView?.image = UIImage(systemName: "folder.fill")
            cell.imageView?.tintColor = .systemYellow
            cell.accessoryType = .disclosureIndicator
            cell.detailTextLabel?.text = nil
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let type = sectionType(for: indexPath.section)
        if type == .pinnedFavorites {
            guard !tableView.isEditing, !isSelectionMode else { return }
            isViewingFavorites = true
            reload()
            return
        }

        guard let entry = entryAt(indexPath) else { return }
        if isSelectionMode {
            switch entry {
            case let .folder(folder):
                if selectedFolderIDs.contains(folder.id) {
                    selectedFolderIDs.remove(folder.id)
                } else {
                    selectedFolderIDs.insert(folder.id)
                }
            case let .bookmark(bookmark):
                if selectedBookmarkIDs.contains(bookmark.id) {
                    selectedBookmarkIDs.remove(bookmark.id)
                } else {
                    selectedBookmarkIDs.insert(bookmark.id)
                }
            }
            tableView.reloadRows(at: [indexPath], with: .none)
            onNavigationStateChanged?()
            return
        }

        switch entry {
        case let .folder(folder):
            if tableView.isEditing {
                presentEditor(for: .editFolder(folder))
            } else {
                folderStack.append(folder)
                reload()
            }
        case let .bookmark(bookmark):
            if tableView.isEditing {
                presentEditor(for: .editBookmark(bookmark))
            } else {
                onOpenURL?(bookmark.url)
            }
        }
    }

    func tableView(_: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        guard !isSelectionMode else { return false }
        let type = sectionType(for: indexPath.section)
        return type != .pinnedFavorites && type != .searchResults
    }

    func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard !isSelectionMode, let entry = entryAt(indexPath) else { return nil }

        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            do {
                switch entry {
                case let .folder(folder):
                    try self.bookmarkStore.deleteFolder(id: folder.id)
                case let .bookmark(bookmark):
                    try self.bookmarkStore.delete(id: bookmark.id)
                    self.searchResults.removeAll { $0.id == bookmark.id }
                }
                self.reload()
                self.onDidMutateBookmarks?()
                completion(true)
            } catch {
                completion(false)
            }
        }
        deleteAction.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }

    func tableView(_: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        guard !isSelectionMode, effectiveSortMode == .none, effectiveShowsFoldersOnTop else { return false }
        let type = sectionType(for: indexPath.section)
        return type == .folders || type == .bookmarks
    }

    func tableView(
        _: UITableView,
        targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath,
        toProposedIndexPath proposedDestinationIndexPath: IndexPath
    ) -> IndexPath {
        Self.clampedMoveTarget(
            source: sourceIndexPath,
            proposed: proposedDestinationIndexPath,
            sectionTypeProvider: { [weak self] in self?.sectionType(for: $0) ?? .bookmarks }
        )
    }

    func tableView(_: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let type = sectionType(for: sourceIndexPath.section)
        guard destinationIndexPath.section == sourceIndexPath.section else { return }

        if type == .folders {
            var updated = currentFolders
            let item = updated.remove(at: sourceIndexPath.row)
            updated.insert(item, at: destinationIndexPath.row)
            currentFolders = updated
            do {
                try bookmarkStore.reorderFolders(updated.map(\.id))
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                    .error("reorderFolders failed: \(error.localizedDescription, privacy: .public)")
            }
        } else if type == .bookmarks {
            var updated = currentBookmarks
            let item = updated.remove(at: sourceIndexPath.row)
            updated.insert(item, at: destinationIndexPath.row)
            currentBookmarks = updated
            do {
                try bookmarkStore.reorderBookmarks(updated.map(\.id))
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                    .error("reorderBookmarks failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func tableView(
        _: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard !isSelectionMode, let entry = entryAt(indexPath) else { return nil }
        let isSearchResult = sectionType(for: indexPath.section) == .searchResults
        switch entry {
        case let .folder(folder):
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                let editAction = UIAction(
                    title: "Edit…",
                    image: UIImage(systemName: "pencil")
                ) { _ in
                    self?.presentEditor(for: .editFolder(folder))
                }
                let deleteAction = UIAction(
                    title: "Delete",
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    do {
                        try self?.bookmarkStore.deleteFolder(id: folder.id)
                        self?.reload()
                        self?.onDidMutateBookmarks?()
                    } catch {
                        Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                            .error("deleteFolder failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
                return UIMenu(children: [editAction, deleteAction])
            }

        case let .bookmark(bookmark):
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                let openAction = UIAction(
                    title: "Open",
                    image: UIImage(systemName: "safari")
                ) { _ in
                    self?.onOpenURL?(bookmark.url)
                }
                let openNewTabAction = UIAction(
                    title: "Open in New Tab",
                    image: UIImage(systemName: "plus.square")
                ) { _ in
                    self?.onOpenInNewTab?(bookmark.url)
                }
                let copyAction = UIAction(
                    title: "Copy Link",
                    image: UIImage(systemName: "doc.on.doc")
                ) { _ in
                    UIPasteboard.general.url = bookmark.url
                }
                let editAction = UIAction(
                    title: "Edit…",
                    image: UIImage(systemName: "pencil")
                ) { _ in
                    self?.presentEditor(for: .editBookmark(bookmark))
                }
                let deleteAction = UIAction(
                    title: "Delete",
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    do {
                        try self?.bookmarkStore.delete(id: bookmark.id)
                        self?.searchResults.removeAll { $0.id == bookmark.id }
                        self?.reload()
                        self?.onDidMutateBookmarks?()
                    } catch {
                        Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                            .error("deleteBookmark failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
                var actions = [openAction, openNewTabAction, copyAction]
                if !isSearchResult {
                    actions.append(editAction)
                }
                actions.append(deleteAction)
                return UIMenu(children: actions)
            }
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        handleTuckScroll(scrollView)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate: Bool) {
        handleTuckEndDragging(scrollView, willDecelerate: willDecelerate)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        handleTuckEndDecelerating(scrollView)
    }
}

// MARK: - LibrarySearchTuckable

extension BookmarksBrowserView: LibrarySearchTuckable {
    var tuckController: LibrarySearchTuckController {
        searchTuck
    }

    var tuckTableView: UITableView {
        tableView
    }

    var tuckSearchHeader: LibrarySearchHeaderView {
        searchHeader
    }

    var isTuckFiltering: Bool {
        !searchQuery.isEmpty
    }
}
