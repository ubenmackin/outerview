// Bookmarks — Hierarchical browser plus folder menus.

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
    var tabGroupsProvider: (() -> [TabGroup])?
    var onOpenURLsInBackground: (([URL]) -> Void)?
    var onOpenURLsInTabGroup: (([URL], TabGroup) -> Void)?
    var onOpenURLsInNewTabGroup: (([URL], String) -> Void)?

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
        searchQuery.isEmpty
    }

    var isSearching: Bool {
        !searchQuery.isEmpty
    }

    var isAtRoot: Bool {
        folderStack.isEmpty && !isViewingFavorites
    }

    var currentNavigationTitle: String {
        if isViewingFavorites {
            return folderStack.last?.title ?? "Favorites"
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
            let currentParentID = folderStack.last?.id
            let rawFolders = bookmarkStore.fetchFolders(parentId: currentParentID, isFavorite: currentParentID == nil ? true : nil)
            let rawBookmarks = currentParentID == nil
                ? bookmarkStore.fetchFavorites(rootOnly: true)
                : bookmarkStore.fetchBookmarks(folderId: currentParentID)
            folderItemCounts = itemCounts(for: rawFolders)
            currentFolders = Self.sortedFolders(rawFolders, by: activeSort)
            currentBookmarks = Self.sortedBookmarks(rawBookmarks, by: activeSort)
            combinedEntries = effectiveShowsFoldersOnTop
                ? []
                : Self.mergedEntries(folders: currentFolders, bookmarks: currentBookmarks, sortMode: activeSort)

            backButton.isHidden = false
            if folderStack.isEmpty {
                backButton.setTitle(" Bookmarks", for: .normal)
                backButton.accessibilityLabel = "Back to Bookmarks"
                titleLabel.text = "Favorites"
            } else if let parent = folderStack.dropLast().last {
                backButton.setTitle(" \(parent.title)", for: .normal)
                backButton.accessibilityLabel = "Back to \(parent.title)"
                titleLabel.text = folderStack.last?.title ?? "Favorites"
            } else {
                backButton.setTitle(" Favorites", for: .normal)
                backButton.accessibilityLabel = "Back to Favorites"
                titleLabel.text = folderStack.last?.title ?? "Favorites"
            }
        } else {
            let currentParentID = folderStack.last?.id
            let rawFolders = bookmarkStore.fetchFolders(parentId: currentParentID, isFavorite: currentParentID == nil ? false : nil)
            let rawBookmarks = bookmarkStore.fetchBookmarks(folderId: currentParentID)
            folderItemCounts = itemCounts(for: rawFolders)
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
            if !effectiveShowsFoldersOnTop {
                return .combinedItems
            }
            return section == 0 ? .folders : .bookmarks
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

    private func itemCounts(for folders: [BookmarkFolder]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for folder in folders {
            counts[folder.id] = bookmarkStore.fetchFolders(parentId: folder.id).count
                + bookmarkStore.fetchBookmarks(folderId: folder.id).count
        }
        return counts
    }

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
            if !folderStack.isEmpty {
                folderStack.removeLast()
                reload()
                return
            }
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
        presentTextPrompt(title: "New Folder", message: "Enter a name for this folder.", placeholder: "Folder Name") { [weak self] name in
            guard let self else { return }
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let parentID = self.folderStack.last?.id
            let isFav = self.isViewingFavorites
            do {
                try self.bookmarkStore.createFolder(title: trimmed, parentId: parentID, isFavorite: isFav)
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                    .error("createFolder failed: \(error.localizedDescription, privacy: .public)")
            }
            self.reload()
            self.onDidMutateBookmarks?()
        }
    }

    /// Single alert seam for folder and tab-group prompts.
    private func presentTextPrompt(title: String, message: String, placeholder: String, initialText: String? = nil, onSave: @escaping (String) -> Void) {
        guard let windowScene = window?.windowScene,
              let rootVC = windowScene.windows.first(where: \.isKeyWindow)?.rootViewController
        else {
            return
        }
        var presenter = rootVC
        while let next = presenter.presentedViewController {
            presenter = next
        }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = placeholder
            field.text = initialText
            field.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak alert] _ in
            guard let raw = alert?.textFields?.first?.text, !raw.isEmpty else { return }
            onSave(raw)
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

    private func promptNewTabGroup(for urls: [URL], defaultTitle: String) {
        guard !urls.isEmpty else { return }
        // Prefill truncates to the persisted group cap so the sheet never shows an overlong name.
        let prefill = String(defaultTitle.prefix(TabGroup.maxNameLength))
        presentTextPrompt(title: "New Tab Group", message: "Enter a name for this tab group.", placeholder: "Group Name", initialText: prefill) { [weak self] raw in
            guard let self else { return }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let name = String(trimmed.prefix(TabGroup.maxNameLength))
            self.onOpenURLsInNewTabGroup?(urls, name)
        }
    }
}

// MARK: - UITableViewDataSource, UITableViewDelegate

extension BookmarksBrowserView: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in _: UITableView) -> Int {
        if !searchQuery.isEmpty {
            return 1
        }
        if isViewingFavorites {
            if !effectiveShowsFoldersOnTop {
                return 1
            }
            return 2
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
            currentBookmarks.isEmpty ? nil : (isViewingFavorites ? "Favorites" : "Bookmarks")
        case .combinedItems:
            combinedEntries.isEmpty ? nil : (isViewingFavorites ? "Favorites" : "Bookmarks")
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
                self?.folderContextMenu(for: folder)
            }
        case let .bookmark(bookmark):
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                self?.bookmarkContextMenu(for: bookmark, isSearchResult: isSearchResult)
            }
        }
    }

    private func folderContextMenu(for folder: BookmarkFolder) -> UIMenu? {
        let allBookmarks = bookmarkStore.fetchAllBookmarks(inFolderId: folder.id)
        // Rejected schemes never become tabs; truncated to the live-page cap.
        let urls = Array(allBookmarks.map(\.url).filter { URLNormalizer.isLoadable($0) }.prefix(TabPool.livePageLimit))
        let hasBookmarks = !urls.isEmpty
        let openAction = UIAction(
            title: "Open",
            image: UIImage(systemName: "safari"),
            attributes: hasBookmarks ? [] : [.disabled]
        ) { [weak self] _ in
            guard !urls.isEmpty else { return }
            for url in urls {
                self?.onOpenInNewTab?(url)
            }
        }
        let openBackgroundAction = UIAction(
            title: "Open in Background",
            image: UIImage(systemName: "plus.square.on.square"),
            attributes: hasBookmarks ? [] : [.disabled]
        ) { [weak self] _ in
            guard !urls.isEmpty else { return }
            self?.onOpenURLsInBackground?(urls)
        }
        let tabGroupElement = folderTabGroupElement(for: folder, urls: urls)
        let editAction = UIAction(
            title: "Edit…",
            image: UIImage(systemName: "pencil")
        ) { [weak self] _ in
            self?.presentEditor(for: .editFolder(folder))
        }
        let deleteAction = UIAction(
            title: "Delete",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { [weak self] _ in
            do {
                try self?.bookmarkStore.deleteFolder(id: folder.id)
                self?.reload()
                self?.onDidMutateBookmarks?()
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                    .error("deleteFolder failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return UIMenu(children: [openAction, openBackgroundAction, tabGroupElement, editAction, deleteAction])
    }

    private func folderTabGroupElement(for folder: BookmarkFolder, urls: [URL]) -> UIMenuElement {
        guard !urls.isEmpty else {
            return UIAction(
                title: "Open in Tab Group",
                image: UIImage(systemName: "square.grid.2x2"),
                attributes: [.disabled]
            ) { _ in }
        }
        var groupElements: [UIMenuElement] = []
        let newGroupAction = UIAction(
            title: "New Tab Group…",
            image: UIImage(systemName: "plus")
        ) { [weak self] _ in
            guard !urls.isEmpty else { return }
            let prefill = String(folder.title.prefix(TabGroup.maxNameLength))
            self?.promptNewTabGroup(for: urls, defaultTitle: prefill)
        }
        groupElements.append(newGroupAction)
        let existingGroups = (tabGroupsProvider?() ?? []).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        for group in existingGroups {
            let groupAction = UIAction(
                title: group.name,
                image: UIImage(systemName: "square.on.square")
            ) { [weak self] _ in
                guard !urls.isEmpty else { return }
                self?.onOpenURLsInTabGroup?(urls, group)
            }
            groupElements.append(groupAction)
        }
        return UIMenu(
            title: "Open in Tab Group",
            image: UIImage(systemName: "square.grid.2x2"),
            children: groupElements
        )
    }

    private func bookmarkContextMenu(for bookmark: Bookmark, isSearchResult: Bool) -> UIMenu? {
        let openAction = UIAction(
            title: "Open",
            image: UIImage(systemName: "safari")
        ) { [weak self] _ in
            self?.onOpenURL?(bookmark.url)
        }
        let openNewTabAction = UIAction(
            title: "Open in New Tab",
            image: UIImage(systemName: "plus.square")
        ) { [weak self] _ in
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
        ) { [weak self] _ in
            self?.presentEditor(for: .editBookmark(bookmark))
        }
        let deleteAction = UIAction(
            title: "Delete",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { [weak self] _ in
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
