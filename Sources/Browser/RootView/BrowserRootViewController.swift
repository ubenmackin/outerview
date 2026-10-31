//
//  BrowserRootViewController.swift
//  OuterView
//

import Combine
import os
import Photos
import SwiftUI
import UIKit

// swiftlint:disable file_length
// Central coordinator owns chrome, tabs, sheets, and overview;
// size reflects single-owner composition, not feature sprawl.

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
// swiftlint:disable:next type_body_length
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

    /// Regular width uses the top toolbar with the centered pill and no rail.
    var chromePlacement: ChromePlacement {
        Self.placement(for: traitCollection.horizontalSizeClass)
    }

    nonisolated static func placement(for sizeClass: UIUserInterfaceSizeClass) -> ChromePlacement {
        sizeClass == .regular ? .regular : .compact
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
                pillSlotLeadingConstraint.isActive = true
                pillSlotTrailingConstraint.isActive = true
                pillSlotCenterYConstraint.isActive = true
            }
        } else {
            if pillView.superview !== view {
                NSLayoutConstraint.deactivate([
                    pillSlotLeadingConstraint,
                    pillSlotTrailingConstraint,
                    pillSlotCenterYConstraint
                ])
                pillView.removeFromSuperview()
                pillView.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(pillView)
            } else {
                pillSlotLeadingConstraint.isActive = false
                pillSlotTrailingConstraint.isActive = false
                pillSlotCenterYConstraint.isActive = false
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
        updateTabStrip()
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
    private(set) var settingsHosting: UIViewController?
    private(set) var isSettingsVisible = false
    let downloadsContainer = UIView()
    var downloadsHosting: UIViewController?
    var isDownloadsVisible = false

    let libraryOverlay = OverlayCardView()
    let settingsOverlay = OverlayCardView()
    let downloadsOverlay = OverlayCardView()
    let bookmarkEditorOverlay = OverlayCardView()
    var libraryCompactConstraints: [NSLayoutConstraint] = []
    /// Last Files picker issued by the downloads rail. Retained so the
    /// wiring stays observable when the host blocks modal presentation.
    var presentedDownloadsPicker: UIDocumentPickerViewController?
    private let bookmarkEditorContainer = UIView()
    private var bookmarkEditorHosting: UIHostingController<BookmarkEditorView>?
    private var activeBookmarkEditorModel: BookmarkEditorModel?
    private(set) var isBookmarkEditorVisible = false

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

    /// Any library/settings/downloads/editor sheet is on screen. On regular
    /// width the toolbar suppresses its duplicated Done/Cancel/Save items
    /// while this is true, leaving only the sheet's inline controls.
    var isSheetOverlayVisible: Bool {
        isLibraryVisible || isSettingsVisible || isDownloadsVisible || isBookmarkEditorVisible
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
    var topBarTopConstraint: NSLayoutConstraint!
    var topBarLeadingConstraint: NSLayoutConstraint!
    var topBarTrailingConstraint: NSLayoutConstraint!
    var pillAnimator: UIViewPropertyAnimator?
    private var structuralTask: Task<Void, Never>?
    private var horizontalSizeClassRegistration: UITraitChangeRegistration?
    var suggestionTask: Task<Void, Never>?
    var findQueryTask: Task<Void, Never>?
    var findStepTask: Task<Void, Never>?
    var downloadProgressCancellable: AnyCancellable?

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
        setupStartPageContent()
        applyChromePlacement()
        updateRailItems()
        loadInitialTabs()
        applyContentInsets()
        applyChromeViews(animated: false)
        subscribeToDownloadProgress()
        updateDownloadProgress()
        observeHorizontalSizeClass()
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
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        scheduleStructuralUpdate()
    }

    private func observeHorizontalSizeClass() {
        // Fold state follows size class; bounds-driven sizing stays
        // in layoutSubviews and viewWillTransition.
        horizontalSizeClassRegistration = registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (owner: BrowserRootViewController, previous: UITraitCollection) in
            MainActor.assumeIsolated {
                if previous.horizontalSizeClass != owner.traitCollection.horizontalSizeClass {
                    owner.scheduleStructuralUpdate()
                }
            }
        }
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
        setupTopBar()
        setupTabStrip()
        setupPill()
        setupFind()
        setupRail()
        setupEditor()
        setupLibrary()
        setupSettings()
        setupDownloads()
        setupBookmarkEditor()
        setupOverlays()
        setupOverview()
        bringChromeToFront()
    }

    private func setupOverlays() {
        for overlay in [libraryOverlay, settingsOverlay, downloadsOverlay, bookmarkEditorOverlay] {
            overlay.translatesAutoresizingMaskIntoConstraints = false
            overlay.isHidden = true
            view.addSubview(overlay)
            NSLayoutConstraint.activate([
                overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                overlay.topAnchor.constraint(equalTo: view.topAnchor),
                overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
    }

    /// Single z-order for the floating layers. The rail is topmost so the
    /// overview's own rail composition (Search/Menu/New/Done) is never
    /// covered by the opaque overview surface; a hidden rail has zero alpha
    /// and is skipped by hit testing.
    func bringChromeToFront() {
        view.bringSubviewToFront(errorContainer)
        if pillView.superview == view {
            view.bringSubviewToFront(pillView)
        }
        view.bringSubviewToFront(findView)
        view.bringSubviewToFront(editorView)
        view.bringSubviewToFront(bookmarksLibraryView)
        view.bringSubviewToFront(settingsContainer)
        view.bringSubviewToFront(downloadsContainer)
        view.bringSubviewToFront(bookmarkEditorContainer)
        view.bringSubviewToFront(libraryOverlay)
        view.bringSubviewToFront(settingsOverlay)
        view.bringSubviewToFront(downloadsOverlay)
        view.bringSubviewToFront(bookmarkEditorOverlay)
        view.bringSubviewToFront(overviewView)
        view.bringSubviewToFront(tabStripView)
        view.bringSubviewToFront(topBarView)
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

    private func setupTopBar() {
        topBarView.translatesAutoresizingMaskIntoConstraints = false
        topBarView.isHidden = true
        view.addSubview(topBarView)
        topBarTopConstraint = topBarView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        topBarLeadingConstraint = topBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        topBarTrailingConstraint = topBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        NSLayoutConstraint.activate([
            topBarTopConstraint,
            topBarLeadingConstraint,
            topBarTrailingConstraint
        ])
    }

    private func setupTabStrip() {
        tabStripView.translatesAutoresizingMaskIntoConstraints = false
        tabStripView.isHidden = true
        tabStripView.onSelectTab = { [weak self] id in
            self?.selectTab(id: id)
        }
        tabStripView.onCloseTab = { [weak self] id in
            self?.closeTab(id: id, replacementIfEmpty: nil)
        }
        tabStripView.onNewTab = { [weak self] in
            guard let self else { return }
            self.createNewTab(isPrivate: self.overviewMode.isPrivate)
        }
        view.addSubview(tabStripView)
        NSLayoutConstraint.activate([
            tabStripView.topAnchor.constraint(equalTo: topBarView.bottomAnchor),
            tabStripView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabStripView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabStripView.heightAnchor.constraint(equalToConstant: TabStripView.stripHeight)
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
        pillSlotLeadingConstraint = pillView.leadingAnchor.constraint(
            equalTo: topBarView.pillSlotView.leadingAnchor
        )
        pillSlotTrailingConstraint = pillView.trailingAnchor.constraint(
            equalTo: topBarView.pillSlotView.trailingAnchor
        )
        pillSlotCenterYConstraint = pillView.centerYAnchor.constraint(
            equalTo: topBarView.pillSlotView.centerYAnchor
        )
        NSLayoutConstraint.activate([
            pillBottomConstraint,
            pillHeightConstraint,
            pillLeadingConstraint,
            pillTrailingConstraint
        ])
        pillView.onPillTap = { [weak self] in self?.handlePillTap() }
        pillView.onPageMenu = { [weak self] in self?.showPageMenu() }
        pillView.pageMenuProvider = { [weak self] in
            self?.makePageMenu() ?? UIMenu()
        }
        pillView.onReload = { [weak self] in self?.activePage()?.reload() }
        pillView.onStop = { [weak self] in self?.activePage()?.stop() }
        pillView.onDownloadsTap = { [weak self] in self?.presentDownloadsFromMenu() }
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
        libraryCompactConstraints = [
            bookmarksLibraryView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bookmarksLibraryView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bookmarksLibraryView.topAnchor.constraint(equalTo: view.topAnchor),
            bookmarksLibraryView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ]
        NSLayoutConstraint.activate(libraryCompactConstraints)
        if let bookmarkStore, let historyStore, let readingListStore {
            bookmarksLibraryView.configureStores(
                bookmarkStore: bookmarkStore,
                historyStore: historyStore,
                readingListStore: readingListStore
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
        bookmarksLibraryView.onReadingListStateChanged = { [weak self] in
            guard let self, self.isLibraryVisible, self.bookmarksLibraryView.currentTab == .readingList else { return }
            self.updateLibraryRailItems(for: .readingList)
        }
    }

    private func setupSettings() {
        settingsContainer.translatesAutoresizingMaskIntoConstraints = false
        settingsContainer.backgroundColor = .systemBackground
        settingsContainer.isHidden = true
        view.addSubview(settingsContainer)
        NSLayoutConstraint.activate([
            settingsContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            settingsContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            settingsContainer.topAnchor.constraint(equalTo: view.topAnchor),
            settingsContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    /// Single present path for settings/downloads/bookmark-editor sheets:
    /// regular renders inside a centered `OverlayCardView`, compact pins
    /// full-bleed inside the container with the trailing edge at the safe
    /// area so the rail column stays clear.
    func presentOverlay(_ overlay: OverlayCardView, newHosting: UIViewController, currentHosting: UIViewController?, container: UIView) {
        let placement = chromePlacement
        overlay.applyPlacement(for: placement)
        currentHosting?.view.removeFromSuperview()
        currentHosting?.removeFromParent()
        if overlay.hostedContent != nil {
            overlay.clearContent()
        }
        addChild(newHosting)
        newHosting.view.translatesAutoresizingMaskIntoConstraints = false
        if placement == .regular {
            overlay.setContent(newHosting.view)
            overlay.isHidden = false
            container.isHidden = true
        } else {
            overlay.isHidden = true
            container.addSubview(newHosting.view)
            NSLayoutConstraint.activate([
                newHosting.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                newHosting.view.topAnchor.constraint(equalTo: container.topAnchor),
                newHosting.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                newHosting.view.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor)
            ])
            container.isHidden = false
        }
        newHosting.didMove(toParent: self)
    }

    /// Single dismiss path mirroring `presentOverlay`: clears card content
    /// when the hosted view lives in the overlay, otherwise detaches it
    /// from the compact container.
    func dismissOverlay(_ overlay: OverlayCardView, hosting: UIViewController?, container: UIView) {
        container.isHidden = true
        overlay.isHidden = true
        if let hosted = hosting?.view, overlay.hostedContent === hosted {
            overlay.clearContent()
        } else {
            hosting?.view.removeFromSuperview()
        }
        hosting?.removeFromParent()
    }

    func presentSettingsSheet() {
        guard let hosting = makeSettingsController() else { return }
        presentOverlay(settingsOverlay, newHosting: hosting, currentHosting: settingsHosting, container: settingsContainer)
        settingsHosting = hosting
        isSettingsVisible = true
        bringChromeToFront()
        updateRailItems()
        applyRailViews(animated: true)
    }

    func dismissSettingsSheet() {
        isSettingsVisible = false
        dismissOverlay(settingsOverlay, hosting: settingsHosting, container: settingsContainer)
        settingsHosting = nil
        updateRailItems()
        applyRailViews(animated: true)
    }

    func presentBookmarkEditor(for target: BookmarkEditorTarget) {
        guard let bookmarkStore else { return }
        let placement = chromePlacement
        let model = BookmarkEditorModel(target: target)
        activeBookmarkEditorModel = model
        let editor = BookmarkEditorView(
            model: model,
            bookmarkStore: bookmarkStore,
            inlineCommands: placement == .regular,
            onCancel: { [weak self] in self?.dismissBookmarkEditor() },
            onSave: { [weak self] in self?.saveBookmarkEditor() }
        )
        let hosting = UIHostingController(rootView: editor)
        presentOverlay(bookmarkEditorOverlay, newHosting: hosting, currentHosting: bookmarkEditorHosting, container: bookmarkEditorContainer)
        bookmarkEditorHosting = hosting

        isBookmarkEditorVisible = true
        bringChromeToFront()
        updateRailItems()
        applyRailViews(animated: true)
    }

    func dismissBookmarkEditor() {
        isBookmarkEditorVisible = false
        dismissOverlay(bookmarkEditorOverlay, hosting: bookmarkEditorHosting, container: bookmarkEditorContainer)
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

    func openBookmarksLibrary(tab: LibraryTab? = nil) {
        let resolved = tab ?? LibraryTabBar.storedTab(defaults: selectionDefaults)
        let placement = chromePlacement
        bookmarksLibraryView.applyPlacement(for: placement)
        libraryOverlay.applyPlacement(for: placement)
        isLibraryVisible = true
        if placement == .regular {
            if libraryOverlay.hostedContent !== bookmarksLibraryView {
                NSLayoutConstraint.deactivate(libraryCompactConstraints)
                bookmarksLibraryView.removeFromSuperview()
                libraryOverlay.setContent(bookmarksLibraryView)
            }
            libraryOverlay.isHidden = false
            bookmarksLibraryView.isHidden = false
        } else {
            if bookmarksLibraryView.superview !== view {
                libraryOverlay.clearContent()
                view.addSubview(bookmarksLibraryView)
                NSLayoutConstraint.activate(libraryCompactConstraints)
            }
            libraryOverlay.isHidden = true
            bookmarksLibraryView.isHidden = false
        }
        bookmarksLibraryView.open(tab: resolved)
        updateLibraryRailItems(for: resolved)
        applyChromeViews(animated: false)
        bringChromeToFront()
    }

    func closeBookmarksLibrary() {
        isLibraryVisible = false
        libraryOverlay.isHidden = true
        bookmarksLibraryView.isHidden = true
        // Mirror dismissOverlay: detach the hosted library from the card so
        // a hidden overlay never retains it; compact re-attaches on next open.
        if libraryOverlay.hostedContent === bookmarksLibraryView {
            libraryOverlay.clearContent()
        }
        updateRailItems()
        applyChromeViews(animated: false)
    }

    func updateLibraryRailItems(for tab: LibraryTab) {
        guard isLibraryVisible else { return }
        var prefix: [RailAction] = []
        var suffix: [RailAction] = [
            .done { [weak self] in
                self?.closeBookmarksLibrary()
            }
        ]
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
        case .readingList:
            if bookmarksLibraryView.isReadingListInSelectionMode {
                let canDelete = bookmarksLibraryView.canDeleteReadingListSelection
                // No Library-exit action while selecting: the blue check ends
                // selection mode first; rail exit returns once it ends.
                prefix = [
                    .deleteSelected(isEnabled: canDelete) { [weak self] in
                        self?.bookmarksLibraryView.deleteReadingListSelectedItems()
                        self?.updateLibraryRailItems(for: .readingList)
                    }
                ]
                suffix = [
                    .done { [weak self] in
                        self?.bookmarksLibraryView.exitReadingListSelectionMode()
                        self?.updateLibraryRailItems(for: .readingList)
                    }
                ]
            } else {
                if let menu = bookmarksLibraryView.makeReadingListMenu() {
                    prefix = [
                        .readingListMenu(menu: menu)
                    ]
                }
                suffix = [
                    .done { [weak self] in
                        self?.closeBookmarksLibrary()
                    }
                ]
            }
        case .favorites:
            prefix = []
        }

        setChromeItems(prefix: prefix, suffix: suffix)
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

    func applyStructuralLayout() {
        let placement = chromePlacement
        applyChromePlacement(for: placement)
        editorView.chromePlacement = placement
        for overlay in [libraryOverlay, settingsOverlay, downloadsOverlay, bookmarkEditorOverlay]
            where overlay.isHidden
        {
            overlay.applyPlacement(for: placement)
        }
        if !isLibraryVisible {
            bookmarksLibraryView.applyPlacement(for: placement)
        }
        updateTabStrip()
        refreshForActiveSnapshot()
        applyChromeViews(animated: false)
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
        Task { @MainActor [weak self] in
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
