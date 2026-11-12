// RootView — Back history and tab group menus for chrome buttons.

import Photos
import UIKit
import WebKit

private enum PhotoSaveFailure: Error {
    case accessDenied
}

extension BrowserRootViewController {
    // MARK: - Back History Menu

    func makeBackMenu() -> UIMenu? {
        guard let backList = peekActivePage()?.backList, !backList.isEmpty else {
            return nil
        }
        let actions = backList.reversed().map { item -> UIAction in
            let title: String = if let trimmedTitle = item.title?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedTitle.isEmpty {
                trimmedTitle
            } else if let host = item.url.host, !host.isEmpty {
                host
            } else {
                item.url.absoluteString
            }

            var subtitle: String?
            if let host = item.url.host, !host.isEmpty {
                let path = item.url.path
                subtitle = (path.isEmpty || path == "/") ? host : (host + path)
            } else {
                subtitle = item.url.absoluteString
            }
            // Skip a subtitle repeating the title when the title fell back to the host.
            if subtitle == title {
                subtitle = nil
            }

            return UIAction(title: title, subtitle: subtitle) { [weak self] _ in
                self?.activePage()?.navigate(to: item)
            }
        }
        return UIMenu(title: "", children: actions)
    }

    // MARK: - Bookmarks Button Long-Press Menu

    func makeBookmarksButtonMenu() -> UIMenu {
        let snapshot = activePage()?.snapshot
        let hasPage = snapshot?.url.map(URLNormalizer.isLoadable) ?? false
        let isForcedStart = selectedTabID.map { forcedStartPageTabs.contains($0) } ?? false
        let canBookmarkActive = hasPage && !isForcedStart

        let readingListAction = UIAction(
            title: "Add to Reading List",
            image: UIImage(systemName: "eyeglasses"),
            attributes: canBookmarkActive ? [] : [.disabled]
        ) { [weak self] _ in
            self?.addActivePageToReadingList()
        }

        let addBookmarkAction = UIAction(
            title: "Add Bookmark",
            image: UIImage(systemName: "book"),
            attributes: canBookmarkActive ? [] : [.disabled]
        ) { [weak self] _ in
            self?.presentAddBookmarkSheet()
        }

        var actions: [UIMenuElement] = [readingListAction, addBookmarkAction]

        let isPrivate = overviewMode.isPrivate
        let activeGroupID = overviewController.selectedGroupID
        let scopeTabs = tabs.filter {
            $0.isPrivate == isPrivate && (isPrivate || $0.groupId == activeGroupID)
        }
        let loadableTabs: [(title: String, url: URL)] = scopeTabs.compactMap { record in
            guard let url = record.url, URLNormalizer.isLoadable(url) else { return nil }
            let title = HostFormatter.displayTitle(url: url, title: record.title)
            return (title, url)
        }

        if loadableTabs.count >= 2 {
            let addMultipleAction = UIAction(
                title: "Add Bookmarks for \(loadableTabs.count) Tabs",
                image: UIImage(systemName: "book")
            ) { [weak self] _ in
                self?.presentAddBookmarksForTabsSheet(tabs: loadableTabs)
            }
            actions.append(addMultipleAction)
        }

        return UIMenu(title: "", children: actions)
    }

    func presentAddBookmarksForTabsSheet(tabs: [(title: String, url: URL)]) {
        let target = BookmarkEditorTarget.addFolderForTabs(defaultTitle: "Saved Tabs", tabs: tabs)
        presentBookmarkEditor(for: target)
    }

    // MARK: - Tab Group Menu

    func makeTabGroupMenu() -> UIMenu {
        let groups = overviewGroups()
        let isPrivate = overviewMode.isPrivate
        let activeGroupID = overviewController.selectedGroupID

        let groupActions = groups.map { group -> UIAction in
            UIAction(
                title: group.name,
                image: UIImage(systemName: "square.on.square"),
                state: (!isPrivate && activeGroupID == group.id) ? .on : .off
            ) { [weak self] _ in
                self?.switchToGroup(group.id)
            }
        }

        let count = currentTabCount()
        let countTitle = TabOverviewViewController.tabsCapsuleCountTitle(count: count)
        let privateAction = UIAction(
            title: "Private",
            image: UIImage(systemName: "hand.raised"),
            state: isPrivate ? .on : .off
        ) { [weak self] _ in
            self?.switchToPrivateMode()
        }
        let tabsAction = UIAction(
            title: countTitle,
            image: UIImage(systemName: "iphone"),
            state: (!isPrivate && activeGroupID == nil) ? .on : .off
        ) { [weak self] _ in
            self?.switchToStandardMode()
        }
        let modesMenu = UIMenu(options: .displayInline, children: [privateAction, tabsAction])

        let closeAction = UIAction(
            title: "Close This Tab",
            image: UIImage(systemName: "xmark"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.closeCurrentTab()
        }
        let moveMenu = makeMoveToGroupSubmenu(groups: groups)
        let newPrivateAction = UIAction(
            title: "New Private Tab",
            image: UIImage(systemName: "square.badge.plus")
        ) { [weak self] _ in
            self?.createNewTab(isPrivate: true)
        }
        let newTabAction = UIAction(
            title: "New Tab",
            image: UIImage(systemName: "plus.square.on.square")
        ) { [weak self] _ in
            self?.createNewTab(isPrivate: false)
        }
        let recentlyClosedMenu = makeRecentlyClosedMenu()
        let opsMenu = UIMenu(options: .displayInline, children: [closeAction, moveMenu, recentlyClosedMenu, newPrivateAction, newTabAction])

        var topChildren: [UIMenuElement] = []
        if !groupActions.isEmpty {
            topChildren.append(contentsOf: groupActions)
        }
        topChildren.append(modesMenu)
        topChildren.append(opsMenu)

        return UIMenu(title: "", children: topChildren)
    }

    private func makeMoveToGroupSubmenu(groups: [TabGroup]) -> UIMenu {
        let currentTab = selectedTabID.flatMap { id in tabs.first(where: { $0.id == id }) }
        guard currentTab?.isPrivate != true else {
            return UIMenu(
                title: "Move to Tab Group",
                image: UIImage(systemName: "arrow.up.right.square"),
                children: []
            )
        }
        var actions: [UIMenuElement] = []
        let newGroupAction = UIAction(
            title: "New Tab Group",
            image: UIImage(systemName: "plus")
        ) { [weak self] _ in
            self?.promptNewTabGroupWithCurrentTab()
        }
        actions.append(newGroupAction)

        if currentTab?.groupId != nil {
            let standardCount = tabs.filter { !$0.isPrivate && $0.groupId == nil }.count
            let ungroupTitle = TabOverviewViewController.tabsCapsuleCountTitle(count: standardCount)
            let ungroupAction = UIAction(
                title: ungroupTitle,
                image: UIImage(systemName: "iphone"),
                state: .off
            ) { [weak self] _ in
                self?.assignCurrentTab(to: nil)
            }
            actions.append(ungroupAction)
        }

        for group in groups {
            let action = UIAction(
                title: group.name,
                image: UIImage(systemName: "square.on.square"),
                state: (currentTab?.groupId == group.id) ? .on : .off
            ) { [weak self] _ in
                self?.assignCurrentTab(to: group.id)
            }
            actions.append(action)
        }

        return UIMenu(
            title: "Move to Tab Group",
            image: UIImage(systemName: "arrow.up.right.square"),
            children: actions
        )
    }

    func currentTabCount() -> Int {
        let isPrivate = overviewMode.isPrivate
        let activeGroupID = overviewController.selectedGroupID
        return tabs.filter {
            $0.isPrivate == isPrivate && (isPrivate || $0.groupId == activeGroupID)
        }.count
    }

    func switchToGroup(_ id: UUID) {
        setOverviewMode(.standard)
        overviewController.setGroupFilter(id)
        if let existing = tabs.first(where: { !$0.isPrivate && $0.groupId == id }) {
            selectTab(id: existing.id)
        } else {
            createNewTab(isPrivate: false)
            if let selected = selectedTabID, let index = tabs.firstIndex(where: { $0.id == selected }) {
                tabs[index].groupId = id
                do {
                    try tabStore?.assignTab(id: selected, toGroup: id)
                } catch {
                    logPersistenceError(error, operation: "assignTab")
                }
            }
        }
        applyBrowsingResumed(animated: true)
        updateTabStrip()
        updateRailItems()
    }

    func makeRecentlyClosedMenu() -> UIMenu {
        let children: [UIMenuElement] = if recentlyClosedTabs.isEmpty {
            [UIAction(title: "No Recently Closed Tabs", attributes: .disabled) { _ in }]
        } else {
            recentlyClosedTabs.prefix(10).map { tab -> UIAction in
                let trimmed = tab.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let title = !trimmed.isEmpty ? trimmed : (tab.url?.host ?? "Untitled")
                return UIAction(
                    title: title,
                    image: UIImage(systemName: "globe")
                ) { [weak self] _ in
                    self?.restoreRecentlyClosedTab(tab)
                }
            }
        }
        return UIMenu(
            title: "Recently Closed Tabs",
            image: UIImage(systemName: "clock.arrow.circlepath"),
            children: children
        )
    }

    func restoreRecentlyClosedTab(_ record: TabRecord) {
        recentlyClosedTabs.removeAll { $0.id == record.id }
        // Restored tabs are standard; leave private mode first so selection matches.
        if overviewMode.isPrivate {
            setOverviewMode(.standard)
            overviewController.setGroupFilter(nil)
        }
        let fresh = TabRecord(
            url: record.url,
            title: record.title,
            isPrivate: false,
            groupId: record.groupId
        )
        tabs.append(fresh)
        tabPool.create(fresh)
        do {
            try tabStore?.saveSession(tabs: tabs, selected: fresh.id)
        } catch {
            logPersistenceError(error, operation: "saveSession")
        }
        selectTab(id: fresh.id)
        applyBrowsingResumed(animated: true)
        updateTabStrip()
        updateRailItems()
    }

    func switchToPrivateMode() {
        requestPrivateMode { [weak self] in self?.performSwitchToPrivateMode() }
    }

    func performSwitchToPrivateMode() {
        setOverviewMode(.privateMode)
        overviewController.setGroupFilter(nil)
        if let existing = tabs.first(where: { $0.isPrivate }) {
            selectTab(id: existing.id)
        } else {
            createNewTab(isPrivate: true)
        }
        applyBrowsingResumed(animated: true)
        updateTabStrip()
        updateRailItems()
    }

    func switchToStandardMode() {
        setOverviewMode(.standard)
        overviewController.setGroupFilter(nil)
        if let existing = tabs.first(where: { !$0.isPrivate && $0.groupId == nil }) {
            selectTab(id: existing.id)
        } else {
            createNewTab(isPrivate: false)
        }
        applyBrowsingResumed(animated: true)
        updateTabStrip()
        updateRailItems()
    }

    func closeCurrentTab() {
        guard let id = selectedTabID else { return }
        closeTab(id: id, replacementIfEmpty: nil)
    }

    func assignCurrentTab(to groupID: UUID?) {
        guard let id = selectedTabID, let index = tabs.firstIndex(where: { $0.id == id }),
              !tabs[index].isPrivate else { return }
        tabs[index].groupId = groupID
        do {
            try tabStore?.assignTab(id: id, toGroup: groupID)
        } catch {
            logPersistenceError(error, operation: "assignTab")
        }
        overviewController.setGroupFilter(groupID)
        updateTabStrip()
        updateRailItems()
    }

    func promptNewTabGroupWithCurrentTab() {
        let alert = UIAlertController(title: "New Tab Group", message: "Enter a name for this tab group.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Tab Group Name"
            field.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let self,
                  let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty
            else { return }
            do {
                let group = try self.tabStore?.createGroup(name: name)
                if let groupID = group?.id {
                    self.assignCurrentTab(to: groupID)
                }
            } catch {
                self.logPersistenceError(error, operation: "createGroup")
            }
        })
        present(alert, animated: true)
    }

    // MARK: - Photos

    func saveImageToPhotos(from url: URL) {
        guard URLNormalizer.isLoadable(url) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                try await self.saveImageDataToPhotos(data)
            } catch {
                self.processPhotoSaveFailure(error)
            }
        }
    }

    private func saveImageDataToPhotos(_ data: Data) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard granted == .authorized || granted == .limited else {
                throw PhotoSaveFailure.accessDenied
            }
        case .limited, .authorized:
            break
        default:
            throw PhotoSaveFailure.accessDenied
        }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }
    }

    private func processPhotoSaveFailure(_ error: Error) {
        guard error is PhotoSaveFailure else {
            logPersistenceError(error, operation: "saveImageToPhotos")
            return
        }
        let alert = UIAlertController(
            title: "Can't Save Photo",
            message: "OuterView does not have permission to add to your photo library.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Element Context

    /// The only place action closures are constructed: each maps a URL back
    /// to a root-level capability, so pages never reach into stores directly.
    func makeElementContextActions() -> ElementContextActions {
        ElementContextActions(
            openLink: { [weak self] url in self?.loadActivePage(url) },
            openInNewTab: { [weak self] url in self?.openInNewTab(url: url, background: true, isPrivate: nil) },
            tabGroups: overviewGroups(),
            openInTabGroup: { [weak self] url, group in self?.openURLsInGroup([url], groupId: group.id) },
            openInNewTabGroup: { [weak self] url, name in self?.openURLsInNewGroup([url], name: name) },
            downloadLinkedFile: { [weak self] url in self?.downloadLinkedFile(url: url) },
            addToReadingList: { [weak self] url in self?.addReadingListEntry(url: url) },
            copyLink: { [weak self] url in self?.copyElementURLToPasteboard(url) },
            share: { [weak self] url in self?.shareElementURL(url) },
            saveToPhotos: { [weak self] url in self?.saveImageToPhotos(from: url) },
            copyImage: { [weak self] url in self?.copyElementURLToPasteboard(url) }
        )
    }

    func downloadLinkedFile(url: URL) {
        guard URLNormalizer.isLoadable(url) else { return }
        let fallback = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        let rowID = downloadsManager.registerRow(
            name: DownloadsManager.sanitizedFileName(fallback),
            fileURL: nil
        )
        let request = URLRequest(url: url)
        if BackgroundDownloadService.shared.start(request: request, suggestedName: fallback, reusing: rowID) == nil {
            downloadsManager.failDownload(id: rowID, reason: "Download service unavailable")
        }
    }

    private func addReadingListEntry(url: URL) {
        guard URLNormalizer.isLoadable(url) else { return }
        let title = HostFormatter.displayTitle(url: url, title: nil)
        do {
            try readingListStore?.add(title: title, url: url)
        } catch {
            logPersistenceError(error, operation: "addToReadingList")
        }
    }

    private func copyElementURLToPasteboard(_ url: URL) {
        UIPasteboard.general.url = url
    }

    private func shareElementURL(_ url: URL) {
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        presentPopover(activity)
    }
}
