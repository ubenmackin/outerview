//
//  BookmarksLibraryView.swift
//  OuterView
//

import os
import UIKit

/// Full-screen overlay for Bookmarks, Favorites, History, and Reading List library (matching Safari).
/// UserDefaults keys libraryTab as Int, overviewMode as String, and overviewGroup as String.
/// Values are read at init and setup and written on every change; private mode is never
/// written and restores as standard. Unparseable values fall back to bookmarks, standard,
/// and nil; a stored group id resolving to no existing group restores as nil.
@MainActor
final class BookmarksLibraryView: UIView, ChromePlacementDriven {
    nonisolated static let libraryTabDefaultsKey = "libraryTab"

    nonisolated static func storedTab(defaults: UserDefaults = .standard) -> LibraryTab {
        LibraryTabBar.storedTab(defaults: defaults)
    }

    nonisolated static func persist(tab: LibraryTab, defaults: UserDefaults = .standard) {
        LibraryTabBar.persist(tab: tab, defaults: defaults)
    }

    var onOpenURL: ((URL) -> Void)?
    var onOpenInNewTab: ((URL) -> Void)?
    var onRequestEdit: ((BookmarkEditorTarget) -> Void)?
    var onDone: (() -> Void)?
    var onTabChanged: ((LibraryTab) -> Void)?
    var onInlineAddFolder: (() -> Void)?
    var onInlineToggleEdit: (() -> Void)?
    var onInlineClearHistory: (() -> Void)?
    var onInlineDelete: (() -> Void)?
    var inlineMenu: UIMenu?
    var onInlineDone: (() -> Void)?

    var chromePlacement: ChromePlacement = .compact {
        didSet {
            if oldValue != chromePlacement {
                applyPlacement()
            }
        }
    }

    private let doneButton = UIButton(type: .system)
    private let addButton = UIButton(type: .system)
    private let editButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let menuButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let inlineStack = UIStackView()
    private var topBarTrailingToHeader: NSLayoutConstraint?
    private var topBarTrailingToStack: NSLayoutConstraint?
    private var stackTrailingToDone: NSLayoutConstraint?
    private var inlineStackCompactTrailing: NSLayoutConstraint?
    private var inlineStackCompactWidth: NSLayoutConstraint?

    var isDoneVisible: Bool {
        !doneButton.isHidden
    }

    var isInlineAddVisible: Bool {
        !addButton.isHidden
    }

    var isInlineEditVisible: Bool {
        !editButton.isHidden
    }

    var isInlineClearVisible: Bool {
        !clearButton.isHidden
    }

    var isInlineMenuVisible: Bool {
        !menuButton.isHidden
    }

    var isInlineDeleteVisible: Bool {
        !deleteButton.isHidden
    }

    var isInlineClearEnabled: Bool {
        clearButton.isEnabled
    }

    var isInlineDeleteEnabled: Bool {
        deleteButton.isEnabled
    }

    var inlineEditAccessibilityLabel: String? {
        editButton.accessibilityLabel
    }

    func performDone() {
        doneButton.sendActions(for: .touchUpInside)
    }

    func performInlineAdd() {
        addButton.sendActions(for: .touchUpInside)
    }

    func performInlineToggleEdit() {
        editButton.sendActions(for: .touchUpInside)
    }

    func performInlineClear() {
        clearButton.sendActions(for: .touchUpInside)
    }

    func performInlineDelete() {
        deleteButton.sendActions(for: .touchUpInside)
    }

    func performInlineDone() {
        performDone()
    }

    private let headerContainer = UIView()
    private let topTabBar: LibraryTabBar
    private let defaults: UserDefaults

    private let contentContainer = UIView()
    private var bookmarksBrowserView: BookmarksBrowserView?
    private var favoritesGridView: FavoritesGridView?
    private var historyListView: HistoryListView?
    private var readingListView: ReadingListView?

    private var activeTab: LibraryTab = .bookmarks

    var currentTab: LibraryTab {
        activeTab
    }

    var isEditingBookmarks: Bool {
        bookmarksBrowserView?.isEditingBookmarks ?? false
    }

    var canClearHistory: Bool {
        historyListView?.canClearHistory ?? false
    }

    var isReadingListInSelectionMode: Bool {
        readingListView?.isSelectionMode ?? false
    }

    var canDeleteReadingListSelection: Bool {
        readingListView?.hasSelectedItems ?? false
    }

    var onReadingListStateChanged: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.topTabBar = LibraryTabBar(defaults: defaults)
        self.activeTab = Self.storedTab(defaults: defaults)
        super.init(frame: .zero)
        setup()
        topTabBar.selectTab(activeTab, notify: false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureStores(
        bookmarkStore: BookmarkStore,
        historyStore: HistoryStore,
        readingListStore: ReadingListStore
    ) {
        let bookView = BookmarksBrowserView(bookmarkStore: bookmarkStore)
        bookView.onOpenURL = { [weak self] url in
            self?.onOpenURL?(url)
        }
        bookView.onOpenInNewTab = { [weak self] url in
            self?.onOpenInNewTab?(url)
        }
        bookView.onRequestEdit = { [weak self] target in
            self?.onRequestEdit?(target)
        }
        self.bookmarksBrowserView = bookView

        let favView = FavoritesGridView(bookmarkStore: bookmarkStore)
        favView.onOpenURL = { [weak self] url in
            self?.onOpenURL?(url)
        }
        favView.onDeleteFavorite = { [weak self] id in
            do {
                try bookmarkStore.delete(id: id)
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                    .error("deleteFavorite failed: \(error.localizedDescription, privacy: .public)")
            }
            self?.favoritesGridView?.reload()
        }
        self.favoritesGridView = favView

        let histView = HistoryListView(historyStore: historyStore)
        histView.onOpenURL = { [weak self] url in
            self?.onOpenURL?(url)
        }
        self.historyListView = histView

        let readingView = ReadingListView(store: readingListStore)
        readingView.onOpenURL = { [weak self] url in
            self?.onOpenURL?(url)
        }
        readingView.onStateChanged = { [weak self] in
            guard let self else { return }
            self.inlineMenu = self.makeReadingListMenu()
            self.updateInlineCommands()
            self.onReadingListStateChanged?()
        }
        readingView.onSelectionModeChanged = { [weak self] _ in
            guard let self else { return }
            self.inlineMenu = self.makeReadingListMenu()
            self.updateInlineCommands()
            self.onReadingListStateChanged?()
        }
        self.readingListView = readingView

        setupContentSubviews()
        updateVisibleTab()
    }

    func open(tab: LibraryTab = .bookmarks) {
        activeTab = tab
        Self.persist(tab: tab, defaults: defaults)
        topTabBar.selectTab(tab, notify: false)
        reload()
        updateVisibleTab()
        onTabChanged?(tab)
    }

    func reload() {
        bookmarksBrowserView?.reload()
        favoritesGridView?.reload()
        historyListView?.reload()
        readingListView?.reload()
        updateInlineCommands()
    }

    func promptNewFolder() {
        bookmarksBrowserView?.promptNewFolder()
    }

    func toggleBookmarksEdit() {
        guard let bookmarksBrowserView else { return }
        bookmarksBrowserView.toggleEditMode()
        updateInlineCommands()
    }

    func promptClearHistory() {
        historyListView?.promptClearHistory()
    }

    func makeReadingListMenu() -> UIMenu? {
        readingListView?.makeMenu()
    }

    func exitReadingListSelectionMode() {
        readingListView?.exitSelectionMode()
        inlineMenu = makeReadingListMenu()
        updateInlineCommands()
    }

    func enterReadingListSelectionMode() {
        readingListView?.enterSelectionMode()
        updateInlineCommands()
    }

    func deleteReadingListSelectedItems() {
        readingListView?.deleteSelectedItems()
        updateInlineCommands()
    }

    func applyPlacement() {
        let isRegular = chromePlacement == .regular
        doneButton.isHidden = !isRegular
        topBarTrailingToHeader?.isActive = !isRegular
        topBarTrailingToStack?.isActive = isRegular
        stackTrailingToDone?.isActive = isRegular
        inlineStackCompactTrailing?.isActive = !isRegular
        inlineStackCompactWidth?.isActive = !isRegular
        updateInlineCommands()
    }

    func updateInlineCommands() {
        let isRegular = chromePlacement == .regular
        guard isRegular else {
            addButton.isHidden = true
            editButton.isHidden = true
            clearButton.isHidden = true
            menuButton.isHidden = true
            deleteButton.isHidden = true
            inlineStack.isHidden = true
            return
        }
        let menu = makeReadingListMenu()
        inlineMenu = menu
        inlineStack.isHidden = false
        let commands = LibraryTabCommands.make(
            for: activeTab,
            isEditingBookmarks: isEditingBookmarks,
            canClearHistory: canClearHistory,
            isInSelection: activeTab == .readingList && isReadingListInSelectionMode,
            canDeleteSelection: canDeleteReadingListSelection,
            hasReadingListMenu: menu != nil
        )
        addButton.isHidden = !commands.showsAdd
        editButton.isHidden = !commands.showsEdit
        clearButton.isHidden = !commands.showsClear
        menuButton.isHidden = !commands.showsMenu
        deleteButton.isHidden = !commands.showsDelete
        if commands.showsEdit {
            editButton.setTitle(commands.isEditingBookmarks ? "Done" : "Edit", for: .normal)
            editButton.accessibilityLabel = commands.isEditingBookmarks ? "Done Editing" : "Edit Bookmarks"
        }
        if commands.showsClear {
            clearButton.isEnabled = commands.canClearHistory
        }
        if commands.showsMenu {
            menuButton.menu = menu
        }
        if commands.showsDelete {
            deleteButton.isEnabled = commands.canDeleteSelection
        }
    }

    // MARK: - Private

    private func setup() {
        backgroundColor = .systemBackground

        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerContainer)

        topTabBar.translatesAutoresizingMaskIntoConstraints = false
        topTabBar.onTabSelected = { [weak self] tab in
            guard let self else { return }
            self.activeTab = tab
            Self.persist(tab: tab, defaults: self.defaults)
            self.updateVisibleTab()
            self.onTabChanged?(tab)
        }
        headerContainer.addSubview(topTabBar)

        setupActionButtons()
        setupContainersAndConstraints()
        topBarTrailingToHeader?.isActive = true
        applyPlacement()
    }

    private func setupActionButtons() {
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.setTitle("Add", for: .normal)
        addButton.accessibilityLabel = "New Folder"
        addButton.addAction(UIAction { [weak self] _ in
            if let callback = self?.onInlineAddFolder {
                callback()
            } else {
                self?.promptNewFolder()
            }
        }, for: .touchUpInside)

        editButton.translatesAutoresizingMaskIntoConstraints = false
        editButton.setTitle("Edit", for: .normal)
        editButton.accessibilityLabel = "Edit Bookmarks"
        editButton.addAction(UIAction { [weak self] _ in
            if let callback = self?.onInlineToggleEdit {
                callback()
            } else {
                self?.toggleBookmarksEdit()
            }
        }, for: .touchUpInside)

        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.setTitle("Clear", for: .normal)
        clearButton.accessibilityLabel = "Clear History"
        clearButton.addAction(UIAction { [weak self] _ in
            if let callback = self?.onInlineClearHistory {
                callback()
            } else {
                self?.promptClearHistory()
            }
        }, for: .touchUpInside)

        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        menuButton.accessibilityLabel = "Reading List Options"
        menuButton.showsMenuAsPrimaryAction = true

        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.setImage(UIImage(systemName: "trash"), for: .normal)
        deleteButton.accessibilityLabel = "Delete Selected"
        deleteButton.addAction(UIAction { [weak self] _ in
            if let callback = self?.onInlineDelete {
                callback()
            } else {
                self?.deleteReadingListSelectedItems()
            }
        }, for: .touchUpInside)

        inlineStack.translatesAutoresizingMaskIntoConstraints = false
        inlineStack.axis = .horizontal
        inlineStack.alignment = .center
        inlineStack.spacing = 8
        inlineStack.addArrangedSubview(addButton)
        inlineStack.addArrangedSubview(editButton)
        inlineStack.addArrangedSubview(clearButton)
        inlineStack.addArrangedSubview(menuButton)
        inlineStack.addArrangedSubview(deleteButton)
        headerContainer.addSubview(inlineStack)

        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.setTitle("Done", for: .normal)
        doneButton.accessibilityLabel = "Done"
        doneButton.isHidden = true
        doneButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            let commands = LibraryTabCommands.make(
                for: self.activeTab,
                isEditingBookmarks: self.isEditingBookmarks,
                canClearHistory: self.canClearHistory,
                isInSelection: self.activeTab == .readingList && self.isReadingListInSelectionMode,
                canDeleteSelection: self.canDeleteReadingListSelection,
                hasReadingListMenu: self.inlineMenu != nil || self.makeReadingListMenu() != nil
            )
            if commands.doneExitsSelection {
                self.exitReadingListSelectionMode()
                return
            }
            if let inlineDone = self.onInlineDone {
                inlineDone()
            } else {
                self.onDone?()
            }
        }, for: .touchUpInside)
        headerContainer.addSubview(doneButton)
    }

    private func setupContainersAndConstraints() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentContainer)

        topBarTrailingToHeader = topTabBar.trailingAnchor.constraint(
            equalTo: headerContainer.trailingAnchor, constant: -16
        )
        topBarTrailingToStack = topTabBar.trailingAnchor.constraint(
            equalTo: inlineStack.leadingAnchor, constant: -8
        )
        stackTrailingToDone = inlineStack.trailingAnchor.constraint(
            equalTo: doneButton.leadingAnchor, constant: -8
        )
        // Compact fallback: the stack is hidden but must keep a defined
        // horizontal position. Pinning trailing plus a zero width collapses it
        // without ambiguity while the regular chain is deactivated.
        inlineStackCompactTrailing = inlineStack.trailingAnchor.constraint(
            equalTo: headerContainer.trailingAnchor, constant: -16
        )
        inlineStackCompactWidth = inlineStack.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            headerContainer.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            headerContainer.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 4),
            headerContainer.heightAnchor.constraint(equalToConstant: 48),

            topTabBar.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 16),
            topTabBar.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            topTabBar.heightAnchor.constraint(equalToConstant: 40),

            inlineStack.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),

            doneButton.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -16),
            doneButton.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),

            contentContainer.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func setupContentSubviews() {
        if let book = bookmarksBrowserView {
            book.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(book)
            pin(book, inside: contentContainer)
        }
        if let fav = favoritesGridView {
            fav.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(fav)
            pin(fav, inside: contentContainer)
        }
        if let hist = historyListView {
            hist.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(hist)
            pin(hist, inside: contentContainer)
        }
        if let reading = readingListView {
            reading.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(reading)
            pin(reading, inside: contentContainer)
        }
    }

    private func pin(_ view: UIView, inside parent: UIView) {
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            view.topAnchor.constraint(equalTo: parent.topAnchor),
            view.bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
    }

    private func updateVisibleTab() {
        bookmarksBrowserView?.isHidden = (activeTab != .bookmarks)
        favoritesGridView?.isHidden = (activeTab != .favorites)
        historyListView?.isHidden = (activeTab != .history)
        readingListView?.isHidden = (activeTab != .readingList)
        updateInlineCommands()
        reassertVisibleSearchTuck()
    }

    private func reassertVisibleSearchTuck() {
        switch activeTab {
        case .bookmarks:
            bookmarksBrowserView?.reassertSearchTuck()
        case .history:
            historyListView?.reassertSearchTuck()
        case .readingList:
            readingListView?.reassertSearchTuck()
        case .favorites:
            break
        }
    }
}
