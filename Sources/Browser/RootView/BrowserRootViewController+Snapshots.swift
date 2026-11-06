// RootView — Snapshot listener wiring plus start-page and pill refresh.

import Foundation
import OSLog
import UIKit

extension BrowserRootViewController {
    // MARK: - Snapshots

    /// Single owner for page wiring: menus, zoom, downloads plus privacy routing.
    /// Called at checkout before load so standard tabs never take private path.
    func wirePage(_ page: WebPageController, for id: UUID) {
        page.contextActions = elementContextActions
        page.siteZoomStore = siteZoomStore
        page.downloadsManager = downloadsManager
        page.isPrivateTab = tabs.first(where: { $0.id == id })?.isPrivate ?? true
        page.backgroundService = BackgroundDownloadService.shared
        page.uiDelegateHandler = self
    }

    func ensureSnapshotListener(for id: UUID, page: WebPageController) {
        // Recreated pages arrive unwired; reassert routing before listening.
        wirePage(page, for: id)
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

    func handleSnapshot(_ snapshot: WebPageSnapshot, for id: UUID) {
        var didChange = false
        var didCommitNewURL = false
        var didTitleChange = false
        // Fail-closed: a missing tab never records history.
        var isPrivateTab = true
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
                let isNewCommittedURL = snapshot.url != nil && lastCommittedURLByTab[id] != snapshot.url
                didCommitNewURL = isNewCommittedURL
                if isNewCommittedURL, let snapURL = snapshot.url {
                    lastCommittedURLByTab[id] = snapURL
                }
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
                updateStartPageContent(with: snapshot)
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
        if didChange {
            if isOverviewVisible {
                overviewController.setItems(overviewItems(), selectedID: selectedTabID)
            }
            updateTabStrip()
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
        bookmarksLibraryView.startPageView?.reload()
        if isEditingAddress {
            let favorites = StartPageViewModel.sortedFavorites(bookmarkStore?.fetchFavorites() ?? [])
            editorView.setFavorites(favorites)
        }
    }

    func updatePillForSnapshot(_ snapshot: WebPageSnapshot) {
        let isLoading = snapshot.url != nil && snapshot.progress < 1 && snapshot.lastError == nil
        pillView.configure(url: snapshot.url, isSecure: snapshot.isSecure, isLoading: isLoading)
        if chromePlacement == .regular, chromeController.state.pill == .minified {
            updateRegularPillGeometry()
        }
    }
}
