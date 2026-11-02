//
//  BrowserRootViewController+Chrome.swift
//  OuterView
//

import UIKit

extension BrowserRootViewController {
    // MARK: - Chrome state

    func handleScrollDelta(_ delta: CGFloat) {
        guard !isOverviewPresented() else { return }
        applyScrollInput(delta: delta)
    }

    func handleDragBegan() {
        guard !isOverviewPresented() else { return }
        applyDragBegan()
    }

    /// Applies only the fields the state machine reports as changed. A nil
    /// field keeps its previous value, so untouched axes skip layout and
    /// never restart the other axis animator.
    func applyCommands(_ commands: ChromeCommands, animated: Bool) {
        guard commands != .noChange else { return }
        if chromePlacement == .regular {
            if commands.rail != nil || commands.pill != nil {
                applyTopBarViews(animated: animated)
            }
            if commands.pill != nil {
                applyPillViews(animated: animated)
            }
            applyContentInsets()
            return
        }
        if commands.pill != nil {
            applyPillViews(animated: animated)
        }
        if commands.rail != nil || commands.pill != nil {
            applyRailViews(animated: animated)
        }
        applyContentInsets()
    }

    func applyChromeViews(animated: Bool) {
        if chromePlacement == .regular {
            applyTopBarViews(animated: animated)
            applyPillViews(animated: animated)
            applyContentInsets()
            return
        }
        applyPillViews(animated: animated)
        applyRailViews(animated: animated)
        applyContentInsets()
    }

    /// Single owner for regular toolbar visibility: editing/overview shows
    /// the bar with both stacks, sheet overlays show the bar but hide the
    /// duplicated stacks, otherwise collapsed shrinks the bar to remnantHeight
    /// while hiding both stacks plus the strip.
    func updateToolbarVisibility(for state: ChromeState) {
        railView.isHidden = true
        topBarView.isHidden = false
        let isCollapsed = Self.isRegularCollapsed(
            state: state,
            isOverviewVisible: isOverviewVisible,
            isSheetOverlayVisible: isSheetOverlayVisible
        )
        topBarView.setCollapsed(isCollapsed)
        if isCollapsed {
            topBarView.leadingStack.isHidden = true
            topBarView.trailingStack.isHidden = true
        } else {
            let isSheetExpanded = suppressesRegularToolbarButtons && state.pill != .editing && !isOverviewVisible
            topBarView.leadingStack.isHidden = isSheetExpanded
            topBarView.trailingStack.isHidden = isSheetExpanded
        }
        topBarView.leadingStack.alpha = topBarView.leadingStack.isHidden ? 0 : 1
        topBarView.trailingStack.alpha = topBarView.trailingStack.isHidden ? 0 : 1
        updateTabStrip()
        updateRegularPillGeometry()
    }

    func updateRegularPillGeometry() {
        guard isViewLoaded, pillView.superview === topBarView.pillSlotView else { return }
        let isMinified = chromeController.state.pill == .minified
        pillSlotLeadingConstraint.isActive = false
        pillSlotTrailingConstraint.isActive = false
        pillSlotMinLeadingConstraint.isActive = true
        pillSlotMaxTrailingConstraint.isActive = true
        pillSlotCenterXConstraint.isActive = true
        pillSlotWidthConstraint.isActive = true
        let target = Self.regularPillTarget(
            slotWidth: topBarView.pillSlotView.bounds.width,
            isMinified: isMinified,
            preferredMinifiedWidth: pillView.preferredMinifiedWidth()
        )
        if pillSlotWidthConstraint.constant != target {
            pillSlotWidthConstraint.constant = target
        }
    }

    func applyTopBarViews(animated: Bool) {
        let state = chromeController.state
        let wasCollapsed = topBarView.isCollapsed
        let willBeCollapsed = Self.isRegularCollapsed(
            state: state,
            isOverviewVisible: isOverviewVisible,
            isSheetOverlayVisible: isSheetOverlayVisible
        )
        let willHideStatusBar = Self.shouldHideStatusBar(
            for: chromePlacement,
            state: state,
            isOverviewVisible: isOverviewVisible,
            isSheetOverlayVisible: isSheetOverlayVisible
        )
        let statusChanged = lastStatusBarHidden != willHideStatusBar

        if animated,
           chromePlacement == .regular,
           isViewLoaded,
           view.window != nil,
           wasCollapsed != willBeCollapsed || statusChanged
        {
            if wasCollapsed, !willBeCollapsed {
                topBarView.leadingStack.alpha = 0
                topBarView.trailingStack.alpha = 0
            }
            topBarAnimator?.stopAnimation(false)
            topBarAnimator?.finishAnimation(at: .current)
            let animator = UIViewPropertyAnimator(
                duration: Self.railHideDuration,
                curve: .easeInOut
            ) { [weak self] in
                guard let self else { return }
                self.updateToolbarVisibility(for: self.chromeController.state)
                self.topBarView.leadingStack.alpha = self.topBarView.leadingStack.isHidden ? 0 : 1
                self.topBarView.trailingStack.alpha = self.topBarView.trailingStack.isHidden ? 0 : 1
                self.updateTopBarPinning(for: self.chromePlacement)
                self.updateHeaderBackgrounds()
                self.updateStartPageTop()
                self.refreshStatusBarAppearanceIfNeeded()
                self.view.layoutIfNeeded()
            }
            topBarAnimator = animator
            animator.addCompletion { [weak self, weak animator] _ in
                if let animator, self?.topBarAnimator === animator {
                    self?.topBarAnimator = nil
                }
            }
            animator.startAnimation()
            return
        }

        topBarAnimator?.stopAnimation(false)
        topBarAnimator?.finishAnimation(at: .current)
        topBarAnimator = nil
        updateToolbarVisibility(for: state)
        updateTopBarPinning(for: chromePlacement)
        updateHeaderBackgrounds()
        updateStartPageTop()
        refreshStatusBarAppearanceIfNeeded()
    }

    // MARK: - Chrome applier (single owner)

    func attachScrollProxy(for id: UUID, page: WebPageController) {
        let proxy: ChromeScrollProxy
        if let existing = scrollProxies[id] {
            proxy = existing
        } else {
            proxy = ChromeScrollProxy()
            proxy.onScrollDelta = { [weak self] delta in
                self?.handleScrollDelta(delta)
            }
            proxy.onDragBegan = { [weak self] in
                self?.handleDragBegan()
            }
            proxy.topInsetProvider = { [weak self] in
                guard let self else { return 0 }
                return Self.topContentInset(
                    for: self.chromePlacement,
                    state: self.chromeController.state,
                    stripVisible: !self.tabStripView.isHidden
                )
            }
            scrollProxies[id] = proxy
        }
        proxy.attach(to: page.webView.scrollView)
    }

    /// Tells only the content about the chrome reservation. The root keeps
    /// the real system safe area so chrome anchored to it never pushes
    /// itself; web content keeps rendering under the chrome and only its
    /// scrollable range grows.
    func applyContentInsets() {
        guard isViewLoaded else { return }
        let placement = chromePlacement
        let state = chromeController.state
        let stripVisible = !tabStripView.isHidden
        let newTop = Self.topContentInset(for: placement, state: state, stripVisible: stripVisible)
        let newAdditionalTop = Self.additionalSafeAreaTopInset(for: placement, state: state)
        if additionalSafeAreaInsets.top != newAdditionalTop {
            additionalSafeAreaInsets.top = newAdditionalTop
        }
        let systemBottom = view.safeAreaInsets.bottom
        let bottom = Self.contentBottomInset(systemBottomInset: systemBottom)
        if let webView = peekActivePage()?.webView {
            let oldTop = webView.obscuredContentInsets.top
            let insets = UIEdgeInsets(top: newTop, left: 0, bottom: bottom, right: 0)
            if webView.obscuredContentInsets != insets {
                let proxy = selectedTabID.flatMap { scrollProxies[$0] }
                proxy?.suppressDeltas = true
                webView.obscuredContentInsets = insets
                if oldTop != newTop {
                    let current = webView.scrollView.contentOffset
                    let compensated = Self.compensatedOffset(
                        current: current,
                        oldTop: oldTop,
                        newTop: newTop
                    )
                    let scrollView = webView.scrollView
                    let minOffsetY = -newTop
                    let maxOffsetY = scrollView.contentSize.height - scrollView.bounds.height + bottom
                    let clampedY = min(max(compensated.y, minOffsetY), max(maxOffsetY, minOffsetY))
                    webView.scrollView.contentOffset = CGPoint(x: compensated.x, y: clampedY)
                }
                proxy?.suppressDeltas = false
            }
        }
        startPageView?.setBottomChromeInset(max(0, bottom - systemBottom))
    }

    func updateTopBarPinning(for placement: ChromePlacement) {
        guard isViewLoaded else { return }
        if placement == .regular {
            topBarTopToSafeAreaConstraint?.isActive = false
            topBarTopToViewConstraint?.isActive = true
            if let toView = topBarTopToViewConstraint {
                topBarTopConstraint = toView
            }
        } else {
            topBarTopToViewConstraint?.isActive = false
            topBarTopToSafeAreaConstraint?.isActive = true
            if let toSafe = topBarTopToSafeAreaConstraint {
                topBarTopConstraint = toSafe
            }
        }
        topBarTrailingConstraint.constant = 0
    }

    func updateHeaderBackgrounds() {
        guard isViewLoaded else { return }
        topBarView.applyHeaderBackground()
        tabStripView.applyHeaderBackground()
    }

    func updateStartPageTop() {
        guard isViewLoaded else { return }
        if startPageTopToStripConstraint == nil {
            let toStrip = startPageContainer.topAnchor.constraint(equalTo: tabStripView.bottomAnchor)
            toStrip.isActive = false
            startPageTopToStripConstraint = toStrip
        }
        if startPageTopToBarConstraint == nil {
            let toBar = startPageContainer.topAnchor.constraint(equalTo: topBarView.bottomAnchor)
            toBar.isActive = false
            startPageTopToBarConstraint = toBar
        }
        guard let toContent = startPageTopToContentConstraint,
              let toStrip = startPageTopToStripConstraint,
              let toBar = startPageTopToBarConstraint
        else { return }
        if chromePlacement != .regular {
            toStrip.isActive = false
            toBar.isActive = false
            toContent.isActive = true
            return
        }
        if !tabStripView.isHidden {
            toContent.isActive = false
            toBar.isActive = false
            toStrip.isActive = true
        } else {
            toContent.isActive = false
            toStrip.isActive = false
            toBar.isActive = true
        }
    }

    func updatePillBottomOffset() {
        guard let pillBottomConstraint else { return }
        let offset = Self.pillBottomOffset(
            for: chromeController.state.pill,
            systemBottomInset: view.safeAreaInsets.bottom
        )
        if pillBottomConstraint.constant != -offset {
            pillBottomConstraint.constant = -offset
        }
    }

    func applyPillViews(animated: Bool) {
        editorView.applyPlacement(for: chromePlacement)
        let state = chromeController.state
        if isFindActive, state.pill != .editing {
            pillView.isHidden = true
            return
        }
        pillView.setAddressState(state)

        if chromePlacement == .regular {
            if pillView.superview !== topBarView.pillSlotView {
                applyChromePlacement(for: .regular)
            }
            let updateToolbarPill = { [weak self] in
                guard let self else { return }
                self.pillHeightConstraint.constant = AddressBarView.heightForState(state.pill)
                self.updateRegularPillGeometry()
                self.pillView.isHidden = state.pill == .editing
                self.editorView.isHidden = state.pill != .editing
                self.view.layoutIfNeeded()
            }
            if animated {
                pillAnimator?.stopAnimation(false)
                pillAnimator?.finishAnimation(at: .current)
                let animator = UIViewPropertyAnimator(
                    duration: Self.pillMorphDuration, curve: .easeInOut, animations: updateToolbarPill
                )
                pillAnimator = animator
                animator.addCompletion { [weak self, weak animator] _ in
                    if let animator, self?.pillAnimator === animator {
                        self?.pillAnimator = nil
                    }
                }
                animator.startAnimation()
            } else {
                updateToolbarPill()
            }
            return
        }
        let updatePillGeometry = { [weak self] in
            guard let self else { return }
            self.pillHeightConstraint.constant = AddressBarView.heightForState(state.pill)
            self.updatePillBottomOffset()
            let isMinified = state.pill == .minified
            self.pillLeadingConstraint.isActive = !isMinified
            self.pillTrailingConstraint.isActive = !isMinified
            self.pillCenterXConstraint.isActive = isMinified
            self.pillWidthConstraint.isActive = isMinified
            if isMinified {
                self.pillWidthConstraint.constant = AddressBarView.widthForBounds(self.pillReferenceWidth)
            }
            self.pillView.isHidden = state.pill == .editing
            self.editorView.isHidden = state.pill != .editing
            self.view.layoutIfNeeded()
        }
        if animated {
            pillAnimator?.stopAnimation(false)
            pillAnimator?.finishAnimation(at: .current)
            let animator = UIViewPropertyAnimator(
                duration: Self.pillMorphDuration, curve: .easeInOut, animations: updatePillGeometry
            )
            pillAnimator = animator
            animator.addCompletion { [weak self, weak animator] _ in
                if let animator, self?.pillAnimator === animator {
                    self?.pillAnimator = nil
                }
            }
            animator.startAnimation()
        } else {
            updatePillGeometry()
        }
    }

    func applyRailViews(animated: Bool) {
        if chromePlacement == .regular {
            applyTopBarViews(animated: animated)
            return
        }
        topBarAnimator?.stopAnimation(false)
        topBarAnimator?.finishAnimation(at: .current)
        topBarAnimator = nil
        topBarView.isHidden = true
        railView.isHidden = false
        updateTopBarPinning(for: .compact)
        updateHeaderBackgrounds()
        updateStartPageTop()
        refreshStatusBarAppearanceIfNeeded()
        var state = chromeController.state
        if currentRailMode == .startPage
            || currentRailMode == .bookmarkEditor
            || currentRailMode == .settings
            || currentRailMode == .downloads
            || isLibraryVisible
            || isSettingsVisible
            || isDownloadsVisible
        {
            state.rail = .visible
        }
        railView.transform = .identity
        railView.alpha = 1
        railView.setRailState(state.rail, pill: state.pill, animated: animated)
    }

    enum RailMode: Equatable {
        case browsing
        case library(LibraryTab)
        case startPage
        case bookmarkEditor
        case settings
        case downloads
    }

    var currentRailMode: RailMode {
        if isBookmarkEditorVisible {
            return .bookmarkEditor
        }
        if isSettingsVisible {
            return .settings
        }
        if isDownloadsVisible {
            return .downloads
        }
        if isLibraryVisible {
            return .library(bookmarksLibraryView.currentTab)
        }
        if isEditingAddress {
            return .startPage
        }
        if let id = selectedTabID, forcedStartPageTabs.contains(id) {
            return .startPage
        }
        return .browsing
    }

    func dismissForcedStartPage() {
        clearForcedStartPageForSelectedTab()
        refreshForActiveSnapshot()
        applyBrowsingResumed(animated: true)
    }

    func dismissStartPageOrEditing() {
        let hadForcedStartPage = selectedTabID.map { forcedStartPageTabs.contains($0) } ?? false
        if isEditingAddress {
            endEditing(submitted: false)
            if hadForcedStartPage {
                dismissForcedStartPage()
            }
            return
        }
        dismissForcedStartPage()
    }

    func makeBrowsingChromeItems() -> (prefix: [RailAction], suffix: [RailAction]) {
        let canGoBack = peekActivePage()?.snapshot.canGoBack ?? false
        return (
            prefix: [
                .back(isEnabled: canGoBack) { [weak self] in self?.activePage()?.goBack() },
                .bookmarks { [weak self] in self?.openBookmarksLibrary() }
            ],
            suffix: [
                .newTab { [weak self] in self?.createNewTab() },
                .tabs { [weak self] in self?.toggleOverview() }
            ]
        )
    }

    func setChromeItems(prefix: [RailAction], suffix: [RailAction]) {
        railView.setItems(prefix: prefix, suffix: suffix)
        let isRegularApplied = chromePlacement == .regular || !topBarView.isHidden
        if isRegularApplied, !isOverviewVisible {
            if suppressesRegularToolbarButtons {
                topBarView.setItems(prefix: [], suffix: [])
            } else if isEditingAddress || isLibraryVisible {
                let browsing = makeBrowsingChromeItems()
                topBarView.setItems(prefix: browsing.prefix, suffix: browsing.suffix)
            } else {
                topBarView.setItems(prefix: prefix, suffix: suffix)
            }
        } else {
            topBarView.setItems(prefix: prefix, suffix: suffix)
        }
    }

    func updateRailItems() {
        switch currentRailMode {
        case .bookmarkEditor:
            setChromeItems(
                prefix: [
                    .cancel { [weak self] in
                        self?.dismissBookmarkEditor()
                    }
                ],
                suffix: [
                    .done { [weak self] in
                        self?.saveBookmarkEditor()
                    }
                ]
            )
        case .settings:
            setChromeItems(
                prefix: [],
                suffix: [
                    .done { [weak self] in
                        self?.dismissSettingsSheet()
                    }
                ]
            )
        case .downloads:
            setChromeItems(
                prefix: [
                    .files { [weak self] in
                        self?.presentDownloadsFilesPicker()
                    },
                    .clear(label: "Clear All", isEnabled: !downloadsManager.rows.isEmpty) { [weak self] in
                        self?.downloadsManager.deleteAll()
                        self?.updateRailItems()
                    }
                ],
                suffix: [
                    .done { [weak self] in
                        self?.dismissDownloadsSheet()
                    }
                ]
            )
        case let .library(tab):
            updateLibraryRailItems(for: tab)
        case .startPage:
            setChromeItems(
                prefix: [],
                suffix: [
                    .done { [weak self] in
                        self?.dismissStartPageOrEditing()
                    }
                ]
            )
        case .browsing:
            let browsing = makeBrowsingChromeItems()
            setChromeItems(prefix: browsing.prefix, suffix: browsing.suffix)
        }
    }

    // MARK: - Scroll bridges

    func isOverviewPresented() -> Bool {
        isOverviewVisible
    }

    func applyScrollInput(delta: CGFloat) {
        let commands = chromeController.handle(.scroll(offsetDelta: delta))
        applyCommands(commands, animated: true)
    }

    func applyDragBegan() {
        let commands = chromeController.handle(.dragBegan)
        applyCommands(commands, animated: true)
    }

    func applyRailMenuTapped() {
        guard !isOverviewPresented() else { return }
        let commands = chromeController.handle(.railMenuTapped)
        applyCommands(commands, animated: true)
    }
}
