//
//  BrowserRootViewController+Overview.swift
//  OuterView
//

import UIKit

extension BrowserRootViewController {
    // MARK: - Overview

    func toggleOverview() {
        setOverviewVisible(!isOverviewVisible)
    }

    func setOverviewVisible(_ visible: Bool) {
        isOverviewVisible = visible
        overviewView.isHidden = !visible
        if visible {
            overviewController.configure(tabs: overviewItems(), selectedID: selectedTabID, mode: overviewMode)
            overviewController.applyRailItems(to: railView)
            bringChromeToFront()
        } else {
            updateRailItems()
        }
    }

    func overviewItems() -> [TabOverviewItem] {
        tabs.map { record in
            let host = HostFormatter.host(of: record.url)
            return TabOverviewItem(
                id: record.id,
                title: record.title,
                host: host.isEmpty ? nil : host,
                url: record.url,
                isPrivate: record.isPrivate
            )
        }
    }

    func closeTab(id: UUID, replacementIfEmpty replacement: TabOverviewItem?) {
        let closedSelected = selectedTabID == id
        let wasPrivate = tabs.first(where: { $0.id == id })?.isPrivate ?? overviewMode.isPrivate
        removeTabs(ids: [id])
        if let replacement {
            // Last-card safe: the grid already inserted this id, so the owner
            // materializes that exact tab instead of inventing a second one.
            let record = TabRecord(
                id: replacement.id,
                url: replacement.url,
                title: replacement.title,
                isPrivate: replacement.isPrivate
            )
            tabs.append(record)
            tabPool.create(record)
            do {
                try tabStore?.upsertTab(record)
            } catch {
                logPersistenceError(error, operation: "upsertTab")
            }
            selectedTabID = record.id
            persistStripAndRefresh(closedSelected: closedSelected, fallbackIsPrivate: replacement.isPrivate)
        } else {
            persistStripAndRefresh(closedSelected: closedSelected, fallbackIsPrivate: wasPrivate)
        }
    }

    func closeAllTabs(in mode: TabOverviewMode) {
        let ids = Set(tabs.filter { $0.isPrivate == mode.isPrivate }.map(\.id))
        guard !ids.isEmpty else { return }
        let closedSelected = selectedTabID.map(ids.contains) ?? false
        removeTabs(ids: ids)
        persistStripAndRefresh(closedSelected: closedSelected, fallbackIsPrivate: mode.isPrivate)
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

    private func persistStripAndRefresh(closedSelected: Bool) {
        persistStripAndRefresh(closedSelected: closedSelected, fallbackIsPrivate: overviewMode.isPrivate)
    }

    private func persistStripAndRefresh(closedSelected: Bool, fallbackIsPrivate: Bool) {
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
        if let selected = selectedTabID {
            do {
                try tabStore?.saveSession(tabs: tabs, selected: selected)
            } catch {
                logPersistenceError(error, operation: "saveSession")
            }
            do {
                try tabStore?.select(id: selected)
            } catch {
                logPersistenceError(error, operation: "select")
            }
            do {
                try tabStore?.reorder(tabs: tabs)
            } catch {
                logPersistenceError(error, operation: "reorder")
            }
        }
        if closedSelected, let selected = selectedTabID, tabs.contains(where: { $0.id == selected }) {
            displaySelectedTab()
        }
        if isOverviewVisible {
            overviewController.setItems(overviewItems(), selectedID: selectedTabID)
        }
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
    // MARK: - Fold handling

    func applyStructuralLayout() {
        refreshForActiveSnapshot()
        view.setNeedsLayout()
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
}
