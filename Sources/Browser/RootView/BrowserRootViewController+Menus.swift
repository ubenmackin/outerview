// RootView — Back history and tab group menus for chrome buttons.

import UIKit
import WebKit

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
        let opsMenu = UIMenu(options: .displayInline, children: [closeAction, moveMenu, newPrivateAction, newTabAction])

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

    func switchToPrivateMode() {
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
}
