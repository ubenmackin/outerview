//
//  TabOverviewViewController+Picker.swift
//  OuterView
//

import UIKit

/// UserDefaults keys libraryTab as Int, overviewMode as String, and overviewGroup as String.
/// Values are read at init and setup and written on every change; private mode is never
/// written and restores as standard. Unparseable values fall back to bookmarks, standard,
/// and nil; a stored group id resolving to no existing group restores as nil.
extension TabOverviewViewController {
    nonisolated static let overviewModeDefaultsKey = "overviewMode"
    nonisolated static let overviewGroupDefaultsKey = "overviewGroup"

    nonisolated static func storedOverviewMode(defaults: UserDefaults = .standard) -> TabOverviewMode {
        guard let raw = defaults.string(forKey: overviewModeDefaultsKey),
              raw == "standard"
        else {
            return .standard
        }
        return .standard
    }

    nonisolated static func storedOverviewGroupID(defaults: UserDefaults = .standard) -> UUID? {
        guard let raw = defaults.string(forKey: overviewGroupDefaultsKey),
              let id = UUID(uuidString: raw)
        else {
            return nil
        }
        return id
    }

    nonisolated static func persistOverviewSelection(
        mode: TabOverviewMode,
        groupID: UUID?,
        defaults: UserDefaults = .standard
    ) {
        // Private mode is never written; a private selection clears stored values.
        guard !mode.isPrivate else {
            defaults.removeObject(forKey: overviewModeDefaultsKey)
            defaults.removeObject(forKey: overviewGroupDefaultsKey)
            return
        }
        defaults.set("standard", forKey: overviewModeDefaultsKey)
        if let groupID {
            defaults.set(groupID.uuidString, forKey: overviewGroupDefaultsKey)
        } else {
            defaults.removeObject(forKey: overviewGroupDefaultsKey)
        }
    }

    func updatePickerBar() {
        let totals = Self.counts(allTabs)
        pickerBar.render(state: TabGroupsSheetState(
            isPrivate: mode.isPrivate,
            selectedGroupID: selectedGroupID,
            standardCount: totals.standard,
            privateCount: totals.privateCount,
            groups: Self.groupCapsuleItems(groups: allGroups, tabs: allTabs)
        ))
    }

    func applyPickerSelection(_ selection: PickerSelection) {
        switch selection {
        case .allStandard:
            applySelectionBatched(mode: .standard, groupID: nil, notify: true)
            Self.persistOverviewSelection(mode: .standard, groupID: nil, defaults: selectionDefaults)
        case .private:
            applySelectionBatched(mode: .privateMode, groupID: nil, notify: true)
            Self.persistOverviewSelection(mode: .privateMode, groupID: nil, defaults: selectionDefaults)
        case let .group(id):
            applySelectionBatched(mode: .standard, groupID: id, notify: true)
            Self.persistOverviewSelection(mode: .standard, groupID: id, defaults: selectionDefaults)
        }
    }

    /// Overview commands shared by the rail ellipsis menu.
    func makeOverviewMenu(includesCloseAll: Bool) -> UIMenu {
        UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                guard let self else {
                    completion([])
                    return
                }
                var children: [UIMenuElement] = [
                    UIAction(title: "Manage Tab Groups", image: UIImage(systemName: "list.bullet.rectangle")) { [weak self] _ in
                        self?.showGroupsSheet()
                    },
                    UIAction(title: "New Group…", image: UIImage(systemName: "folder.badge.plus")) { [weak self] _ in
                        self?.promptNewGroupCreation(withTabIDs: [])
                    }
                ]
                if includesCloseAll {
                    children.append(
                        UIAction(title: "Close All Tabs", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                            self?.showCloseAllSheet()
                        }
                    )
                }
                completion(children)
            }
        ])
    }

    func moveToGroupMenu(forTab id: UUID) -> UIMenu {
        let tab = allTabs.first(where: { $0.id == id })
        var children: [UIMenuElement] = []
        for group in allGroups {
            let action = UIAction(
                title: group.name,
                state: tab?.groupId == group.id ? .on : .off
            ) { [weak self] _ in
                guard let self else { return }
                self.delegate?.tabOverview(self, didAssignTab: id, toGroup: group.id)
            }
            children.append(action)
        }
        children.append(
            UIAction(title: "New Group…") { [weak self] _ in
                self?.promptNewGroupCreation(withTabIDs: [id])
            }
        )
        if tab?.groupId != nil {
            children.append(
                UIAction(title: "Remove from Group", attributes: .destructive) { [weak self] _ in
                    guard let self else { return }
                    self.delegate?.tabOverview(self, didAssignTab: id, toGroup: nil)
                }
            )
        }
        return UIMenu(title: "Move to Group…", children: children)
    }

    func promptNewGroupCreation(withTabIDs tabIDs: [UUID]) {
        let alert = UIAlertController(title: "New Group", message: "Enter a name for this group.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Group Name"
            field.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let raw = alert?.textFields?.first?.text,
                  !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return }
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            self.delegate?.tabOverview(self, didCreateGroup: name, withTabIDs: tabIDs)
        })
        if let popover = alert.popoverPresentationController {
            popover.sourceView = pickerBar
            popover.sourceRect = pickerBar.bounds
        }
        present(alert, animated: true)
    }

    /// One Safari-style sheet for mode + group selection. The sheet re-reads
    /// `stateProvider` itself, so the owner only applies emitted actions.
    func showGroupsSheet() {
        let sheet = TabGroupsSheetController(stateProvider: { [weak self] in
            guard let self else {
                return TabGroupsSheetState(
                    isPrivate: false,
                    selectedGroupID: nil,
                    standardCount: 0,
                    privateCount: 0,
                    groups: []
                )
            }
            let totals = Self.counts(allTabs)
            return TabGroupsSheetState(
                isPrivate: mode.isPrivate,
                selectedGroupID: selectedGroupID,
                standardCount: totals.standard,
                privateCount: totals.privateCount,
                groups: Self.groupCapsuleItems(groups: allGroups, tabs: allTabs)
            )
        })
        sheet.onAction = { [weak self] in self?.handleGroupsSheetAction($0) }
        sheet.modalPresentationStyle = .pageSheet
        if let presentation = sheet.sheetPresentationController {
            presentation.detents = [.medium(), .large()]
            presentation.prefersGrabberVisible = true
        }
        present(sheet, animated: true)
    }

    func handleGroupsSheetAction(_ action: TabGroupsSheetController.Action) {
        switch action {
        case .selectStandardAll:
            applySelectionBatched(mode: .standard, groupID: nil, notify: true)
            Self.persistOverviewSelection(mode: .standard, groupID: nil, defaults: selectionDefaults)
        case .selectPrivate:
            applySelectionBatched(mode: .privateMode, groupID: nil, notify: true)
            Self.persistOverviewSelection(mode: .privateMode, groupID: nil, defaults: selectionDefaults)
        case let .selectGroup(id):
            applySelectionBatched(mode: .standard, groupID: id, notify: true)
            Self.persistOverviewSelection(mode: .standard, groupID: id, defaults: selectionDefaults)
        case let .createGroup(name, withAllStandardTabs):
            let tabIDs = withAllStandardTabs ? Self.tabs(allTabs, in: .standard).map(\.id) : []
            delegate?.tabOverview(self, didCreateGroup: name, withTabIDs: tabIDs)
        case let .renameGroup(id, name):
            delegate?.tabOverview(self, didRenameGroup: id, toName: name)
        case let .deleteGroup(id):
            delegate?.tabOverview(self, didDeleteGroup: id)
        }
    }
}
