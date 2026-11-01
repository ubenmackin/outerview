//
//  BrowserRootViewController.swift
//  OuterView
//

import os
import Photos
import SwiftUI
import UIKit

/// Failure kind distinguishing Photos permission denial, which is surfaced to
/// the user, from ordinary save errors, which are only logged.
private enum PhotoSaveFailure: Error {
    case accessDenied
}

/// Single chrome applier: tab content, floating rail + pill, editor, error
/// overlay, and tab overview placeholder. Content renders full-bleed while
/// chrome floats above it.
/// UserDefaults keys libraryTab as Int, overviewMode as String, and overviewGroup as String.
/// Values are read at init and setup and written on every change; private mode is never
/// written and restores as standard. Unparseable values fall back to bookmarks, standard,
/// and nil; a stored group id resolving to no existing group restores as nil.
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

    /// Shared Contract REGULAR-COLLAPSE: collapsed keeps topBarView visible with
    /// both stacks plus strip hidden; expanded centered with min(380,slotWidth)
    /// and collapsed centered with domain-hugging capsule width capped at
    /// min(220,slotWidth); collapsed top inset equals TopBarView.remnantHeight;
    /// additionalSafeArea top is zero in every placement and state; no remnant view exists anywhere.
    nonisolated static var regularRemnantHeight: CGFloat {
        TopBarView.remnantHeight
    }

    nonisolated static var regularTrailingClearance: CGFloat {
        TopBarView.trailingStatusInset
    }

    /// Regular pill width capped by the laid-out slot; zero slot defers to the cap until layout runs.
    nonisolated static func regularPillTarget(
        slotWidth: CGFloat,
        isMinified: Bool,
        preferredMinifiedWidth: CGFloat = AddressBarView.minifiedMaxWidth
    ) -> CGFloat {
        let cap = isMinified
            ? min(AddressBarView.minifiedMaxWidth, preferredMinifiedWidth)
            : TopBarView.expandedPillMaxWidth
        return slotWidth > 0 ? min(cap, slotWidth) : cap
    }

    nonisolated static func topContentInset(
        for placement: ChromePlacement,
        state: ChromeState,
        stripVisible: Bool
    ) -> CGFloat {
        guard placement == .regular else { return 0 }
        if state.pill == .editing || state.rail == .visible {
            return TopBarView.barHeight + (stripVisible ? TabStripView.stripHeight : 0)
        }
        return TopBarView.remnantHeight
    }

    nonisolated static func additionalSafeAreaTopInset(
        for _: ChromePlacement,
        state _: ChromeState
    ) -> CGFloat {
        0
    }

    nonisolated static func compensatedOffset(current: CGPoint, oldTop: CGFloat, newTop: CGFloat) -> CGPoint {
        let shiftedY = current.y + (newTop - oldTop)
        return CGPoint(x: current.x, y: max(0, shiftedY))
    }

    /// Bounds width the minified capsule measures against. The minified pill
    /// centers on the full view because the rail is out of the way whenever
    /// the user is scrolling.
    var pillReferenceWidth: CGFloat {
        view.bounds.width
    }

    /// Regular width uses the top toolbar with the centered pill and no rail.
    var chromePlacement: ChromePlacement {
        Self.placement(for: traitCollection.horizontalSizeClass)
    }

    nonisolated static func placement(for sizeClass: UIUserInterfaceSizeClass) -> ChromePlacement {
        sizeClass == .regular ? .regular : .compact
    }

    /// Regular disables the vertical bar so status moves to the top axis;
    /// compact keeps automatic so the outer column inset is never at risk.
    nonisolated static func verticalBarBehavior(for placement: ChromePlacement) -> UIVerticalBarBehavior {
        placement == .regular ? .disabled : .automatic
    }

    override var preferredVerticalBarBehavior: UIVerticalBarBehavior {
        Self.verticalBarBehavior(for: chromePlacement)
    }

    nonisolated static func isRegularCollapsed(
        state: ChromeState,
        isOverviewVisible: Bool,
        isSheetOverlayVisible: Bool
    ) -> Bool {
        if state.pill == .editing || isOverviewVisible || isSheetOverlayVisible {
            return false
        }
        return state.rail == .hidden
    }

    nonisolated static func shouldHideStatusBar(
        for placement: ChromePlacement,
        state: ChromeState,
        isOverviewVisible: Bool,
        isSheetOverlayVisible: Bool
    ) -> Bool {
        guard placement == .regular else { return false }
        return isRegularCollapsed(
            state: state,
            isOverviewVisible: isOverviewVisible,
            isSheetOverlayVisible: isSheetOverlayVisible
        )
    }

    override var prefersStatusBarHidden: Bool {
        Self.shouldHideStatusBar(
            for: chromePlacement,
            state: chromeController.state,
            isOverviewVisible: isOverviewVisible,
            isSheetOverlayVisible: isSheetOverlayVisible
        )
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }

    func refreshStatusBarAppearanceIfNeeded() {
        let hidden = prefersStatusBarHidden
        guard lastStatusBarHidden != hidden else { return }
        lastStatusBarHidden = hidden
        setNeedsStatusBarAppearanceUpdate()
    }

    /// Moves the shared pill between the bottom anchors and the toolbar slot.
    func applyChromePlacement() {
        applyChromePlacement(for: chromePlacement)
    }

    func applyChromePlacement(for placement: ChromePlacement) {
        let isRegular = placement == .regular
        topBarView.isHidden = !isRegular
        railView.isHidden = isRegular
        if isRegular {
            updateToolbarVisibility(for: chromeController.state)
            if pillView.superview !== topBarView.pillSlotView {
                NSLayoutConstraint.deactivate([
                    pillBottomConstraint,
                    pillLeadingConstraint,
                    pillTrailingConstraint,
                    pillCenterXConstraint,
                    pillWidthConstraint
                ])
                pillView.removeFromSuperview()
                pillView.translatesAutoresizingMaskIntoConstraints = false
                topBarView.pillSlotView.addSubview(pillView)
                pillSlotCenterXConstraint.isActive = false
                pillSlotWidthConstraint.isActive = false
                NSLayoutConstraint.activate([
                    pillSlotLeadingConstraint,
                    pillSlotTrailingConstraint,
                    pillSlotCenterYConstraint
                ])
            } else {
                pillBottomConstraint.isActive = false
                pillLeadingConstraint.isActive = false
                pillTrailingConstraint.isActive = false
                pillCenterXConstraint.isActive = false
                pillWidthConstraint.isActive = false
                pillSlotCenterYConstraint.isActive = true
            }
            updateRegularPillGeometry()
        } else {
            topBarAnimator?.stopAnimation(false)
            topBarAnimator?.finishAnimation(at: .current)
            topBarAnimator = nil
            if pillView.superview !== view {
                NSLayoutConstraint.deactivate([
                    pillSlotLeadingConstraint,
                    pillSlotTrailingConstraint,
                    pillSlotCenterYConstraint,
                    pillSlotCenterXConstraint,
                    pillSlotWidthConstraint,
                    pillSlotMinLeadingConstraint,
                    pillSlotMaxTrailingConstraint
                ])
                pillView.removeFromSuperview()
                pillView.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(pillView)
            } else {
                pillSlotLeadingConstraint.isActive = false
                pillSlotTrailingConstraint.isActive = false
                pillSlotCenterYConstraint.isActive = false
                pillSlotCenterXConstraint.isActive = false
                pillSlotWidthConstraint.isActive = false
                pillSlotMinLeadingConstraint.isActive = false
                pillSlotMaxTrailingConstraint.isActive = false
            }
            let isMinified = chromeController.state.pill == .minified
            pillBottomConstraint.isActive = true
            pillHeightConstraint.isActive = true
            pillLeadingConstraint.isActive = !isMinified
            pillTrailingConstraint.isActive = !isMinified
            pillCenterXConstraint.isActive = isMinified
            pillWidthConstraint.isActive = isMinified
            if isMinified {
                pillWidthConstraint.constant = AddressBarView.widthForBounds(pillReferenceWidth)
            }
        }
        editorView.applyPlacement(for: placement)
        if !isOverviewVisible {
            updateRailItems()
        }
        updateTabStrip()
        updateTopBarPinning(for: placement)
        updateHeaderBackgrounds()
        updateStartPageTop()
        refreshStatusBarAppearanceIfNeeded()
        bringChromeToFront()
    }

    // MARK: - Layers

    let contentContainer = UIView()
    let startPageContainer = UIView()
    let errorContainer = UIView()
    let errorStackView = UIStackView()
    let errorIconView = UIImageView()
    let errorTitleLabel = UILabel()
    let errorHostLabel = UILabel()
    let errorDetailLabel = UILabel()
    let errorHintLabel = UILabel()
    let errorButtonStack = UIStackView()
    let retryButton = UIButton(type: .system)
    let copyErrorButton = UIButton(type: .system)
    var errorCopyText = ""
    let railView = SideRailView()
    let pillView = AddressBarView()
    let topBarView = TopBarView()
    let tabStripView = TabStripView()
    let findView = FindInPageView()
    let editorView = AddressEditorView()
    let bookmarksLibraryView: BookmarksLibraryView
    let settingsContainer = UIView()
    var settingsHosting: UIViewController?
    var isSettingsVisible = false
    let downloadsContainer = UIView()
    var downloadsHosting: UIViewController?
    var isDownloadsVisible = false

    let libraryOverlay = OverlayCardView()
    let settingsOverlay = OverlayCardView()
    let downloadsOverlay = OverlayCardView()
    let bookmarkEditorOverlay = OverlayCardView()
    var libraryCompactConstraints: [NSLayoutConstraint] = []
    var librarySheetController: LibrarySheetViewController?
    /// Last Files picker issued by the downloads rail. Retained so the
    /// wiring stays observable when the host blocks modal presentation.
    var presentedDownloadsPicker: UIDocumentPickerViewController?
    let bookmarkEditorContainer = UIView()
    var bookmarkEditorHosting: UIHostingController<BookmarkEditorView>?
    var activeBookmarkEditorModel: BookmarkEditorModel?
    var isBookmarkEditorVisible = false
    var isBookmarkEditorPresentedModally = false

    var isLibrarySheetPresented: Bool {
        librarySheetController?.presentingViewController != nil
    }

    /// Read-only inline-command state for the bookmark editor sheet. Tests
    /// verify behaviour through this accessor instead of reaching the hosting
    /// controller directly.
    var bookmarkEditorInlineCommands: Bool? {
        bookmarkEditorHosting?.rootView.inlineCommands
    }

    var bookmarkEditorShowsInlineCancel: Bool? {
        bookmarkEditorHosting?.rootView.showsInlineCancel
    }

    var bookmarkEditorShowsInlineSave: Bool? {
        bookmarkEditorHosting?.rootView.showsInlineSave
    }

    func performBookmarkEditorCancel() {
        bookmarkEditorHosting?.rootView.performInlineCancel()
    }

    func performBookmarkEditorSave() {
        bookmarkEditorHosting?.rootView.performInlineSave()
    }

    /// Any library/settings/downloads/editor sheet is on screen. Used to keep
    /// the `.regular` top bar un-collapsed and the status bar visible while a
    /// sheet or modal library is presented.
    var isSheetOverlayVisible: Bool {
        isLibraryVisible || isSettingsVisible || isDownloadsVisible || isBookmarkEditorVisible
    }

    /// Inline `OverlayCardView` sheets hide `TopBarView`'s button stacks on
    /// `.regular`. Modal `LibrarySheetViewController` and `.regular` address
    /// editing keep `TopBarView`'s browsing buttons visible underneath.
    var suppressesRegularToolbarButtons: Bool {
        isSettingsVisible || isDownloadsVisible || (isBookmarkEditorVisible && !isBookmarkEditorPresentedModally)
    }

    var isEditingAddress = false
    var isFindActive = false
    var findBottomConstraint: NSLayoutConstraint?
    let overviewView = UIView()
    let overviewController: TabOverviewViewController
    var overviewMode: TabOverviewMode {
        didSet {
            guard isViewLoaded else { return }
            updateTabStrip()
        }
    }

    let selectionDefaults: UserDefaults

    var pillHeightConstraint: NSLayoutConstraint!
    var pillBottomConstraint: NSLayoutConstraint!
    var pillLeadingConstraint: NSLayoutConstraint!
    var pillTrailingConstraint: NSLayoutConstraint!
    var pillWidthConstraint: NSLayoutConstraint!
    var pillCenterXConstraint: NSLayoutConstraint!
    var pillSlotLeadingConstraint: NSLayoutConstraint!
    var pillSlotTrailingConstraint: NSLayoutConstraint!
    var pillSlotCenterYConstraint: NSLayoutConstraint!
    var pillSlotCenterXConstraint: NSLayoutConstraint!
    var pillSlotWidthConstraint: NSLayoutConstraint!
    var pillSlotMinLeadingConstraint: NSLayoutConstraint!
    var pillSlotMaxTrailingConstraint: NSLayoutConstraint!
    var topBarTopConstraint: NSLayoutConstraint!
    var topBarTopToViewConstraint: NSLayoutConstraint?
    var topBarTopToSafeAreaConstraint: NSLayoutConstraint?
    var topBarLeadingConstraint: NSLayoutConstraint!
    var topBarTrailingConstraint: NSLayoutConstraint!
    var startPageTopToContentConstraint: NSLayoutConstraint?
    var startPageTopToStripConstraint: NSLayoutConstraint?
    var startPageTopToBarConstraint: NSLayoutConstraint?
    var pillAnimator: UIViewPropertyAnimator?
    var topBarAnimator: UIViewPropertyAnimator?
    var lastStatusBarHidden: Bool?
    private var structuralTask: Task<Void, Never>?
    private var horizontalSizeClassRegistration: UITraitChangeRegistration?
    private var lastVerticalBarPlacement: ChromePlacement?
    /// Poke count for the vertical-bar configuration; tests observe it to
    /// confirm a placement change invalidated the system configuration.
    var verticalBarConfigurationUpdateCount = 0
    var suggestionTask: Task<Void, Never>?
    var findQueryTask: Task<Void, Never>?
    var findStepTask: Task<Void, Never>?

    // MARK: - State

    var chromeController = ChromeStateController()
    var tabs: [TabRecord] = [] {
        didSet {
            guard isViewLoaded else { return }
            updateTabStrip()
        }
    }

    var selectedTabID: UUID? {
        didSet {
            guard isViewLoaded else { return }
            updateTabStrip()
        }
    }

    var isOverviewVisible = false
    var isLibraryVisible = false

    let tabPool = TabPool()
    var scrollProxies: [UUID: ChromeScrollProxy] = [:]
    var snapshotListenerIDs: [UUID: UUID] = [:]
    var forcedStartPageTabs = Set<UUID>()
    var startPageView: StartPageView?
    /// Single construction site for element context-menu actions; every page
    /// receives it when its snapshot listener is wired.
    private(set) var elementContextActions: ElementContextActions?
    /// Shared per-site text zoom; every page receives it at the same wiring
    /// site so zoom persists across tabs and relaunch.
    let siteZoomStore = SiteZoomStore()
    /// Shared download pipeline; every page reports into it at the same
    /// wiring site so navigation-driven downloads always land.
    let downloadsManager = DownloadsManager()

    private var database: OuterViewDatabase?
    var bookmarkStore: BookmarkStore?
    var historyStore: HistoryStore?
    var readingListStore: ReadingListStore?
    private(set) var recentSearchStore: RecentSearchStore?
    var tabStore: TabStore?
    var restoreCoordinator: SessionRestoreCoordinator?
    var boundListenerPages: [UUID: ObjectIdentifier] = [:]

    /// Camera/system occlusion union forwarded to the rail. Derived from the
    /// current bounds on every layout pass so chrome stays below the top
    /// status/camera region on both displays.
    private var reservedOcclusionUnion: CGRect = .zero

    init(database: OuterViewDatabase? = nil, defaults: UserDefaults = .standard) {
        self.selectionDefaults = defaults
        self.bookmarksLibraryView = BookmarksLibraryView(defaults: defaults)
        self.overviewController = TabOverviewViewController()
        self.overviewMode = TabOverviewViewController.storedOverviewMode(defaults: defaults)
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
        overviewController.selectionDefaults = defaults
        elementContextActions = makeElementContextActions()
        if let database = self.database {
            bookmarkStore = BookmarkStore(database: database)
            historyStore = HistoryStore(database: database)
            readingListStore = ReadingListStore(database: database)
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
        wireLibraryInlineCommands()
        setupStartPageContent()
        applyChromePlacement()
        lastVerticalBarPlacement = chromePlacement
        updateRailItems()
        loadInitialTabs()
        applyContentInsets()
        applyChromeViews(animated: false)
        subscribeToDownloadProgress()
        updateDownloadProgress()
        observeHorizontalSizeClass()
    }

    func wireLibraryInlineCommands() {
        bookmarksLibraryView.onInlineAddFolder = { [weak self] in
            self?.bookmarksLibraryView.promptNewFolder()
        }
        bookmarksLibraryView.onInlineToggleEdit = { [weak self] in
            guard let self else { return }
            self.bookmarksLibraryView.toggleBookmarksEdit()
            self.updateLibraryRailItems(for: .bookmarks)
        }
        bookmarksLibraryView.onInlineClearHistory = { [weak self] in
            self?.bookmarksLibraryView.promptClearHistory()
        }
        bookmarksLibraryView.onInlineDelete = { [weak self] in
            guard let self else { return }
            let tab = self.bookmarksLibraryView.currentTab
            self.bookmarksLibraryView.deleteSelectedItemsForActiveTab()
            self.updateStartPageContent()
            self.updateLibraryRailItems(for: tab)
        }
        bookmarksLibraryView.onInlineDone = { [weak self] in
            self?.closeBookmarksLibrary()
        }
        bookmarksLibraryView.updateInlineCommands()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updatePillBottomOffset()
        updateFindBottomOffset()
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
        if pillSlotWidthConstraint.isActive {
            let target = Self.regularPillTarget(
                slotWidth: topBarView.pillSlotView.bounds.width,
                isMinified: chromeController.state.pill == .minified,
                preferredMinifiedWidth: pillView.preferredMinifiedWidth()
            )
            if pillSlotWidthConstraint.constant != target {
                pillSlotWidthConstraint.constant = target
            }
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        scheduleStructuralUpdate()
    }

    private func observeHorizontalSizeClass() {
        // Fold state follows size class; bounds-driven sizing stays
        // in layoutSubviews and viewWillTransition.
        horizontalSizeClassRegistration = registerForTraitChanges([UITraitHorizontalSizeClass.self]) { @MainActor (owner: BrowserRootViewController, previous: UITraitCollection) in
            if previous.horizontalSizeClass != owner.traitCollection.horizontalSizeClass {
                owner.scheduleStructuralUpdate()
            }
        }
    }
}

extension BrowserRootViewController {
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
        // listeners; the old controller and its subscriptions are gone. It
        // also arrives with no menu wiring, so context actions reattach here.
        page.contextActions = elementContextActions
        page.siteZoomStore = siteZoomStore
        page.downloadsManager = downloadsManager
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
        var didTitleChange = false
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
                didTitleChange = record.title != snapshot.title
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
        if !didCommitNewURL, didTitleChange, !isPrivateTab, snapshot.lastError == nil, let url = snapshot.url, URLNormalizer.isLoadable(url),
           tabs.first(where: { $0.id == id })?.url == url,
           let trimmed = snapshot.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmed.isEmpty
        {
            let title = HostFormatter.displayTitle(url: url, title: trimmed)
            do {
                try historyStore?.refreshTitle(url: url, title: title)
            } catch {
                logPersistenceError(error, operation: "refreshHistoryTitle")
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
        startPageView?.viewModel.reload()
        let snapshot = snapshot ?? peekActivePage()?.snapshot
        startPageView?.updateActivePage(url: snapshot?.url, title: snapshot?.title)
        startPageView?.reload()
        if isEditingAddress {
            let favorites = StartPageViewModel.sortedFavorites(bookmarkStore?.fetchFavorites() ?? [])
            editorView.setFavorites(favorites)
        }
    }

    private func updatePillForSnapshot(_ snapshot: WebPageSnapshot) {
        let isLoading = snapshot.url != nil && snapshot.progress < 1 && snapshot.lastError == nil
        pillView.configure(url: snapshot.url, isSecure: snapshot.isSecure, isLoading: isLoading)
        if chromePlacement == .regular, chromeController.state.pill == .minified {
            updateRegularPillGeometry()
        }
    }

    // MARK: - Fold handling

    func scheduleStructuralUpdate() {
        structuralTask?.cancel()
        structuralTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(Self.structuralDebounceInterval * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.applyStructuralLayout()
        }
    }

    func applyStructuralLayout() {
        let placement = chromePlacement
        if lastVerticalBarPlacement != placement {
            lastVerticalBarPlacement = placement
            verticalBarConfigurationUpdateCount += 1
            setNeedsUpdateOfVerticalBarConfiguration()
        }
        applyChromePlacement(for: placement)
        editorView.chromePlacement = placement
        overviewController.showsInlineCommands = (placement == .regular)
        for overlay in [libraryOverlay, settingsOverlay, downloadsOverlay, bookmarkEditorOverlay]
            where overlay.isHidden
        {
            overlay.applyPlacement(for: placement)
        }
        if !isLibraryVisible {
            bookmarksLibraryView.applyPlacement(for: placement)
        } else if placement == .compact, let sheet = librarySheetController {
            sheet.onDidDismiss = nil
            sheet.dismiss(animated: false)
            sheet.detachLibraryView()
            librarySheetController = nil
            if bookmarksLibraryView.superview !== view {
                view.addSubview(bookmarksLibraryView)
                NSLayoutConstraint.activate(libraryCompactConstraints)
            }
            bookmarksLibraryView.applyPlacement(for: .compact)
            bookmarksLibraryView.isHidden = false
        }
        if isEditingAddress, let id = selectedTabID, peekActivePage()?.snapshot.url != nil {
            if placement == .regular {
                forcedStartPageTabs.remove(id)
            } else {
                forcedStartPageTabs.insert(id)
            }
        }
        updateTabStrip()
        updateTopBarPinning(for: placement)
        updateHeaderBackgrounds()
        updateStartPageTop()
        refreshForActiveSnapshot()
        applyChromeViews(animated: false)
        applyContentInsets()
        view.setNeedsLayout()
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
        // Private mode is never written; a private selection clears the stored group.
        if mode.isPrivate {
            selectionDefaults.removeObject(forKey: TabOverviewViewController.overviewModeDefaultsKey)
            selectionDefaults.removeObject(forKey: TabOverviewViewController.overviewGroupDefaultsKey)
        } else {
            TabOverviewViewController.persistOverviewSelection(
                mode: mode,
                groupID: overviewController.selectedGroupID,
                defaults: selectionDefaults
            )
        }
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
        var settingsView = SettingsView(
            database: database,
            siteZoomStore: siteZoomStore,
            inlineCommands: chromePlacement == .regular
        )
        settingsView.onDidClearHistory = { [weak self] in self?.refreshStartPageAfterHistoryClear() }
        settingsView.onDidClearTabs = { [weak self] in self?.resetAllTabsToSingleEmptyTab() }
        settingsView.onDone = { [weak self] in self?.dismissSettingsSheet() }
        return UIHostingController(rootView: settingsView)
    }

    /// Re-reads history-backed start page content after Settings clears the
    /// store so the recents list empties immediately.
    func refreshStartPageAfterHistoryClear() {
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

    // MARK: - Element context actions

    /// The only place action closures are constructed: each maps a URL back
    /// to a root-level capability, so pages never reach into stores directly.
    private func makeElementContextActions() -> ElementContextActions {
        ElementContextActions(
            openInNewTab: { [weak self] url in
                self?.openInNewTab(url: url)
            },
            addToReadingList: { [weak self] url in
                self?.addReadingListEntry(url: url)
            },
            copyLink: { [weak self] url in
                self?.copyElementURLToPasteboard(url)
            },
            share: { [weak self] url in
                self?.shareElementURL(url)
            },
            saveToPhotos: { [weak self] url in
                self?.saveImageToPhotos(from: url)
            },
            copyImage: { [weak self] url in
                self?.copyElementURLToPasteboard(url)
            }
        )
    }

    private func addReadingListEntry(url: URL) {
        guard URLNormalizer.isLoadable(url) else { return }
        let title = HostFormatter.displayTitle(url: url, title: nil)
        do {
            try readingListStore?.add(title: title, url: url)
        } catch {
            logPersistenceError(error, operation: "addToReadingList")
        }
    }

    private func copyElementURLToPasteboard(_ url: URL) {
        UIPasteboard.general.url = url
    }

    private func shareElementURL(_ url: URL) {
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        presentPopover(activity)
    }

    private func saveImageToPhotos(from url: URL) {
        guard URLNormalizer.isLoadable(url) else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                try await saveImageDataToPhotos(data)
            } catch {
                processPhotoSaveFailure(error)
            }
        }
    }

    /// Prompts for add-only Photos access on the first save, then inserts the
    /// downloaded bytes as a single photo resource.
    private func saveImageDataToPhotos(_ data: Data) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard granted == .authorized || granted == .limited else {
                throw PhotoSaveFailure.accessDenied
            }
        case .limited, .authorized:
            break
        default:
            throw PhotoSaveFailure.accessDenied
        }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }
    }

    private func processPhotoSaveFailure(_ error: Error) {
        // Permission denial is the only failure users can act on; the rest
        // stays a log entry so failed saves never retry behind the user's back.
        guard error is PhotoSaveFailure else {
            logPersistenceError(error, operation: "saveImageToPhotos")
            return
        }
        let alert = UIAlertController(
            title: "Can't Save Photo",
            message: "OuterView does not have permission to add to your photo library.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
