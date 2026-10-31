//
//  StartPageView.swift
//  OuterView
//

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
        setupHierarchy()
        observeHorizontalSizeClass()
        reload()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        let favoritesEmpty = viewModel.isFavoritesEmpty
        let recentsEmpty = viewModel.isRecentsEmpty
        collectionView.isHidden = favoritesEmpty
        emptyStateStack.isHidden = !favoritesEmpty
        addCurrentPageTile.isEnabled = viewModel.canAddCurrentPage
        addCurrentPageTile.alpha = viewModel.canAddCurrentPage ? 1 : 0.5
        recentsHeaderLabel.isHidden = recentsEmpty
        recentsStack.isHidden = recentsEmpty
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

    /// Extra bottom room, beyond the safe area, so the last row scrolls
    /// clear of the floating address pill.
    func setBottomChromeInset(_ inset: CGFloat) {
        guard scrollView.contentInset.bottom != inset else { return }
        scrollView.contentInset.bottom = inset
        scrollView.verticalScrollIndicatorInsets.bottom = inset
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

        favoritesHeaderLabel.text = "Favorites"
        favoritesHeaderLabel.font = .preferredFont(forTextStyle: .headline)
        favoritesHeaderLabel.adjustsFontForContentSizeCategory = true
        favoritesHeaderLabel.accessibilityIdentifier = "StartPage.FavoritesHeader"
        contentStack.addArrangedSubview(favoritesHeaderLabel)

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
        let count = viewModel.favorites.count
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
                self.delegate?.startPage(self, didOpenURL: url)
            }, for: .touchUpInside)

            Task { [weak button, targetURL = url] in
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
        viewModel.favorites.count
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
        let bookmark = viewModel.favorites[indexPath.item]
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
        delegate?.startPage(self, didOpenURL: viewModel.favorites[indexPath.item].url)
    }

    func collectionView(
        _: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point _: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard indexPath.item < viewModel.favorites.count else { return nil }
        let bookmark = viewModel.favorites[indexPath.item]
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
