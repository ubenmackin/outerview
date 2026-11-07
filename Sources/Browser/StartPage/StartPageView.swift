// StartPage — Unified start surface with scrollable recents.

import os
import UIKit

/// Navigation hook for start page rows. Taps reduce to a URL; the owner loads
/// it into the active tab, which dismisses the start page.
@MainActor
protocol StartPageViewDelegate: AnyObject {
    func startPage(_ view: StartPageView, didOpenURL url: URL)
}

/// No-URL content for a new or restored-clean tab: favorites grid plus
/// recently-visited rows over a scroll view. Recents collapse fully when
/// empty; zero favorites swap the grid for two prompt tiles.
@MainActor
final class StartPageView: UIView {
    weak var delegate: StartPageViewDelegate?
    var onImportTapped: (() -> Void)?
    var onDeleteFavorite: ((UUID) -> Void)?

    let viewModel: StartPageViewModel

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let favoritesHeaderStack = UIStackView()
    private let folderBackButton = UIButton(type: .system)
    private let favoritesHeaderLabel = UILabel()
    private let collectionView: UICollectionView
    private let flowLayout: UICollectionViewFlowLayout
    private var collectionHeightConstraint: NSLayoutConstraint!
    private let emptyStateStack = UIStackView()
    private let importTile = DashedPromptTile()
    private let addCurrentPageTile = DashedPromptTile()
    private let recentsHeaderLabel = UILabel()
    private let recentsStack = UIStackView()

    init(viewModel: StartPageViewModel) {
        self.viewModel = viewModel
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = .zero
        layout.itemSize = CGSize(
            width: FavoriteTileCell.tileLength,
            height: FavoriteTileCell.cellHeight
        )
        flowLayout = layout
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.dragInteractionEnabled = true
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        setupHierarchy()
        observeHorizontalSizeClass()
        reload()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        viewModel.reload()
        if viewModel.isAtRoot {
            folderBackButton.isHidden = true
            favoritesHeaderLabel.text = "Favorites"
        } else {
            folderBackButton.isHidden = false
            favoritesHeaderLabel.text = viewModel.currentTitle
        }
        let favoritesEmpty = viewModel.isFavoritesEmpty
        let recentsEmpty = viewModel.isRecentsEmpty
        collectionView.isHidden = favoritesEmpty
        emptyStateStack.isHidden = !favoritesEmpty || !viewModel.isAtRoot
        addCurrentPageTile.isEnabled = viewModel.canAddCurrentPage
        addCurrentPageTile.alpha = viewModel.canAddCurrentPage ? 1 : 0.5
        recentsHeaderLabel.isHidden = recentsEmpty || !viewModel.isAtRoot
        recentsStack.isHidden = recentsEmpty || !viewModel.isAtRoot
        rebuildRecentRows()
        collectionView.reloadData()
        updateCollectionHeight()
        setNeedsLayout()
    }

    func updateActivePage(url: URL?, title: String?) {
        viewModel.updateActivePage(url: url, title: title)
        addCurrentPageTile.isEnabled = viewModel.canAddCurrentPage
        addCurrentPageTile.alpha = viewModel.canAddCurrentPage ? 1 : 0.5
    }

    nonisolated static func canBeginDrag(itemCount: Int, index: Int) -> Bool {
        FavoritesGridView.canBeginDrag(itemCount: itemCount, index: index)
    }

    nonisolated static func reorderedIDs(
        currentIDs: [UUID],
        draggedIDs: [UUID],
        destinationIndex: Int
    ) -> [UUID] {
        FavoritesGridView.reorderedIDs(
            currentIDs: currentIDs,
            draggedIDs: draggedIDs,
            destinationIndex: destinationIndex
        )
    }

    func applyOrderedFavorites(_ ordered: [UUID]) -> Bool {
        viewModel.applyOrderedFavorites(ordered)
    }

    /// Extra bottom room, beyond the safe area, so the last row scrolls
    /// clear of the floating address pill.
    func setBottomChromeInset(_ inset: CGFloat) {
        // Reasserted on every inset update so short lists stay draggable.
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .onDrag
        guard scrollView.contentInset.bottom != inset else { return }
        scrollView.contentInset.bottom = inset
        scrollView.verticalScrollIndicatorInsets.bottom = inset
        // Clamp stale offset after shrink so short lists park at top.
        let minY = -scrollView.adjustedContentInset.top
        let maxY = scrollView.contentSize.height - scrollView.bounds.height + inset
        let clampedY = min(max(scrollView.contentOffset.y, minY), max(maxY, minY))
        if scrollView.contentOffset.y != clampedY {
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: clampedY), animated: false)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateFlowItemSize()
        updateCollectionHeight()
    }

    // MARK: - Private

    private func observeHorizontalSizeClass() {
        // Grid density follows size class; bounds-driven sizing stays in layoutSubviews.
        _ = registerForTraitChanges([UITraitHorizontalSizeClass.self]) { @MainActor (owner: StartPageView, previous: UITraitCollection) in
            if previous.horizontalSizeClass != owner.traitCollection.horizontalSizeClass {
                owner.updateFlowItemSize()
                owner.updateCollectionHeight()
            }
        }
    }

    private func setupHierarchy() {
        backgroundColor = .systemBackground

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.backgroundColor = .clear
        // Drag dismisses keyboard; bounce keeps short lists scrollable.
        scrollView.keyboardDismissMode = .onDrag
        scrollView.alwaysBounceVertical = true
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor)
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16
            ),
            contentStack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16
            ),
            contentStack.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32
            )
        ])

        favoritesHeaderStack.axis = .horizontal
        favoritesHeaderStack.spacing = 8
        favoritesHeaderStack.alignment = .center
        favoritesHeaderStack.translatesAutoresizingMaskIntoConstraints = false

        folderBackButton.setImage(UIImage(systemName: "chevron.backward"), for: .normal)
        folderBackButton.setTitle(" Favorites", for: .normal)
        folderBackButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        folderBackButton.titleLabel?.adjustsFontForContentSizeCategory = true
        folderBackButton.accessibilityLabel = "Back to Favorites"
        folderBackButton.isHidden = true
        folderBackButton.addAction(UIAction { [weak self] _ in
            self?.viewModel.popFolder()
            self?.reload()
        }, for: .touchUpInside)
        favoritesHeaderStack.addArrangedSubview(folderBackButton)

        favoritesHeaderLabel.text = "Favorites"
        favoritesHeaderLabel.font = .preferredFont(forTextStyle: .headline)
        favoritesHeaderLabel.adjustsFontForContentSizeCategory = true
        favoritesHeaderLabel.accessibilityIdentifier = "StartPage.FavoritesHeader"
        favoritesHeaderStack.addArrangedSubview(favoritesHeaderLabel)

        contentStack.addArrangedSubview(favoritesHeaderStack)

        collectionView.backgroundColor = .clear
        collectionView.isScrollEnabled = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.accessibilityIdentifier = "StartPage.FavoritesGrid"
        collectionView.register(FavoriteTileCell.self, forCellWithReuseIdentifier: FavoriteTileCell.reuseIdentifier)
        contentStack.addArrangedSubview(collectionView)
        collectionHeightConstraint = collectionView.heightAnchor.constraint(equalToConstant: 0)
        collectionHeightConstraint.isActive = true

        emptyStateStack.axis = .horizontal
        emptyStateStack.spacing = 12
        emptyStateStack.distribution = .fillEqually
        emptyStateStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(emptyStateStack)

        importTile.setTitle("Import from Safari…", for: .normal)
        importTile.accessibilityIdentifier = "StartPage.ImportTile"
        importTile.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.onImportTapped?()
        }, for: .touchUpInside)
        emptyStateStack.addArrangedSubview(importTile)
        importTile.heightAnchor.constraint(equalToConstant: 92).isActive = true

        addCurrentPageTile.setTitle("Add Current Page", for: .normal)
        addCurrentPageTile.accessibilityIdentifier = "StartPage.AddCurrentPageTile"
        addCurrentPageTile.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            do {
                try self.viewModel.addCurrentPage()
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "StartPage")
                    .error("addCurrentPage failed: \(error.localizedDescription, privacy: .public)")
            }
            self.reload()
        }, for: .touchUpInside)
        emptyStateStack.addArrangedSubview(addCurrentPageTile)

        recentsHeaderLabel.text = "Recently Visited"
        recentsHeaderLabel.font = .preferredFont(forTextStyle: .headline)
        recentsHeaderLabel.adjustsFontForContentSizeCategory = true
        recentsHeaderLabel.accessibilityIdentifier = "StartPage.RecentsHeader"
        contentStack.addArrangedSubview(recentsHeaderLabel)

        recentsStack.axis = .vertical
        recentsStack.spacing = 4
        recentsStack.accessibilityIdentifier = "StartPage.RecentsList"
        contentStack.addArrangedSubview(recentsStack)
    }

    private func contentWidthForColumns() -> CGFloat {
        let scrollWidth = scrollView.bounds.width
        if scrollWidth > 0 {
            return scrollWidth - 32
        }
        // Before first layout the scroll view has no width; fall back to the
        // view width so the initial grid still resolves to a valid density.
        guard bounds.width > 0 else { return 1 }
        return max(bounds.width - 32, 1)
    }

    private func itemSize(forContentWidth width: CGFloat) -> CGSize {
        let columns = StartPageViewModel.columnCount(for: traitCollection)
        let totalSpacing = CGFloat(max(columns - 1, 0)) * flowLayout.minimumInteritemSpacing
        let itemWidth = floor((width - totalSpacing) / CGFloat(columns))
        // Icon stays fixed; the title block stretches with the column.
        let itemHeight = itemWidth + (FavoriteTileCell.cellHeight - FavoriteTileCell.tileLength)
        return CGSize(width: max(itemWidth, 1), height: max(itemHeight, 1))
    }

    private func updateFlowItemSize() {
        let size = itemSize(forContentWidth: contentWidthForColumns())
        if flowLayout.itemSize != size {
            flowLayout.itemSize = size
            flowLayout.invalidateLayout()
        }
    }

    private func updateCollectionHeight() {
        let count = viewModel.favoriteItems.count
        guard !collectionView.isHidden, count > 0 else { return }
        updateFlowItemSize()
        let columns = StartPageViewModel.columnCount(for: traitCollection)
        let rows = (count + columns - 1) / columns
        let itemHeight = flowLayout.itemSize.height
        let total = CGFloat(rows) * itemHeight + CGFloat(max(rows - 1, 0)) * flowLayout.minimumLineSpacing
        if collectionHeightConstraint.constant != total {
            collectionHeightConstraint.constant = total
        }
    }

    private static func roundFavicon(_ image: UIImage, size: CGFloat = 26, cornerRadius: CGFloat = 6) -> UIImage {
        let targetSize = CGSize(width: size, height: size)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: targetSize)
            UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).addClip()
            image.draw(in: rect)
        }
    }

    private func rebuildRecentRows() {
        for arranged in recentsStack.arrangedSubviews {
            recentsStack.removeArrangedSubview(arranged)
            arranged.removeFromSuperview()
        }
        for entry in viewModel.recents {
            let url = entry.url
            var configuration = UIButton.Configuration.plain()
            configuration.baseForegroundColor = .label
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.foregroundColor = UIColor.label
                outgoing.font = UIFont.preferredFont(forTextStyle: .body)
                return outgoing
            }
            configuration.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.foregroundColor = UIColor.secondaryLabel
                outgoing.font = UIFont.preferredFont(forTextStyle: .subheadline)
                return outgoing
            }
            configuration.image = Self.roundFavicon(FaviconService.shared.cachedFaviconOrMonogram(for: url, size: 26))
            configuration.imagePadding = 12
            configuration.title = HostFormatter.displayTitle(url: url, title: entry.title.isEmpty ? nil : entry.title)
            configuration.subtitle = HostFormatter.displayTitle(url: url, title: HostFormatter.host(of: url))
            configuration.contentInsets = NSDirectionalEdgeInsets(
                top: 8, leading: 4, bottom: 8, trailing: 4
            )
            let button = UIButton(configuration: configuration)
            button.contentHorizontalAlignment = .leading
            button.titleLabel?.lineBreakMode = .byTruncatingTail
            button.subtitleLabel?.lineBreakMode = .byTruncatingTail
            button.accessibilityIdentifier = "StartPage.RecentRow.\(url.absoluteString)"
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                // Fail closed: non-web schemes never leave the start page.
                guard URLNormalizer.isLoadable(url) else { return }
                self.delegate?.startPage(self, didOpenURL: url)
            }, for: .touchUpInside)

            Task { @MainActor [weak button, targetURL = url] in
                let fetched = await FaviconService.shared.favicon(for: targetURL, size: 26)
                guard let button else { return }
                var config = button.configuration
                config?.image = Self.roundFavicon(fetched)
                button.configuration = config
            }

            recentsStack.addArrangedSubview(button)
        }
    }
}

// MARK: - UICollectionViewDataSource, UICollectionViewDelegate

extension StartPageView: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        viewModel.favoriteItems.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: FavoriteTileCell.reuseIdentifier,
            for: indexPath
        ) as? FavoriteTileCell
        else {
            return UICollectionViewCell()
        }
        let item = viewModel.favoriteItems[indexPath.item]
        switch item {
        case let .bookmark(bookmark):
            cell.onCopyURL = {
                UIPasteboard.general.url = bookmark.url
            }
            cell.onDelete = { [weak self] in
                self?.onDeleteFavorite?(bookmark.id)
            }
            cell.configure(with: bookmark)
        case let .folder(folder):
            cell.onCopyURL = nil
            cell.onDelete = { [weak self] in
                self?.onDeleteFavorite?(folder.id)
            }
            let previews = viewModel.previewBookmarks(for: folder)
            cell.configure(with: folder, previewBookmarks: previews)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        let item = viewModel.favoriteItems[indexPath.item]
        switch item {
        case let .bookmark(bookmark):
            delegate?.startPage(self, didOpenURL: bookmark.url)
        case let .folder(folder):
            viewModel.openFolder(folder)
            reload()
        }
    }

    func collectionView(
        _: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point _: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPath.item < viewModel.favoriteItems.count else { return nil }
        let item = viewModel.favoriteItems[indexPath.item]
        switch item {
        case let .bookmark(bookmark):
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                let copyAction = UIAction(title: "Copy Link", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.url = bookmark.url
                }
                let deleteAction = UIAction(
                    title: "Remove from Favorites",
                    image: UIImage(systemName: "star.slash"),
                    attributes: .destructive
                ) { _ in
                    self?.onDeleteFavorite?(bookmark.id)
                }
                return UIMenu(children: [copyAction, deleteAction])
            }
        case let .folder(folder):
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                let deleteAction = UIAction(
                    title: "Delete Folder",
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    self?.onDeleteFavorite?(folder.id)
                }
                return UIMenu(children: [deleteAction])
            }
        }
    }
}

// MARK: - UICollectionViewDragDelegate, UICollectionViewDropDelegate

extension StartPageView: UICollectionViewDragDelegate, UICollectionViewDropDelegate {
    func collectionView(
        _: UICollectionView,
        itemsForBeginning _: UIDragSession,
        at indexPath: IndexPath
    ) -> [UIDragItem] {
        guard Self.canBeginDrag(itemCount: viewModel.favoriteItems.count, index: indexPath.item) else { return [] }
        let dragItem = UIDragItem(itemProvider: NSItemProvider())
        dragItem.localObject = viewModel.favoriteItems[indexPath.item].id
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
        let currentIDs = viewModel.favoriteItems.map(\.id)
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
        guard ordered != currentIDs, localItems.count == 1, let item = localItems.first else {
            for item in localItems {
                if let source = item.sourceIndexPath {
                    coordinator.drop(item.dragItem, toItemAt: source)
                }
            }
            return
        }
        guard let sourceIndexPath = item.sourceIndexPath else {
            reload()
            return
        }
        let targetItem = min(max(rawDestination, 0), ordered.count - 1)
        let targetIndexPath = IndexPath(item: targetItem, section: 0)
        collectionView.performBatchUpdates({
            _ = applyOrderedFavorites(ordered)
            collectionView.deleteItems(at: [sourceIndexPath])
            collectionView.insertItems(at: [targetIndexPath])
        }, completion: { [weak self] _ in
            guard let self else { return }
            do {
                try self.viewModel.persistReorderedFavorites(ordered)
            } catch {
                Logger(subsystem: "com.volcrypt.OuterView", category: "Persistence")
                    .error("reorderFavorites failed: \(error.localizedDescription, privacy: .public)")
                self.reload()
            }
        })
        coordinator.drop(item.dragItem, toItemAt: targetIndexPath)
    }
}

// MARK: - Dashed prompt tile

private final class DashedPromptTile: UIButton {
    private let dashLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        var configuration = UIButton.Configuration.plain()
        configuration.titleLineBreakMode = .byWordWrapping
        self.configuration = configuration
        titleLabel?.numberOfLines = 2
        titleLabel?.textAlignment = .center
        backgroundColor = .clear
        dashLayer.fillColor = UIColor.clear.cgColor
        dashLayer.strokeColor = UIColor.secondaryLabel.cgColor
        dashLayer.lineWidth = 1.5
        dashLayer.lineDashPattern = [6, 4]
        layer.addSublayer(dashLayer)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dashLayer.frame = bounds
        dashLayer.path = UIBezierPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 1),
            cornerRadius: 12
        ).cgPath
    }
}
