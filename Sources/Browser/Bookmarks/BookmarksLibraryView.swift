// Bookmarks — Full-screen library overlay hosting tab lists with a native header.

import os
import UIKit

/// Library overlay: compact full-screen, regular page-sheet content.
/// Hosts Bookmarks, Favorites, History, and Reading List.
/// Stored tab falls back to bookmarks when unparseable.
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
    var tabGroupsProvider: (() -> [TabGroup])? {
        didSet {
            bookmarksBrowserView?.tabGroupsProvider = tabGroupsProvider
        }
    }

    var onOpenURLsInBackground: (([URL]) -> Void)? {
        didSet {
            bookmarksBrowserView?.onOpenURLsInBackground = onOpenURLsInBackground
        }
    }

    var onOpenURLsInTabGroup: (([URL], TabGroup) -> Void)? {
        didSet {
            bookmarksBrowserView?.onOpenURLsInTabGroup = onOpenURLsInTabGroup
        }
    }

    var onOpenURLsInNewTabGroup: (([URL], String) -> Void)? {
        didSet {
            bookmarksBrowserView?.onOpenURLsInNewTabGroup = onOpenURLsInNewTabGroup
        }
    }

    var chromePlacement: ChromePlacement = .compact {
        didSet {
            if oldValue != chromePlacement {
                applyPlacement()
            }
        }
    }

    var isNonDuoPhone: Bool = false {
        didSet {
            if oldValue != isNonDuoPhone {
                applyPlacement()
            }
        }
    }

    // MARK: - Regular Safari Sheet Header Controls

    private let regularHeaderRow = UIView()
    private let leadingTitleStack = UIStackView()
    private let folderBackButton = AccessibleButton(type: .system)
    private let sectionTitleLabel = UILabel()
    private let trailingStack = UIStackView()
    private let trailingToolbar = SystemToolbarMapper.toolbar(items: [])
    private var trailingToolbarWidthConstraint: NSLayoutConstraint!
    private var contentBottomConstraint: NSLayoutConstraint!

    private var compactHeaderConstraints: [NSLayoutConstraint] = []
    private var regularHeaderConstraints: [NSLayoutConstraint] = []

    /// Glass buttons owning all trailing controls.
    var trailingButtons: [UIButton] {
        trailingStack.arrangedSubviews.compactMap { $0 as? UIButton }
    }

    /// Glass toolbar owning all trailing controls for backward compatibility.
    var headerToolbar: UIToolbar {
        trailingToolbar
    }

    var trailingToolbarItems: [UIBarButtonItem] {
        trailingToolbar.items ?? []
    }

    var isDoneVisible: Bool {
        guard !regularHeaderRow.isHidden else { return false }
        return trailingToolbarItems.contains {
            $0.accessibilityLabel == "Done" || $0.accessibilityLabel == "Done Editing"
        }
    }

    var isOptionsMenuVisible: Bool {
        guard !regularHeaderRow.isHidden else { return false }
        return trailingToolbarItems.contains {
            ($0.accessibilityLabel ?? "").hasSuffix("Options")
        }
    }

    var currentOptionsMenu: UIMenu? {
        trailingToolbarItems.first {
            ($0.accessibilityLabel ?? "").hasSuffix("Options")
        }?.menu
    }

    var isInlineAddVisible: Bool {
        guard !regularHeaderRow.isHidden else { return false }
        return trailingToolbarItems.contains { $0.accessibilityLabel == "New Folder" }
    }

    var isInlineDeleteVisible: Bool {
        guard !regularHeaderRow.isHidden else { return false }
        return trailingToolbarItems.contains { $0.accessibilityLabel == "Delete Selected" }
    }

    var isInlineDeleteEnabled: Bool {
        trailingToolbarItems.first { $0.accessibilityLabel == "Delete Selected" }?.isEnabled ?? false
    }

    var isFolderBackVisible: Bool {
        !regularHeaderRow.isHidden && !folderBackButton.isHidden
    }

    var displayedSectionTitle: String? {
        sectionTitleLabel.text
    }

    var closeButtonAccessibilityLabel: String? {
        trailingToolbarItems.first {
            $0.accessibilityLabel == "Done" || $0.accessibilityLabel == "Done Editing"
        }?.accessibilityLabel
    }

    var hasAnyVisibleButtonTitle: Bool {
        trailingToolbarItems.contains {
            guard let title = $0.title, !title.isEmpty else { return false }
            // Image items render the symbol, never the title string.
            if $0.image != nil {
                return false
            }
            return $0.primaryAction?.image == nil
        }
    }

    func performDone() {
        handlePrimaryCloseOrDone()
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
    private(set) var startPageView: StartPageView?
    private(set) var recentSearchesView: RecentSearchesView?
    private(set) var historyListView: HistoryListView?
    private(set) var readingListView: ReadingListView?

    enum FirstTabMode {
        case startPage
        case recentSearches
    }

    private(set) var firstTabMode: FirstTabMode = .startPage
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
    var onSelectSearchQuery: ((String) -> Void)?

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
        readingListStore: ReadingListStore,
        recentSearchStore: RecentSearchStore? = nil
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
            self?.startPageView?.reload()
            self?.onDidMutateLibraryData?()
        }
        bookView.tabGroupsProvider = tabGroupsProvider
        bookView.onOpenURLsInBackground = { [weak self] urls in
            self?.onOpenURLsInBackground?(urls)
        }
        bookView.onOpenURLsInTabGroup = { [weak self] urls, group in
            self?.onOpenURLsInTabGroup?(urls, group)
        }
        bookView.onOpenURLsInNewTabGroup = { [weak self] urls, name in
            self?.onOpenURLsInNewTabGroup?(urls, name)
        }
        self.bookmarksBrowserView = bookView

        let startPageVM = StartPageViewModel(bookmarkStore: bookmarkStore, historyStore: historyStore)
        let spView = StartPageView(viewModel: startPageVM)
        spView.delegate = self
        spView.onDeleteFavorite = { [weak self] id in
            do {
                try startPageVM.deleteItem(id: id)
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                    .error("deleteFavorite failed: \(error.localizedDescription, privacy: .public)")
            }
            self?.startPageView?.reload()
            self?.bookmarksBrowserView?.reload()
            self?.onDidMutateLibraryData?()
        }
        self.startPageView = spView

        let rView = RecentSearchesView(recentSearchStore: recentSearchStore)
        rView.onSelectQuery = { [weak self] query in
            self?.onSelectSearchQuery?(query)
        }
        rView.onDeleteQuery = { [weak self] id in
            do {
                try recentSearchStore?.delete(id: id)
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                    .error("delete recentSearch failed: \(error.localizedDescription, privacy: .public)")
            }
            self?.recentSearchesView?.reload()
        }
        rView.onClearAll = { [weak self] in
            do {
                try recentSearchStore?.clear()
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                    .error("clear recentSearches failed: \(error.localizedDescription, privacy: .public)")
            }
            self?.recentSearchesView?.reload()
        }
        self.recentSearchesView = rView

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

    func showRecentSearches() {
        activeTab = .startPage
        topTabBar.selectTab(.startPage, notify: false)
        firstTabMode = .recentSearches
        topTabBar.setStartPageIcon(isSearching: true)
        recentSearchesView?.reload()
        updateVisibleTab()
    }

    func resetFirstTabMode() {
        firstTabMode = .startPage
        topTabBar.setStartPageIcon(isSearching: false)
        updateVisibleTab()
    }

    func open(tab: LibraryTab = .bookmarks) {
        resetRegularSelectionModes()
        firstTabMode = .startPage
        topTabBar.setStartPageIcon(isSearching: false)
        activeTab = tab
        Self.persist(tab: tab, defaults: defaults)
        topTabBar.selectTab(tab, notify: false)
        reload()
        updateVisibleTab()
        onTabChanged?(tab)
    }

    func reload() {
        bookmarksBrowserView?.reload()
        startPageView?.reload()
        recentSearchesView?.reload()
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
        if let menu = readingListView?.makeMenu() {
            return menu
        }
        // Bare library has no list view yet; vend stored-default sections
        // so the trailing button never renders an empty menu.
        let displayMode = ReadingListView.storedDisplayMode(defaults: defaults)
        let filterMode = ReadingListView.storedFilterMode(defaults: defaults)
        let largeAction = UIAction(
            title: "Large",
            image: UIImage(systemName: "rectangle.grid.1x2"),
            state: displayMode == .large ? .on : .off
        ) { [weak self] _ in
            guard let self else { return }
            self.readingListView?.setDisplayMode(.large)
            ReadingListView.persist(displayMode: .large, defaults: self.defaults)
            self.updateInlineCommands()
        }
        let compactAction = UIAction(
            title: "Compact",
            image: UIImage(systemName: "list.bullet"),
            state: displayMode == .compact ? .on : .off
        ) { [weak self] _ in
            guard let self else { return }
            self.readingListView?.setDisplayMode(.compact)
            ReadingListView.persist(displayMode: .compact, defaults: self.defaults)
            self.updateInlineCommands()
        }
        let allAction = UIAction(
            title: "All",
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
            state: filterMode == .all ? .on : .off
        ) { [weak self] _ in
            guard let self else { return }
            self.readingListView?.setFilterMode(.all)
            ReadingListView.persist(filterMode: .all, defaults: self.defaults)
            self.updateInlineCommands()
        }
        let unreadAction = UIAction(
            title: "Unread Only",
            image: UIImage(systemName: "circle"),
            state: filterMode == .unreadOnly ? .on : .off
        ) { [weak self] _ in
            guard let self else { return }
            self.readingListView?.setFilterMode(.unreadOnly)
            ReadingListView.persist(filterMode: .unreadOnly, defaults: self.defaults)
            self.updateInlineCommands()
        }
        let selectAction = UIAction(
            title: "Select Items",
            image: UIImage(systemName: "checkmark.circle")
        ) { [weak self] _ in
            self?.enterReadingListSelectionMode()
        }
        let displaySection = UIMenu(title: "", options: .displayInline, children: [largeAction, compactAction])
        let filterSection = UIMenu(title: "", options: .displayInline, children: [allAction, unreadAction])
        let actionsSection = UIMenu(title: "", options: .displayInline, children: [selectAction])
        return UIMenu(title: "", children: [displaySection, filterSection, actionsSection])
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
        let isRegular = chromePlacement == .regular || isNonDuoPhone
        backgroundColor = isRegular ? .systemGroupedBackground : .systemBackground
        NSLayoutConstraint.deactivate(isRegular ? compactHeaderConstraints : regularHeaderConstraints)
        regularHeaderRow.isHidden = !isRegular
        NSLayoutConstraint.activate(isRegular ? regularHeaderConstraints : compactHeaderConstraints)
        applyChildHeaderVisibility()
        contentBottomConstraint?.constant = isNonDuoPhone ? -84 : 0
        updateInlineCommands()
    }

    func updateInlineCommands() {
        guard chromePlacement == .regular || isNonDuoPhone else {
            // Hidden controls must not keep stale regular items.
            SystemToolbarMapper.clearStack(trailingStack)
            trailingToolbar.items = []
            return
        }

        let readingMenu = makeReadingListMenu()
        inlineMenu = readingMenu
        let commands = LibraryTabCommands.make(
            for: activeTab,
            isEditingBookmarks: isEditingBookmarks,
            canClearHistory: canClearHistory,
            isInSelection: isActiveTabInSelectionMode,
            canDeleteSelection: canDeleteActiveTabSelection
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
    }

    private func applyRegularTrailingButtons(for commands: LibraryTabCommands, readingMenu: UIMenu?) {
        var actions: [RailAction] = []
        switch activeTab {
        case .bookmarks:
            if commands.showsDelete {
                actions.append(.deleteSelected(isEnabled: commands.canDeleteSelection) { [weak self] in
                    self?.triggerInlineDelete()
                })
            } else if commands.isEditingBookmarks {
                let canCreate = bookmarksBrowserView?.canCreateFolder ?? true
                actions.append(RailAction(
                    systemImageName: "folder.badge.plus",
                    accessibilityLabel: "New Folder",
                    isEnabled: canCreate,
                    handler: { [weak self] in self?.triggerInlineAdd() }
                ))
            } else {
                actions.append(RailAction(
                    systemImageName: "ellipsis",
                    accessibilityLabel: "Bookmarks Options",
                    menu: makeBookmarksOptionsMenu()
                ))
            }

        case .history:
            if commands.showsDelete {
                actions.append(.deleteSelected(isEnabled: commands.canDeleteSelection) { [weak self] in
                    self?.triggerInlineDelete()
                })
            } else {
                actions.append(RailAction(
                    systemImageName: "ellipsis",
                    accessibilityLabel: "History Options",
                    menu: makeHistoryOptionsMenu(canClear: commands.canClearHistory)
                ))
            }

        case .readingList:
            if commands.showsDelete {
                actions.append(.deleteSelected(isEnabled: commands.canDeleteSelection) { [weak self] in
                    self?.triggerInlineDelete()
                })
            } else if commands.showsMenu, let menu = readingMenu ?? makeReadingListMenu(),
                      !menu.children.isEmpty
            {
                actions.append(.readingListMenu(menu: menu))
            }

        case .startPage:
            break
        }

        // Close stays visible on empty lists; selection swaps it to Done.
        // In Mode 3 (isNonDuoPhone), dismiss is owned solely by the bottom bar.
        if !isNonDuoPhone {
            if commands.isEditingBookmarks {
                actions.append(RailAction(
                    systemImageName: "checkmark",
                    accessibilityLabel: "Done Editing",
                    isProminent: true,
                    handler: { [weak self] in self?.handlePrimaryCloseOrDone() }
                ))
            } else if commands.doneExitsSelection {
                actions.append(RailAction(
                    systemImageName: "checkmark",
                    accessibilityLabel: "Done",
                    isProminent: true,
                    handler: { [weak self] in self?.handlePrimaryCloseOrDone() }
                ))
            } else {
                actions.append(RailAction(
                    systemImageName: "xmark",
                    accessibilityLabel: "Done",
                    handler: { [weak self] in self?.handlePrimaryCloseOrDone() }
                ))
            }
        }
        // Populate trailingStack with individual native Liquid Glass buttons
        SystemToolbarMapper.clearStack(trailingStack)
        for action in actions {
            let button = SystemToolbarMapper.makeButton(for: action)
            trailingStack.addArrangedSubview(button)
        }

        // Keep trailingToolbar in sync for test/contract compatibility
        trailingToolbar.items = SystemToolbarMapper.makeItems(actions)
        let targetWidth = CGFloat(actions.count) * SystemToolbarMapper.hitTarget
            + CGFloat(max(0, actions.count - 1)) * SystemToolbarMapper.bottomBarSpacing
        if trailingToolbarWidthConstraint?.constant != targetWidth {
            trailingToolbarWidthConstraint?.constant = targetWidth
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
            self.firstTabMode = .startPage
            self.topTabBar.setStartPageIcon(isSearching: false)
            self.activeTab = tab
            Self.persist(tab: tab, defaults: self.defaults)
            if tab == .startPage {
                self.startPageView?.reload()
            }
            self.updateVisibleTab()
            self.onTabChanged?(tab)
        }
        headerContainer.addSubview(topTabBar)

        setupRegularHeaderControls()
        setupContainersAndConstraints()
        applyPlacement()
    }

    private func setupRegularHeaderControls() {
        // Plain back chevron without circle fill.
        folderBackButton.translatesAutoresizingMaskIntoConstraints = false
        let backConfig = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        folderBackButton.setImage(UIImage(systemName: "chevron.backward", withConfiguration: backConfig), for: .normal)
        folderBackButton.setTitle(nil, for: .normal)
        folderBackButton.tintColor = .label
        folderBackButton.backgroundColor = .clear
        folderBackButton.accessibilityLabel = "Back to Bookmarks"
        folderBackButton.isHidden = true
        folderBackButton.addAction(UIAction { [weak self] _ in
            self?.bookmarksBrowserView?.popNavigation()
        }, for: .touchUpInside)
        NSLayoutConstraint.activate([
            folderBackButton.widthAnchor.constraint(equalToConstant: SystemToolbarMapper.hitTarget),
            folderBackButton.heightAnchor.constraint(equalToConstant: SystemToolbarMapper.hitTarget)
        ])

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

        // Native glass button stack (HStack equivalent) owns visible controls
        trailingStack.translatesAutoresizingMaskIntoConstraints = false
        trailingStack.axis = .horizontal
        trailingStack.alignment = .center
        trailingStack.spacing = SystemToolbarMapper.bottomBarSpacing
        regularHeaderRow.addSubview(trailingStack)

        // Glass toolbar owns trailing controls off-screen for test/contract compatibility
        trailingToolbar.isHidden = true
        trailingToolbar.layoutMargins = .zero
        trailingToolbar.directionalLayoutMargins = .zero
        regularHeaderRow.addSubview(trailingToolbar)
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
            constant: 4
        )
        compactHeaderConstraints = [
            compactTop,
            headerContainer.heightAnchor.constraint(equalToConstant: 48),
            compactTabLeading,
            compactTabTrailing,
            contentContainer.topAnchor.constraint(equalTo: headerContainer.bottomAnchor)
        ]

        let regHeaderHeight = regularHeaderRow.heightAnchor.constraint(equalToConstant: 44)
        regHeaderHeight.priority = UILayoutPriority(999)
        trailingToolbarWidthConstraint = trailingToolbar.widthAnchor.constraint(equalToConstant: 0)
        trailingToolbarWidthConstraint.priority = UILayoutPriority(999)
        let regTabRowHeight = headerContainer.heightAnchor.constraint(equalToConstant: 44)
        regTabRowHeight.priority = UILayoutPriority(999)
        let titleSpacing = leadingTitleStack.trailingAnchor.constraint(
            lessThanOrEqualTo: trailingStack.leadingAnchor, constant: -12
        )
        titleSpacing.priority = UILayoutPriority(999)

        regularHeaderConstraints = [
            regularHeaderRow.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 14),
            regLeading,
            regTrailing,
            regHeaderHeight,
            leadingTitleStack.leadingAnchor.constraint(equalTo: regularHeaderRow.leadingAnchor),
            leadingTitleStack.centerYAnchor.constraint(equalTo: regularHeaderRow.centerYAnchor),
            trailingStack.trailingAnchor.constraint(equalTo: regularHeaderRow.trailingAnchor),
            trailingStack.centerYAnchor.constraint(equalTo: regularHeaderRow.centerYAnchor),
            trailingStack.heightAnchor.constraint(equalToConstant: 44),
            trailingToolbar.trailingAnchor.constraint(equalTo: regularHeaderRow.trailingAnchor),
            trailingToolbar.centerYAnchor.constraint(equalTo: regularHeaderRow.centerYAnchor),
            trailingToolbarWidthConstraint,
            titleSpacing,
            headerContainer.topAnchor.constraint(equalTo: regularHeaderRow.bottomAnchor, constant: 8),
            regTabRowHeight,
            regTabLeading,
            regTabTrailing,
            contentContainer.topAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: 4)
        ]

        contentBottomConstraint = contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor)
        NSLayoutConstraint.activate([
            headerContainer.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            topTabBar.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            topTabBar.heightAnchor.constraint(equalToConstant: 40),

            contentContainer.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            contentBottomConstraint
        ])
    }

    private func setupContentSubviews() {
        if let book = bookmarksBrowserView {
            book.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(book)
            pin(book, inside: contentContainer)
        }
        if let sp = startPageView {
            sp.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(sp)
            pin(sp, inside: contentContainer)
        }
        if let recents = recentSearchesView {
            recents.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(recents)
            pin(recents, inside: contentContainer)
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
        let hideInnerHeaders = chromePlacement == .regular || isNonDuoPhone
        bookmarksBrowserView?.setHeaderBarHidden(hideInnerHeaders)
        historyListView?.setHeaderBarHidden(hideInnerHeaders)
        readingListView?.setHeaderBarHidden(hideInnerHeaders)
    }

    private func updateVisibleTab() {
        bookmarksBrowserView?.isHidden = (activeTab != .bookmarks)
        startPageView?.isHidden = (activeTab != .startPage || firstTabMode != .startPage)
        recentSearchesView?.isHidden = (activeTab != .startPage || firstTabMode != .recentSearches)
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
        case .startPage:
            break
        }
    }
}

// MARK: - StartPageViewDelegate

extension BookmarksLibraryView: StartPageViewDelegate {
    func startPage(_: StartPageView, didOpenURL url: URL) {
        onOpenURL?(url)
    }
}
