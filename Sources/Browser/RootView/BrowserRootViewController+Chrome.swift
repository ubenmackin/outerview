// RootView — Chrome state plus Modes 3 and 4 bottom-pill composition.

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

    /// Single owner for regular toolbar visibility.
    /// Sheet overlays show the bar but hide duplicated stacks.
    /// Collapsed shrinks to remnant height hiding stacks plus strip.
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
        if isOverviewVisible {
            pillView.isHidden = true
        } else if chromePlacement == .regular {
            pillView.isHidden = state.pill == .editing
        }
        updateTabStrip()
        updateRegularPillGeometry()
    }

    func updateRegularPillGeometry() {
        guard isViewLoaded, pillView.superview === topBarView.pillSlotView else { return }
        let isMinified = chromeController.state.pill == .minified
        pillSlotLeadingConstraint?.isActive = false
        pillSlotTrailingConstraint?.isActive = false
        pillSlotMinLeadingConstraint?.isActive = true
        pillSlotMaxTrailingConstraint?.isActive = true
        pillSlotCenterXConstraint?.isActive = true
        pillSlotWidthConstraint?.isActive = true
        let target = Self.regularPillTarget(
            slotWidth: topBarView.pillSlotView.bounds.width,
            isMinified: isMinified,
            preferredMinifiedWidth: pillView.preferredMinifiedWidth()
        )
        if pillSlotWidthConstraint?.constant != target {
            pillSlotWidthConstraint?.constant = target
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
            for: interfaceMode,
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
                    stripVisible: !self.tabStripView.isHidden,
                    interfaceMode: self.interfaceMode,
                    safeAreaTop: self.view.safeAreaInsets.top
                )
            }
            proxy.onScrollSettled = { [weak self] in
                self?.reconcileTopInsetAfterSettle()
            }
            scrollProxies[id] = proxy
        }
        proxy.attach(to: page.webView.scrollView)
    }

    /// Reserves chrome space for content only; root keeps real safe area.
    /// Chrome anchored to safe area never pushes itself.
    /// Web content renders under chrome; only scroll range grows.
    func applyContentInsets() {
        guard isViewLoaded else { return }
        let placement = chromePlacement
        let state = chromeController.state
        let stripVisible = !tabStripView.isHidden
        let safeAreaTop = view.safeAreaInsets.top
        let newTop = Self.topContentInset(
            for: placement,
            state: state,
            stripVisible: stripVisible,
            interfaceMode: interfaceMode,
            safeAreaTop: safeAreaTop
        )
        let newAdditionalTop = Self.additionalSafeAreaTopInset(for: placement, state: state)
        if additionalSafeAreaInsets.top != newAdditionalTop {
            additionalSafeAreaInsets.top = newAdditionalTop
        }
        let systemBottom = view.safeAreaInsets.bottom
        let bottom = Self.contentBottomInset(systemBottomInset: systemBottom)
        if let webView = peekActivePage()?.webView {
            let oldTop = webView.obscuredContentInsets.top
            let insets = UIEdgeInsets(top: newTop, left: 0, bottom: bottom, right: 0)
            if webView.obscuredContentInsets != insets || webView.scrollView.contentInset != insets {
                let proxy = selectedTabID.flatMap { scrollProxies[$0] }
                proxy?.suppressDeltas = true
                webView.obscuredContentInsets = insets
                webView.scrollView.contentInset = insets
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
                    let target = CGPoint(x: compensated.x, y: clampedY)
                    scrollView.setContentOffset(target, animated: false)
                    // Clear stale underlap immediately so headers park below the cluster.
                    view.layoutIfNeeded()
                }
                proxy?.suppressDeltas = false
            }
        }
        startPageView?.setBottomChromeInset(max(0, bottom - systemBottom))
    }

    func reconcileTopInsetAfterSettle() {
        guard interfaceMode == .duoInnerOrPadLandscape,
              chromeController.state.pill != .minified,
              !isOverviewVisible,
              let webView = peekActivePage()?.webView else { return }
        let expectedTop = Self.topContentInset(
            for: chromePlacement,
            state: chromeController.state,
            stripVisible: !tabStripView.isHidden,
            interfaceMode: interfaceMode,
            safeAreaTop: view.safeAreaInsets.top
        )
        // Settled near the collapsed remnant (e.g. -48) while expanded expects
        // -expectedTop (e.g. -128): re-assert insets then park below the header.
        if webView.scrollView.contentOffset.y > -expectedTop, webView.scrollView.contentOffset.y <= -TopBarView.remnantHeight + 1 {
            let currentX = webView.scrollView.contentOffset.x
            applyContentInsets()
            webView.scrollView.setContentOffset(CGPoint(x: currentX, y: -expectedTop), animated: true)
        }
    }

    func updateTopBarPinning(for _: ChromePlacement) {
        guard isViewLoaded else { return }
        if interfaceMode == .duoInnerOrPadLandscape {
            if topBarTopToSafeAreaConstraint?.isActive == true {
                topBarTopToSafeAreaConstraint?.isActive = false
            }
            if topBarTopToViewConstraint?.isActive != true {
                topBarTopToViewConstraint?.isActive = true
            }
            if let toView = topBarTopToViewConstraint, topBarTopConstraint !== toView {
                topBarTopConstraint = toView
            }
        } else {
            if topBarTopToViewConstraint?.isActive == true {
                topBarTopToViewConstraint?.isActive = false
            }
            if topBarTopToSafeAreaConstraint?.isActive != true {
                topBarTopToSafeAreaConstraint?.isActive = true
            }
            if let toSafe = topBarTopToSafeAreaConstraint, topBarTopConstraint !== toSafe {
                topBarTopConstraint = toSafe
            }
        }
        if topBarTrailingConstraint?.constant != 0 {
            topBarTrailingConstraint?.constant = 0
        }
    }

    func updateHeaderBackgrounds() {
        guard isViewLoaded else { return }
        topBarView.applyHeaderBackground()
        tabStripView.applyHeaderBackground()
    }

    private func ensureStartPageConstraints() {
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
    }

    private func targetStartPageTopConstraint(
        toBar: NSLayoutConstraint,
        toStrip: NSLayoutConstraint,
        toContent: NSLayoutConstraint
    ) -> NSLayoutConstraint {
        if interfaceMode == .nonDuoPhone {
            return topBarView.isHidden ? toContent : toBar
        }
        if chromePlacement != .regular {
            return toContent
        }
        return tabStripView.isHidden ? toBar : toStrip
    }

    private func setConstraintActive(_ constraint: NSLayoutConstraint, _ active: Bool) {
        if constraint.isActive != active {
            constraint.isActive = active
        }
    }

    func updateStartPageTop() {
        guard isViewLoaded else { return }
        ensureStartPageConstraints()
        guard let toContent = startPageTopToContentConstraint,
              let toStrip = startPageTopToStripConstraint,
              let toBar = startPageTopToBarConstraint
        else { return }

        let target = targetStartPageTopConstraint(toBar: toBar, toStrip: toStrip, toContent: toContent)
        for constraint in [toBar, toStrip, toContent] {
            setConstraintActive(constraint, constraint === target)
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
            applyRegularPillViews(state: state, animated: animated)
            return
        }
        applyCompactPillViews(state: state, animated: animated)
    }

    private func applyRegularPillViews(state: ChromeState, animated: Bool) {
        if pillView.superview !== topBarView.pillSlotView {
            applyChromePlacement(for: .regular)
        }
        let updateToolbarPill: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            self.pillHeightConstraint?.constant = AddressBarView.heightForState(state.pill)
            self.updateRegularPillGeometry()
            self.pillView.isHidden = self.isOverviewVisible || state.pill == .editing
            self.editorView.isHidden = state.pill != .editing
            self.view.layoutIfNeeded()
        }
        runPillMorph(animated: animated, update: updateToolbarPill)
    }

    private func applyCompactPillViews(state: ChromeState, animated: Bool) {
        if pillView.superview !== view {
            applyChromePlacement(for: .compact)
        }
        let updatePillGeometry: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            self.updateCompactPillGeometry(state: state)
            if self.view.window != nil {
                self.view.layoutIfNeeded()
            }
        }
        runPillMorph(animated: animated, update: updatePillGeometry)
    }

    private func runPillMorph(animated: Bool, update: @MainActor @escaping () -> Void) {
        if animated {
            pillAnimator?.stopAnimation(false)
            pillAnimator?.finishAnimation(at: .current)
            let animator = UIViewPropertyAnimator(
                duration: Self.pillMorphDuration, curve: .easeInOut, animations: update
            )
            pillAnimator = animator
            animator.addCompletion { [weak self, weak animator] _ in
                if let animator, self?.pillAnimator === animator {
                    self?.pillAnimator = nil
                }
            }
            animator.startAnimation()
        } else {
            update()
        }
    }

    private func updateCompactPillGeometry(state: ChromeState) {
        pillHeightConstraint?.constant = AddressBarView.heightForState(state.pill)
        updatePillBottomOffset()
        let isMinified = state.pill == .minified
        let isNonDuo = interfaceMode == .nonDuoPhone
        let isPortrait = interfaceMode == .duoInnerOrPadPortrait
        if isNonDuo || isPortrait {
            pillLeadingConstraint?.isActive = false
            pillTrailingConstraint?.isActive = false
            pillBottomLeadingConstraint?.isActive = !isMinified
            pillBottomTrailingConstraint?.isActive = !isMinified
        } else {
            pillBottomLeadingConstraint?.isActive = false
            pillBottomTrailingConstraint?.isActive = false
            pillLeadingConstraint?.isActive = !isMinified
            pillTrailingConstraint?.isActive = !isMinified
        }
        pillCenterXConstraint?.isActive = isMinified
        pillWidthConstraint?.isActive = isMinified
        if isMinified {
            pillWidthConstraint?.constant = AddressBarView.widthForBounds(pillReferenceWidth)
        }
        editorView.isNonDuoPhone = (interfaceMode == .nonDuoPhone || interfaceMode == .duoInnerOrPadPortrait)
        editorView.isEditing = isEditingAddress
        updateCompactBottomStacks(state: state)
        editorView.isHidden = state.pill != .editing
    }

    private func updateCompactBottomStacks(state: ChromeState) {
        if interfaceMode == .nonDuoPhone {
            applyNonDuoChromeVisibility()
            if isEditingAddress, chromePlacement == .compact {
                bottomLeadingStack.isHidden = true
                bottomTrailingStack.isHidden = true
            }
        } else if interfaceMode == .duoInnerOrPadPortrait {
            applyPortraitChromeVisibility()
            if isEditingAddress {
                bottomLeadingStack.isHidden = true
                bottomTrailingStack.isHidden = true
                verticalTabBarView.alpha = 0
                verticalTabBarView.isUserInteractionEnabled = false
                verticalTabBarView.isHidden = true
            }
        } else {
            pillView.isHidden = isOverviewVisible || state.pill == .editing
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

        let mode = interfaceMode
        if mode == .nonDuoPhone {
            if !railView.isHidden {
                railView.isHidden = true
            }
            let showsTopBar = shouldShowNonDuoTopBar
            if topBarView.isHidden != !showsTopBar {
                topBarView.isHidden = !showsTopBar
            }
            topBarView.showsBackgroundBar = !showsTopBar
            updateTopBarPinning(for: .compact)
            updateHeaderBackgrounds()
            updateStartPageTop()
            refreshStatusBarAppearanceIfNeeded()
            let updateStacks: @MainActor () -> Void = { [weak self] in
                self?.applyNonDuoChromeVisibility()
            }
            if animated {
                UIView.animate(withDuration: Self.pillMorphDuration, animations: updateStacks)
            } else {
                updateStacks()
            }
            return
        }

        if mode == .duoInnerOrPadPortrait {
            if !railView.isHidden {
                railView.isHidden = true
            }
            if !topBarView.isHidden {
                topBarView.isHidden = true
            }
            updateTopBarPinning(for: .compact)
            updateHeaderBackgrounds()
            updateStartPageTop()
            refreshStatusBarAppearanceIfNeeded()
            let updatePortrait: @MainActor () -> Void = { [weak self] in
                self?.applyPortraitChromeVisibility()
            }
            if animated {
                UIView.animate(withDuration: Self.pillMorphDuration, animations: updatePortrait)
            } else {
                updatePortrait()
            }
            return
        }

        if !topBarView.isHidden {
            topBarView.isHidden = true
        }
        if railView.isHidden {
            railView.isHidden = false
        }
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
        bookmarksLibraryView.resetFirstTabMode()
        let hadForcedStartPage = selectedTabID.map { forcedStartPageTabs.contains($0) } ?? false
        if isEditingAddress {
            endEditing(submitted: false)
            if isLibraryVisible {
                closeBookmarksLibrary()
            }
            if hadForcedStartPage {
                dismissForcedStartPage()
            }
            return
        }
        if isLibraryVisible {
            closeBookmarksLibrary()
        }
        dismissForcedStartPage()
    }

    func makeBrowsingChromeItems() -> (prefix: [RailAction], suffix: [RailAction]) {
        let canGoBack = peekActivePage()?.snapshot.canGoBack ?? false
        let backAction = RailAction.back(
            isEnabled: canGoBack,
            menuProvider: { [weak self] in self?.makeBackMenu() },
            handler: { [weak self] in self?.activePage()?.goBack() }
        )
        let tabAction = RailAction.tabs(
            menuProvider: { [weak self] in self?.makeTabGroupMenu() },
            handler: { [weak self] in self?.toggleOverview() }
        )

        if interfaceMode == .nonDuoPhone {
            return (
                prefix: [backAction],
                suffix: [tabAction]
            )
        }

        return (
            prefix: [
                backAction,
                .bookmarks(
                    menuProvider: { [weak self] in self?.makeBookmarksButtonMenu() },
                    handler: { [weak self] in self?.openBookmarksLibrary() }
                )
            ],
            suffix: [
                .newTab { [weak self] in self?.createNewTab() },
                tabAction
            ]
        )
    }

    /// Portrait overlay covers overview plus editing plus find; editor
    /// plus library use dedicated branches so trailing Dismiss survives.
    var isPortraitChromeOverlay: Bool {
        isOverviewVisible || isEditingAddress || isFindActive
    }

    func setChromeItems(prefix: [RailAction], suffix: [RailAction]) {
        railView.setItems(prefix: prefix, suffix: suffix)
        if interfaceMode == .nonDuoPhone || interfaceMode == .duoInnerOrPadPortrait {
            let isPortrait = interfaceMode == .duoInnerOrPadPortrait
            let isEditing = isEditingAddress && chromePlacement == .compact
            if isEditing {
                SystemToolbarMapper.populateBottomStack(bottomLeadingStack, with: [])
                SystemToolbarMapper.populateBottomStack(bottomTrailingStack, with: [])
                topBarView.setItems(prefix: [], suffix: [])
                editorView.isNonDuoPhone = true
                editorView.isEditing = true
                if interfaceMode == .nonDuoPhone {
                    applyNonDuoChromeVisibility()
                } else {
                    applyPortraitChromeVisibility()
                }
                bottomLeadingStack.isHidden = true
                bottomTrailingStack.isHidden = true
                if view.window != nil {
                    view.layoutIfNeeded()
                }
                return
            }
            editorView.isNonDuoPhone = (interfaceMode == .nonDuoPhone || isPortrait)
            editorView.isEditing = isEditingAddress
            let isOverlay = isPortrait ? isPortraitChromeOverlay : isNonDuoChromeOverlay
            if isOverlay {
                SystemToolbarMapper.populateBottomStack(bottomLeadingStack, with: [])
                SystemToolbarMapper.populateBottomStack(bottomTrailingStack, with: [])
                if !isPortrait, shouldShowNonDuoTopBar {
                    topBarView.setItems(prefix: prefix, suffix: suffix)
                } else {
                    topBarView.setItems(prefix: [], suffix: [])
                }
            } else if isLibraryVisible {
                topBarView.setItems(prefix: [], suffix: [])
                SystemToolbarMapper.populateBottomStack(bottomLeadingStack, with: [])
                SystemToolbarMapper.populateBottomStack(bottomTrailingStack, with: suffix)
            } else {
                topBarView.setItems(prefix: [], suffix: [])
                SystemToolbarMapper.populateBottomStack(bottomLeadingStack, with: prefix)
                SystemToolbarMapper.populateBottomStack(bottomTrailingStack, with: suffix)
            }
            if interfaceMode == .nonDuoPhone {
                applyNonDuoChromeVisibility()
            } else {
                applyPortraitChromeVisibility()
            }
            return
        }
        editorView.isNonDuoPhone = false
        editorView.isEditing = isEditingAddress
        let isRegularApplied = chromePlacement == .regular || !topBarView.isHidden
        if isRegularApplied, !isOverviewVisible {
            if suppressesRegularToolbarButtons {
                topBarView.setItems(prefix: [], suffix: [])
            } else if isEditingAddress || isLibraryVisible || isSettingsVisible || isDownloadsVisible {
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
                        self?.promptClearAllDownloads()
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
            let suffixActions: [RailAction] = if isEditingAddress {
                []
            } else {
                [
                    .done { [weak self] in
                        self?.dismissStartPageOrEditing()
                    }
                ]
            }
            setChromeItems(
                prefix: [],
                suffix: suffixActions
            )
        case .browsing:
            let browsing = makeBrowsingChromeItems()
            setChromeItems(prefix: browsing.prefix, suffix: browsing.suffix)
        }
    }

    /// Library rail plus inline header share one commands model.
    /// Both render from `LibraryTabCommands.make` so per-tab sets never drift.
    func updateLibraryRailItems(for tab: LibraryTab) {
        guard isLibraryVisible else { return }
        let readingMenu = bookmarksLibraryView.makeReadingListMenu()
        let commands = LibraryTabCommands.make(
            for: tab,
            isEditingBookmarks: bookmarksLibraryView.isEditingBookmarks,
            canClearHistory: bookmarksLibraryView.canClearHistory,
            isInSelection: bookmarksLibraryView.isActiveTabInSelectionMode,
            canDeleteSelection: bookmarksLibraryView.canDeleteActiveTabSelection
        )
        var prefix: [RailAction] = []
        // Portrait uses bottom stacks like Mode 3, so it shares the Dismiss affordance.
        let suffix: [RailAction] = if interfaceMode == .nonDuoPhone || interfaceMode == .duoInnerOrPadPortrait {
            [
                RailAction(
                    systemImageName: "xmark",
                    accessibilityLabel: "Dismiss",
                    handler: { [weak self] in
                        if commands.doneExitsSelection {
                            self?.bookmarksLibraryView.exitActiveTabSelectionMode()
                            self?.updateLibraryRailItems(for: tab)
                        } else {
                            self?.closeBookmarksLibrary()
                        }
                    }
                )
            ]
        } else if commands.doneExitsSelection {
            [
                .done { [weak self] in
                    self?.bookmarksLibraryView.exitActiveTabSelectionMode()
                    self?.updateLibraryRailItems(for: tab)
                }
            ]
        } else {
            [
                .done { [weak self] in
                    self?.closeBookmarksLibrary()
                }
            ]
        }
        if commands.showsAdd {
            prefix.append(.addFolder { [weak self] in
                self?.bookmarksLibraryView.promptNewFolder()
            })
        }
        if commands.showsEdit {
            let isEditing = commands.isEditingBookmarks
            prefix.append(.edit(isEditing: isEditing) { [weak self] in
                self?.bookmarksLibraryView.toggleBookmarksEdit()
                self?.updateLibraryRailItems(for: tab)
            })
        }
        if commands.showsClear {
            let canClear = commands.canClearHistory
            prefix.append(.clear(isEnabled: canClear) { [weak self] in
                self?.bookmarksLibraryView.promptClearHistory()
            })
        }
        if commands.showsMenu, let menu = readingMenu {
            prefix.append(.readingListMenu(menu: menu))
        }
        if commands.showsDelete {
            let canDelete = commands.canDeleteSelection
            prefix.append(.deleteSelected(isEnabled: canDelete) { [weak self] in
                self?.bookmarksLibraryView.deleteSelectedItemsForActiveTab()
                self?.updateLibraryRailItems(for: tab)
            })
        }
        setChromeItems(prefix: prefix, suffix: suffix)
        bookmarksLibraryView.updateInlineCommands()
    }

    // MARK: - Modes 3 and 4 bottom chrome

    /// Mode 3 editor overlay keeps the transparent bar for Cancel/Save.
    /// Diverges from portrait overlay: overview plus non-modal editor only;
    /// library stays out so its trailing Dismiss survives.
    var shouldShowNonDuoTopBar: Bool {
        (isBookmarkEditorVisible && !isBookmarkEditorPresentedModally)
            && !isOverviewVisible
    }

    /// Sheet or overview covering Mode 3 browsing chrome.
    /// Covers overview plus non-modal editor; editing and find route
    /// through editing, library stays out so Dismiss survives.
    var isNonDuoChromeOverlay: Bool {
        isOverviewVisible || (isBookmarkEditorVisible && !isBookmarkEditorPresentedModally)
    }

    /// Shared bottom-stack fade so Mode 3 and Mode 4 stay in sync.
    private func setBottomStacksFaded(_ hidden: Bool) {
        bottomLeadingStack.alpha = hidden ? 0 : 1
        bottomTrailingStack.alpha = hidden ? 0 : 1
        bottomLeadingStack.isUserInteractionEnabled = !hidden
        bottomTrailingStack.isUserInteractionEnabled = !hidden
    }

    /// Shared bottom-stack hide so Mode 3 and Mode 4 stay in sync.
    private func setBottomStacksHidden(hideLeading: Bool, hideTrailing: Bool) {
        bottomLeadingStack.isHidden = hideLeading
        bottomTrailingStack.isHidden = hideTrailing
    }

    /// Shared pill anchor for bottom chrome; minified keeps centered constraints.
    private func layoutBottomPillAnchors(hideLeading: Bool, hideTrailing: Bool) {
        guard chromeController.state.pill != .minified else { return }
        if hideLeading {
            pillBottomLeadingConstraint?.isActive = false
            pillLeadingConstraint?.isActive = true
        } else {
            pillLeadingConstraint?.isActive = false
            pillBottomLeadingConstraint?.isActive = true
        }
        if hideTrailing {
            pillBottomTrailingConstraint?.isActive = false
            pillTrailingConstraint?.isActive = true
        } else {
            pillTrailingConstraint?.isActive = false
            pillBottomTrailingConstraint?.isActive = true
        }
    }

    /// Shared bottom-chrome applier for Mode 3 and Mode 4: fade plus hide
    /// plus page-menu plus pill-hidden plus pill anchors. Top, rail, strip,
    /// and vertical-bar visibility stay in the per-mode callers.
    private func applyBottomChromeVisibility(
        isPortrait: Bool,
        isOverlay: Bool,
        hideBottomButtons: Bool,
        hideLeading: Bool,
        hideTrailing: Bool
    ) {
        setBottomStacksFaded(hideBottomButtons)
        setBottomStacksHidden(hideLeading: hideLeading, hideTrailing: hideTrailing)
        pillView.showsPageMenu = !isLibraryVisible
        let hidePillForOverlay = isPortrait ? isOverviewVisible : isOverlay
        if hidePillForOverlay {
            pillView.isHidden = true
        } else if isFindActive, chromeController.state.pill != .editing {
            pillView.isHidden = true
        } else {
            pillView.isHidden = chromeController.state.pill == .editing
        }
        layoutBottomPillAnchors(hideLeading: hideLeading, hideTrailing: hideTrailing)
    }

    /// Single visibility owner for Mode 3 bottom pill versus transparent bar versus hidden.
    func applyNonDuoChromeVisibility() {
        guard interfaceMode == .nonDuoPhone, chromePlacement != .regular else { return }
        let showsTopBar = shouldShowNonDuoTopBar
        let isOverlay = isNonDuoChromeOverlay
        let hideBottomButtons = isOverlay || chromeController.state.pill == .minified || chromeController.state.rail == .hidden
        topBarView.isHidden = !showsTopBar
        topBarView.showsBackgroundBar = !showsTopBar
        verticalTabBarView.isHidden = true
        let hideLeading = hideBottomButtons || isLibraryVisible || bottomLeadingStack.arrangedSubviews.isEmpty
        let hideTrailing = hideBottomButtons || bottomTrailingStack.arrangedSubviews.isEmpty
        applyBottomChromeVisibility(
            isPortrait: false,
            isOverlay: isOverlay,
            hideBottomButtons: hideBottomButtons,
            hideLeading: hideLeading,
            hideTrailing: hideTrailing
        )
    }

    /// Single visibility owner for Mode 4 (Duo inner / iPad portrait) bottom chrome plus vertical tab bar.
    func applyPortraitChromeVisibility() {
        guard interfaceMode == .duoInnerOrPadPortrait else { return }
        let isOverlay = isPortraitChromeOverlay
        let hideBottomButtons = isOverlay || chromeController.state.pill == .minified || chromeController.state.rail == .hidden
        topBarView.isHidden = true
        railView.isHidden = true
        tabStripView.isHidden = true
        // Library hides the leading stack so the pill can expand to the edge.
        let hideLeading = hideBottomButtons || isLibraryVisible || bottomLeadingStack.arrangedSubviews.isEmpty
        let hideTrailing = hideBottomButtons || bottomTrailingStack.arrangedSubviews.isEmpty
        applyBottomChromeVisibility(
            isPortrait: true,
            isOverlay: isOverlay,
            hideBottomButtons: hideBottomButtons,
            hideLeading: hideLeading,
            hideTrailing: hideTrailing
        )
        let freshTabs = TabOverviewViewController.tabs(overviewItems(), in: overviewMode)
        verticalTabBarView.showsNewTabButton = false
        verticalTabBarView.render(tabs: freshTabs, selectedID: selectedTabID)
        let hideSideTab = shouldHidePortraitChrome(itemCount: freshTabs.count)
        verticalTabBarView.alpha = hideSideTab ? 0 : 1
        verticalTabBarView.isUserInteractionEnabled = !hideSideTab
        verticalTabBarView.isHidden = hideSideTab
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
