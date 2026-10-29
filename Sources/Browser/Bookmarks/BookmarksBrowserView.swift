//
//  BookmarksBrowserView.swift
//  OuterView
//

import os
import SwiftUI
import UIKit

/// Subtitle-style cell so dequeued reuse keeps its detail label.
@MainActor
final class BookmarkRowCell: UITableViewCell {
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

    private let bookmarkStore: BookmarkStore
    private var folderStack: [BookmarkFolder] = []
    private var isViewingFavorites: Bool = false
    private var currentFolders: [BookmarkFolder] = []
    private var currentBookmarks: [Bookmark] = []

    private let navBar = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let searchHeader = LibrarySearchHeaderView(
        frame: CGRect(x: 0, y: 0, width: 0, height: LibrarySearchHeaderView.defaultHeight)
    )
    private var searchQuery: String = ""
    private var searchResults: [Bookmark] = []
    private let searchTuck = LibrarySearchTuckController()

    var isEditingBookmarks: Bool {
        tableView.isEditing
    }

    var canCreateFolder: Bool {
        !isViewingFavorites && searchQuery.isEmpty
    }

    enum Section: Equatable {
        case searchResults
        case pinnedFavorites
        case folders
        case bookmarks
    }

    init(bookmarkStore: BookmarkStore) {
        self.bookmarkStore = bookmarkStore
        super.init(frame: .zero)
        setup()
        reload()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        if isViewingFavorites {
            currentFolders = []
            currentBookmarks = bookmarkStore.fetchFavorites()
            backButton.isHidden = false
            backButton.setTitle(" Bookmarks", for: .normal)
            backButton.accessibilityLabel = "Back to Bookmarks"
            titleLabel.text = "Favorites"
        } else {
            let currentParentID = folderStack.last?.id
            currentFolders = bookmarkStore.fetchFolders(parentId: currentParentID)
            currentBookmarks = bookmarkStore.fetchBookmarks(folderId: currentParentID)

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
        tableView.reloadData()
        reassertSearchTuck()
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
        } else if folderStack.isEmpty {
            switch section {
            case 0: return .pinnedFavorites
            case 1: return .folders
            default: return .bookmarks
            }
        } else {
            return section == 0 ? .folders : .bookmarks
        }
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
                if !self.searchQuery.isEmpty {
                    self.searchResults = self.bookmarkStore.fetchAll().filter {
                        $0.title.localizedCaseInsensitiveContains(self.searchQuery) ||
                            $0.url.absoluteString.localizedCaseInsensitiveContains(self.searchQuery)
                    }
                } else {
                    self.searchResults = []
                }
                self.tableView.reloadData()
                self.reassertSearchTuck()
            },
            onCleared: { [weak self] in
                guard let self else { return }
                self.searchQuery = ""
                self.searchResults = []
                self.tableView.reloadData()
                self.reassertSearchTuck()
            }
        )

        NSLayoutConstraint.activate([
            navBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            navBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            navBar.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            navBar.heightAnchor.constraint(equalToConstant: 40),

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
        let editing = !tableView.isEditing
        tableView.setEditing(editing, animated: true)
    }

    func promptNewFolder() {
        guard !isViewingFavorites,
              let windowScene = window?.windowScene,
              let rootVC = windowScene.windows.first(where: \.isKeyWindow)?.rootViewController
        else {
            return
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
        rootVC.present(alert, animated: true)
    }

    func presentEditor(for target: BookmarkEditorTarget) {
        onRequestEdit?(target)
    }
}

// MARK: - UITableViewDataSource, UITableViewDelegate

extension BookmarksBrowserView: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in _: UITableView) -> Int {
        if !searchQuery.isEmpty {
            return 1
        }
        if isViewingFavorites {
            return 1
        } else if folderStack.isEmpty {
            return 3
        } else {
            return 2
        }
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
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "BookmarkRowCell", for: indexPath)
        cell.backgroundColor = .secondarySystemGroupedBackground

        switch sectionType(for: indexPath.section) {
        case .searchResults:
            let bookmark = searchResults[indexPath.row]
            cell.textLabel?.text = bookmark.title.isEmpty ? HostFormatter.host(of: bookmark.url) : bookmark.title
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

        case .bookmarks:
            let bookmark = currentBookmarks[indexPath.row]
            cell.textLabel?.text = bookmark.title.isEmpty ? HostFormatter.host(of: bookmark.url) : bookmark.title
            cell.detailTextLabel?.text = HostFormatter.host(of: bookmark.url)
            cell.imageView?.image = UIImage(systemName: bookmark.isFavorite ? "star.fill" : "bookmark.fill")
            cell.imageView?.tintColor = bookmark.isFavorite ? .systemOrange : .systemBlue
            cell.accessoryType = .none
        }

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let type = sectionType(for: indexPath.section)

        switch type {
        case .searchResults:
            let bookmark = searchResults[indexPath.row]
            if tableView.isEditing {
                presentEditor(for: .editBookmark(bookmark))
            } else {
                onOpenURL?(bookmark.url)
            }

        case .pinnedFavorites:
            guard !tableView.isEditing else { return }
            isViewingFavorites = true
            reload()

        case .folders:
            let folder = currentFolders[indexPath.row]
            if tableView.isEditing {
                presentEditor(for: .editFolder(folder))
            } else {
                folderStack.append(folder)
                reload()
            }

        case .bookmarks:
            let bookmark = currentBookmarks[indexPath.row]
            if tableView.isEditing {
                presentEditor(for: .editBookmark(bookmark))
            } else {
                onOpenURL?(bookmark.url)
            }
        }
    }

    func tableView(_: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        let type = sectionType(for: indexPath.section)
        return type != .pinnedFavorites && type != .searchResults
    }

    func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let type = sectionType(for: indexPath.section)
        guard type != .pinnedFavorites else { return nil }

        let deleteAction = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            do {
                if type == .searchResults {
                    let bookmark = self.searchResults[indexPath.row]
                    try self.bookmarkStore.delete(id: bookmark.id)
                    self.searchResults.remove(at: indexPath.row)
                } else if type == .folders {
                    let folder = self.currentFolders[indexPath.row]
                    try self.bookmarkStore.deleteFolder(id: folder.id)
                } else {
                    let bookmark = self.currentBookmarks[indexPath.row]
                    try self.bookmarkStore.delete(id: bookmark.id)
                }
                self.reload()
                completion(true)
            } catch {
                completion(false)
            }
        }
        deleteAction.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }

    func tableView(_: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        let type = sectionType(for: indexPath.section)
        return type != .pinnedFavorites && type != .searchResults
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
        let type = sectionType(for: indexPath.section)
        switch type {
        case .pinnedFavorites:
            return nil

        case .searchResults:
            guard indexPath.row < searchResults.count else { return nil }
            let bookmark = searchResults[indexPath.row]
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
                let deleteAction = UIAction(
                    title: "Delete",
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    do {
                        try self?.bookmarkStore.delete(id: bookmark.id)
                        self?.searchResults.removeAll(where: { $0.id == bookmark.id })
                        self?.reload()
                    } catch {
                        Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                            .error("deleteBookmark failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
                return UIMenu(children: [openAction, openNewTabAction, copyAction, deleteAction])
            }

        case .folders:
            guard indexPath.row < currentFolders.count else { return nil }
            let folder = currentFolders[indexPath.row]
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
                    } catch {
                        Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                            .error("deleteFolder failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
                return UIMenu(children: [editAction, deleteAction])
            }

        case .bookmarks:
            guard indexPath.row < currentBookmarks.count else { return nil }
            let bookmark = currentBookmarks[indexPath.row]
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
                        self?.reload()
                    } catch {
                        Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                            .error("deleteBookmark failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
                return UIMenu(children: [openAction, openNewTabAction, copyAction, editAction, deleteAction])
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
