//
//  BrowserRootViewController+Tabs.swift
//  OuterView
//

import UIKit

enum PillSwipeDirection: Sendable {
    case left
    case right
}

@MainActor
final class HorizontalSwitchSession {
    let originID: UUID
    let originIndex: Int
    let scopeIDs: [UUID]
    var direction: PillSwipeDirection?
    var targetID: UUID?
    let outgoingSnapshot: UIView
    var incomingView: UIView?
    var didResolveTarget = false
    /// Set once finish starts a commit animator; abandon then keeps selection.
    var didCommit = false

    init(originID: UUID, originIndex: Int, scopeIDs: [UUID], outgoingSnapshot: UIView) {
        self.originID = originID
        self.originIndex = originIndex
        self.scopeIDs = scopeIDs
        self.outgoingSnapshot = outgoingSnapshot
    }
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

    /// Safari mapping: left means next (+1), right means previous (-1).
    nonisolated static func pillTargetIndex(currentIndex: Int, count: Int, direction: PillSwipeDirection) -> Int? {
        switch direction {
        case .left:
            let next = currentIndex + 1
            return next < count ? next : nil
        case .right:
            let previous = currentIndex - 1
            return previous >= 0 ? previous : nil
        }
    }

    func handleHorizontalPan(_ event: PillPanEvent) {
        guard !isEditingAddress, !isFindActive, !isOverviewVisible else { return }
        switch event {
        case .began:
            beginInteractiveSwitch()
        case let .changed(translation: translation, velocity: _):
            updateInteractiveSwitch(translation: translation)
        case let .ended(translation: translation, velocity: velocity):
            finishInteractiveSwitch(translation: translation, velocity: velocity)
        }
    }

    private func beginInteractiveSwitch() {
        guard !isEditingAddress, !isFindActive, !isOverviewVisible else { return }
        if let existing = horizontalSwitchSession {
            // Interrupted gesture: silence its animator and drop the views;
            // restore the origin only when no commit had started.
            horizontalSwitchAnimator?.stopAnimation(true)
            horizontalSwitchAnimator = nil
            existing.outgoingSnapshot.removeFromSuperview()
            existing.incomingView?.transform = .identity
            if !existing.didCommit, selectedTabID != existing.originID {
                selectTab(id: existing.originID)
            }
            horizontalSwitchSession = nil
        }
        guard let selected = selectedTabID else { return }
        let width = contentContainer.bounds.width
        guard width > 0 else { return }
        let scope = TabOverviewViewController.visibleTabs(overviewItems(), mode: overviewMode, query: "", groupId: overviewController.selectedGroupID)
        guard let currentIndex = scope.firstIndex(where: { $0.id == selected }), let outgoing = contentContainer.snapshotView(afterScreenUpdates: false) else { return }
        outgoing.frame = contentContainer.bounds
        outgoing.transform = .identity
        contentContainer.addSubview(outgoing)
        let session = HorizontalSwitchSession(
            originID: selected,
            originIndex: currentIndex,
            scopeIDs: scope.map(\.id),
            outgoingSnapshot: outgoing
        )
        horizontalSwitchSession = session
    }

    private func updateInteractiveSwitch(translation: CGFloat) {
        guard !isEditingAddress, !isFindActive, !isOverviewVisible, let session = horizontalSwitchSession else { return }
        let width = contentContainer.bounds.width
        guard width > 0 else { return }
        let clamped = max(-width, min(width, translation))
        if !session.didResolveTarget {
            guard clamped != 0 else { return }
            let direction: PillSwipeDirection = clamped < 0 ? .left : .right
            session.direction = direction
            if let targetIndex = Self.pillTargetIndex(currentIndex: session.originIndex, count: session.scopeIDs.count, direction: direction) {
                let targetID = session.scopeIDs[targetIndex]
                session.targetID = targetID
                selectTab(id: targetID)
                // displaySelectedTab clears the snapshot; re-add it on top.
                session.outgoingSnapshot.frame = contentContainer.bounds
                if session.outgoingSnapshot.superview !== contentContainer {
                    contentContainer.addSubview(session.outgoingSnapshot)
                } else {
                    contentContainer.bringSubviewToFront(session.outgoingSnapshot)
                }
                session.incomingView = currentHorizontalIncomingView()
                session.didResolveTarget = true
            } else {
                session.targetID = nil
                session.incomingView = nil
                if session.outgoingSnapshot.superview !== contentContainer {
                    session.outgoingSnapshot.frame = contentContainer.bounds
                    contentContainer.addSubview(session.outgoingSnapshot)
                }
                session.didResolveTarget = true
            }
        }
        guard session.didResolveTarget, let direction = session.direction else { return }
        // Target stays locked after first resolve; reversal only mirrors the
        // drag against the locked side, never re-resolves a new target.
        let sign: CGFloat = direction == .right ? 1 : -1
        if let incoming = session.incomingView {
            session.outgoingSnapshot.transform = CGAffineTransform(translationX: clamped, y: 0)
            incoming.transform = CGAffineTransform(translationX: clamped - sign * width, y: 0)
        } else {
            // No incoming tab: elastic preview at reduced travel.
            session.outgoingSnapshot.transform = CGAffineTransform(translationX: clamped * AddressBarView.elasticFactor, y: 0)
        }
    }

    private func finishInteractiveSwitch(translation: CGFloat, velocity: CGFloat) {
        guard !isEditingAddress, !isFindActive, !isOverviewVisible, let session = horizontalSwitchSession else { return }
        let width = contentContainer.bounds.width
        guard width > 0 else {
            session.outgoingSnapshot.removeFromSuperview()
            session.incomingView?.transform = .identity
            horizontalSwitchSession = nil
            return
        }
        let clamped = max(-width, min(width, translation))
        guard let direction = session.direction else {
            session.outgoingSnapshot.transform = .identity
            session.incomingView?.transform = .identity
            session.outgoingSnapshot.removeFromSuperview()
            horizontalSwitchSession = nil
            return
        }
        // Locked direction owns the settle side; a reversed finger still
        // settles toward the locked target or back based on magnitude.
        let sign: CGFloat = direction == .right ? 1 : -1
        let shouldCommit = AddressBarView.shouldCommitHorizontal(translationX: clamped, width: width)
        // Right-at-first always bounces with no selection change.
        if direction == .right, session.originIndex == 0 {
            cancelHorizontalSwitch(session: session, velocity: velocity)
            return
        }
        if session.targetID != nil {
            if shouldCommit {
                commitHorizontalSwitch(session: session, width: width, sign: sign, velocity: velocity)
            } else {
                cancelHorizontalSwitch(session: session, velocity: velocity)
            }
        } else if direction == .left, shouldCommit {
            commitHorizontalOverflow(session: session, width: width, sign: sign, velocity: velocity, clamped: clamped)
        } else {
            cancelHorizontalSwitch(session: session, velocity: velocity)
        }
    }

    private func currentHorizontalIncomingView() -> UIView? {
        if !startPageContainer.isHidden {
            return startPageContainer
        }
        if let webView = peekActivePage()?.webView, webView.superview === contentContainer {
            return webView
        }
        return nil
    }

    private func commitHorizontalSwitch(session: HorizontalSwitchSession, width: CGFloat, sign: CGFloat, velocity: CGFloat) {
        guard let incoming = session.incomingView else {
            session.outgoingSnapshot.removeFromSuperview()
            if horizontalSwitchSession === session {
                horizontalSwitchSession = nil
            }
            return
        }
        session.didCommit = true
        let outgoing = session.outgoingSnapshot
        let remaining = abs(sign * width - outgoing.transform.tx)
        let duration = AddressBarView.settleDuration(remaining: remaining, velocity: velocity)
        let animator = UIViewPropertyAnimator(duration: duration, curve: .easeOut) {
            outgoing.transform = CGAffineTransform(translationX: sign * width, y: 0)
            incoming.transform = .identity
        }
        horizontalSwitchAnimator = animator
        animator.addCompletion { [weak self, weak animator] _ in
            outgoing.removeFromSuperview()
            incoming.transform = .identity
            guard let self else { return }
            if self.horizontalSwitchSession === session {
                self.horizontalSwitchSession = nil
            }
            if self.horizontalSwitchAnimator === animator {
                self.horizontalSwitchAnimator = nil
            }
        }
        animator.startAnimation()
    }

    private func cancelHorizontalSwitch(session: HorizontalSwitchSession, velocity: CGFloat) {
        let outgoing = session.outgoingSnapshot
        let incoming = session.incomingView
        let originID = session.originID
        let remaining = abs(outgoing.transform.tx)
        let duration = AddressBarView.settleDuration(remaining: remaining, velocity: velocity)
        let animator = UIViewPropertyAnimator(duration: duration, curve: .easeOut) {
            outgoing.transform = .identity
            incoming?.transform = .identity
        }
        horizontalSwitchAnimator = animator
        animator.addCompletion { [weak self, weak animator] _ in
            outgoing.removeFromSuperview()
            incoming?.transform = .identity
            guard let self else { return }
            if self.horizontalSwitchSession === session {
                self.horizontalSwitchSession = nil
            }
            if self.horizontalSwitchAnimator === animator {
                self.horizontalSwitchAnimator = nil
            }
            // Elastic previews never left the origin; skip persistence churn.
            if self.selectedTabID != originID {
                self.selectTab(id: originID)
            }
        }
        animator.startAnimation()
    }

    /// Single overflow creator: same-scope Start Page tab for left-past-last.
    private func makeOverflowTabInCurrentScope() -> TabRecord {
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
        return record
    }

    private func commitHorizontalOverflow(session: HorizontalSwitchSession, width: CGFloat, sign: CGFloat, velocity: CGFloat, clamped: CGFloat) {
        session.didCommit = true
        let record = makeOverflowTabInCurrentScope()
        selectedTabID = record.id
        let outgoing = session.outgoingSnapshot
        outgoing.removeFromSuperview()
        displaySelectedTab()
        outgoing.frame = contentContainer.bounds
        outgoing.transform = CGAffineTransform(translationX: clamped * AddressBarView.elasticFactor, y: 0)
        contentContainer.addSubview(outgoing)
        guard let incoming = currentHorizontalIncomingView() else {
            let remaining = abs(sign * width - clamped * AddressBarView.elasticFactor)
            let duration = AddressBarView.settleDuration(remaining: remaining, velocity: velocity)
            let animator = UIViewPropertyAnimator(duration: duration, curve: .easeOut) {
                outgoing.transform = CGAffineTransform(translationX: sign * width, y: 0)
            }
            horizontalSwitchAnimator = animator
            animator.addCompletion { [weak self, weak animator] _ in
                outgoing.removeFromSuperview()
                guard let self else { return }
                if self.horizontalSwitchSession === session {
                    self.horizontalSwitchSession = nil
                }
                if self.horizontalSwitchAnimator === animator {
                    self.horizontalSwitchAnimator = nil
                }
            }
            animator.startAnimation()
            return
        }
        incoming.transform = CGAffineTransform(translationX: clamped - sign * width, y: 0)
        session.incomingView = incoming
        let remaining = abs(sign * width - clamped * AddressBarView.elasticFactor)
        let duration = AddressBarView.settleDuration(remaining: remaining, velocity: velocity)
        let animator = UIViewPropertyAnimator(duration: duration, curve: .easeOut) {
            outgoing.transform = CGAffineTransform(translationX: sign * width, y: 0)
            incoming.transform = .identity
        }
        horizontalSwitchAnimator = animator
        animator.addCompletion { [weak self, weak animator] _ in
            outgoing.removeFromSuperview()
            incoming.transform = .identity
            guard let self else { return }
            if self.horizontalSwitchSession === session {
                self.horizontalSwitchSession = nil
            }
            if self.horizontalSwitchAnimator === animator {
                self.horizontalSwitchAnimator = nil
            }
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
