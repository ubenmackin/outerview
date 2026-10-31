//
//  TabStripView.swift
//  OuterView
//

import UIKit

@MainActor
final class TabStripView: UIView {
    nonisolated static let stripHeight: CGFloat = 44
    nonisolated static let cellWidth: CGFloat = 160
    nonisolated static let cellHeight: CGFloat = 36

    var onSelectTab: ((UUID) -> Void)?
    var onCloseTab: ((UUID) -> Void)?
    var onNewTab: (() -> Void)?

    private(set) var displayedTabs: [TabOverviewItem] = []
    private(set) var displayedSelectedID: UUID?

    let collectionView: UICollectionView
    let newTabButton = UIButton(type: .system)
    private let flowLayout = UICollectionViewFlowLayout()

    override init(frame: CGRect) {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.stripHeight)
    }

    func render(tabs: [TabOverviewItem], selectedID: UUID?) {
        displayedTabs = tabs
        displayedSelectedID = selectedID
        collectionView.reloadData()
    }

    private func setup() {
        backgroundColor = .clear
        isOpaque = false

        flowLayout.scrollDirection = .horizontal
        flowLayout.minimumInteritemSpacing = 8
        flowLayout.minimumLineSpacing = 8
        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        flowLayout.itemSize = CGSize(width: Self.cellWidth, height: Self.cellHeight)

        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(TabStripCell.self, forCellWithReuseIdentifier: TabStripCell.reuseIdentifier)
        addSubview(collectionView)

        newTabButton.setImage(UIImage(systemName: "plus"), for: .normal)
        newTabButton.tintColor = .label
        newTabButton.accessibilityLabel = "New Tab"
        newTabButton.translatesAutoresizingMaskIntoConstraints = false
        newTabButton.addAction(UIAction { [weak self] _ in self?.onNewTab?() }, for: .touchUpInside)
        addSubview(newTabButton)

        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            collectionView.trailingAnchor.constraint(equalTo: newTabButton.leadingAnchor, constant: -8),
            collectionView.centerYAnchor.constraint(equalTo: centerYAnchor),
            collectionView.heightAnchor.constraint(equalToConstant: Self.cellHeight),
            newTabButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            newTabButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            newTabButton.widthAnchor.constraint(equalToConstant: 36),
            newTabButton.heightAnchor.constraint(equalToConstant: 36)
        ])
    }
}

extension TabStripView: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_: UICollectionView, numberOfItemsInSection _: Int) -> Int {
        displayedTabs.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: TabStripCell.reuseIdentifier,
            for: indexPath
        ) as? TabStripCell
        else {
            return UICollectionViewCell()
        }
        let item = displayedTabs[indexPath.item]
        cell.configure(with: item, isSelected: item.id == displayedSelectedID)
        cell.onClose = { [weak self] in
            self?.onCloseTab?(item.id)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard indexPath.item < displayedTabs.count else { return }
        onSelectTab?(displayedTabs[indexPath.item].id)
    }
}

/// Fixed 160 by 36 cell with favicon plus title plus close affordance.
@MainActor
final class TabStripCell: UICollectionViewCell {
    static let reuseIdentifier = "TabStripCell"

    var onClose: (() -> Void)?

    private let faviconView = UIImageView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private var currentID: UUID?
    private var faviconTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        faviconTask?.cancel()
        faviconTask = nil
        onClose = nil
        currentID = nil
        faviconView.image = nil
        titleLabel.text = nil
    }

    func configure(with item: TabOverviewItem, isSelected: Bool) {
        faviconTask?.cancel()
        faviconTask = nil
        currentID = item.id
        if let url = item.url {
            titleLabel.text = HostFormatter.displayTitle(url: url, title: item.title)
            faviconView.image = FaviconService.shared.cachedFaviconOrMonogram(for: url, size: 16)
            faviconTask = Task { [weak self, targetURL = url, targetID = item.id] in
                let image = await FaviconService.shared.favicon(for: targetURL, size: 16)
                guard !Task.isCancelled, self?.currentID == targetID else { return }
                self?.faviconView.image = image
            }
        } else {
            titleLabel.text = "New Tab"
            faviconView.image = UIImage(systemName: "globe")
        }
        contentView.backgroundColor = isSelected ? .secondarySystemFill : .clear
        isAccessibilityElement = true
        accessibilityTraits = isSelected ? [.button, .selected] : [.button]
        accessibilityLabel = titleLabel.text
    }

    private func setup() {
        contentView.layer.cornerRadius = 8
        contentView.clipsToBounds = true

        faviconView.contentMode = .scaleAspectFit
        faviconView.tintColor = .secondaryLabel
        faviconView.translatesAutoresizingMaskIntoConstraints = false
        faviconView.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            faviconView.widthAnchor.constraint(equalToConstant: 16),
            faviconView.heightAnchor.constraint(equalToConstant: 16)
        ])

        titleLabel.font = .preferredFont(forTextStyle: .caption1)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        closeButton.setImage(
            UIImage(
                systemName: "xmark",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            ),
            for: .normal
        )
        closeButton.tintColor = .secondaryLabel
        closeButton.accessibilityLabel = "Close Tab"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        NSLayoutConstraint.activate([
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24)
        ])

        let stack = UIStackView(arrangedSubviews: [faviconView, titleLabel, closeButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 4),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
    }
}
