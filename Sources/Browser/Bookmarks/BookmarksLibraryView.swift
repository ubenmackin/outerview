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

    var chromePlacement: ChromePlacement = .compact {
        didSet {
            if oldValue != chromePlacement {
                applyPlacement()
            }
        }
    }

    private let doneButton = UIButton(type: .system)
    private var topBarTrailingToHeader: NSLayoutConstraint?
    private var topBarTrailingToDone: NSLayoutConstraint?

    /// Read-only Done visibility for tests; the button itself stays private
    /// so owners cannot mutate or hide the inline control.
    var isDoneVisible: Bool {
        !doneButton.isHidden
    }

    /// Behavioural Done activation for tests; wires through the button so
    /// the control wiring stays covered without exposing the button.
    func performDone() {
        doneButton.sendActions(for: .touchUpInside)
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
            self?.onReadingListStateChanged?()
        }
        readingView.onSelectionModeChanged = { [weak self] _ in
            self?.onReadingListStateChanged?()
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
    }

    func promptNewFolder() {
        bookmarksBrowserView?.promptNewFolder()
    }

    func toggleBookmarksEdit() {
        bookmarksBrowserView?.toggleEditMode()
    }

    func promptClearHistory() {
        historyListView?.promptClearHistory()
    }

    func makeReadingListMenu() -> UIMenu? {
        readingListView?.makeMenu()
    }

    func exitReadingListSelectionMode() {
        readingListView?.exitSelectionMode()
    }

    func deleteReadingListSelectedItems() {
        readingListView?.deleteSelectedItems()
    }

    func applyPlacement() {
        let isRegular = chromePlacement == .regular
        doneButton.isHidden = !isRegular
        topBarTrailingToHeader?.isActive = !isRegular
        topBarTrailingToDone?.isActive = isRegular
    }

    // MARK: - Private

    private func setup() {
        backgroundColor = .systemBackground

        // Header container (safeArea protected)
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

        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.setTitle("Done", for: .normal)
        doneButton.accessibilityLabel = "Done"
        doneButton.isHidden = true
        doneButton.addAction(UIAction { [weak self] _ in self?.onDone?() }, for: .touchUpInside)
        headerContainer.addSubview(doneButton)

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentContainer)

        topBarTrailingToHeader = topTabBar.trailingAnchor.constraint(
            equalTo: headerContainer.trailingAnchor, constant: -16
        )
        topBarTrailingToDone = topTabBar.trailingAnchor.constraint(
            equalTo: doneButton.leadingAnchor, constant: -8
        )

        NSLayoutConstraint.activate([
            headerContainer.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            headerContainer.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 4),
            headerContainer.heightAnchor.constraint(equalToConstant: 48),

            topTabBar.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor, constant: 16),
            topTabBar.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            topTabBar.heightAnchor.constraint(equalToConstant: 40),

            doneButton.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor, constant: -16),
            doneButton.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),

            contentContainer.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        topBarTrailingToHeader?.isActive = true
        applyPlacement()
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
