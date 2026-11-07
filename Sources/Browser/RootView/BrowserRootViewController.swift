// RootView — Central browser coordinator owning chrome placement and tab content.

import os
import SwiftUI

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

    /// Mode 3 parks web content below the status cluster: inset equals
    /// live safeAreaTop, never zero when a top inset is vended.
    nonisolated static func topContentInset(
        for placement: ChromePlacement,
        state: ChromeState,
        stripVisible: Bool,
        interfaceMode: BrowserInterfaceMode = .duoInnerOrPad,
        safeAreaTop: CGFloat = 0
    ) -> CGFloat {
        if interfaceMode == .nonDuoPhone {
            return max(0, safeAreaTop)
        }
        guard placement == .regular else { return 0 }
        if state.pill == .editing || state.pill != .minified {
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
        let shiftedY = current.y + (oldTop - newTop)
        return CGPoint(x: current.x, y: max(-newTop, shiftedY))
    }

    /// Bounds width the minified capsule measures against. The minified pill
    /// centers on the full view because the rail is out of the way whenever
    /// the user is scrolling.
    var pillReferenceWidth: CGFloat {
        view.bounds.width
    }

    nonisolated static func isDuoOuterDisplay(
        safeAreaInsets: UIEdgeInsets = .zero,
        bounds: CGRect = .zero,
        deviceName: String? = nil
    ) -> Bool {
        if safeAreaInsets.right >= 44 {
            return true
        }
        if abs(bounds.width - 466) < 1 || abs(bounds.height - 466) < 1 {
            return true
        }
        let envDeviceName = deviceName ?? ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]
        if let name = envDeviceName, name.localizedCaseInsensitiveContains("Duo") {
            return true
        }
        return false
    }

    nonisolated static func interfaceMode(
        horizontalSizeClass: UIUserInterfaceSizeClass,
        safeAreaInsets: UIEdgeInsets = .zero,
        bounds: CGRect = .zero,
        deviceName: String? = nil
    ) -> BrowserInterfaceMode {
        if CommandLine.arguments.contains("-OuterViewInnerDisplay") || horizontalSizeClass == .regular {
            return .duoInnerOrPad
        }
        if CommandLine.arguments.contains("-OuterViewNonDuoPhone") {
            return .nonDuoPhone
        }
        if CommandLine.arguments.contains("-OuterViewDuoOuter") {
            return .duoOuter
        }
        if isDuoOuterDisplay(safeAreaInsets: safeAreaInsets, bounds: bounds, deviceName: deviceName) {
            return .duoOuter
        }
        return .nonDuoPhone
    }

    var interfaceMode: BrowserInterfaceMode {
        let windowBounds = view.window?.bounds
        let effectiveBounds: CGRect = if let wb = windowBounds, wb.width > 0 {
            wb
        } else {
            view.bounds
        }
        let windowInsets = view.window?.safeAreaInsets ?? .zero
        let effectiveSafeArea = windowInsets.right > 0 ? windowInsets : view.safeAreaInsets
        return Self.interfaceMode(
            horizontalSizeClass: traitCollection.horizontalSizeClass,
            safeAreaInsets: effectiveSafeArea,
            bounds: effectiveBounds
        )
    }

    /// Regular width uses the top toolbar with the centered pill and no rail.
    var chromePlacement: ChromePlacement {
        interfaceMode == .duoInnerOrPad ? .regular : .compact
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
        return state.pill == .minified
    }

    nonisolated static func shouldHideStatusBar(
        for mode: BrowserInterfaceMode,
        state: ChromeState,
        isOverviewVisible: Bool,
        isSheetOverlayVisible: Bool
    ) -> Bool {
        // Active in both Mode 1 (Duo outer screen) and Mode 2 (Duo inner screen + iPads)
        // when scrolling down and the address bar is collapsed (minified).
        guard mode == .duoOuter || mode == .duoInnerOrPad else { return false }
        if state.pill == .editing || isOverviewVisible || isSheetOverlayVisible {
            return false
        }
        return state.pill == .minified
    }

    override var prefersStatusBarHidden: Bool {
        Self.shouldHideStatusBar(
            for: interfaceMode,
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
        parent?.setNeedsStatusBarAppearanceUpdate()
    }

    /// Mode 3 shows the transparent bar for the editor overlay.
    /// Editor over library keeps the bar so Cancel/Save stay reachable.
    var shouldShowNonDuoTopBar: Bool {
        (isBookmarkEditorVisible && !isBookmarkEditorPresentedModally)
            && !isOverviewVisible
    }

    /// Any sheet or overview covering the Mode 3 browsing chrome.
    var isNonDuoChromeOverlay: Bool {
        isOverviewVisible || (isBookmarkEditorVisible && !isBookmarkEditorPresentedModally)
    }

    /// Single visibility owner for Mode 3 bottom pill versus transparent bar versus hidden.
    func applyNonDuoChromeVisibility() {
        guard interfaceMode == .nonDuoPhone, chromePlacement != .regular else { return }
        let showsTopBar = shouldShowNonDuoTopBar
        let isOverlay = isNonDuoChromeOverlay
        let hideBottomButtons = isOverlay || chromeController.state.pill == .minified || chromeController.state.rail == .hidden
        topBarView.isHidden = !showsTopBar
        topBarView.showsBackgroundBar = !showsTopBar
        bottomLeadingStack.alpha = hideBottomButtons ? 0 : 1
        bottomTrailingStack.alpha = hideBottomButtons ? 0 : 1
        bottomLeadingStack.isUserInteractionEnabled = !hideBottomButtons
        bottomTrailingStack.isUserInteractionEnabled = !hideBottomButtons
        let hideLeading = hideBottomButtons || isLibraryVisible || bottomLeadingStack.arrangedSubviews.isEmpty
        bottomLeadingStack.isHidden = hideLeading
        bottomTrailingStack.isHidden = hideBottomButtons || bottomTrailingStack.arrangedSubviews.isEmpty
        pillView.showsPageMenu = !isLibraryVisible
        if isOverlay {
            pillView.isHidden = true
        } else if isFindActive, chromeController.state.pill != .editing {
            pillView.isHidden = true
        } else {
            pillView.isHidden = chromeController.state.pill == .editing
        }
        let isMinified = chromeController.state.pill == .minified
        if !isMinified {
            if hideLeading {
                pillBottomLeadingConstraint?.isActive = false
                pillLeadingConstraint.isActive = true
            } else {
                pillLeadingConstraint.isActive = false
                pillBottomLeadingConstraint?.isActive = true
            }
        }
    }

    /// Moves the shared pill between the bottom anchors and the toolbar slot.
    func applyChromePlacement() {
        applyChromePlacement(for: chromePlacement)
    }

    func applyChromePlacement(for placement: ChromePlacement) {
        let isRegular = placement == .regular
        let isNonDuo = (interfaceMode == .nonDuoPhone) && !isRegular
        pillView.isSwipeEnabled = interfaceMode != .duoInnerOrPad

        topBarView.isNonDuoPhone = isNonDuo
        if isRegular {
            topBarView.showsBackgroundBar = true
        } else if isNonDuo {
            topBarView.showsBackgroundBar = !shouldShowNonDuoTopBar
        } else {
            topBarView.showsBackgroundBar = true
        }
        topBarView.isHidden = !isRegular
        railView.isHidden = isRegular || isNonDuo

        if isRegular {
            bottomLeadingStack.isHidden = true
            bottomTrailingStack.isHidden = true
            updateToolbarVisibility(for: chromeController.state)
            if pillView.superview !== topBarView.pillSlotView {
                NSLayoutConstraint.deactivate([
                    pillBottomConstraint,
                    pillLeadingConstraint,
                    pillTrailingConstraint,
                    pillCenterXConstraint,
                    pillWidthConstraint
                ])
                pillBottomLeadingConstraint?.isActive = false
                pillBottomTrailingConstraint?.isActive = false
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
                pillBottomLeadingConstraint?.isActive = false
                pillBottomTrailingConstraint?.isActive = false
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
            if isNonDuo {
                pillLeadingConstraint.isActive = false
                pillTrailingConstraint.isActive = false
                pillBottomLeadingConstraint?.isActive = !isMinified
                pillBottomTrailingConstraint?.isActive = !isMinified
                pillCenterXConstraint.isActive = isMinified
                pillWidthConstraint.isActive = isMinified
                applyNonDuoChromeVisibility()
            } else {
                bottomLeadingStack.isHidden = true
                bottomTrailingStack.isHidden = true
                pillBottomLeadingConstraint?.isActive = false
                pillBottomTrailingConstraint?.isActive = false
                pillLeadingConstraint.isActive = !isMinified
                pillTrailingConstraint.isActive = !isMinified
                pillCenterXConstraint.isActive = isMinified
                pillWidthConstraint.isActive = isMinified
            }
            if isMinified {
                pillWidthConstraint.constant = AddressBarView.widthForBounds(pillReferenceWidth)
            }
        }
        overviewController.isRegular = (placement == .regular)
        overviewController.showsInlineCommands = (interfaceMode == .nonDuoPhone)
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
    let bottomLeadingStack = UIStackView()
    let bottomTrailingStack = UIStackView()
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
    /// `.regular`. Modal sheets (Settings, Downloads, Library) keep
    /// `TopBarView`'s browsing buttons and tab strip visible underneath.
    var suppressesRegularToolbarButtons: Bool {
        isBookmarkEditorVisible && !isBookmarkEditorPresentedModally
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
    var pillBottomLeadingConstraint: NSLayoutConstraint!
    var pillBottomTrailingConstraint: NSLayoutConstraint!
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
    /// Live horizontal pill-switch session plus its settle animator. Stored on
    /// the instance so gestures never outlive the controller via a global.
    var horizontalSwitchSession: HorizontalSwitchSession?
    var horizontalSwitchAnimator: UIViewPropertyAnimator?
    var overviewDragAnimator: UIViewPropertyAnimator?
    var overviewDragAnchorY: CGFloat = 0
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
    var lastCommittedURLByTab: [UUID: URL] = [:]
    var screenshotTabPreviews: [UUID: UIImage] = [:]
    /// Single construction site for element context-menu actions; every page
    /// receives it when its snapshot listener is wired.
    private(set) var elementContextActions: ElementContextActions?
    /// Shared per-site text zoom; every page receives it at the same wiring
    /// site so zoom persists across tabs and relaunch.
    let siteZoomStore = SiteZoomStore()
    /// Shared download pipeline; every page reports into it at the same
    /// wiring site so navigation-driven downloads always land.
    let downloadsManager = DownloadsManager()

    // MARK: - Privacy & Security (Phase 2)

    var biometricAuthService: BiometricAuthenticating = BiometricAuthService.shared
    var isPrivateSessionLocked = false
    var recentlyClosedTabs: [TabRecord] = []
    private var contentBlockerObserver: NSObjectProtocol?

    var isBiometricAuthEnabled: Bool {
        selectionDefaults.object(forKey: SettingsViewModel.requireBiometricsDefaultsKey) as? Bool ?? true
    }

    var shouldRequireBiometricsForPrivateMode: Bool {
        guard isBiometricAuthEnabled else { return false }
        return tabs.contains(where: \.isPrivate)
    }

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
        } else if Self.isScreenshotRun {
            do {
                self.database = try OuterViewDatabase(inMemory: true)
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "BrowserRoot")
                    .error("Screenshot database init failed: \(error.localizedDescription, privacy: .public)")
                self.database = nil
            }
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
        wireDownloadSplit()
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
        // Seed last so restore cannot clobber the fixture tabs.
        applyScreenshotSeedIfNeeded()
        applyContentInsets()
        applyChromeViews(animated: false)
        subscribeToDownloadProgress()
        updateDownloadProgress()
        observeHorizontalSizeClass()
        observeContentBlockerChanges()
        setupQuickActionHandling()
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

    /// Single gate for private entry; failure restores standard chrome.
    func requestPrivateMode(authenticatedApply: @escaping @MainActor () -> Void) {
        guard shouldRequireBiometricsForPrivateMode else {
            authenticatedApply()
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if await self.biometricAuthService.authenticate(reason: "Unlock Private Browsing") {
                authenticatedApply()
            } else {
                self.overviewController.applySelectionBatched(mode: .standard, groupID: nil, notify: false)
                self.switchToStandardMode()
            }
        }
    }

    /// Scene changes forwarded from the app entry. Persistence is owned by the
    /// restore coordinator; background fails foreground transfers, active only
    /// refreshes pool recency. Chrome state is intentionally untouched.
    func handleScenePhase(_ phase: ScenePhase) {
        restoreCoordinator?.handleScenePhase(phase)
        if phase == .background {
            // Suspend fail-closed: private work fails, daemon tasks survive.
            downloadsManager.suspendForegroundDownloads()
            // Any private tab locks, even when standard is frontmost.
            if isBiometricAuthEnabled, tabs.contains(where: \.isPrivate) {
                isPrivateSessionLocked = true
            }
        }
        if phase == .active {
            let selectedIsPrivate = tabs.first(where: { $0.id == selectedTabID })?.isPrivate ?? false
            let isPrivateVisible = overviewMode.isPrivate || selectedIsPrivate
            if isPrivateSessionLocked, isPrivateVisible, shouldRequireBiometricsForPrivateMode {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let authenticated = await self.biometricAuthService.authenticate(reason: "Unlock Private Browsing")
                    if authenticated {
                        self.isPrivateSessionLocked = false
                        self.markActivePageActivated()
                    } else {
                        // Fail-closed to standard; clear lock so standard never re-prompts.
                        self.isPrivateSessionLocked = false
                        self.switchToStandardMode()
                    }
                }
                return
            }
            // Standard browsing never re-prompts: stale lock clears outside private.
            if !isPrivateVisible || !shouldRequireBiometricsForPrivateMode {
                isPrivateSessionLocked = false
            }
            markActivePageActivated()
        }
    }

    func logPersistenceError(_ error: Error, operation: String) {
        Logger(subsystem: "com.volcrypt.OuterView", category: "BrowserRoot")
            .error("\(operation, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
    }

    /// Single live owner for the tracker toggle: shared configs cover future
    /// tabs while live web views update in place with no restart.
    func applyContentBlockerEnabled(_ enabled: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let controllers = [self.tabPool.configuration(isPrivate: false).userContentController,
                               self.tabPool.configuration(isPrivate: true).userContentController]
                + self.tabPool.pages.compactMap { $0.page?.webView.configuration.userContentController }
            await ContentBlockerService.shared.setEnabled(enabled, controllers: controllers)
        }
    }

    func observeContentBlockerChanges() {
        guard contentBlockerObserver == nil else { return }
        contentBlockerObserver = NotificationCenter.default.addObserver(forName: .outerViewContentBlockerChanged, object: nil, queue: .main) { [weak self] note in
            let posted = note.userInfo?["enabled"] as? Bool
            Task { @MainActor [weak self, posted] in
                guard let self else { return }
                let enabled = posted ?? (self.selectionDefaults.object(forKey: SettingsViewModel.blockTrackersDefaultsKey) as? Bool ?? true)
                self.applyContentBlockerEnabled(enabled)
            }
        }
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

    func applyStructuralLayout() {
        let placement = chromePlacement
        if lastVerticalBarPlacement != placement {
            lastVerticalBarPlacement = placement
            verticalBarConfigurationUpdateCount += 1
            setNeedsUpdateOfVerticalBarConfiguration()
        }
        applyChromePlacement(for: placement)
        editorView.chromePlacement = placement
        overviewController.isRegular = (placement == .regular)
        overviewController.showsInlineCommands = (interfaceMode == .nonDuoPhone)
        bookmarksLibraryView.isNonDuoPhone = (interfaceMode == .nonDuoPhone)
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

    func setupQuickActionHandling() {
        QuickActionDispatcher.shared.registerHandler { @MainActor [weak self] in self?.handleQuickAction($0) }
    }

    func handleQuickAction(_ action: QuickAction) {
        handleQuickActionRouted(action)
    }

    func makeSettingsController() -> UIViewController? {
        guard let database else { return nil }
        var settingsView = SettingsView(
            database: database,
            siteZoomStore: siteZoomStore,
            inlineCommands: chromePlacement == .regular || interfaceMode == .nonDuoPhone
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
}

extension Notification.Name {
    static let outerViewContentBlockerChanged = Notification.Name("OuterViewContentBlockerChanged")
}
