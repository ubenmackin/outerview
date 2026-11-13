// RootView — Hierarchy plus pill, overlay, and vertical tab bar setup.

import os
import SwiftUI
import UIKit

extension BrowserRootViewController {
    // MARK: - Setup

    func setupHierarchy() {
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
        let startTop = startPageContainer.topAnchor.constraint(equalTo: contentContainer.topAnchor)
        startPageTopToContentConstraint = startTop
        NSLayoutConstraint.activate([
            startPageContainer.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            startPageContainer.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            startTop,
            startPageContainer.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])

        setupErrorOverlay()
        setupTopBar()
        setupTabStrip()
        setupPill()
        setupVerticalTabBar()
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

    func setupOverlays() {
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

    /// Single z-order for floating layers; rail stays topmost.
    /// Overview rail composition is never covered by its surface.
    /// Hidden rail has zero alpha and skips hit testing.
    func bringChromeToFront() {
        view.bringSubviewToFront(errorContainer)
        // Modes 3 plus 4 retain pill above library for Dismiss;
        // elsewhere library covers pill.
        if interfaceMode == .nonDuoPhone || interfaceMode == .duoInnerOrPadPortrait {
            if bookmarksLibraryView.superview === view {
                view.bringSubviewToFront(bookmarksLibraryView)
            }
            if pillView.superview == view {
                view.bringSubviewToFront(bottomLeadingStack)
                view.bringSubviewToFront(bottomTrailingStack)
                view.bringSubviewToFront(pillView)
            }
        } else {
            if pillView.superview == view {
                view.bringSubviewToFront(bottomLeadingStack)
                view.bringSubviewToFront(bottomTrailingStack)
                view.bringSubviewToFront(pillView)
            }
            if bookmarksLibraryView.superview === view {
                view.bringSubviewToFront(bookmarksLibraryView)
            }
        }
        view.bringSubviewToFront(findView)
        view.bringSubviewToFront(editorView)
        view.bringSubviewToFront(settingsContainer)
        view.bringSubviewToFront(downloadsContainer)
        view.bringSubviewToFront(bookmarkEditorContainer)
        view.bringSubviewToFront(libraryOverlay)
        view.bringSubviewToFront(settingsOverlay)
        view.bringSubviewToFront(downloadsOverlay)
        view.bringSubviewToFront(bookmarkEditorOverlay)
        view.bringSubviewToFront(overviewView)
        view.bringSubviewToFront(tabStripView)
        if chromePlacement == .regular {
            view.bringSubviewToFront(topBarView)
            view.bringSubviewToFront(editorView)
        } else if !isOverviewVisible {
            view.bringSubviewToFront(topBarView)
        }
        view.bringSubviewToFront(verticalTabBarView)
        view.bringSubviewToFront(railView)
    }

    func setupBookmarkEditor() {
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

    func setupRail() {
        railView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(railView)
        NSLayoutConstraint.activate([
            railView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            railView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            railView.topAnchor.constraint(equalTo: view.topAnchor),
            railView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    /// REGULAR-COLLAPSE: collapsed keeps bar visible hiding stacks plus strip.
    /// Pill centers via bar-scoped centerX plus width; collapsed inset is remnant height.
    /// Additional safe-area top is zero; no remnant view exists.
    func setupTopBar() {
        topBarView.translatesAutoresizingMaskIntoConstraints = false
        topBarView.isHidden = true
        topBarView.onSlotWidthChanged = { [weak self] in
            guard let self, self.pillSlotWidthConstraint?.isActive == true else { return }
            self.updateRegularPillGeometry()
            self.topBarView.pillSlotView.layoutIfNeeded()
        }
        view.addSubview(topBarView)
        let toSafeArea = topBarView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        let toViewTop = topBarView.topAnchor.constraint(equalTo: view.topAnchor)
        topBarTopToSafeAreaConstraint = toSafeArea
        topBarTopToViewConstraint = toViewTop
        topBarTopConstraint = toSafeArea
        let topBarLeading = topBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        let topBarTrailing = topBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        topBarLeadingConstraint = topBarLeading
        topBarTrailingConstraint = topBarTrailing
        NSLayoutConstraint.activate([
            toSafeArea,
            topBarLeading,
            topBarTrailing
        ])
    }

    func setupTabStrip() {
        tabStripView.translatesAutoresizingMaskIntoConstraints = false
        tabStripView.isHidden = true
        tabStripView.onSelectTab = { [weak self] id in
            self?.selectTab(id: id)
        }
        tabStripView.onCloseTab = { [weak self] id in
            self?.closeTab(id: id, replacementIfEmpty: nil)
        }
        tabStripView.onReorderTabs = { [weak self] orderedIDs in
            guard let self else { return }
            self.reorderTabs(orderedIDs: orderedIDs, isPrivate: self.overviewMode.isPrivate)
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

    func setupVerticalTabBar() {
        verticalTabBarView.translatesAutoresizingMaskIntoConstraints = false
        verticalTabBarView.isHidden = true
        verticalTabBarView.onSelectTab = { [weak self] id in
            self?.selectTab(id: id)
        }
        verticalTabBarView.onCloseTab = { [weak self] id in
            self?.closeTab(id: id, replacementIfEmpty: nil)
        }
        verticalTabBarView.onNewTab = { [weak self] in
            guard let self else { return }
            self.createNewTab(isPrivate: self.overviewMode.isPrivate)
        }
        view.addSubview(verticalTabBarView)

        let trailing = verticalTabBarView.trailingAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.trailingAnchor,
            constant: -16
        )
        let leading = verticalTabBarView.leadingAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.leadingAnchor,
            constant: 16
        )
        verticalTabBarTrailingConstraint = trailing
        verticalTabBarLeadingConstraint = leading
        let bottom = verticalTabBarView.bottomAnchor.constraint(
            equalTo: pillView.topAnchor,
            constant: -16
        )
        verticalTabBarBottomConstraint = bottom

        NSLayoutConstraint.activate([
            verticalTabBarView.widthAnchor.constraint(equalToConstant: VerticalTabBarView.barWidth),
            bottom,
            verticalTabBarView.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 16)
        ])

        updateVerticalTabBarPosition()
        observePortraitTabBarPosition()
    }

    private func observePortraitTabBarPosition() {
        guard !hasPortraitObserver() else { return }
        let observer = NotificationCenter.default.addObserver(
            forName: .portraitTabBarPositionChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.updateVerticalTabBarPosition()
            }
        }
        storePortraitObserver(observer)
    }

    func updateVerticalTabBarPosition() {
        let position = selectionDefaults.string(forKey: SettingsViewModel.portraitTabBarPositionDefaultsKey)
            .flatMap(PortraitTabBarPosition.init(rawValue:)) ?? .right
        // Skip redundant re-constraining so preference no-ops never relayout.
        if position == .left {
            guard verticalTabBarTrailingConstraint?.isActive != false
                || verticalTabBarLeadingConstraint?.isActive != true else { return }
            verticalTabBarTrailingConstraint?.isActive = false
            verticalTabBarLeadingConstraint?.isActive = true
        } else {
            guard verticalTabBarTrailingConstraint?.isActive != true
                || verticalTabBarLeadingConstraint?.isActive != false else { return }
            verticalTabBarLeadingConstraint?.isActive = false
            verticalTabBarTrailingConstraint?.isActive = true
        }
        guard isViewLoaded else { return }
        view.setNeedsLayout()
        // Detached views apply on the next attached pass; forcing layout
        // without a window re-enters viewDidLayoutSubviews mid-setup.
        if view.window != nil {
            view.layoutIfNeeded()
        }
    }

    func setupPill() {
        pillView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pillView)
        let pillHeight = pillView.heightAnchor.constraint(
            equalToConstant: AddressBarView.heightForState(.expanded)
        )
        let pillLeading = pillView.leadingAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16
        )
        let pillTrailing = pillView.trailingAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16
        )
        pillCenterXConstraint = pillView.centerXAnchor.constraint(
            equalTo: view.centerXAnchor
        )
        pillWidthConstraint = pillView.widthAnchor.constraint(
            equalToConstant: AddressBarView.widthForBounds(view.bounds.width)
        )
        let pillBottom = pillView.bottomAnchor.constraint(
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
        let pillSlotCenterX = pillView.centerXAnchor.constraint(
            equalTo: topBarView.centerXAnchor
        )
        // Bar-centered wins so an asymmetric slot never drags the capsule off-center.
        pillSlotCenterX.priority = .required
        let pillSlotWidth = pillView.widthAnchor.constraint(
            equalToConstant: AddressBarView.minifiedMaxWidth
        )
        pillSlotWidth.priority = UILayoutPriority(998)
        let pillSlotMinLeading = pillView.leadingAnchor.constraint(
            greaterThanOrEqualTo: topBarView.pillSlotView.leadingAnchor
        )
        pillSlotMinLeading.priority = .defaultHigh
        let pillSlotMaxTrailing = pillView.trailingAnchor.constraint(
            lessThanOrEqualTo: topBarView.pillSlotView.trailingAnchor
        )
        pillSlotMaxTrailing.priority = .defaultHigh

        pillHeightConstraint = pillHeight
        pillLeadingConstraint = pillLeading
        pillTrailingConstraint = pillTrailing
        pillBottomConstraint = pillBottom
        pillSlotCenterXConstraint = pillSlotCenterX
        pillSlotWidthConstraint = pillSlotWidth
        pillSlotMinLeadingConstraint = pillSlotMinLeading
        pillSlotMaxTrailingConstraint = pillSlotMaxTrailing

        // Mode 3: 44 pt native Liquid Glass buttons with 8 pt
        // spacing; outer insets stay 16 pt with 8 pt pill gaps.
        for stack in [bottomLeadingStack, bottomTrailingStack] {
            stack.axis = .horizontal
            stack.alignment = .center
            stack.spacing = SystemToolbarMapper.bottomBarSpacing
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.isHidden = true
            stack.layer.cornerRadius = SystemToolbarMapper.bottomBarCornerRadius
            stack.clipsToBounds = true
            view.addSubview(stack)
        }
        pillBottomLeadingConstraint = pillView.leadingAnchor.constraint(
            equalTo: bottomLeadingStack.trailingAnchor, constant: 8
        )
        pillBottomTrailingConstraint = pillView.trailingAnchor.constraint(
            equalTo: bottomTrailingStack.leadingAnchor, constant: -8
        )
        let bottomLeadingCenterY = bottomLeadingStack.centerYAnchor.constraint(
            equalTo: pillView.centerYAnchor
        )
        let bottomTrailingCenterY = bottomTrailingStack.centerYAnchor.constraint(
            equalTo: pillView.centerYAnchor
        )
        bottomLeadingCenterYConstraint = bottomLeadingCenterY
        bottomTrailingCenterYConstraint = bottomTrailingCenterY

        NSLayoutConstraint.activate([
            pillBottom,
            pillHeight,
            pillLeading,
            pillTrailing,
            bottomLeadingStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            bottomLeadingCenterY,
            bottomLeadingStack.heightAnchor.constraint(equalToConstant: SystemToolbarMapper.bottomBarHeight),
            bottomTrailingStack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            bottomTrailingCenterY,
            bottomTrailingStack.heightAnchor.constraint(equalToConstant: SystemToolbarMapper.bottomBarHeight)
        ])
        pillView.onPillTap = { [weak self] in self?.handlePillTap() }
        pillView.onHorizontalPan = { [weak self] event in self?.handleHorizontalPan(event) }
        pillView.onVerticalPan = { [weak self] event in self?.handleVerticalPan(event) }
        pillView.onPageMenu = { [weak self] in self?.showPageMenu() }
        pillView.pageMenuProvider = { [weak self] in
            self?.makePageMenu() ?? UIMenu()
        }
        pillView.onReload = { [weak self] in self?.activePage()?.reload() }
        pillView.onStop = { [weak self] in self?.activePage()?.stop() }
        pillView.onDownloadsTap = { [weak self] in self?.presentDownloadsFromMenu() }
    }

    func setupEditor() {
        editorView.translatesAutoresizingMaskIntoConstraints = false
        editorView.isHidden = true
        // Injected toolbar reference so the regular panel tracks the toolbar's
        // bottom edge instead of assuming safeArea.top equals the toolbar origin.
        editorView.toolbarAnchorView = topBarView
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
        editorView.onSelectFavorite = { [weak self] url in
            guard let self else { return }
            guard URLNormalizer.isLoadable(url) else {
                self.showEditorInputError(
                    Self.inputErrorMessage(for: .unsupportedScheme(url.scheme?.lowercased() ?? "unknown"))
                )
                return
            }
            self.clearEditorInputError()
            self.clearForcedStartPageForSelectedTab()
            self.loadActivePage(url)
            self.endEditing(submitted: true)
            if self.isLibraryVisible {
                self.closeBookmarksLibrary()
            }
        }
        editorView.onDone = { [weak self] in self?.dismissStartPageOrEditing() }
    }

    func setupLibrary() {
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
                readingListStore: readingListStore,
                recentSearchStore: recentSearchStore
            )
        }
        bookmarksLibraryView.onSelectSearchQuery = { [weak self] query in
            self?.closeBookmarksLibrary()
            self?.submitAddressText(query)
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
            // Dismissing only the keyboard would strand editing flags on with no focus.
            if self?.isEditingAddress == true {
                self?.endEditing(submitted: false)
            }
            self?.updateLibraryRailItems(for: tab)
        }
        bookmarksLibraryView.onReadingListStateChanged = { [weak self] in
            guard let self, self.isLibraryVisible, self.bookmarksLibraryView.currentTab == .readingList else { return }
            self.updateLibraryRailItems(for: .readingList)
        }
        bookmarksLibraryView.onDidMutateLibraryData = { [weak self] in
            self?.updateStartPageContent()
        }
        bookmarksLibraryView.tabGroupsProvider = { [weak self] in
            guard let self else { return [] }
            let groups = self.tabStore?.fetchGroups() ?? []
            // Zero-member groups stay hidden from the folder submenu.
            return groups.filter { group in
                self.tabs.contains { $0.groupId == group.id && !$0.isPrivate }
            }
        }
        bookmarksLibraryView.onOpenURLsInBackground = { [weak self] urls in
            self?.openURLsInBackground(urls)
        }
        bookmarksLibraryView.onOpenURLsInTabGroup = { [weak self] urls, group in
            self?.openURLsInGroup(urls, groupId: group.id)
        }
        bookmarksLibraryView.onOpenURLsInNewTabGroup = { [weak self] urls, name in
            self?.openURLsInNewGroup(urls, name: name)
        }
    }

    func setupSettings() {
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

    /// Single present path for settings/downloads/bookmark-editor sheets.
    /// Regular centers in `OverlayCardView`; compact pins full-bleed.
    /// Compact trailing edge respects safe area so rail stays clear.
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
        settingsHosting = hosting
        isSettingsVisible = true
        let isModalSheet = interfaceMode != .duoOuter
        if isModalSheet {
            hosting.modalPresentationStyle = .pageSheet
            hosting.presentationController?.delegate = self
            if let sheet = hosting.sheetPresentationController {
                sheet.prefersGrabberVisible = true
            }
            if view.window != nil {
                present(hosting, animated: shouldAnimateModalSheets)
            }
        } else {
            presentOverlay(settingsOverlay, newHosting: hosting, currentHosting: nil, container: settingsContainer)
        }
        bringChromeToFront()
        updateRailItems()
        applyRailViews(animated: true)
    }

    func dismissSettingsSheet() {
        isSettingsVisible = false
        if let hosting = settingsHosting {
            if hosting.presentingViewController != nil {
                hosting.dismiss(animated: shouldAnimateModalSheets)
            }
            dismissOverlay(settingsOverlay, hosting: hosting, container: settingsContainer)
            settingsHosting = nil
        }
        updateRailItems()
        applyRailViews(animated: true)
    }

    var shouldAnimateModalSheets: Bool {
        view.window != nil && !AppEnvironment.isTestHost
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

        if placement == .regular,
           let librarySheet = librarySheetController,
           librarySheet.presentingViewController != nil
        {
            if isBookmarkEditorPresentedModally {
                bookmarkEditorHosting?.dismiss(animated: false)
            } else {
                dismissOverlay(bookmarkEditorOverlay, hosting: bookmarkEditorHosting, container: bookmarkEditorContainer)
            }
            hosting.modalPresentationStyle = .pageSheet
            if let sheet = hosting.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = false
                sheet.preferredCornerRadius = 28
            }
            bookmarkEditorHosting = hosting
            isBookmarkEditorPresentedModally = true
            isBookmarkEditorVisible = true
            librarySheet.present(hosting, animated: shouldAnimateModalSheets)
            updateRailItems()
            applyRailViews(animated: true)
            return
        }

        if placement == .regular || interfaceMode == .nonDuoPhone {
            hosting.modalPresentationStyle = .pageSheet
            if let sheet = hosting.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = false
                sheet.preferredCornerRadius = 28
            }
            bookmarkEditorHosting = hosting
            isBookmarkEditorPresentedModally = true
            isBookmarkEditorVisible = true
            if view.window != nil {
                present(hosting, animated: shouldAnimateModalSheets)
            }
            updateRailItems()
            applyRailViews(animated: true)
            return
        }

        isBookmarkEditorPresentedModally = false
        presentOverlay(bookmarkEditorOverlay, newHosting: hosting, currentHosting: bookmarkEditorHosting, container: bookmarkEditorContainer)
        bookmarkEditorHosting = hosting

        isBookmarkEditorVisible = true
        bringChromeToFront()
        updateRailItems()
        applyRailViews(animated: true)
    }

    func dismissBookmarkEditor() {
        isBookmarkEditorVisible = false
        if isBookmarkEditorPresentedModally {
            isBookmarkEditorPresentedModally = false
            bookmarkEditorHosting?.dismiss(animated: shouldAnimateModalSheets)
        } else {
            dismissOverlay(bookmarkEditorOverlay, hosting: bookmarkEditorHosting, container: bookmarkEditorContainer)
        }
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
        bookmarksLibraryView.isNonDuoPhone = (interfaceMode == .nonDuoPhone || interfaceMode == .duoInnerOrPadPortrait)
        bookmarksLibraryView.isMode4 = (interfaceMode == .duoInnerOrPadPortrait)
        if interfaceMode == .nonDuoPhone {
            pillView.showsPageMenu = false
        }
        bookmarksLibraryView.applyPlacement(for: placement)
        libraryOverlay.applyPlacement(for: placement)
        libraryOverlay.isHidden = true
        if libraryOverlay.hostedContent === bookmarksLibraryView {
            libraryOverlay.clearContent()
        }
        isLibraryVisible = true
        if placement == .regular {
            if bookmarksLibraryView.superview === view {
                NSLayoutConstraint.deactivate(libraryCompactConstraints)
                bookmarksLibraryView.removeFromSuperview()
            }
            let sheet: LibrarySheetViewController
            if let existing = librarySheetController {
                sheet = existing
            } else {
                let created = LibrarySheetViewController(libraryView: bookmarksLibraryView)
                created.onDidDismiss = { [weak self] in
                    self?.handleLibrarySheetSystemDismiss()
                }
                librarySheetController = created
                sheet = created
            }
            bookmarksLibraryView.isHidden = false
            bookmarksLibraryView.open(tab: resolved)
            updateLibraryRailItems(for: resolved)
            applyChromeViews(animated: false)
            bringChromeToFront()
            if view.window != nil {
                if sheet.presentingViewController == nil {
                    present(sheet, animated: shouldAnimateModalSheets)
                }
                if sheet.viewIfLoaded?.window != nil || !shouldAnimateModalSheets {
                    sheet.attachLibraryViewIfNeeded()
                }
            }
        } else {
            if let sheet = librarySheetController {
                sheet.onDidDismiss = nil
                if sheet.presentingViewController != nil {
                    sheet.dismiss(animated: false)
                }
                sheet.detachLibraryView()
                librarySheetController = nil
            }
            if bookmarksLibraryView.superview !== view {
                view.addSubview(bookmarksLibraryView)
                NSLayoutConstraint.activate(libraryCompactConstraints)
            }
            bookmarksLibraryView.isHidden = false
            bookmarksLibraryView.open(tab: resolved)
            updateLibraryRailItems(for: resolved)
            applyChromeViews(animated: false)
            bringChromeToFront()
        }
    }

    func closeBookmarksLibrary() {
        bookmarksLibraryView.resetFirstTabMode()
        pillView.showsPageMenu = true
        bookmarksLibraryView.resetRegularSelectionModes()
        isLibraryVisible = false
        libraryOverlay.isHidden = true
        if let sheet = librarySheetController {
            sheet.onDidDismiss = nil
            if isBookmarkEditorPresentedModally {
                isBookmarkEditorPresentedModally = false
                isBookmarkEditorVisible = false
                bookmarkEditorHosting = nil
                activeBookmarkEditorModel = nil
            }
            let detachAndClear = { [weak self, weak sheet] in
                sheet?.detachLibraryView()
                if self?.librarySheetController === sheet {
                    self?.librarySheetController = nil
                }
                self?.bookmarksLibraryView.isHidden = true
            }
            if sheet.presentingViewController != nil {
                if shouldAnimateModalSheets {
                    sheet.dismiss(animated: true, completion: detachAndClear)
                } else {
                    sheet.dismiss(animated: false)
                    detachAndClear()
                }
            } else {
                detachAndClear()
            }
        } else {
            bookmarksLibraryView.isHidden = true
            if libraryOverlay.hostedContent === bookmarksLibraryView {
                libraryOverlay.clearContent()
            }
        }
        updateRailItems()
        applyChromeViews(animated: false)
    }

    func handleLibrarySheetSystemDismiss() {
        bookmarksLibraryView.resetRegularSelectionModes()
        let sheet = librarySheetController
        sheet?.onDidDismiss = nil
        sheet?.detachLibraryView()
        librarySheetController = nil
        if isBookmarkEditorPresentedModally {
            isBookmarkEditorPresentedModally = false
            isBookmarkEditorVisible = false
            bookmarkEditorHosting = nil
            activeBookmarkEditorModel = nil
        }
        isLibraryVisible = false
        libraryOverlay.isHidden = true
        bookmarksLibraryView.isHidden = true
        updateRailItems()
        applyChromeViews(animated: false)
    }

    func setupOverview() {
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
            if let preview = self?.screenshotTabPreviews[id] {
                completion(preview)
                return
            }
            guard let page = self?.tabPool.pages.first(where: { $0.id == id })?.page else {
                completion(nil)
                return
            }
            page.takeSnapshot(completion: completion)
        }
    }

    func setupStartPageContent() {
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
                try viewModel.deleteItem(id: id)
            } catch {
                self?.logPersistenceError(error, operation: "deleteFavorite")
            }
            self?.updateStartPageContent()
            self?.bookmarksLibraryView.reload()
        }
        startView.tabGroupsProvider = { [weak self] in
            guard let self else { return [] }
            let groups = self.tabStore?.fetchGroups() ?? []
            return groups.filter { group in
                self.tabs.contains { $0.groupId == group.id && !$0.isPrivate }
            }
        }
        startView.onOpenInNewTab = { [weak self] url in
            self?.openNewTab(with: url)
        }
        startView.onOpenURLsInBackground = { [weak self] urls in
            self?.openURLsInBackground(urls)
        }
        startView.onOpenURLsInTabGroup = { [weak self] urls, group in
            self?.openURLsInGroup(urls, groupId: group.id)
        }
        startView.onOpenURLsInNewTabGroup = { [weak self] urls, name in
            self?.openURLsInNewGroup(urls, name: name)
        }
        startView.onRequestEdit = { [weak self] target in
            self?.presentBookmarkEditor(for: target)
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

// MARK: - UIAdaptivePresentationControllerDelegate

extension BrowserRootViewController: UIAdaptivePresentationControllerDelegate {
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        if presentationController.presentedViewController === settingsHosting {
            dismissSettingsSheet()
        } else if presentationController.presentedViewController === downloadsHosting {
            dismissDownloadsSheet()
        }
    }
}
