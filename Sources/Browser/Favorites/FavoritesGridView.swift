//
//  FavoritesGridView.swift
//  OuterView
//

import os
import UIKit

/// Displays user favorites as large favicon tiles in a responsive grid.
@MainActor
final class FavoritesGridView: UIView {
    var onOpenURL: ((URL) -> Void)?
    var onDeleteFavorite: ((UUID) -> Void)?

    private let bookmarkStore: BookmarkStore
    private var favorites: [Bookmark] = []

    private let collectionView: UICollectionView
    private let flowLayout: UICollectionViewFlowLayout
    private let emptyLabel = UILabel()

    nonisolated static func itemSize(forContentWidth width: CGFloat, columns: Int) -> CGSize {
        let count = max(1, columns)
        let totalSpacing = CGFloat(max(count - 1, 0)) * 16
        let raw = floor((width - totalSpacing) / CGFloat(count))
        // Clamp tiny widths to the minimum tile so rotation never collapses or clips.
        let side = max(76, raw)
        return CGSize(width: side, height: side + 36)
    }

    nonisolated static func canBeginDrag(itemCount: Int, index: Int) -> Bool {
        index >= 0 && index < itemCount
    }

    nonisolated static func reorderedIDs(
        currentIDs: [UUID],
        draggedIDs: [UUID],
        destinationIndex: Int
    ) -> [UUID] {
        guard !currentIDs.isEmpty,
              let draggedID = draggedIDs.first,
              let from = currentIDs.firstIndex(of: draggedID)
        else { return currentIDs }
        let clamped = min(max(destinationIndex, 0), currentIDs.count - 1)
        guard from != clamped else { return currentIDs }
        var result = currentIDs
        let element = result.remove(at: from)
        result.insert(element, at: clamped)
        return result
    }

    init(bookmarkStore: BookmarkStore) {
        self.bookmarkStore = bookmarkStore
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 16
        layout.minimumLineSpacing = 16
        layout.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        layout.itemSize = CGSize(width: FavoriteTileCell.tileLength, height: FavoriteTileCell.cellHeight)
        self.flowLayout = layout
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)
        setup()
        reload()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        favorites = bookmarkStore.fetchFavorites()
        collectionView.isHidden = favorites.isEmpty
        emptyLabel.isHidden = !favorites.isEmpty
        collectionView.reloadData()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let columns = StartPageViewModel.columnCount(for: traitCollection)
        let size = Self.itemSize(forContentWidth: bounds.width - 32, columns: columns)
        if flowLayout.itemSize != size {
            flowLayout.itemSize = size
            flowLayout.invalidateLayout()
        }
    }

    // MARK: - Private

    private func setup() {
        backgroundColor = .clear

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "No Favorites Yet"
        emptyLabel.font = .preferredFont(forTextStyle: .subheadline)
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.isHidden = true
        addSubview(emptyLabel)

        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.dragInteractionEnabled = true
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        collectionView.register(FavoriteTileCell.self, forCellWithReuseIdentifier: FavoriteTileCell.reuseIdentifier)
        addSubview(collectionView)

        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

// MARK: - UICollectionViewDataSource, UICollectionViewDelegate

extension FavoritesGridView: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        favorites.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: FavoriteTileCell.reuseIdentifier,
            for: indexPath
        ) as? FavoriteTileCell
        else {
            return UICollectionViewCell()
        }
        let bookmark = favorites[indexPath.item]
        cell.onCopyURL = {
            UIPasteboard.general.url = bookmark.url
        }
        cell.onDelete = { [weak self] in
            self?.onDeleteFavorite?(bookmark.id)
        }
        cell.configure(with: bookmark)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        let bookmark = favorites[indexPath.item]
        onOpenURL?(bookmark.url)
    }

    func collectionView(
        _: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point _: CGPoint
    ) -> UIContextMenuConfiguration? {
        let bookmark = favorites[indexPath.item]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let copyAction = UIAction(title: "Copy URL", image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.url = bookmark.url
            }
            let deleteAction = UIAction(
                title: "Remove from Favorites",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { _ in
                self?.onDeleteFavorite?(bookmark.id)
            }
            return UIMenu(children: [copyAction, deleteAction])
        }
    }
}

// MARK: - UICollectionViewDragDelegate, UICollectionViewDropDelegate

extension FavoritesGridView: UICollectionViewDragDelegate, UICollectionViewDropDelegate {
    func collectionView(
        _: UICollectionView,
        itemsForBeginning _: UIDragSession,
        at indexPath: IndexPath
    ) -> [UIDragItem] {
        guard Self.canBeginDrag(itemCount: favorites.count, index: indexPath.item) else { return [] }
        let dragItem = UIDragItem(itemProvider: NSItemProvider())
        dragItem.localObject = favorites[indexPath.item].id
        return [dragItem]
    }

    func collectionView(
        _: UICollectionView,
        dropSessionDidUpdate session: UIDropSession,
        withDestinationIndexPath _: IndexPath?
    ) -> UICollectionViewDropProposal {
        guard session.localDragSession != nil else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }
        return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        performDropWith coordinator: UICollectionViewDropCoordinator
    ) {
        guard coordinator.proposal.operation == .move else { return }
        let localItems = coordinator.items.filter { $0.dragItem.localObject is UUID }
        guard !localItems.isEmpty else { return }
        let currentIDs = favorites.map(\.id)
        guard !currentIDs.isEmpty else { return }
        let draggedIDs = localItems.compactMap { $0.dragItem.localObject as? UUID }
        guard !draggedIDs.isEmpty else { return }
        // Nil destination means past the trailing edge.
        let rawDestination = coordinator.destinationIndexPath?.item ?? currentIDs.count
        let ordered = Self.reorderedIDs(
            currentIDs: currentIDs,
            draggedIDs: draggedIDs,
            destinationIndex: rawDestination
        )
        guard ordered != currentIDs else {
            for item in localItems {
                if let source = item.sourceIndexPath {
                    coordinator.drop(item.dragItem, toItemAt: source)
                }
            }
            return
        }
        let byID = Dictionary(uniqueKeysWithValues: favorites.map { ($0.id, $0) })
        var reordered: [Bookmark] = []
        reordered.reserveCapacity(ordered.count)
        for id in ordered {
            guard let bookmark = byID[id] else {
                reload()
                return
            }
            reordered.append(bookmark)
        }
        favorites = reordered
        do {
            try bookmarkStore.reorderBookmarks(ordered)
        } catch {
            Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                .error("reorderFavorites failed: \(error.localizedDescription, privacy: .public)")
            reload()
            return
        }
        collectionView.reloadData()
        let keptID = draggedIDs.first(where: { currentIDs.contains($0) })
        for item in localItems {
            guard let id = item.dragItem.localObject as? UUID else { continue }
            if let kept = keptID, id == kept,
               let final = ordered.firstIndex(of: id)
            {
                coordinator.drop(item.dragItem, toItemAt: IndexPath(item: final, section: 0))
            } else if let source = item.sourceIndexPath {
                coordinator.drop(item.dragItem, toItemAt: source)
            }
        }
    }
}
