//
//  FavoritesGridView.swift
//  OuterView
//

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
        collectionView.dataSource = self
        collectionView.delegate = self
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
