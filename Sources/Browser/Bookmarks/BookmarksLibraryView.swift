//
//  BookmarksLibraryView.swift
//  OuterView
//

import os
import UIKit

/// Full-screen overlay on compact and native page-sheet content on regular for
/// Bookmarks, Favorites, History, and Reading List (matching Safari).
/// UserDefaults keys libraryTab as Int, overviewMode as String, and overviewGroup as String.
/// Values are read at init and setup and written on every change; private mode is never
/// written and restores as standard. Unparseable values fall back to bookmarks, standard,
/// and nil; a stored group id resolving to no existing group restores as nil.
@MainActor
final class BookmarksLibraryView: UIView, ChromePlacementDriven {
    nonisolated static let libraryTabDefaultsKey = "libraryTab"
    nonisolated static let circleButtonDiameter: CGFloat = 36

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

    var isNonDuoPhone: Bool = false {
        didSet {
            compactHeaderTopConstraint?.constant = isNonDuoPhone ? 48 : 4
        }
    }

    // MARK: - Regular Safari Sheet Header Controls

    private let regularHeaderRow = UIView()
    private let leadingTitleStack = UIStackView()
    private let folderBackButton = AccessibleButton(type: .system)
    private let sectionTitleLabel = UILabel()
    private let trailingCircleStack = UIStackView()
    private let optionsMenuButton = AccessibleButton(type: .system)
    private let addFolderCircleButton = AccessibleButton(type: .system)
    private let deleteCircleButton = AccessibleButton(type: .system)
    private let closeOrDoneCircleButton = AccessibleButton(type: .system)

    private var compactHeaderTopConstraint: NSLayoutConstraint?
    private var compactHeaderConstraints: [NSLayoutConstraint] = []
    private var regularHeaderConstraints: [NSLayoutConstraint] = []

    var isDoneVisible: Bool {
        chromePlacement == .regular && !regularHeaderRow.isHidden && !closeOrDoneCircleButton.isHidden
    }

    var isOptionsMenuVisible: Bool {
        chromePlacement == .regular && !regularHeaderRow.isHidden && !optionsMenuButton.isHidden
    }

    var currentOptionsMenu: UIMenu? {
        optionsMenuButton.menu
    }

    var isInlineAddVisible: Bool {
        chromePlacement == .regular && !regularHeaderRow.isHidden && !addFolderCircleButton.isHidden
    }

    var isInlineDeleteVisible: Bool {
        chromePlacement == .regular && !regularHeaderRow.isHidden && !deleteCircleButton.isHidden
    }

    var isInlineDeleteEnabled: Bool {
        deleteCircleButton.isEnabled
    }

    var isFolderBackVisible: Bool {
        chromePlacement == .regular && !regularHeaderRow.isHidden && !folderBackButton.isHidden
    }

    var displayedSectionTitle: String? {
        sectionTitleLabel.text
    }

    var closeButtonAccessibilityLabel: String? {
        closeOrDoneCircleButton.accessibilityLabel
    }

    var hasAnyVisibleButtonTitle: Bool {
        let buttons = [
            folderBackButton,
            optionsMenuButton,
            addFolderCircleButton,
            deleteCircleButton,
            closeOrDoneCircleButton
        ]
        return buttons.contains { !$0.isHidden && !(($0.title(for: .normal) ?? "").isEmpty) }
    }

    func performDone() {
        closeOrDoneCircleButton.sendActions(for: .touchUpInside)
    }

    func performInlineAdd() {
        triggerInlineAdd()
    }

    func performInlineToggleEdit() {
        triggerInlineToggleEdit()
    }

    func performInlineClear() {
        triggerInlineClear()
    }

    func performInlineDelete() {
        triggerInlineDelete()
    }

    func performInlineDone() {
        performDone()
    }

    private let headerContainer = UIView()
    private let topTabBar: LibraryTabBar
    let defaults: UserDefaults

    private let contentContainer = UIView()
    private(set) var bookmarksBrowserView: BookmarksBrowserView?
    private(set) var favoritesGridView: FavoritesGridView?
    private(set) var historyListView: HistoryListView?
    private(set) var readingListView: ReadingListView?

    private(set) var activeTab: LibraryTab = .bookmarks

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
    var onDidMutateLibraryData: (() -> Void)?

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
        let bookView = BookmarksBrowserView(bookmarkStore: bookmarkStore, defaults: defaults)
        bookView.onOpenURL = { [weak self] url in
            self?.onOpenURL?(url)
        }
        bookView.onOpenInNewTab = { [weak self] url in
            self?.onOpenInNewTab?(url)
        }
        bookView.onRequestEdit = { [weak self] target in
            self?.onRequestEdit?(target)
        }
        bookView.onNavigationStateChanged = { [weak self] in
            self?.updateInlineCommands()
        }
        bookView.onDidMutateBookmarks = { [weak self] in
            self?.favoritesGridView?.reload()
            self?.onDidMutateLibraryData?()
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
            self?.bookmarksBrowserView?.reload()
            self?.onDidMutateLibraryData?()
        }
        self.favoritesGridView = favView

        let histView = HistoryListView(historyStore: historyStore)
        histView.onOpenURL = { [weak self] url in
            self?.onOpenURL?(url)
        }
        histView.onStateChanged = { [weak self] in
            self?.updateInlineCommands()
        }
        histView.onDidMutateHistory = { [weak self] in
            self?.onDidMutateLibraryData?()
        }
        self.historyListView = histView

        let readingView = ReadingListView(store: readingListStore, defaults: defaults)
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
        applyChildHeaderVisibility()
        updateVisibleTab()
    }

    func open(tab: LibraryTab = .bookmarks) {
        resetRegularSelectionModes()
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
        backgroundColor = isRegular ? .systemGroupedBackground : .systemBackground
        NSLayoutConstraint.deactivate(isRegular ? compactHeaderConstraints : regularHeaderConstraints)
        regularHeaderRow.isHidden = !isRegular
        NSLayoutConstraint.activate(isRegular ? regularHeaderConstraints : compactHeaderConstraints)
        applyChildHeaderVisibility()
        updateInlineCommands()
    }

    func updateInlineCommands() {
        guard chromePlacement == .regular else {
            optionsMenuButton.isHidden = true
            addFolderCircleButton.isHidden = true
            deleteCircleButton.isHidden = true
            closeOrDoneCircleButton.isHidden = true
            folderBackButton.isHidden = true
            return
        }

        let readingMenu = makeReadingListMenu()
        inlineMenu = readingMenu
        let commands = LibraryTabCommands.make(
            for: activeTab,
            isEditingBookmarks: isEditingBookmarks,
            canClearHistory: canClearHistory,
            isInSelection: isActiveTabInSelectionMode,
            canDeleteSelection: canDeleteActiveTabSelection,
            hasReadingListMenu: readingMenu != nil
        )

        if activeTab == .bookmarks, let bookmarksBrowserView {
            sectionTitleLabel.text = bookmarksBrowserView.currentNavigationTitle
            folderBackButton.isHidden = bookmarksBrowserView.isAtRoot
            folderBackButton.accessibilityLabel = bookmarksBrowserView.backNavigationAccessibilityLabel
        } else {
            sectionTitleLabel.text = activeTab.title
            folderBackButton.isHidden = true
        }

        applyRegularTrailingButtons(for: commands, readingMenu: readingMenu)

        closeOrDoneCircleButton.isHidden = false
        if commands.isEditingBookmarks {
            styleAccentCheckButton(closeOrDoneCircleButton, accessibilityLabel: "Done Editing")
        } else if commands.doneExitsSelection {
            styleAccentCheckButton(closeOrDoneCircleButton, accessibilityLabel: "Done")
        } else {
            styleCloseButton(closeOrDoneCircleButton, accessibilityLabel: "Done")
        }
    }

    private func applyRegularTrailingButtons(for commands: LibraryTabCommands, readingMenu: UIMenu?) {
        switch activeTab {
        case .bookmarks:
            if commands.showsDelete {
                optionsMenuButton.isHidden = true
                optionsMenuButton.menu = nil
                addFolderCircleButton.isHidden = true
                deleteCircleButton.isHidden = false
                deleteCircleButton.isEnabled = commands.canDeleteSelection
            } else if commands.isEditingBookmarks {
                optionsMenuButton.isHidden = true
                optionsMenuButton.menu = nil
                addFolderCircleButton.isHidden = false
                addFolderCircleButton.isEnabled = bookmarksBrowserView?.canCreateFolder ?? true
                deleteCircleButton.isHidden = true
            } else {
                optionsMenuButton.menu = makeBookmarksOptionsMenu()
                optionsMenuButton.accessibilityLabel = "Bookmarks Options"
                optionsMenuButton.isHidden = false
                addFolderCircleButton.isHidden = true
                deleteCircleButton.isHidden = true
            }

        case .history:
            addFolderCircleButton.isHidden = true
            if commands.showsDelete {
                optionsMenuButton.isHidden = true
                optionsMenuButton.menu = nil
                deleteCircleButton.isHidden = false
                deleteCircleButton.isEnabled = commands.canDeleteSelection
            } else {
                optionsMenuButton.menu = makeHistoryOptionsMenu(canClear: commands.canClearHistory)
                optionsMenuButton.accessibilityLabel = "History Options"
                optionsMenuButton.isHidden = false
                deleteCircleButton.isHidden = true
            }

        case .readingList:
            addFolderCircleButton.isHidden = true
            if commands.showsDelete {
                optionsMenuButton.isHidden = true
                optionsMenuButton.menu = nil
                deleteCircleButton.isHidden = false
                deleteCircleButton.isEnabled = commands.canDeleteSelection
            } else if commands.showsMenu, let readingMenu {
                optionsMenuButton.menu = readingMenu
                optionsMenuButton.accessibilityLabel = "Reading List Options"
                optionsMenuButton.isHidden = false
                deleteCircleButton.isHidden = true
            } else {
                optionsMenuButton.isHidden = true
                optionsMenuButton.menu = nil
                deleteCircleButton.isHidden = true
            }

        case .favorites:
            optionsMenuButton.isHidden = true
            optionsMenuButton.menu = nil
            addFolderCircleButton.isHidden = true
            deleteCircleButton.isHidden = true
        }
    }

    // MARK: - Private

    private func setup() {
        backgroundColor = .systemBackground

        regularHeaderRow.translatesAutoresizingMaskIntoConstraints = false
        regularHeaderRow.isHidden = true
        addSubview(regularHeaderRow)

        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerContainer)

        topTabBar.translatesAutoresizingMaskIntoConstraints = false
        topTabBar.onTabSelected = { [weak self] tab in
            guard let self else { return }
            self.resetRegularSelectionModes()
            self.activeTab = tab
            Self.persist(tab: tab, defaults: self.defaults)
            self.updateVisibleTab()
            self.onTabChanged?(tab)
        }
        headerContainer.addSubview(topTabBar)

        setupRegularHeaderControls()
        setupContainersAndConstraints()
        applyPlacement()
    }

    private func setupRegularHeaderControls() {
        styleNeutralCircleButton(
            folderBackButton,
            symbolName: "chevron.backward",
            accessibilityLabel: "Back to Bookmarks"
        )
        folderBackButton.isHidden = true
        folderBackButton.addAction(UIAction { [weak self] _ in
            self?.bookmarksBrowserView?.popNavigation()
        }, for: .touchUpInside)

        let baseTitleFont = UIFont.systemFont(ofSize: 22, weight: .bold)
        sectionTitleLabel.font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: baseTitleFont)
        sectionTitleLabel.adjustsFontForContentSizeCategory = true
        sectionTitleLabel.textColor = .label
        sectionTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        leadingTitleStack.translatesAutoresizingMaskIntoConstraints = false
        leadingTitleStack.axis = .horizontal
        leadingTitleStack.alignment = .center
        leadingTitleStack.spacing = 10
        leadingTitleStack.addArrangedSubview(folderBackButton)
        leadingTitleStack.addArrangedSubview(sectionTitleLabel)
        regularHeaderRow.addSubview(leadingTitleStack)

        styleNeutralCircleButton(
            optionsMenuButton,
            symbolName: "ellipsis",
            accessibilityLabel: "Library Options"
        )
        optionsMenuButton.showsMenuAsPrimaryAction = true

        styleNeutralCircleButton(
            addFolderCircleButton,
            symbolName: "folder.badge.plus",
            accessibilityLabel: "New Folder"
        )
        addFolderCircleButton.isHidden = true
        addFolderCircleButton.addAction(UIAction { [weak self] _ in
            self?.triggerInlineAdd()
        }, for: .touchUpInside)

        styleNeutralCircleButton(
            deleteCircleButton,
            symbolName: "trash",
            accessibilityLabel: "Delete Selected",
            tintColor: .systemRed
        )
        deleteCircleButton.isHidden = true
        deleteCircleButton.addAction(UIAction { [weak self] _ in
            self?.triggerInlineDelete()
        }, for: .touchUpInside)

        styleCloseButton(closeOrDoneCircleButton, accessibilityLabel: "Done")
        closeOrDoneCircleButton.addAction(UIAction { [weak self] _ in
            self?.handlePrimaryCloseOrDone()
        }, for: .touchUpInside)

        trailingCircleStack.translatesAutoresizingMaskIntoConstraints = false
        trailingCircleStack.axis = .horizontal
        trailingCircleStack.alignment = .center
        trailingCircleStack.spacing = 10
        trailingCircleStack.addArrangedSubview(optionsMenuButton)
        trailingCircleStack.addArrangedSubview(addFolderCircleButton)
        trailingCircleStack.addArrangedSubview(deleteCircleButton)
        trailingCircleStack.addArrangedSubview(closeOrDoneCircleButton)
        regularHeaderRow.addSubview(trailingCircleStack)
    }

    private func styleNeutralCircleButton(
        _ button: UIButton,
        symbolName: String,
        accessibilityLabel: String,
        tintColor: UIColor = .label
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        button.setImage(UIImage(systemName: symbolName, withConfiguration: config), for: .normal)
        button.setTitle(nil, for: .normal)
        button.tintColor = tintColor
        button.backgroundColor = .tertiarySystemFill
        button.layer.cornerRadius = Self.circleButtonDiameter / 2
        button.clipsToBounds = true
        button.accessibilityLabel = accessibilityLabel
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Self.circleButtonDiameter),
            button.heightAnchor.constraint(equalToConstant: Self.circleButtonDiameter)
        ])
    }

    private func styleCloseButton(_ button: UIButton, accessibilityLabel: String) {
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        button.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        button.setTitle(nil, for: .normal)
        button.tintColor = .secondaryLabel
        button.backgroundColor = .tertiarySystemFill
        button.layer.cornerRadius = Self.circleButtonDiameter / 2
        button.clipsToBounds = true
        button.accessibilityLabel = accessibilityLabel
        if button.constraints.isEmpty {
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: Self.circleButtonDiameter),
                button.heightAnchor.constraint(equalToConstant: Self.circleButtonDiameter)
            ])
        }
    }

    private func styleAccentCheckButton(_ button: UIButton, accessibilityLabel: String) {
        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)
        button.setImage(UIImage(systemName: "checkmark", withConfiguration: config), for: .normal)
        button.setTitle(nil, for: .normal)
        button.tintColor = .white
        button.backgroundColor = .systemBlue
        button.layer.cornerRadius = Self.circleButtonDiameter / 2
        button.clipsToBounds = true
        button.accessibilityLabel = accessibilityLabel
    }

    private func setupContainersAndConstraints() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentContainer)

        let regLeading = regularHeaderRow.leadingAnchor.constraint(
            equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20
        )
        regLeading.priority = UILayoutPriority(999)
        let regTrailing = regularHeaderRow.trailingAnchor.constraint(
            equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20
        )
        regTrailing.priority = UILayoutPriority(999)
        let regTabLeading = topTabBar.leadingAnchor.constraint(
            equalTo: headerContainer.leadingAnchor, constant: 20
        )
        regTabLeading.priority = UILayoutPriority(999)
        let regTabTrailing = topTabBar.trailingAnchor.constraint(
            equalTo: headerContainer.trailingAnchor, constant: -20
        )
        regTabTrailing.priority = UILayoutPriority(999)

        let compactTabLeading = topTabBar.leadingAnchor.constraint(
            equalTo: headerContainer.leadingAnchor, constant: 16
        )
        compactTabLeading.priority = UILayoutPriority(999)
        let compactTabTrailing = topTabBar.trailingAnchor.constraint(
            equalTo: headerContainer.trailingAnchor, constant: -16
        )
        compactTabTrailing.priority = UILayoutPriority(999)

        let compactTop = headerContainer.topAnchor.constraint(
            equalTo: safeAreaLayoutGuide.topAnchor,
            constant: isNonDuoPhone ? 48 : 4
        )
        compactHeaderTopConstraint = compactTop
        compactHeaderConstraints = [
            compactTop,
            headerContainer.heightAnchor.constraint(equalToConstant: 48),
            compactTabLeading,
            compactTabTrailing,
            contentContainer.topAnchor.constraint(equalTo: headerContainer.bottomAnchor)
        ]

        let regHeaderHeight = regularHeaderRow.heightAnchor.constraint(equalToConstant: 44)
        regHeaderHeight.priority = UILayoutPriority(999)
        let regTabRowHeight = headerContainer.heightAnchor.constraint(equalToConstant: 44)
        regTabRowHeight.priority = UILayoutPriority(999)
        let titleSpacing = leadingTitleStack.trailingAnchor.constraint(
            lessThanOrEqualTo: trailingCircleStack.leadingAnchor, constant: -12
        )
        titleSpacing.priority = UILayoutPriority(999)

        regularHeaderConstraints = [
            regularHeaderRow.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 14),
            regLeading,
            regTrailing,
            regHeaderHeight,
            leadingTitleStack.leadingAnchor.constraint(equalTo: regularHeaderRow.leadingAnchor),
            leadingTitleStack.centerYAnchor.constraint(equalTo: regularHeaderRow.centerYAnchor),
            trailingCircleStack.trailingAnchor.constraint(equalTo: regularHeaderRow.trailingAnchor),
            trailingCircleStack.centerYAnchor.constraint(equalTo: regularHeaderRow.centerYAnchor),
            titleSpacing,
            headerContainer.topAnchor.constraint(equalTo: regularHeaderRow.bottomAnchor, constant: 8),
            regTabRowHeight,
            regTabLeading,
            regTabTrailing,
            contentContainer.topAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: 4)
        ]

        NSLayoutConstraint.activate([
            headerContainer.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            topTabBar.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            topTabBar.heightAnchor.constraint(equalToConstant: 40),

            contentContainer.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
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

    private func applyChildHeaderVisibility() {
        let hideInnerHeaders = chromePlacement == .regular
        bookmarksBrowserView?.setHeaderBarHidden(hideInnerHeaders)
        historyListView?.setHeaderBarHidden(hideInnerHeaders)
        readingListView?.setHeaderBarHidden(hideInnerHeaders)
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
