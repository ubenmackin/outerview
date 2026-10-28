//
//  BrowserRootViewController.swift
//  OuterView
//

import os
import SwiftUI
import UIKit

/// Single chrome applier: tab content, floating rail + pill, editor, error
/// overlay, and tab overview placeholder. Content renders full-bleed while
/// chrome floats above it.
@MainActor
final class BrowserRootViewController: UIViewController {
    nonisolated static let railHideDuration: TimeInterval = 0.25
    nonisolated static let pillMorphDuration: TimeInterval = 0.3
    nonisolated static let structuralDebounceInterval: TimeInterval = 0.15

    /// Gap between the expanded pill and the system bottom safe area.
    nonisolated static let expandedPillBottomGap: CGFloat = 4

    /// Smallest distance between the minified pill and the screen edge.
    nonisolated static let minifiedPillMinimumBottom: CGFloat = 8

    /// How far the minified pill sinks into the bottom safe area, so it sits
    /// just above the home indicator the way Safari's compact bar does.
    nonisolated static let minifiedPillSink: CGFloat = 14

    /// Breathing room kept between the expanded pill and the last line of
    /// scrollable content.
    nonisolated static let contentBottomGap: CGFloat = 8

    /// Distance from the bottom edge of the view to the bottom of the pill.
    /// The root ignores no insets of its own, so `systemBottomInset` is the
    /// real home-indicator inset (34 pt on the Duo).
    nonisolated static func pillBottomOffset(for pill: PillState, systemBottomInset: CGFloat) -> CGFloat {
        switch pill {
        case .minified:
            max(minifiedPillMinimumBottom, systemBottomInset - minifiedPillSink)
        case .expanded, .editing:
            systemBottomInset + expandedPillBottomGap
        }
    }

    /// Bottom inset the page content reserves so its last line can scroll
    /// clear of the expanded pill. Content still renders under the chrome;
    /// this only extends the scrollable range. Kept constant across pill
    /// states so pages never reflow mid-scroll.
    nonisolated static func contentBottomInset(systemBottomInset: CGFloat) -> CGFloat {
        pillBottomOffset(for: .expanded, systemBottomInset: systemBottomInset)
            + AddressBarView.heightForState(.expanded)
            + contentBottomGap
    }

    /// Bounds width the minified capsule measures against. The minified pill
    /// centers on the full view because the rail is out of the way whenever
    /// the user is scrolling.
    var pillReferenceWidth: CGFloat {
        view.bounds.width
    }

    // MARK: - Layers

    let contentContainer = UIView()
    let startPageContainer = UIView()
    private let errorContainer = UIView()
    private let errorLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    let railView = SideRailView()
    let pillView = AddressBarView()
    let editorView = AddressEditorView()
    let bookmarksLibraryView = BookmarksLibraryView()
    private let bookmarkEditorContainer = UIView()
    private var bookmarkEditorHosting: UIHostingController<BookmarkEditorView>?
    private var activeBookmarkEditorModel: BookmarkEditorModel?
    private(set) var isBookmarkEditorVisible = false
    var isEditingAddress = false
    let overviewView = UIView()
    let overviewController = TabOverviewViewController()
    var overviewMode: TabOverviewMode = .standard

    var pillHeightConstraint: NSLayoutConstraint!
    var pillBottomConstraint: NSLayoutConstraint!
    var pillLeadingConstraint: NSLayoutConstraint!
    var pillTrailingConstraint: NSLayoutConstraint!
    var pillWidthConstraint: NSLayoutConstraint!
    var pillCenterXConstraint: NSLayoutConstraint!
    var pillAnimator: UIViewPropertyAnimator?
    private var structuralTask: Task<Void, Never>?
    var suggestionTask: Task<Void, Never>?

    // MARK: - State

    var chromeController = ChromeStateController()
    var tabs: [TabRecord] = []
    var selectedTabID: UUID?
    var isOverviewVisible = false
    var isLibraryVisible = false

    let tabPool = TabPool()
    var scrollProxies: [UUID: ChromeScrollProxy] = [:]
    var snapshotListenerIDs: [UUID: UUID] = [:]
    var forcedStartPageTabs = Set<UUID>()
    var startPageView: StartPageView?

    private var database: OuterViewDatabase?
    var bookmarkStore: BookmarkStore?
    var historyStore: HistoryStore?
    private(set) var recentSearchStore: RecentSearchStore?
    var tabStore: TabStore?
    var restoreCoordinator: SessionRestoreCoordinator?
    var boundListenerPages: [UUID: ObjectIdentifier] = [:]

    /// Camera/system occlusion union forwarded to the rail. Derived from the
    /// current bounds on every layout pass so chrome stays below the top
    /// status/camera region on both displays.
    private var reservedOcclusionUnion: CGRect = .zero

    init(database: OuterViewDatabase? = nil) {
        if let database {
            self.database = database
        } else {
            do {
                self.database = try OuterViewDatabase()
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "BrowserRoot")
                    .error("OuterViewDatabase init failed, falling back to in-memory: \(error.localizedDescription, privacy: .public)")
                do {
                    self.database = try OuterViewDatabase(inMemory: true)
                } catch {
                    Logger(subsystem: "com.volcrypt.OuterView", category: "BrowserRoot")
                        .error("In-memory database init failed: \(error.localizedDescription, privacy: .public)")
                    self.database = nil
                }
            }
        }
        super.init(nibName: nil, bundle: nil)
        if let database = self.database {
            bookmarkStore = BookmarkStore(database: database)
            historyStore = HistoryStore(database: database)
            recentSearchStore = RecentSearchStore(database: database)
            let tabs = TabStore(database: database)
            tabStore = tabs
            let coordinator = SessionRestoreCoordinator(tabStore: tabs)
            coordinator.tabsProvider = { @MainActor [weak self] in self?.tabs ?? [] }
            coordinator.selectionProvider = { @MainActor [weak self] in self?.selectedTabID }
            restoreCoordinator = coordinator
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupHierarchy()
        setupStartPageContent()
        updateRailItems()
        loadInitialTabs()
        applyContentInsets()
        applyChromeViews(animated: false)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updatePillBottomOffset()
        applyContentInsets()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let occlusionWidth = SideRailView.safeColumnWidth
        let occlusionHeight = SideRailView.reservedOcclusionHeight
        reservedOcclusionUnion = CGRect(
            x: max(0, view.bounds.width - occlusionWidth),
            y: 0,
            width: occlusionWidth,
            height: occlusionHeight
        )
        railView.reservedOcclusionUnion = reservedOcclusionUnion
        applyRailViews(animated: false)
        if pillWidthConstraint.isActive {
            let width = AddressBarView.widthForBounds(pillReferenceWidth)
            if pillWidthConstraint.constant != width {
                pillWidthConstraint.constant = width
            }
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        scheduleStructuralUpdate()
    }

    // MARK: - Setup

    private func setupHierarchy() {
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentContainer)
        NSLayoutConstraint.activate([
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentContainer.topAnchor.constraint(equalTo: view.topAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        startPageContainer.translatesAutoresizingMaskIntoConstraints = false
        startPageContainer.backgroundColor = .systemBackground
        contentContainer.addSubview(startPageContainer)
        NSLayoutConstraint.activate([
            startPageContainer.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            startPageContainer.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            startPageContainer.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            startPageContainer.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])

        setupErrorOverlay()
        setupPill()
        setupRail()
        setupEditor()
        setupLibrary()
        setupBookmarkEditor()
        setupOverview()
        bringChromeToFront()
    }

    /// Single z-order for the floating layers. The rail is topmost so the
    /// overview's own rail composition (Search/Menu/New/Done) is never
    /// covered by the opaque overview surface; a hidden rail has zero alpha
    /// and is skipped by hit testing.
    func bringChromeToFront() {
        view.bringSubviewToFront(errorContainer)
        view.bringSubviewToFront(pillView)
        view.bringSubviewToFront(editorView)
        view.bringSubviewToFront(bookmarksLibraryView)
        view.bringSubviewToFront(bookmarkEditorContainer)
        view.bringSubviewToFront(overviewView)
        view.bringSubviewToFront(railView)
    }

    private func setupBookmarkEditor() {
        bookmarkEditorContainer.translatesAutoresizingMaskIntoConstraints = false
        bookmarkEditorContainer.backgroundColor = .systemBackground
        bookmarkEditorContainer.isHidden = true
        view.addSubview(bookmarkEditorContainer)
        NSLayoutConstraint.activate([
            bookmarkEditorContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bookmarkEditorContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bookmarkEditorContainer.topAnchor.constraint(equalTo: view.topAnchor),
            bookmarkEditorContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupRail() {
        railView.translatesAutoresizingMaskIntoConstraints = false
        railView.onQuickMenuTapped = { [weak self] in
            self?.applyRailMenuTapped()
        }
        view.addSubview(railView)
        NSLayoutConstraint.activate([
            railView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            railView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            railView.topAnchor.constraint(equalTo: view.topAnchor),
            railView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupPill() {
        pillView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pillView)
        pillHeightConstraint = pillView.heightAnchor.constraint(
            equalToConstant: AddressBarView.heightForState(.expanded)
        )
        pillLeadingConstraint = pillView.leadingAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16
        )
        pillTrailingConstraint = pillView.trailingAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16
        )
        pillCenterXConstraint = pillView.centerXAnchor.constraint(
            equalTo: view.centerXAnchor
        )
        pillWidthConstraint = pillView.widthAnchor.constraint(
            equalToConstant: AddressBarView.widthForBounds(view.bounds.width)
        )
        pillBottomConstraint = pillView.bottomAnchor.constraint(
            equalTo: view.bottomAnchor,
            constant: -Self.pillBottomOffset(for: .expanded, systemBottomInset: view.safeAreaInsets.bottom)
        )
        NSLayoutConstraint.activate([
            pillBottomConstraint,
            pillHeightConstraint,
            pillLeadingConstraint,
            pillTrailingConstraint
        ])
        pillView.onPillTap = { [weak self] in self?.beginEditing() }
        pillView.onPageMenu = { [weak self] in self?.showPageMenu() }
        pillView.pageMenuProvider = { [weak self] in
            self?.makePageMenu() ?? UIMenu()
        }
        pillView.onReload = { [weak self] in self?.activePage()?.reload() }
        pillView.onStop = { [weak self] in self?.activePage()?.stop() }
    }

    private func setupEditor() {
        editorView.translatesAutoresizingMaskIntoConstraints = false
        editorView.isHidden = true
        view.addSubview(editorView)
        NSLayoutConstraint.activate([
            editorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            editorView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            editorView.topAnchor.constraint(equalTo: view.topAnchor),
            editorView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        editorView.onSubmit = { [weak self] text in self?.submitAddressText(text) }
        editorView.onTextChanged = { [weak self] text in self?.refreshSuggestions(for: text) }
        editorView.onSelectSuggestion = { [weak self] suggestion in self?.openSuggestion(suggestion) }
    }

    private func setupLibrary() {
        bookmarksLibraryView.translatesAutoresizingMaskIntoConstraints = false
        bookmarksLibraryView.isHidden = true
        view.addSubview(bookmarksLibraryView)
        NSLayoutConstraint.activate([
            bookmarksLibraryView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bookmarksLibraryView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bookmarksLibraryView.topAnchor.constraint(equalTo: view.topAnchor),
            bookmarksLibraryView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        if let bookmarkStore, let historyStore {
            bookmarksLibraryView.configureStores(
                bookmarkStore: bookmarkStore,
                historyStore: historyStore
            )
        }
        bookmarksLibraryView.onOpenURL = { [weak self] url in
            self?.loadActivePage(url)
            self?.closeBookmarksLibrary()
        }
        bookmarksLibraryView.onOpenInNewTab = { [weak self] url in
            self?.closeBookmarksLibrary()
            self?.openNewTab(with: url)
        }
        bookmarksLibraryView.onDone = { [weak self] in
            self?.closeBookmarksLibrary()
        }
        bookmarksLibraryView.onRequestEdit = { [weak self] target in
            self?.presentBookmarkEditor(for: target)
        }
        bookmarksLibraryView.onTabChanged = { [weak self] tab in
            self?.updateLibraryRailItems(for: tab)
        }
    }

    func presentBookmarkEditor(for target: BookmarkEditorTarget) {
        guard let bookmarkStore else { return }
        let model = BookmarkEditorModel(target: target)
        activeBookmarkEditorModel = model
        let editor = BookmarkEditorView(model: model, bookmarkStore: bookmarkStore)
        let hosting = UIHostingController(rootView: editor)

        bookmarkEditorHosting?.view.removeFromSuperview()
        bookmarkEditorHosting?.removeFromParent()

        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        bookmarkEditorContainer.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: bookmarkEditorContainer.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: bookmarkEditorContainer.safeAreaLayoutGuide.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: bookmarkEditorContainer.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: bookmarkEditorContainer.bottomAnchor)
        ])
        hosting.didMove(toParent: self)
        bookmarkEditorHosting = hosting

        isBookmarkEditorVisible = true
        bookmarkEditorContainer.isHidden = false
        bringChromeToFront()
        updateRailItems()
        applyRailViews(animated: true)
    }

    func dismissBookmarkEditor() {
        isBookmarkEditorVisible = false
        bookmarkEditorContainer.isHidden = true
        bookmarkEditorHosting?.view.removeFromSuperview()
        bookmarkEditorHosting?.removeFromParent()
        bookmarkEditorHosting = nil
        activeBookmarkEditorModel = nil
        updateRailItems()
        applyRailViews(animated: true)
    }

    func saveBookmarkEditor() {
        guard let model = activeBookmarkEditorModel, let bookmarkStore else { return }
        guard model.isValid else {
            model.errorMessage = "Please enter a valid title and URL."
            return
        }
        do {
            try model.save(bookmarkStore: bookmarkStore)
            dismissBookmarkEditor()
            updateStartPageContent()
            bookmarksLibraryView.reload()
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "BookmarkEditor")
                .error("Failed to save bookmark/folder: \(error.localizedDescription, privacy: .public)")
            model.errorMessage = error.localizedDescription
        }
    }

    func openBookmarksLibrary(tab: LibraryTab = .bookmarks) {
        isLibraryVisible = true
        bookmarksLibraryView.open(tab: tab)
        bookmarksLibraryView.isHidden = false
        updateLibraryRailItems(for: tab)
        bringChromeToFront()
    }

    func closeBookmarksLibrary() {
        isLibraryVisible = false
        bookmarksLibraryView.isHidden = true
        updateRailItems()
    }

    func updateLibraryRailItems(for tab: LibraryTab) {
        guard isLibraryVisible else { return }
        var prefix: [RailAction] = []
        switch tab {
        case .bookmarks:
            let isEditing = bookmarksLibraryView.isEditingBookmarks
            prefix = [
                .addFolder { [weak self] in
                    self?.bookmarksLibraryView.promptNewFolder()
                },
                .edit(isEditing: isEditing) { [weak self] in
                    self?.bookmarksLibraryView.toggleBookmarksEdit()
                    self?.updateLibraryRailItems(for: .bookmarks)
                }
            ]
        case .history:
            let canClear = bookmarksLibraryView.canClearHistory
            prefix = [
                .clear(isEnabled: canClear) { [weak self] in
                    self?.bookmarksLibraryView.promptClearHistory()
                }
            ]
        case .favorites:
            prefix = []
        }

        railView.setItems(
            prefix: prefix,
            suffix: [
                .done { [weak self] in
                    self?.closeBookmarksLibrary()
                }
            ]
        )
    }

    private func setupOverview() {
        overviewView.translatesAutoresizingMaskIntoConstraints = false
        overviewView.backgroundColor = .systemBackground
        overviewView.isHidden = true
        view.addSubview(overviewView)
        NSLayoutConstraint.activate([
            overviewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overviewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overviewView.topAnchor.constraint(equalTo: view.topAnchor),
            overviewView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        addChild(overviewController)
        overviewController.view.translatesAutoresizingMaskIntoConstraints = false
        overviewView.addSubview(overviewController.view)
        NSLayoutConstraint.activate([
            overviewController.view.leadingAnchor.constraint(equalTo: overviewView.leadingAnchor),
            overviewController.view.trailingAnchor.constraint(equalTo: overviewView.trailingAnchor),
            overviewController.view.topAnchor.constraint(equalTo: overviewView.topAnchor),
            overviewController.view.bottomAnchor.constraint(equalTo: overviewView.bottomAnchor)
        ])
        overviewController.didMove(toParent: self)
        overviewController.delegate = self
        // Peek without touching recency so grid previews never disturb eviction order.
        overviewController.previewProvider = { [weak self] id, completion in
            guard let page = self?.tabPool.pages.first(where: { $0.id == id })?.page else {
                completion(nil)
                return
            }
            page.takeSnapshot(completion: completion)
        }
    }

    private func setupErrorOverlay() {
        errorContainer.translatesAutoresizingMaskIntoConstraints = false
        errorContainer.backgroundColor = .systemBackground
        errorContainer.isHidden = true
        view.addSubview(errorContainer)
        NSLayoutConstraint.activate([
            errorContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            errorContainer.topAnchor.constraint(equalTo: view.topAnchor),
            errorContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center
        errorLabel.font = .preferredFont(forTextStyle: .body)
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorContainer.addSubview(errorLabel)
        retryButton.setTitle("Retry", for: .normal)
        retryButton.titleLabel?.adjustsFontForContentSizeCategory = true
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.addAction(UIAction { [weak self] _ in self?.activePage()?.reload() }, for: .touchUpInside)
        errorContainer.addSubview(retryButton)
        NSLayoutConstraint.activate([
            errorLabel.centerXAnchor.constraint(equalTo: errorContainer.safeAreaLayoutGuide.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: errorContainer.centerYAnchor),
            errorLabel.leadingAnchor.constraint(greaterThanOrEqualTo: errorContainer.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            errorLabel.trailingAnchor.constraint(lessThanOrEqualTo: errorContainer.safeAreaLayoutGuide.trailingAnchor, constant: -32),
            retryButton.centerXAnchor.constraint(equalTo: errorContainer.safeAreaLayoutGuide.centerXAnchor),
            retryButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 16)
        ])
    }

    private func setupStartPageContent() {
        guard let bookmarkStore, let historyStore else {
            let fallback = UILabel()
            fallback.text = "Start Page"
            fallback.textAlignment = .center
            fallback.translatesAutoresizingMaskIntoConstraints = false
            startPageContainer.addSubview(fallback)
            NSLayoutConstraint.activate([
                fallback.centerXAnchor.constraint(equalTo: startPageContainer.centerXAnchor),
                fallback.centerYAnchor.constraint(equalTo: startPageContainer.centerYAnchor)
            ])
            return
        }
        let viewModel = StartPageViewModel(bookmarkStore: bookmarkStore, historyStore: historyStore)
        let startView = StartPageView(viewModel: viewModel)
        startView.delegate = self
        startView.onImportTapped = { [weak self] in self?.presentSettings() }
        startView.onDeleteFavorite = { [weak self] id in
            do {
                try self?.bookmarkStore?.delete(id: id)
            } catch {
                self?.logPersistenceError(error, operation: "deleteFavorite")
            }
            self?.updateStartPageContent()
            self?.bookmarksLibraryView.reload()
        }
        startView.translatesAutoresizingMaskIntoConstraints = false
        startPageContainer.addSubview(startView)
        NSLayoutConstraint.activate([
            startView.leadingAnchor.constraint(equalTo: startPageContainer.leadingAnchor),
            startView.trailingAnchor.constraint(equalTo: startPageContainer.trailingAnchor),
            startView.topAnchor.constraint(equalTo: startPageContainer.topAnchor),
            startView.bottomAnchor.constraint(equalTo: startPageContainer.bottomAnchor)
        ])
        startPageView = startView
    }

    // MARK: - App lifecycle

    /// Scene changes forwarded from the app entry. Persistence is owned by the
    /// restore coordinator; foreground only refreshes pool recency so eviction
    /// stays ordered by real activity. Chrome state is intentionally untouched.
    func handleScenePhase(_ phase: ScenePhase) {
        restoreCoordinator?.handleScenePhase(phase)
        if phase == .active {
            markActivePageActivated()
        }
    }

    func logPersistenceError(_ error: Error, operation: String) {
        Logger(subsystem: "com.volcrypt.OuterView", category: "BrowserRoot")
            .error("\(operation, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
    }

    // MARK: - Snapshots

    func ensureSnapshotListener(for id: UUID, page: WebPageController) {
        // A recreated page (after eviction) is a new instance with no
        // listeners; the old controller and its subscriptions are gone.
        if let bound = boundListenerPages[id],
           bound == ObjectIdentifier(page),
           snapshotListenerIDs[id] != nil
        {
            return
        }
        let listenerID = page.addSnapshotListener { [weak self] snapshot in
            guard let self else { return }
            self.handleSnapshot(snapshot, for: id)
        }
        snapshotListenerIDs[id] = listenerID
        boundListenerPages[id] = ObjectIdentifier(page)
    }

    private func handleSnapshot(_ snapshot: WebPageSnapshot, for id: UUID) {
        var didChange = false
        var didCommitNewURL = false
        var isPrivateTab = false
        // Rejected schemes never persist: neither the in-memory strip nor the
        // stores may adopt them, even if the web view somehow reports one.
        let isSnapshotURLAllowed = snapshot.url.map(URLNormalizer.isLoadable) ?? true
        if let index = tabs.firstIndex(where: { $0.id == id }) {
            let record = tabs[index]
            isPrivateTab = record.isPrivate
            if !isSnapshotURLAllowed {
                if record.url != nil || record.title != nil {
                    didChange = true
                    record.url = nil
                    record.title = nil
                    record.lastActiveAt = Date()
                    do {
                        try tabStore?.upsertTab(record)
                    } catch {
                        logPersistenceError(error, operation: "upsertTab")
                    }
                }
            } else if record.url != snapshot.url || record.title != snapshot.title {
                didChange = true
                didCommitNewURL = record.url != snapshot.url && snapshot.url != nil
                record.url = snapshot.url
                record.title = snapshot.title
                record.lastActiveAt = Date()
                do {
                    try tabStore?.upsertTab(record)
                } catch {
                    logPersistenceError(error, operation: "upsertTab")
                }
            }
        }
        // One history row per committed navigation; progress and title refreshes
        // for the same URL must not duplicate it. Private tabs never record.
        if didCommitNewURL, let url = snapshot.url, URLNormalizer.isLoadable(url), snapshot.lastError == nil, !isPrivateTab {
            let title = HostFormatter.displayTitle(url: url, title: snapshot.title)
            do {
                try historyStore?.record(visit: PageVisit(url: url, title: title))
            } catch {
                logPersistenceError(error, operation: "recordVisit")
            }
        }
        if isOverviewVisible, didChange {
            overviewController.setItems(overviewItems(), selectedID: selectedTabID)
        }
        guard id == selectedTabID else { return }
        refreshForSnapshot(snapshot)
    }

    func refreshForActiveSnapshot() {
        guard let page = peekActivePage() else {
            startPageContainer.isHidden = false
            return
        }
        refreshForSnapshot(page.snapshot)
    }

    func refreshForSnapshot(_ snapshot: WebPageSnapshot) {
        guard let id = selectedTabID else { return }
        let showStart = shouldShowStartPage(for: id, snapshot: snapshot)
        startPageContainer.isHidden = !showStart
        if let webView = peekActivePage()?.webView {
            webView.isHidden = showStart
        }
        updateStartPageContent(with: snapshot)
        updatePillForSnapshot(snapshot)
        updateErrorOverlay(for: snapshot)
        updateRailItems()
    }

    func updateStartPageContent(with snapshot: WebPageSnapshot? = nil) {
        let snapshot = snapshot ?? peekActivePage()?.snapshot
        startPageView?.updateActivePage(url: snapshot?.url, title: snapshot?.title)
        startPageView?.reload()
    }

    private func updatePillForSnapshot(_ snapshot: WebPageSnapshot) {
        let isLoading = snapshot.url != nil && snapshot.progress < 1 && snapshot.lastError == nil
        pillView.configure(url: snapshot.url, isSecure: snapshot.isSecure, isLoading: isLoading)
    }

    // MARK: - Fold handling

    func scheduleStructuralUpdate() {
        structuralTask?.cancel()
        structuralTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(Self.structuralDebounceInterval * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.applyStructuralLayout()
        }
    }

    // MARK: - Error overlay

    func updateErrorOverlay(for snapshot: WebPageSnapshot) {
        guard let message = snapshot.lastError else {
            errorContainer.isHidden = true
            return
        }
        errorContainer.isHidden = false
        errorLabel.text = message
        bringChromeToFront()
        UIAccessibility.post(notification: .screenChanged, argument: errorContainer)
    }

    // MARK: - Bridges for same-type extensions

    /// Single gateway for the browsing-resumed FSM input so extensions never
    /// touch the state machine directly.
    func applyBrowsingResumed(animated: Bool) {
        let commands = chromeController.handle(.browsingResumed)
        applyCommands(commands, animated: animated)
    }

    func setOverviewMode(_ mode: TabOverviewMode) {
        overviewMode = mode
    }

    func clearForcedStartPageForSelectedTab() {
        if let id = selectedTabID {
            forcedStartPageTabs.remove(id)
        }
    }

    func saveFavorite(url: URL, title: String) {
        guard URLNormalizer.isLoadable(url) else { return }
        do {
            try bookmarkStore?.upsertFavorite(url: url, title: title)
        } catch {
            logPersistenceError(error, operation: "upsertFavorite")
        }
    }

    func makeSettingsController() -> UIViewController? {
        guard let database else { return nil }
        var settingsView = SettingsView(database: database)
        settingsView.onDidClearHistory = { [weak self] in self?.refreshStartPageAfterHistoryClear() }
        settingsView.onDidClearTabs = { [weak self] in self?.resetAllTabsToSingleEmptyTab() }
        return UIHostingController(rootView: settingsView)
    }

    /// Re-reads history-backed start page content after Settings clears the
    /// store so the recents list empties immediately.
    func refreshStartPageAfterHistoryClear() {
        startPageView?.viewModel.reload()
        updateStartPageContent()
    }

    /// Presents an action sheet or share sheet anchored to the pill so callers
    /// never reach the chrome views.
    func presentPopover(_ controller: UIViewController) {
        if let popover = controller.popoverPresentationController {
            popover.sourceView = pillView
            popover.sourceRect = pillView.bounds
        }
        present(controller, animated: true)
    }
}
