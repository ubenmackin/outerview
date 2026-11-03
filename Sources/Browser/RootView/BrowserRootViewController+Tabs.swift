//
//  BrowserRootViewController+Tabs.swift
//  OuterView
//

import UIKit

enum PillSwipeDirection: Sendable {
    case left
    case right
}

extension BrowserRootViewController {
    // MARK: - Tabs

    func loadInitialTabs() {
        // Screenshot runs seed fixed tabs; restore would clobber them.
        guard !Self.isScreenshotRun else {
            return
        }
        if let argIndex = ProcessInfo.processInfo.arguments.firstIndex(of: "-openURL"),
           argIndex + 1 < ProcessInfo.processInfo.arguments.count,
           let url = URL(string: ProcessInfo.processInfo.arguments[argIndex + 1]),
           URLNormalizer.isLoadable(url)
        {
            let record = TabRecord(url: url, isPrivate: false)
            tabs = [record]
            tabPool.create(record)
            selectTab(id: record.id)
            return
        }
        if let coordinator = restoreCoordinator, bootstrap(from: coordinator.restore()) {
            return
        } else if restoreCoordinator == nil, let tabStore, bootstrap(from: tabStore.loadSession()) {
            return
        }
        createNewTab()
    }

    func bootstrap(from session: (tabs: [TabRecord], selected: UUID?)) -> Bool {
        guard !session.tabs.isEmpty else { return false }
        tabs = session.tabs
        for record in tabs {
            tabPool.reserve(record)
        }
        guard let fallbackID = tabs.first?.id else { return false }
        let selected = session.selected.flatMap { id in tabs.first { $0.id == id }?.id }
        selectTab(id: selected ?? fallbackID)
        return true
    }

    func createNewTab(isPrivate: Bool = false) {
        let record = TabRecord(isPrivate: isPrivate)
        tabs.append(record)
        tabPool.create(record)
        do {
            try tabStore?.saveSession(tabs: tabs, selected: record.id)
        } catch {
            logPersistenceError(error, operation: "saveSession")
        }
        let commands = chromeController.handle(.browsingResumed)
        selectTab(id: record.id)
        applyCommands(commands, animated: true)
        if isOverviewVisible {
            overviewController.setItems(overviewItems(), selectedID: selectedTabID)
        } else {
            setOverviewVisible(false)
        }
    }

    func openNewTab(with url: URL) {
        createNewTab()
        loadActivePage(url)
    }

    /// Opens `url` on a fresh non-private tab inserted directly after the
    /// selected one, without disturbing tabs further down the strip. When
    /// `background` is false the new tab becomes selected and chrome resumes
    /// through the browsing-resumed override.
    func openInNewTab(url: URL, background: Bool = false) {
        let record = TabRecord(url: url, isPrivate: false)
        let insertIndex: Int =
            if let selected = selectedTabID, let index = tabs.firstIndex(where: { $0.id == selected }) {
                index + 1
            } else {
                tabs.count
            }
        tabs.insert(record, at: insertIndex)
        tabPool.create(record)
        do {
            try tabStore?.saveSession(tabs: tabs, selected: selectedTabID)
        } catch {
            logPersistenceError(error, operation: "saveSession")
        }
        if background {
            if isOverviewVisible {
                overviewController.setItems(overviewItems(), selectedID: selectedTabID)
            }
            return
        }
        selectTab(id: record.id)
        applyBrowsingResumed(animated: true)
    }

    func displaySelectedTab() {
        for subview in contentContainer.subviews where subview !== startPageContainer {
            subview.removeFromSuperview()
        }
        guard let id = selectedTabID, let page = tabPool.page(for: id) else {
            startPageContainer.isHidden = false
            return
        }
        // Checkout wiring precedes load so standard tabs never read private defaults.
        wirePage(page, for: id)
        if let record = tabs.first(where: { $0.id == id }),
           page.snapshot.url == nil, let url = record.url
        {
            if URLNormalizer.isLoadable(url) {
                page.load(url)
            } else {
                // Scrub a persisted rejected scheme so it never reloads and
                // never resurfaces in the overview.
                record.url = nil
                record.title = nil
            }
        }
        attachScrollProxy(for: id, page: page)
        ensureSnapshotListener(for: id, page: page)
        let webView = page.webView
        webView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.insertSubview(webView, at: 0)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            webView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            webView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
        applyContentInsets()
        refreshForSnapshot(page.snapshot)
    }

    func shouldShowStartPage(for id: UUID, snapshot: WebPageSnapshot) -> Bool {
        if forcedStartPageTabs.contains(id) {
            return true
        }
        return snapshot.url == nil
    }

    func showStartPageForActiveTab() {
        guard let id = selectedTabID else { return }
        forcedStartPageTabs.insert(id)
        refreshForActiveSnapshot()
    }

    /// Bumps the selected page's recency without disturbing chrome. A live
    /// page is touched in place; an evicted page is redisplayed so its web
    /// view is recreated and its URL reloaded.
    func markActivePageActivated() {
        guard let id = selectedTabID else { return }
        let isLive = tabPool.pages.first(where: { $0.id == id })?.page != nil
        if isLive {
            if let page = tabPool.page(for: id) {
                wirePage(page, for: id)
            }
        } else {
            displaySelectedTab()
        }
        if let index = tabs.firstIndex(where: { $0.id == id }) {
            tabs[index].lastActiveAt = Date()
        }
    }

    func selectTab(id: UUID) {
        if isFindActive {
            endFind()
        }
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
        if let index = tabs.firstIndex(where: { $0.id == id }) {
            tabs[index].lastActiveAt = Date()
        }
        do {
            try tabStore?.saveSession(tabs: tabs, selected: id)
        } catch {
            logPersistenceError(error, operation: "saveSession")
        }
        displaySelectedTab()
    }

    func handlePillSwipe(direction: PillSwipeDirection) {
        guard !isEditingAddress, !isFindActive, !isOverviewVisible, let selected = selectedTabID else { return }
        let scope = TabOverviewViewController.visibleTabs(overviewItems(), mode: overviewMode, query: "", groupId: overviewController.selectedGroupID)
        guard let currentIndex = scope.firstIndex(where: { $0.id == selected }) else { return }
        switch direction {
        case .left:
            // Clamp at the first tab so a leading-edge swipe keeps selection.
            guard currentIndex > 0 else { return }
            slideToTab(id: scope[currentIndex - 1].id, direction: direction)
        case .right:
            if currentIndex + 1 < scope.count {
                slideToTab(id: scope[currentIndex + 1].id, direction: direction)
            } else {
                createNewTabInCurrentScope()
            }
        }
    }

    func createNewTabInCurrentScope() {
        let outgoing = contentContainer.snapshotView(afterScreenUpdates: false)
        // Private scope never inherits a group; standard scope stays grouped.
        let groupId = overviewMode.isPrivate ? nil : overviewController.selectedGroupID
        let record = TabRecord(isPrivate: overviewMode.isPrivate, groupId: groupId)
        tabs.append(record)
        tabPool.create(record)
        do {
            try tabStore?.saveSession(tabs: tabs, selected: record.id)
        } catch {
            logPersistenceError(error, operation: "saveSession")
        }
        selectedTabID = record.id
        displaySelectedTab()
        runPillSwipeSlide(outgoingSnapshot: outgoing, direction: .right)
    }

    private func slideToTab(id: UUID, direction: PillSwipeDirection) {
        let outgoing = contentContainer.snapshotView(afterScreenUpdates: false)
        guard tabs.contains(where: { $0.id == id }) else {
            outgoing?.removeFromSuperview()
            return
        }
        selectedTabID = id
        if let index = tabs.firstIndex(where: { $0.id == id }) {
            tabs[index].lastActiveAt = Date()
        }
        do {
            try tabStore?.saveSession(tabs: tabs, selected: id)
        } catch {
            logPersistenceError(error, operation: "saveSession")
        }
        displaySelectedTab()
        runPillSwipeSlide(outgoingSnapshot: outgoing, direction: direction)
    }

    private func runPillSwipeSlide(outgoingSnapshot: UIView?, direction: PillSwipeDirection) {
        guard let outgoing = outgoingSnapshot else { return }
        let width = contentContainer.bounds.width
        guard width > 0 else {
            outgoing.removeFromSuperview()
            return
        }
        let incoming: UIView?
        if !startPageContainer.isHidden {
            incoming = startPageContainer
        } else if let webView = peekActivePage()?.webView, webView.superview === contentContainer {
            incoming = webView
        } else {
            outgoing.removeFromSuperview()
            return
        }
        guard let incoming else {
            outgoing.removeFromSuperview()
            return
        }
        // Positive shift follows a right swipe; negative follows a left swipe.
        let shift: CGFloat = direction == .right ? width : -width
        outgoing.frame = contentContainer.bounds
        contentContainer.addSubview(outgoing)
        incoming.transform = CGAffineTransform(translationX: -shift, y: 0)
        let animator = UIViewPropertyAnimator(duration: 0.25, curve: .easeInOut) {
            outgoing.transform = CGAffineTransform(translationX: shift, y: 0)
            incoming.transform = .identity
        }
        animator.addCompletion { _ in
            outgoing.removeFromSuperview()
            incoming.transform = .identity
        }
        animator.startAnimation()
    }

    /// Pure read path: no wiring or recency change; checkout owns wiring.
    func activePage() -> WebPageController? {
        peekActivePage()
    }

    /// Read-only view of the active page that leaves the pool's recency alone,
    /// so snapshot-driven refreshes never disturb eviction order.
    func peekActivePage() -> WebPageController? {
        guard let id = selectedTabID else { return nil }
        return tabPool.pages.first(where: { $0.id == id })?.page
    }

    /// Adopts the single fresh tab Settings already persisted: drops every
    /// live page and per-tab entry so a background save cannot resurrect
    /// closed tabs, then displays the fresh empty tab.
    func resetAllTabsToSingleEmptyTab() {
        if isFindActive {
            endFind()
        }
        for id in tabs.map(\.id) {
            prunePerTabState(id: id)
            tabPool.delete(id: id)
        }
        tabs.removeAll()
        forcedStartPageTabs.removeAll()
        let session = tabStore?.loadSession() ?? (tabs: [], selected: nil)
        if !session.tabs.isEmpty {
            tabs = session.tabs
            for record in tabs {
                tabPool.reserve(record)
            }
            let fallback = tabs.first?.id
            let selected = session.selected.flatMap { id in tabs.first(where: { $0.id == id })?.id }
            selectedTabID = selected ?? fallback
        } else {
            let record = TabRecord(isPrivate: false)
            tabs = [record]
            tabPool.create(record)
            do {
                try tabStore?.saveSession(tabs: tabs, selected: record.id)
            } catch {
                logPersistenceError(error, operation: "saveSession")
            }
            selectedTabID = record.id
        }
        displaySelectedTab()
        if isOverviewVisible {
            overviewController.setItems(overviewItems(), selectedID: selectedTabID)
        }
        updateStartPageContent()
    }
}
