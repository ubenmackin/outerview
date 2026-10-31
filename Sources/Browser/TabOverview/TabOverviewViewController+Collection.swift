//
//  TabOverviewViewController+Collection.swift
//  OuterView
//

import UIKit

// MARK: - UICollectionViewDataSource, UICollectionViewDelegate

extension TabOverviewViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        visibleItems.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: TabCardCell.reuseIdentifier,
            for: indexPath
        ) as? TabCardCell
        else {
            return UICollectionViewCell()
        }
        let item = visibleItems[indexPath.item]
        cell.configure(with: item, preview: previews[item.id], isSelected: item.id == selectedID)
        cell.onClose = { [weak self] in self?.closeTab(id: item.id) }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        let item = visibleItems[indexPath.item]
        delegate?.tabOverview(self, didSelectTab: item.id)
    }

    /// Batch contract for closing other tabs: the grid refreshes once
    /// (single picker rebuild + reload + empty-state update) while the
    /// owner is still notified once per closed tab via `didCloseTab`
    /// (with `replacementIfEmpty` always nil since the kept tab survives),
    /// so per-tab teardown stays per-tab.
    func closeOtherTabs(keeping keepID: UUID) {
        guard allTabs.contains(where: { $0.id == keepID }) else { return }
        let idsToClose = Self.tabs(allTabs, in: mode).filter { $0.id != keepID }.map(\.id)
        guard !idsToClose.isEmpty else { return }
        showCloseOtherTabsSheet(keeping: keepID, idsToClose: idsToClose)
    }

    private func showCloseOtherTabsSheet(keeping keepID: UUID, idsToClose: [UUID]) {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Close Other Tabs", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.closeOtherTabsConfirmed(keeping: keepID, idsToClose: idsToClose)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(
                x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0
            )
            popover.permittedArrowDirections = []
        }
        present(sheet, animated: true)
    }

    private func closeOtherTabsConfirmed(keeping keepID: UUID, idsToClose: [UUID]) {
        guard allTabs.contains(where: { $0.id == keepID }) else { return }
        let existing = Set(allTabs.map(\.id))
        let confirmed = idsToClose.filter { $0 != keepID && existing.contains($0) }
        guard !confirmed.isEmpty else { return }
        let confirmedSet = Set(confirmed)
        allTabs.removeAll(where: { confirmedSet.contains($0.id) })
        for id in confirmed {
            previews[id] = nil
        }
        if let current = selectedID, confirmedSet.contains(current) {
            selectedID = keepID
        }
        updatePickerBar()
        collectionView.reloadData()
        updateEmptyState()
        for id in confirmed {
            delegate?.tabOverview(self, didCloseTab: id, replacementIfEmpty: nil)
        }
    }

    private func makeCardContextMenu(for item: TabOverviewItem) -> UIMenu {
        var actions: [UIMenuElement] = []

        if let url = item.url {
            actions.append(
                UIAction(title: "Copy Link", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.url = url
                }
            )
        }

        actions.append(moveToGroupMenu(forTab: item.id))

        if Self.tabs(allTabs, in: mode).count > 1 {
            actions.append(
                UIAction(
                    title: "Close Other Tabs",
                    image: UIImage(systemName: "xmark.circle"),
                    attributes: .destructive
                ) { [weak self] _ in
                    self?.closeOtherTabs(keeping: item.id)
                }
            )
        }

        actions.append(
            UIAction(
                title: "Close Tab",
                image: UIImage(systemName: "xmark"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.closeTab(id: item.id)
            }
        )

        return UIMenu(children: actions)
    }

    func collectionView(
        _: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point _: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPath.item < visibleItems.count else { return nil }
        let item = visibleItems[indexPath.item]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return UIMenu() }
            return self.makeCardContextMenu(for: item)
        }
    }
}

// MARK: - UICollectionViewDragDelegate, UICollectionViewDropDelegate

extension TabOverviewViewController: UICollectionViewDragDelegate, UICollectionViewDropDelegate {
    func collectionView(_: UICollectionView, dragSessionWillBegin _: UIDragSession) {
        isDragReordering = true
    }

    func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd _: UIDragSession) {
        isDragReordering = false
        guard !pendingPreviewIDs.isEmpty else { return }
        let ids = pendingPreviewIDs
        pendingPreviewIDs.removeAll()
        for id in ids {
            guard allTabs.contains(where: { $0.id == id }) else { continue }
            for (index, item) in visibleItems.enumerated() where item.id == id {
                collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
                break
            }
        }
    }

    func collectionView(
        _: UICollectionView,
        itemsForBeginning _: UIDragSession,
        at indexPath: IndexPath
    ) -> [UIDragItem] {
        guard filterQuery.isEmpty, selectedGroupID == nil, indexPath.item < visibleItems.count else { return [] }
        let tab = visibleItems[indexPath.item]
        let item = UIDragItem(itemProvider: NSItemProvider())
        item.localObject = tab.id
        return [item]
    }

    func collectionView(
        _: UICollectionView,
        dropSessionDidUpdate session: UIDropSession,
        withDestinationIndexPath _: IndexPath?
    ) -> UICollectionViewDropProposal {
        guard filterQuery.isEmpty, selectedGroupID == nil, session.localDragSession != nil else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }
        return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        performDropWith coordinator: UICollectionViewDropCoordinator
    ) {
        guard filterQuery.isEmpty, selectedGroupID == nil else {
            return
        }

        let destinationIndexPath: IndexPath
        if let dest = coordinator.destinationIndexPath {
            destinationIndexPath = dest
        } else {
            let section = max(0, collectionView.numberOfSections - 1)
            let row = collectionView.numberOfItems(inSection: section)
            destinationIndexPath = IndexPath(item: row, section: section)
        }

        guard coordinator.proposal.operation == .move else {
            return
        }

        let localItems = coordinator.items.filter { $0.dragItem.localObject is UUID }
        guard !localItems.isEmpty else {
            return
        }

        let ids = visibleItems.map(\.id)
        guard !ids.isEmpty else {
            return
        }

        let draggedIDs = localItems.compactMap { $0.dragItem.localObject as? UUID }
        let rawDestination = destinationIndexPath.item
        let orderedIDs = Self.reorderedIDs(
            currentIDs: ids,
            draggedIDs: draggedIDs,
            destinationIndex: rawDestination
        )

        if orderedIDs == ids {
            for item in localItems {
                if let source = item.sourceIndexPath {
                    coordinator.drop(item.dragItem, toItemAt: source)
                } else if let id = item.dragItem.localObject as? UUID,
                          let current = ids.firstIndex(of: id)
                {
                    coordinator.drop(item.dragItem, toItemAt: IndexPath(item: current, section: 0))
                }
            }
            return
        }

        if localItems.count == 1,
           let item = localItems.first,
           let sourceIndexPath = item.sourceIndexPath
        {
            let targetItem = min(destinationIndexPath.item, ids.count - 1)
            let targetIndexPath = IndexPath(item: targetItem, section: destinationIndexPath.section)
            collectionView.performBatchUpdates({
                self.applyLocalReorder(orderedIDs: orderedIDs)
                collectionView.deleteItems(at: [sourceIndexPath])
                collectionView.insertItems(at: [targetIndexPath])
            }, completion: { _ in
                self.delegate?.tabOverview(self, didReorderTabs: orderedIDs)
            })
            coordinator.drop(item.dragItem, toItemAt: targetIndexPath)
        } else {
            applyLocalReorder(orderedIDs: orderedIDs)
            collectionView.reloadData()
            for item in localItems {
                guard let id = item.dragItem.localObject as? UUID,
                      let final = orderedIDs.firstIndex(of: id) else { continue }
                coordinator.drop(item.dragItem, toItemAt: IndexPath(item: final, section: 0))
            }
            delegate?.tabOverview(self, didReorderTabs: orderedIDs)
        }
    }
}
