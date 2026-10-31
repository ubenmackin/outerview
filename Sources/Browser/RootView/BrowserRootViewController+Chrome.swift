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
            if commands.pill != nil {
                applyPillViews(animated: animated)
            }
            if commands.rail != nil || commands.pill != nil {
                applyTopBarViews(animated: animated)
            }
            return
        }
        if commands.pill != nil {
            applyPillViews(animated: animated)
        }
        if commands.rail != nil || commands.pill != nil {
            applyRailViews(animated: animated)
        }
    }

    func applyChromeViews(animated: Bool) {
        if chromePlacement == .regular {
            applyPillViews(animated: animated)
            applyTopBarViews(animated: animated)
            return
        }
        applyPillViews(animated: animated)
        applyRailViews(animated: animated)
    }

    /// Single owner for regular toolbar visibility: editing/overview shows
    /// the bar with both stacks, sheet overlays show the bar but hide the
    /// duplicated stacks, otherwise the collapsed rail state drives the bar.
    /// All regular placement sites delegate here; none re-implement the
    /// branching.
    func updateToolbarVisibility(for state: ChromeState) {
        railView.isHidden = true
        if state.pill == .editing || isOverviewVisible {
            topBarView.isHidden = false
            topBarView.leadingStack.isHidden = false
            topBarView.trailingStack.isHidden = false
            tabStripView.isHidden = true
            return
        }
        if isSheetOverlayVisible {
            topBarView.isHidden = false
            topBarView.leadingStack.isHidden = true
            topBarView.trailingStack.isHidden = true
            tabStripView.isHidden = true
            return
        }
        let isCollapsed = state.rail == .hidden
        topBarView.isHidden = isCollapsed
        topBarView.leadingStack.isHidden = isCollapsed
        topBarView.trailingStack.isHidden = isCollapsed
        if isCollapsed {
            tabStripView.isHidden = true
        } else {
            updateTabStrip()
        }
    }

    func applyTopBarViews(animated _: Bool) {
        updateToolbarVisibility(for: chromeController.state)
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
            scrollProxies[id] = proxy
        }
        proxy.attach(to: page.webView.scrollView)
    }

    /// Tells only the content about the chrome reservation. The root keeps
    /// the real system safe area so chrome anchored to it never pushes
    /// itself; web content keeps rendering under the chrome and only its
    /// scrollable range grows.
    func applyContentInsets() {
        let systemBottom = view.safeAreaInsets.bottom
        let bottom = Self.contentBottomInset(systemBottomInset: systemBottom)
        if let webView = peekActivePage()?.webView {
            let insets = UIEdgeInsets(top: 0, left: 0, bottom: bottom, right: 0)
            if webView.obscuredContentInsets != insets {
                webView.obscuredContentInsets = insets
            }
        }
        startPageView?.setBottomChromeInset(max(0, bottom - systemBottom))
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
                self.pillView.isHidden = state.pill == .editing
                self.editorView.isHidden = state.pill != .editing
                self.view.layoutIfNeeded()
            }
            if animated {
                pillAnimator?.stopAnimation(true)
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
            pillAnimator?.stopAnimation(true)
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
        topBarView.isHidden = true
        railView.isHidden = false
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
        if isEditingAddress {
            endEditing(submitted: false)
        }
        dismissForcedStartPage()
    }

    func setChromeItems(prefix: [RailAction], suffix: [RailAction]) {
        railView.setItems(prefix: prefix, suffix: suffix)
        if chromePlacement == .regular, isSheetOverlayVisible, !isOverviewVisible {
            topBarView.setItems(prefix: [], suffix: [])
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
            let canGoBack = peekActivePage()?.snapshot.canGoBack ?? false
            setChromeItems(
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
