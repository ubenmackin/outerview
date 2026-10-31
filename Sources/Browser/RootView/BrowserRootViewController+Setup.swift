//
//  BrowserRootViewController+Setup.swift
//  OuterView
//

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

    func setupTopBar() {
        topBarView.translatesAutoresizingMaskIntoConstraints = false
        topBarView.isHidden = true
        view.addSubview(topBarView)
        let toSafeArea = topBarView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        let toViewTop = topBarView.topAnchor.constraint(equalTo: view.topAnchor)
        topBarTopToSafeAreaConstraint = toSafeArea
        topBarTopToViewConstraint = toViewTop
        topBarTopConstraint = toSafeArea
        topBarLeadingConstraint = topBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        topBarTrailingConstraint = topBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        NSLayoutConstraint.activate([
            toSafeArea,
            topBarLeadingConstraint,
            topBarTrailingConstraint
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

    func setupPill() {
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
        // Single-owner composition: the per-tab branching lives in
        // `LibraryTabCommands.make` and both the rail and the inline header
        // render from it, mirroring `overviewMenuActions`.
        let readingMenu = bookmarksLibraryView.makeReadingListMenu()
        let commands = LibraryTabCommands.make(
            for: tab,
            isEditingBookmarks: bookmarksLibraryView.isEditingBookmarks,
            canClearHistory: bookmarksLibraryView.canClearHistory,
            isInSelection: tab == .readingList && bookmarksLibraryView.isReadingListInSelectionMode,
            canDeleteSelection: bookmarksLibraryView.canDeleteReadingListSelection,
            hasReadingListMenu: readingMenu != nil
        )
        var prefix: [RailAction] = []
        let suffix: [RailAction] = if commands.doneExitsSelection {
            // No Library-exit action while selecting: the blue check ends
            // selection mode first; rail exit returns once it ends.
            [
                .done { [weak self] in
                    self?.bookmarksLibraryView.exitReadingListSelectionMode()
                    self?.updateLibraryRailItems(for: .readingList)
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
                self?.updateLibraryRailItems(for: .bookmarks)
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
                self?.bookmarksLibraryView.deleteReadingListSelectedItems()
                self?.updateLibraryRailItems(for: .readingList)
            })
        }

        setChromeItems(prefix: prefix, suffix: suffix)
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
