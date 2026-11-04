//
//  BrowserRootViewController+Overview.swift
//  OuterView
//

import UIKit

/// UserDefaults keys libraryTab as Int, overviewMode as String, and overviewGroup as String.
/// Values are read at init and setup and written on every change; private mode is never
/// written and restores as standard. Unparseable values fall back to bookmarks, standard,
/// and nil; a stored group id resolving to no existing group restores as nil.
extension BrowserRootViewController {
    // MARK: - Overview

    func toggleOverview() {
        setOverviewVisible(!isOverviewVisible)
    }

    func setOverviewVisible(_ visible: Bool) {
        isOverviewVisible = visible
        if visible {
            overviewView.alpha = 1
            overviewView.isHidden = false
            let groups = overviewGroups()
            // A stored group resolving to no existing group restores as nil.
            let candidate = overviewController.selectedGroupID
                ?? TabOverviewViewController.storedOverviewGroupID(defaults: selectionDefaults)
            let validFilter = candidate.flatMap { id in
                groups.contains(where: { $0.id == id }) ? id : nil
            }
            overviewController.configure(
                tabs: overviewItems(groups: groups),
                selectedID: selectedTabID,
                mode: overviewMode,
                groups: groups,
                selectedGroupID: validFilter
            )
            if chromePlacement == .regular {
                topBarAnimator?.stopAnimation(false)
                topBarAnimator?.finishAnimation(at: .current)
                topBarAnimator = nil
                updateToolbarVisibility(for: chromeController.state)
                topBarView.leadingStack.alpha = 1
                topBarView.trailingStack.alpha = 1
                refreshStatusBarAppearanceIfNeeded()
            }
            applyOverviewChromeItems()
            bringChromeToFront()
        } else {
            overviewView.isHidden = true
            overviewView.alpha = 1
            updateRailItems()
            applyChromeViews(animated: false)
        }
    }

    /// Single owner for overview chrome composition. Overview and sheet
    /// overlays are mutually exclusive — the overview surface sits above the
    /// sheet overlays — so toolbar writes route through `setChromeItems` to
    /// keep the single sheet-suppression owner instead of writing
    /// `topBarView` directly.
    func applyOverviewChromeItems() {
        let items = overviewController.overviewChromeItems()
        setChromeItems(prefix: items.prefix, suffix: items.suffix)
    }

    func overviewGroups() -> [TabGroup] {
        tabStore?.fetchGroups() ?? []
    }

    func overviewItems(groups: [TabGroup]? = nil) -> [TabOverviewItem] {
        let resolved = groups ?? overviewGroups()
        let names = Dictionary(uniqueKeysWithValues: resolved.map { ($0.id, $0.name) })
        return tabs.map { record in
            let host = HostFormatter.host(of: record.url)
            return TabOverviewItem(
                id: record.id,
                title: record.title,
                host: host.isEmpty ? nil : host,
                url: record.url,
                isPrivate: record.isPrivate,
                groupId: record.groupId,
                groupName: record.groupId.flatMap { names[$0] }
            )
        }
    }

    func refreshOverview(groups: [TabGroup], selectedGroupID: UUID?) {
        overviewController.setGroups(groups, selectedGroupID: selectedGroupID)
        overviewController.setItems(overviewItems(groups: groups), selectedID: selectedTabID)
        updateTabStrip()
    }

    func closeTab(id: UUID, replacementIfEmpty replacement: TabOverviewItem?) {
        let closedSelected = selectedTabID == id
        let wasPrivate = tabs.first(where: { $0.id == id })?.isPrivate ?? overviewMode.isPrivate
        removeTabs(ids: [id])
        let wasLastTab = tabs.isEmpty
        if let replacement {
            // Last-card safe: the grid already inserted this id, so the owner
            // materializes that exact tab instead of inventing a second one.
            let record = TabRecord(
                id: replacement.id,
                url: replacement.url,
                title: replacement.title,
                isPrivate: replacement.isPrivate,
                groupId: replacement.groupId
            )
            tabs.append(record)
            tabPool.create(record)
            do {
                try tabStore?.upsertTab(record)
            } catch {
                logPersistenceError(error, operation: "upsertTab")
            }
            selectedTabID = record.id
            if wasLastTab {
                if closedSelected, isFindActive {
                    endFind()
                }
                persistStrip()
                if let selected = selectedTabID, tabs.contains(where: { $0.id == selected }) {
                    displaySelectedTab()
                }
                setOverviewVisible(false)
                return
            }
            persistStripAndRefresh(closedSelected: closedSelected, fallbackIsPrivate: replacement.isPrivate)
            if isOverviewVisible {
                applyOverviewChromeItems()
            }
        } else {
            persistStripAndRefresh(closedSelected: closedSelected, fallbackIsPrivate: wasPrivate)
            if isOverviewVisible {
                applyOverviewChromeItems()
            }
        }
    }

    func closeAllTabs(in mode: TabOverviewMode) {
        let ids = Set(tabs.filter { $0.isPrivate == mode.isPrivate }.map(\.id))
        guard !ids.isEmpty else { return }
        let closedSelected = selectedTabID.map(ids.contains) ?? false
        removeTabs(ids: ids)
        if tabs.isEmpty {
            if closedSelected, isFindActive {
                endFind()
            }
            let record = TabRecord(isPrivate: mode.isPrivate)
            tabs.append(record)
            tabPool.create(record)
            do {
                try tabStore?.upsertTab(record)
            } catch {
                logPersistenceError(error, operation: "upsertTab")
            }
            selectedTabID = record.id
            persistStrip()
            if let selected = selectedTabID, tabs.contains(where: { $0.id == selected }) {
                displaySelectedTab()
            }
            setOverviewVisible(false)
            return
        }
        persistStripAndRefresh(closedSelected: closedSelected, fallbackIsPrivate: mode.isPrivate)
        if isOverviewVisible {
            applyOverviewChromeItems()
        }
    }

    private func removeTabs(ids: Set<UUID>) {
        for id in ids {
            prunePerTabState(id: id)
            tabPool.delete(id: id)
            do {
                try tabStore?.deleteTab(id: id)
            } catch {
                logPersistenceError(error, operation: "deleteTab")
            }
        }
        tabs.removeAll { ids.contains($0.id) }
    }

    /// Single write path for the strip snapshot: order plus selection stay
    /// in sync across close, close-all, and reorder flows.
    private func persistStrip() {
        guard let store = tabStore, let selected = selectedTabID else {
            updateTabStrip()
            return
        }
        do {
            try store.saveSession(tabs: tabs, selected: selected)
        } catch {
            logPersistenceError(error, operation: "saveSession")
        }
        do {
            try store.select(id: selected)
        } catch {
            logPersistenceError(error, operation: "select")
        }
        do {
            try store.reorder(tabs: tabs)
        } catch {
            logPersistenceError(error, operation: "reorder")
        }
        updateTabStrip()
    }

    private func persistStripAndRefresh(closedSelected: Bool) {
        persistStripAndRefresh(closedSelected: closedSelected, fallbackIsPrivate: overviewMode.isPrivate)
    }

    private func persistStripAndRefresh(closedSelected: Bool, fallbackIsPrivate: Bool) {
        if closedSelected, isFindActive {
            endFind()
        }
        if tabs.isEmpty {
            let record = TabRecord(isPrivate: fallbackIsPrivate)
            tabs.append(record)
            tabPool.create(record)
            do {
                try tabStore?.upsertTab(record)
            } catch {
                logPersistenceError(error, operation: "upsertTab")
            }
            selectedTabID = record.id
        } else if closedSelected {
            selectedTabID = tabs.last?.id
        }
        persistStrip()
        if closedSelected, let selected = selectedTabID, tabs.contains(where: { $0.id == selected }) {
            displaySelectedTab()
        }
        if isOverviewVisible {
            overviewController.setItems(overviewItems(), selectedID: selectedTabID)
        }
        updateTabStrip()
    }

    /// Drops every per-tab entry so closed tabs release their proxies,
    /// listeners, and start-page pins. Detaches from the live page first when
    /// one is still resident.
    func prunePerTabState(id: UUID) {
        if let page = tabPool.pages.first(where: { $0.id == id })?.page {
            if let proxy = scrollProxies[id] {
                proxy.detach(from: page.webView.scrollView)
            }
            if let listenerID = snapshotListenerIDs[id] {
                page.removeSnapshotListener(listenerID)
            }
        }
        scrollProxies[id] = nil
        snapshotListenerIDs[id] = nil
        boundListenerPages[id] = nil
        forcedStartPageTabs.remove(id)
    }
}

extension BrowserRootViewController {
    // MARK: - Vertical overview drag

    func handleVerticalPan(_ event: PillPanEvent) {
        guard !isEditingAddress, !isFindActive, !isOverviewVisible else { return }
        switch event {
        case .began:
            beginOverviewDrag()
        case let .changed(translation: translation, velocity: _):
            updateOverviewDrag(translation: translation)
        case let .ended(translation: translation, velocity: velocity):
            finishOverviewDrag(translation: translation, velocity: velocity)
        }
    }

    private func beginOverviewDrag() {
        guard !isEditingAddress, !isFindActive, !isOverviewVisible else { return }
        overviewDragAnimator?.stopAnimation(true)
        overviewDragAnimator = nil
        if let existing = horizontalSwitchSession {
            // Interrupted switch: silence its animator and drop the views;
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
        let groups = overviewGroups()
        let candidate = overviewController.selectedGroupID
            ?? TabOverviewViewController.storedOverviewGroupID(defaults: selectionDefaults)
        let validFilter = candidate.flatMap { id in
            groups.contains(where: { $0.id == id }) ? id : nil
        }
        overviewController.configure(
            tabs: overviewItems(groups: groups),
            selectedID: selectedTabID,
            mode: overviewMode,
            groups: groups,
            selectedGroupID: validFilter
        )
        contentContainer.transform = .identity
        contentContainer.layer.cornerRadius = 0
        contentContainer.clipsToBounds = true
        overviewView.alpha = 0
        overviewView.isHidden = false
        view.insertSubview(overviewView, belowSubview: contentContainer)
    }

    private func updateOverviewDrag(translation: CGFloat) {
        guard !isEditingAddress, !isFindActive, !isOverviewVisible, !overviewView.isHidden else { return }
        let height = view.bounds.height
        guard height > 0, translation < 0 else { return }
        let progress = min(1, -translation / height)
        let scale = AddressBarView.overviewDragScale(progress: progress)
        let drift = AddressBarView.overviewDragDrift(translation: translation)
        // Scale first, then translate, so the page shrinks in place
        // with a slight upward drift instead of sliding off-screen.
        contentContainer.transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: 0, y: drift))
        contentContainer.layer.cornerRadius = AddressBarView.overviewDragRadius(progress: progress)
        overviewView.alpha = progress
    }

    private func finishOverviewDrag(translation: CGFloat, velocity: CGFloat) {
        guard !isEditingAddress, !isFindActive, !isOverviewVisible, !overviewView.isHidden else { return }
        let height = view.bounds.height
        guard height > 0 else {
            contentContainer.transform = .identity
            contentContainer.layer.cornerRadius = 0
            overviewView.alpha = 0
            overviewView.isHidden = true
            return
        }
        let commit = translation < 0 && AddressBarView.shouldCommitVertical(translationY: translation, height: height)
        if commit {
            let progress = min(1, -translation / height)
            let remaining = (1 - progress) * height * 0.20
            let duration = AddressBarView.settleDuration(remaining: remaining, velocity: velocity)
            let cardScale = AddressBarView.overviewDragScale(progress: 1)
            let drift = AddressBarView.overviewDragDrift(translation: -height)
            let target = CGAffineTransform(scaleX: cardScale, y: cardScale)
                .concatenating(CGAffineTransform(translationX: 0, y: drift))
            let container = contentContainer
            let overview = overviewView
            let animator = UIViewPropertyAnimator(duration: duration, curve: .easeOut) {
                container.transform = target
                container.layer.cornerRadius = AddressBarView.overviewDragRadius(progress: 1)
                overview.alpha = 1
            }
            overviewDragAnimator = animator
            animator.addCompletion { [weak self, weak animator] _ in
                guard let self else { return }
                self.setOverviewVisible(true)
                self.contentContainer.transform = .identity
                self.contentContainer.layer.cornerRadius = 0
                self.contentContainer.clipsToBounds = false
                if self.overviewDragAnimator === animator {
                    self.overviewDragAnimator = nil
                }
            }
            animator.startAnimation()
        } else {
            // Cancel pops back from the presented displacement with no tab change.
            let remaining = abs(contentContainer.transform.ty)
            let duration = AddressBarView.settleDuration(remaining: remaining, velocity: velocity)
            let container = contentContainer
            let overview = overviewView
            let animator = UIViewPropertyAnimator(duration: duration, curve: .easeOut) {
                container.transform = .identity
                container.layer.cornerRadius = 0
                overview.alpha = 0
            }
            overviewDragAnimator = animator
            animator.addCompletion { [weak self, weak animator] _ in
                guard let self else { return }
                self.overviewView.isHidden = true
                self.contentContainer.transform = .identity
                self.contentContainer.layer.cornerRadius = 0
                self.contentContainer.clipsToBounds = false
                self.bringChromeToFront()
                if self.overviewDragAnimator === animator {
                    self.overviewDragAnimator = nil
                }
            }
            animator.startAnimation()
        }
    }
}

extension BrowserRootViewController {
    // MARK: - Tab strip

    func updateTabStrip() {
        if topBarView.isHidden || topBarView.isNonDuoPhone {
            tabStripView.isHidden = true
            return
        }
        if isOverviewVisible || isSheetOverlayVisible {
            tabStripView.isHidden = true
            return
        }
        if chromeController.state.pill == .minified || chromeController.state.pill == .editing {
            tabStripView.isHidden = true
            return
        }
        let items = TabOverviewViewController.tabs(overviewItems(), in: overviewMode)
        guard items.count >= 2 else {
            tabStripView.isHidden = true
            return
        }
        tabStripView.isHidden = false
        tabStripView.render(tabs: items, selectedID: selectedTabID)
    }
}

extension BrowserRootViewController: TabOverviewViewControllerDelegate {
    func tabOverview(_ overview: TabOverviewViewController, didSelectTab id: UUID) {
        setOverviewMode(overview.mode)
        selectTab(id: id)
        setOverviewVisible(false)
    }

    func tabOverview(
        _: TabOverviewViewController,
        didCloseTab id: UUID,
        replacementIfEmpty replacement: TabOverviewItem?
    ) {
        closeTab(id: id, replacementIfEmpty: replacement)
    }

    func tabOverviewDidRequestNewTab(_: TabOverviewViewController, in mode: TabOverviewMode) {
        setOverviewMode(mode)
        createNewTab(isPrivate: mode.isPrivate)
    }

    func tabOverview(_: TabOverviewViewController, didChangeMode mode: TabOverviewMode) {
        setOverviewMode(mode)
    }

    func tabOverviewDidRequestCloseAll(_: TabOverviewViewController, in mode: TabOverviewMode) {
        closeAllTabs(in: mode)
    }

    func tabOverviewDidFinish(_ overview: TabOverviewViewController) {
        setOverviewMode(overview.mode)
        setOverviewVisible(false)
    }

    func tabOverview(_: TabOverviewViewController, didCreateGroup name: String, withTabIDs tabIDs: [UUID]) {
        guard let store = tabStore else { return }
        do {
            let group = try store.createGroup(name: name)
            // Private tabs are never assigned; they stay off disk entirely,
            // so a persisted row for them does not exist to assign.
            for record in tabs where tabIDs.contains(record.id) && !record.isPrivate {
                record.groupId = group.id
                try store.assignTab(id: record.id, toGroup: group.id)
            }
            try store.saveSession(tabs: tabs, selected: selectedTabID)
            refreshOverview(groups: store.fetchGroups(), selectedGroupID: group.id)
        } catch {
            logPersistenceError(error, operation: "createGroup")
        }
    }

    func tabOverview(_ overview: TabOverviewViewController, didAssignTab id: UUID, toGroup groupId: UUID?) {
        guard let store = tabStore else { return }
        do {
            if let index = tabs.firstIndex(where: { $0.id == id }) {
                tabs[index].groupId = groupId
            }
            try store.assignTab(id: id, toGroup: groupId)
            try store.saveSession(tabs: tabs, selected: selectedTabID)
            let groups = store.fetchGroups()
            refreshOverview(groups: groups, selectedGroupID: overview.selectedGroupID)
        } catch {
            logPersistenceError(error, operation: "assignTab")
        }
    }

    func tabOverview(_ overview: TabOverviewViewController, didRenameGroup id: UUID, toName name: String) {
        guard let store = tabStore else { return }
        do {
            try store.renameGroup(id: id, name: name)
            try store.saveSession(tabs: tabs, selected: selectedTabID)
            let groups = store.fetchGroups()
            refreshOverview(groups: groups, selectedGroupID: overview.selectedGroupID)
        } catch {
            logPersistenceError(error, operation: "renameGroup")
        }
    }

    func tabOverview(_ overview: TabOverviewViewController, didDeleteGroup id: UUID) {
        guard let store = tabStore else { return }
        do {
            try store.deleteGroup(id: id)
            for record in tabs where record.groupId == id {
                record.groupId = nil
            }
            try store.saveSession(tabs: tabs, selected: selectedTabID)
            let groups = store.fetchGroups()
            let valid = overview.selectedGroupID == id ? nil : overview.selectedGroupID
            refreshOverview(groups: groups, selectedGroupID: valid)
        } catch {
            logPersistenceError(error, operation: "deleteGroup")
        }
    }

    func tabOverview(_ overview: TabOverviewViewController, didReorderTabs orderedIDs: [UUID]) {
        let isPrivate = overview.mode.isPrivate
        var byID: [UUID: TabRecord] = [:]
        var privacyByID: [UUID: Bool] = [:]
        for record in tabs {
            byID[record.id] = record
            privacyByID[record.id] = record.isPrivate
        }
        let splicedIDs = TabOverviewViewController.spliceTabOrder(
            currentIDs: tabs.map(\.id),
            privacyByID: privacyByID,
            orderedIDs: orderedIDs,
            isPrivate: isPrivate
        )
        tabs = splicedIDs.compactMap { byID[$0] }
        persistStrip()
    }
}
